## Benchmark: Parallel Search vs Sequential Search
##
## Tests whether level-based parallelization provides speedup
## for model search operations.
##
## Run: nim c -r -d:release --threads:on tests/benchmark_parallel_search.nim

import std/[times, monotimes, strformat, strutils, cpuinfo, math]
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table as coretable
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/manager/vb
import ../src/occam/search/parallel


proc makeTestVarList(n: int; cardinality: int): VariableList =
  result = initVariableList()
  for i in 0..<n:
    let name = $chr(ord('A') + i)
    discard result.add(initVariable(name, name, Cardinality(cardinality)))


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


proc runSearchBenchmark(
    nvars, card, width, levels: int
): tuple[seqMs, parMs, speedup: float64; modelsFound: int] =
  ## Run search benchmark and return timings

  let varList = makeTestVarList(nvars, card)
  let inputTable = makeRandomTable(varList)
  var mgr = initVBManager(varList, inputTable)
  let startModel = mgr.bottomRefModel

  # Warm up
  discard parallelSearch(
    varList, inputTable, startModel, SearchLoopless,
    SearchAIC, width, levels, useParallel = false
  )

  # Sequential timing (average of 3 runs) - wall clock
  let seqStart = getMonoTime()
  var seqResults: seq[SearchCandidate]
  for _ in 1..3:
    seqResults = parallelSearch(
      varList, inputTable, startModel, SearchLoopless,
      SearchAIC, width, levels, useParallel = false
    )
  let seqMs = float64(inNanoseconds(getMonoTime() - seqStart)) / 1_000_000.0 / 3.0

  # Parallel timing (average of 3 runs) - wall clock
  let parStart = getMonoTime()
  var parResults: seq[SearchCandidate]
  for _ in 1..3:
    parResults = parallelSearch(
      varList, inputTable, startModel, SearchLoopless,
      SearchAIC, width, levels, useParallel = true
    )
  let parMs = float64(inNanoseconds(getMonoTime() - parStart)) / 1_000_000.0 / 3.0

  let speedup = if parMs > 0.1: seqMs / parMs else: 0.0

  (seqMs, parMs, speedup, seqResults.len)


proc main() =
  echo ""
  echo "=" .repeat(90)
  echo "PARALLEL SEARCH BENCHMARK"
  echo "=" .repeat(90)
  echo ""
  echo "CPU cores: ", countProcessors()
  echo ""
  echo "Testing if level-based parallelization provides speedup for search operations."
  echo "Each seed model generates ~10-50 neighbors, providing more work per thread."
  echo ""

  # Test various configurations
  echo "Configuration                       States    Width  Levels    Seq(ms)    Par(ms)   Speedup  Models"
  echo "-" .repeat(100)

  # Small problems - likely too fast for parallelization
  for (nvars, card, width, levels) in [(5, 3, 3, 3), (5, 3, 5, 4), (6, 3, 3, 3), (6, 3, 5, 4)]:
    let stateSpace = card ^ nvars
    let (seqMs, parMs, speedup, models) = runSearchBenchmark(nvars, card, width, levels)
    let marker = if speedup > 1.1: " <<<" elif speedup > 1.0: " <" else: ""
    let configStr = &"{nvars}v x {card}c"
    echo &"{configStr:<35} {stateSpace:>10} {width:>8} {levels:>7} {seqMs:>10.1f} {parMs:>10.1f} {speedup:>9.2f}x {models:>6}{marker}"

  echo ""
  echo "Medium problems - may benefit from parallelization"
  echo "-" .repeat(100)

  for (nvars, card, width, levels) in [(6, 4, 5, 5), (7, 3, 5, 5), (7, 3, 7, 5), (7, 4, 5, 4)]:
    let stateSpace = card ^ nvars
    let (seqMs, parMs, speedup, models) = runSearchBenchmark(nvars, card, width, levels)
    let marker = if speedup > 1.1: " <<<" elif speedup > 1.0: " <" else: ""
    let configStr = &"{nvars}v x {card}c"
    echo &"{configStr:<35} {stateSpace:>10} {width:>8} {levels:>7} {seqMs:>10.1f} {parMs:>10.1f} {speedup:>9.2f}x {models:>6}{marker}"

  echo ""
  echo "Larger problems - more likely to benefit"
  echo "-" .repeat(100)

  for (nvars, card, width, levels) in [(8, 3, 5, 5), (8, 3, 7, 5), (8, 4, 5, 4), (9, 3, 5, 4)]:
    let stateSpace = card ^ nvars
    if stateSpace > 100000:
      continue  # Skip very large to keep reasonable
    let (seqMs, parMs, speedup, models) = runSearchBenchmark(nvars, card, width, levels)
    let marker = if speedup > 1.1: " <<<" elif speedup > 1.0: " <" else: ""
    let configStr = &"{nvars}v x {card}c"
    echo &"{configStr:<35} {stateSpace:>10} {width:>8} {levels:>7} {seqMs:>10.1f} {parMs:>10.1f} {speedup:>9.2f}x {models:>6}{marker}"

  echo ""
  echo "Wide searches (more seeds per level = more parallelism opportunity)"
  echo "-" .repeat(100)

  for (nvars, card, width, levels) in [(6, 3, 10, 5), (6, 3, 15, 5), (7, 3, 10, 5), (7, 3, 15, 4)]:
    let stateSpace = card ^ nvars
    let (seqMs, parMs, speedup, models) = runSearchBenchmark(nvars, card, width, levels)
    let marker = if speedup > 1.1: " <<<" elif speedup > 1.0: " <" else: ""
    let configStr = &"{nvars}v x {card}c (wide)"
    echo &"{configStr:<35} {stateSpace:>10} {width:>8} {levels:>7} {seqMs:>10.1f} {parMs:>10.1f} {speedup:>9.2f}x {models:>6}{marker}"

  echo ""
  echo "=" .repeat(90)
  echo "SUMMARY"
  echo "=" .repeat(90)
  echo ""
  echo "Level-based parallelization is designed to amortize thread overhead by:"
  echo "  - Processing each seed model's entire neighbor set in one thread"
  echo "  - With width=5 and ~50 neighbors per seed, each thread does ~50 evaluations"
  echo ""
  echo "Legend: <<< = significant speedup (>1.1x), < = marginal speedup (>1.0x)"
  echo ""


when isMainModule:
  main()
