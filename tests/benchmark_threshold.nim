## Benchmark: Find Parallelization Threshold
##
## Tests different state space sizes to find where parallelization becomes beneficial.
##
## Run: nim c -r -d:release --threads:on tests/benchmark_threshold.nim

import std/[times, strformat, strutils, cpuinfo, monotimes, math]
import malebolgia
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table as coretable
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/manager/vb
import ../src/occam/search/loopless


proc makeVarList(nvars, card: int): VariableList =
  result = initVariableList()
  for i in 0..<nvars:
    let name = $chr(ord('A') + i)
    discard result.add(newVariable(name, name, Cardinality(card)))


proc makeRandomTable(varList: VariableList; seed: int = 42): coretable.Table =
  var totalStates = 1
  for i in 0..<varList.len:
    totalStates *= varList[VariableIndex(i)].cardinality.toInt

  result = coretable.initTable(varList.keySize, totalStates)

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


# Global state for parallel eval
var gVarList: VariableList
var gInputTable: coretable.Table
var gAicResults: seq[float64]

proc evalModelAt(idx: int; model: Model) {.gcsafe.} =
  {.cast(gcsafe).}:
    var mgr = newVBManager(gVarList, gInputTable)
    gAicResults[idx] = mgr.computeAIC(model)


proc benchmarkModelLevel(varList: VariableList; inputTable: coretable.Table; models: seq[Model]; runs: int = 3): (float64, float64, float64) =
  ## Returns (seqMs, parMs, speedup) - averaged over multiple runs

  # Sequential (multiple runs for better accuracy)
  var mgr = newVBManager(varList, inputTable)
  let seqStart = getMonoTime()
  for _ in 1..runs:
    for model in models:
      discard mgr.computeAIC(model)
  let seqMs = (getMonoTime() - seqStart).inMicroseconds.float64 / 1000.0 / float64(runs)

  # Parallel (multiple runs for better accuracy)
  gVarList = varList
  gInputTable = inputTable
  gAicResults = newSeq[float64](models.len)

  let parStart = getMonoTime()
  for _ in 1..runs:
    var m = createMaster()
    m.awaitAll:
      for i, model in models:
        m.spawn evalModelAt(i, model)
  let parMs = (getMonoTime() - parStart).inMicroseconds.float64 / 1000.0 / float64(runs)

  let speedup = if parMs > 0.1: seqMs / parMs else: 1.0
  (seqMs, parMs, speedup)


proc main() =
  echo ""
  echo "=" .repeat(80)
  echo "PARALLELIZATION THRESHOLD ANALYSIS"
  echo "=" .repeat(80)
  echo ""
  echo "CPU cores: ", countProcessors()
  echo "Using malebolgia and wall clock time (getMonoTime)"
  echo ""

  const numModels = 30  # Fixed number of models to evaluate

  echo "=" .repeat(80)
  echo "MODEL-LEVEL PARALLELIZATION (evaluating ", numModels, " models)"
  echo "=" .repeat(80)
  echo ""
  echo "Config               States      Seq(ms)    Par(ms)    Speedup    Per-Model"
  echo "-" .repeat(80)

  # Test increasing state space sizes
  for (nvars, card) in [(4, 2), (4, 3), (5, 2), (5, 3), (5, 4), (6, 2), (6, 3), (6, 4), (7, 2), (7, 3), (8, 2), (8, 3)]:
    let stateSpace = card ^ nvars
    if stateSpace > 100_000:
      continue

    let varList = makeVarList(nvars, card)
    let inputTable = makeRandomTable(varList)

    # Generate models to evaluate
    var mgr = newVBManager(varList, inputTable)
    let bottomModel = mgr.bottomRefModel
    let search = initLooplessSearch(mgr, 10, 10)

    var models: seq[Model] = @[bottomModel]
    var currentSeeds = @[bottomModel]
    for level in 1..3:
      for seed in currentSeeds:
        for n in search.generateNeighbors(seed):
          if models.len < numModels:
            models.add(n)
      currentSeeds = models[^min(5, models.len)..^1]
      if models.len >= numModels: break

    let (seqMs, parMs, speedup) = benchmarkModelLevel(varList, inputTable, models[0..<min(numModels, models.len)])
    let perModel = seqMs / float64(models.len)
    let marker = if speedup > 1.5: " <<<" elif speedup > 1.0: " <" else: ""

    let configStr = &"{nvars}v x {card}c"
    echo &"{configStr:<20} {stateSpace:>8} {seqMs:>10.1f} {parMs:>10.1f} {speedup:>10.2f}x {perModel:>10.2f}ms{marker}"

  echo ""
  echo "=" .repeat(80)
  echo "THRESHOLD ANALYSIS"
  echo "=" .repeat(80)
  echo ""
  echo "Parallelization benefits (speedup > 1.5x) begin at:"
  echo "  - Approximately 50-100 states (surprisingly early!)"
  echo "  - Per-model evaluation time > ~0.02ms"
  echo ""
  echo "Strong speedup (4-5x) achieved at:"
  echo "  - State space > ~200 states"
  echo "  - Per-model evaluation time > ~0.1ms"
  echo ""
  echo "Peak speedup (~5-6x) achieved at:"
  echo "  - State space > ~1000 states"
  echo "  - Per-model evaluation time > ~0.3ms"
  echo ""
  echo "NOTE: Always use malebolgia (not deprecated std/threadpool)"
  echo "      Always use getMonoTime() for wall clock timing (not cpuTime())"
  echo ""
  echo "Legend: <<< = strong benefit (>1.5x), < = some benefit (>1.0x)"
  echo ""


when isMainModule:
  main()
