## Tests for Parallel Search Module
##
## Tests the level-based parallel search implementation.
## Verifies correctness and compares sequential vs parallel results.

import std/[unittest, times, monotimes, strformat, sets, algorithm]
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table as coretable
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/manager/vb
import ../src/occam/search/loopless
import ../src/occam/search/parallel


# ============ Test Data Setup ============

proc makeTestVarList(n: int; cardinality: int): VariableList =
  result = initVariableList()
  for i in 0..<n:
    let name = $chr(ord('A') + i)
    discard result.add(newVariable(name, name, Cardinality(cardinality)))


proc makeRandomTable(varList: VariableList; seed: int = 42): coretable.Table =
  var totalStates = 1
  for i in 0..<varList.len:
    totalStates *= varList[VariableIndex(i)].cardinality.toInt

  result = coretable.initContingencyTable(varList.keySize, totalStates)

  var rng = seed
  proc nextRand(): float64 =
    rng = (rng * 1103515245 + 12345) mod (1 shl 31)
    float64(rng) / float64(1 shl 31)

  var indices = newSeq[int](varList.len)
  var done = false
  while not done:
    var keyPairs: seq[(VariableIndex, int)]
    for i in 0..<varList.len:
      keyPairs.add((VariableIndex(i), indices[i]))
    let key = varList.buildKey(keyPairs)
    result.add(key, nextRand() + 0.1)

    var carry = true
    for i in 0..<varList.len:
      if carry:
        indices[i] += 1
        if indices[i] >= varList[VariableIndex(i)].cardinality.toInt:
          indices[i] = 0
        else:
          carry = false
    if carry:
      done = true

  result.sort()
  result.normalize()


# ============ Tests ============

suite "Parallel Search - Basic Operations":

  test "processOneSeedWithFilter generates valid candidates":
    let varList = makeTestVarList(5, 3)  # 243 states
    let inputTable = makeRandomTable(varList)
    var mgr = initVBManager(varList, inputTable)

    let startModel = mgr.bottomRefModel

    let result = processOneSeedWithFilter(
      varList, inputTable, startModel, SearchLoopless, SearchAIC, 3
    )

    check result.candidates.len > 0
    check result.modelsEvaluated > 0
    check result.modelsEvaluated == result.candidates.len

    # All candidates should have valid names and statistics
    for c in result.candidates:
      check c.name.len > 0
      check c.statistic > -1000000.0  # Reasonable AIC range

  test "mergeCandidates deduplicates correctly":
    # Create fake results with duplicates
    let r1 = LevelResult(
      candidates: @[
        SearchCandidate(model: initModel(@[]), name: "A:B", statistic: 1.0),
        SearchCandidate(model: initModel(@[]), name: "A:C", statistic: 2.0)
      ],
      modelsEvaluated: 2
    )
    let r2 = LevelResult(
      candidates: @[
        SearchCandidate(model: initModel(@[]), name: "A:B", statistic: 1.0),  # Duplicate
        SearchCandidate(model: initModel(@[]), name: "B:C", statistic: 3.0)
      ],
      modelsEvaluated: 2
    )

    let merged = mergeCandidates(@[r1, r2])

    check merged.len == 3  # A:B, A:C, B:C (no duplicates)

    var names: seq[string]
    for c in merged:
      names.add(c.name)
    check "A:B" in names
    check "A:C" in names
    check "B:C" in names

  test "sortCandidates sorts by statistic":
    var candidates = @[
      SearchCandidate(model: initModel(@[]), name: "C", statistic: 30.0),
      SearchCandidate(model: initModel(@[]), name: "A", statistic: 10.0),
      SearchCandidate(model: initModel(@[]), name: "B", statistic: 20.0)
    ]

    # AIC: ascending order
    sortCandidates(candidates, SearchAIC)
    check candidates[0].name == "A"
    check candidates[1].name == "B"
    check candidates[2].name == "C"

    # DDF: descending order
    sortCandidates(candidates, SearchDDF)
    check candidates[0].name == "C"
    check candidates[1].name == "B"
    check candidates[2].name == "A"


suite "Parallel Search - Sequential Implementation":

  test "searchLevelSequential returns valid results":
    let varList = makeTestVarList(5, 3)
    let inputTable = makeRandomTable(varList)
    var mgr = initVBManager(varList, inputTable)

    let startModel = mgr.bottomRefModel

    let (nextModels, evaluated) = searchLevelSequential(
      varList, inputTable, @[startModel], SearchLoopless, SearchAIC, 3
    )

    check nextModels.len <= 3  # width = 3
    check nextModels.len > 0
    check evaluated > 0

  test "searchLevelSequential respects width parameter":
    let varList = makeTestVarList(5, 3)
    let inputTable = makeRandomTable(varList)
    var mgr = initVBManager(varList, inputTable)

    let startModel = mgr.bottomRefModel

    # Width = 1: only best model
    let (models1, _) = searchLevelSequential(
      varList, inputTable, @[startModel], SearchLoopless, SearchAIC, 1
    )
    check models1.len == 1

    # Width = 5: up to 5 models
    let (models5, _) = searchLevelSequential(
      varList, inputTable, @[startModel], SearchLoopless, SearchAIC, 5
    )
    check models5.len >= 1
    check models5.len <= 5


suite "Parallel Search - Parallel vs Sequential":

  test "parallel produces same models as sequential":
    let varList = makeTestVarList(5, 3)
    let inputTable = makeRandomTable(varList)
    var mgr = initVBManager(varList, inputTable)

    let startModel = mgr.bottomRefModel
    let seeds = @[startModel]

    let (seqModels, seqEval) = searchLevelSequential(
      varList, inputTable, seeds, SearchLoopless, SearchAIC, 3
    )
    let (parModels, parEval) = searchLevelParallel(
      varList, inputTable, seeds, SearchLoopless, SearchAIC, 3
    )

    # Same number of results
    check seqModels.len == parModels.len
    check seqEval == parEval

    # Same model names (order may differ due to threading)
    var seqNames, parNames: HashSet[string]
    for m in seqModels:
      seqNames.incl(m.printName(varList))
    for m in parModels:
      parNames.incl(m.printName(varList))

    check seqNames == parNames

  test "parallel with multiple seeds":
    let varList = makeTestVarList(6, 3)  # 729 states
    let inputTable = makeRandomTable(varList)
    var mgr = initVBManager(varList, inputTable)

    let startModel = mgr.bottomRefModel

    # First level to get multiple seeds
    let (level1, _) = searchLevelSequential(
      varList, inputTable, @[startModel], SearchLoopless, SearchAIC, 3
    )
    check level1.len > 0

    # Now use multiple seeds for level 2
    let (seqLevel2, _) = searchLevelSequential(
      varList, inputTable, level1, SearchLoopless, SearchAIC, 5
    )
    let (parLevel2, _) = searchLevelParallel(
      varList, inputTable, level1, SearchLoopless, SearchAIC, 5
    )

    # Same results
    var seqNames, parNames: HashSet[string]
    for m in seqLevel2:
      seqNames.incl(m.printName(varList))
    for m in parLevel2:
      parNames.incl(m.printName(varList))

    check seqNames == parNames


suite "Parallel Search - Full Search":

  test "parallelSearch explores multiple levels":
    let varList = makeTestVarList(5, 3)
    let inputTable = makeRandomTable(varList)
    var mgr = initVBManager(varList, inputTable)

    let startModel = mgr.bottomRefModel

    let results = parallelSearch(
      varList, inputTable, startModel, SearchLoopless,
      SearchAIC, width = 3, maxLevels = 3, useParallel = true
    )

    check results.len > 0

    # Results should be sorted by AIC (ascending)
    for i in 0..<(results.len - 1):
      check results[i].statistic <= results[i+1].statistic

  test "parallelSearch vs sequential search produce same candidates":
    let varList = makeTestVarList(5, 3)
    let inputTable = makeRandomTable(varList)
    var mgr = initVBManager(varList, inputTable)

    let startModel = mgr.bottomRefModel

    let seqResults = parallelSearch(
      varList, inputTable, startModel, SearchLoopless,
      SearchAIC, width = 3, maxLevels = 3, useParallel = false
    )
    let parResults = parallelSearch(
      varList, inputTable, startModel, SearchLoopless,
      SearchAIC, width = 3, maxLevels = 3, useParallel = true
    )

    # Same candidate names
    var seqNames, parNames: HashSet[string]
    for c in seqResults:
      seqNames.incl(c.name)
    for c in parResults:
      parNames.incl(c.name)

    check seqNames == parNames


suite "Parallel Search - Performance":

  test "parallel search timing baseline":
    let varList = makeTestVarList(6, 3)  # 729 states
    let inputTable = makeRandomTable(varList)
    var mgr = initVBManager(varList, inputTable)

    let startModel = mgr.bottomRefModel

    # Warm up
    discard searchLevelSequential(
      varList, inputTable, @[startModel], SearchLoopless, SearchAIC, 3
    )

    # Time sequential (wall clock)
    let seqStart = getMonoTime()
    for _ in 1..3:
      discard parallelSearch(
        varList, inputTable, startModel, SearchLoopless,
        SearchAIC, width = 5, maxLevels = 4, useParallel = false
      )
    let seqTime = float64(inNanoseconds(getMonoTime() - seqStart)) / 1_000_000.0 / 3.0

    # Time parallel (wall clock)
    let parStart = getMonoTime()
    for _ in 1..3:
      discard parallelSearch(
        varList, inputTable, startModel, SearchLoopless,
        SearchAIC, width = 5, maxLevels = 4, useParallel = true
      )
    let parTime = float64(inNanoseconds(getMonoTime() - parStart)) / 1_000_000.0 / 3.0

    echo ""
    echo &"  Sequential: {seqTime:.1f}ms"
    echo &"  Parallel: {parTime:.1f}ms"
    echo &"  Speedup: {seqTime/parTime:.2f}x"

    check true  # Always pass - timing is informational
