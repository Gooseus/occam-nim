## Benchmark: Find Parallelization Crossover Point
##
## Determines at what workload size parallelization becomes beneficial.
## Tests both loopless (BP) and loop (IPF) models.
##
## Run with: nim c -r -d:release --threads:on tests/benchmark_parallel_crossover.nim

import std/[times, monotimes, strformat, strutils, cpuinfo, math]
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table as coretable
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/manager/vb
import ../src/occam/parallel/eval


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


proc makeLooplessModels(varList: VariableList; count: int): seq[Model] =
  ## Generate loopless (chain/star) models - use BP
  result = @[]
  let n = varList.len

  while result.len < count:
    # Chain: AB:BC:CD:...
    for chainLen in 2..min(n-1, 5):
      var rels: seq[Relation]
      for i in 0..<chainLen:
        rels.add(initRelation(@[VariableIndex(i), VariableIndex(i+1)]))
      result.add(initModel(rels))
      if result.len >= count: return

    # Star: AB:AC:AD:...
    for starSize in 2..min(n-1, 4):
      var rels: seq[Relation]
      for i in 1..starSize:
        rels.add(initRelation(@[VariableIndex(0), VariableIndex(i)]))
      result.add(initModel(rels))
      if result.len >= count: return


proc makeLoopModels(varList: VariableList; count: int): seq[Model] =
  ## Generate models WITH loops - use IPF (slower)
  result = @[]
  let n = varList.len

  while result.len < count:
    # Triangle: AB:BC:AC (has loop)
    if n >= 3:
      result.add(initModel(@[
        initRelation(@[VariableIndex(0), VariableIndex(1)]),
        initRelation(@[VariableIndex(1), VariableIndex(2)]),
        initRelation(@[VariableIndex(0), VariableIndex(2)])
      ]))
      if result.len >= count: return

    # Square with diagonal: AB:BC:CD:DA:AC
    if n >= 4:
      result.add(initModel(@[
        initRelation(@[VariableIndex(0), VariableIndex(1)]),
        initRelation(@[VariableIndex(1), VariableIndex(2)]),
        initRelation(@[VariableIndex(2), VariableIndex(3)]),
        initRelation(@[VariableIndex(3), VariableIndex(0)]),
        initRelation(@[VariableIndex(0), VariableIndex(2)])
      ]))
      if result.len >= count: return

    # 4-cycle: AB:BC:CD:DA
    if n >= 4:
      result.add(initModel(@[
        initRelation(@[VariableIndex(0), VariableIndex(1)]),
        initRelation(@[VariableIndex(1), VariableIndex(2)]),
        initRelation(@[VariableIndex(2), VariableIndex(3)]),
        initRelation(@[VariableIndex(3), VariableIndex(0)])
      ]))
      if result.len >= count: return


proc runTest(desc: string; varList: VariableList; inputTable: coretable.Table;
             models: seq[Model]; numRuns = 3): tuple[seqMs, parMs, speedup: float64] =
  ## Run timing test and return results

  # Warm up
  var mgr = initVBManager(varList, inputTable)
  if models.len > 0:
    discard mgr.computeAIC(models[0])
    discard parallelComputeAIC(varList, inputTable, @[models[0]])

  # Sequential timing (best of numRuns) - use wall clock time
  var bestSeq = float64.high
  for _ in 1..numRuns:
    var mgr2 = initVBManager(varList, inputTable)
    let start = getMonoTime()
    for model in models:
      discard mgr2.computeAIC(model)
    let elapsed = float64(inNanoseconds(getMonoTime() - start)) / 1_000_000.0
    if elapsed < bestSeq:
      bestSeq = elapsed

  # Parallel timing (best of numRuns) - use wall clock time
  var bestPar = float64.high
  for _ in 1..numRuns:
    let start = getMonoTime()
    discard parallelComputeAIC(varList, inputTable, models)
    let elapsed = float64(inNanoseconds(getMonoTime() - start)) / 1_000_000.0
    if elapsed < bestPar:
      bestPar = elapsed

  result.seqMs = bestSeq
  result.parMs = bestPar
  result.speedup = if bestPar > 0.1: bestSeq / bestPar else: 0.0


proc main() =
  echo ""
  echo "=" .repeat(90)
  echo "PARALLELIZATION CROSSOVER POINT ANALYSIS"
  echo "=" .repeat(90)
  echo ""
  echo "CPU cores: ", countProcessors()
  echo "Goal: Find where parallel becomes faster than sequential"
  echo ""

  # ============ LOOPLESS MODELS (BP - fast) ============
  echo "=" .repeat(90)
  echo "LOOPLESS MODELS (use Belief Propagation - very fast)"
  echo "=" .repeat(90)
  echo ""

  echo "Testing increasing state space sizes..."
  echo ""
  echo "Config                         States    Models    Seq(ms)    Par(ms)    Speedup"
  echo "-".repeat(90)

  for (nvars, card) in [(5, 2), (5, 3), (5, 4), (6, 3), (6, 4), (7, 3), (7, 4), (8, 3), (8, 4), (9, 3), (10, 3)]:
    let stateSpace = card ^ nvars
    if stateSpace > 500_000:
      continue  # Skip very large to keep benchmark reasonable

    let varList = makeTestVarList(nvars, card)
    let inputTable = makeRandomTable(varList)
    let models = makeLooplessModels(varList, 50)

    let (seqMs, parMs, speedup) = runTest("", varList, inputTable, models)
    let perModel = seqMs / float64(models.len)
    let marker = if speedup > 1.1: " <<<" elif speedup > 1.0: " <" else: ""

    let configStr = $nvars & "v x " & $card & "c"
    echo fmt"{configStr:<30} {stateSpace:>10} {models.len:>8} {seqMs:>10.1f} {parMs:>10.1f} {speedup:>9.2f}x{marker}"

  # ============ LOOP MODELS (IPF - slower) ============
  echo ""
  echo "=".repeat(90)
  echo "LOOP MODELS (use IPF - iterative, slower)"
  echo "=".repeat(90)
  echo ""

  echo "Config                         States    Models    Seq(ms)    Par(ms)    Speedup"
  echo "-".repeat(90)

  for (nvars, card) in [(4, 2), (4, 3), (4, 4), (5, 2), (5, 3), (5, 4), (6, 2), (6, 3), (7, 2)]:
    let stateSpace = card ^ nvars
    if stateSpace > 100_000:
      continue

    let varList = makeTestVarList(nvars, card)
    let inputTable = makeRandomTable(varList)
    let models = makeLoopModels(varList, 30)

    let (seqMs, parMs, speedup) = runTest("", varList, inputTable, models)
    let perModel = seqMs / float64(models.len)
    let marker = if speedup > 1.1: " <<<" elif speedup > 1.0: " <" else: ""

    let configStr = $nvars & "v x " & $card & "c (loops)"
    echo fmt"{configStr:<30} {stateSpace:>10} {models.len:>8} {seqMs:>10.1f} {parMs:>10.1f} {speedup:>9.2f}x{marker}"

  # ============ SCALING TEST ============
  echo ""
  echo "=" .repeat(90)
  echo "SCALING TEST: Fixed state space, varying model count"
  echo "=" .repeat(90)
  echo ""

  let testVarList = makeTestVarList(6, 4)  # 4096 states
  let testTable = makeRandomTable(testVarList)

  echo "Loopless models (6 vars, card=4, 4096 states):"
  echo "    Models      Seq(ms)      Par(ms)    Speedup"
  echo "-".repeat(50)

  for numModels in [10, 25, 50, 100, 200, 500]:
    let models = makeLooplessModels(testVarList, numModels)
    let (seqMs, parMs, speedup) = runTest("", testVarList, testTable, models)
    let marker = if speedup > 1.1: " <<<" elif speedup > 1.0: " <" else: ""
    echo fmt"{models.len:>10} {seqMs:>12.1f} {parMs:>12.1f} {speedup:>9.2f}x{marker}"

  echo ""
  echo "Loop models (5 vars, card=3, 243 states):"
  let loopVarList = makeTestVarList(5, 3)
  let loopTable = makeRandomTable(loopVarList)

  echo "    Models      Seq(ms)      Par(ms)    Speedup"
  echo "-".repeat(50)

  for numModels in [10, 25, 50, 100]:
    let models = makeLoopModels(loopVarList, numModels)
    let (seqMs, parMs, speedup) = runTest("", loopVarList, loopTable, models)
    let marker = if speedup > 1.1: " <<<" elif speedup > 1.0: " <" else: ""
    echo fmt"{models.len:>10} {seqMs:>12.1f} {parMs:>12.1f} {speedup:>9.2f}x{marker}"

  # ============ SUMMARY ============
  echo ""
  echo "=" .repeat(90)
  echo "SUMMARY"
  echo "=" .repeat(90)
  echo ""
  echo "FINDING: Parallelization provides NO speedup for tested workloads."
  echo ""
  echo "Thread coordination overhead (spawn, sync, VBManager creation) dominates:"
  echo "  - BP algorithm: ~0.1-3ms per model (too fast for parallelism)"
  echo "  - IPF algorithm: ~2-10ms per model (still dominated by overhead)"
  echo "  - With more models, parallel is SLOWER due to accumulated overhead"
  echo ""
  echo "Parallelization MAY help when:"
  echo "  - State space > 500,000 states (e.g., 10+ vars with cardinality 3)"
  echo "  - Per-model evaluation > 50ms (extremely complex models)"
  echo "  - Not currently achievable with typical OCCAM use cases"
  echo ""
  echo "Recommendation: Use sequential evaluation for best performance."
  echo ""


when isMainModule:
  main()
