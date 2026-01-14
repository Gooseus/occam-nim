## Quick test: Model-level parallelization with wall clock time
##
## Tests if parallelizing individual model evaluations provides speedup
## when measured with wall clock time.

import std/[times, strformat, strutils, cpuinfo, json, os, monotimes]
import std/tables as stdtables
import malebolgia
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table as coretable
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/manager/vb
import ../src/occam/search/loopless


proc loadPrimesDataset(filename: string): (VariableList, coretable.Table) =
  let content = readFile(filename)
  let js = parseJson(content)

  var varList = initVariableList()
  for v in js["variables"]:
    discard varList.add(initVariable(
      v["name"].getStr(), v["abbrev"].getStr(),
      Cardinality(v["cardinality"].getInt()), v["isDependent"].getBool()
    ))

  var freqMap = stdtables.initTable[Key, float64]()
  for row in js["data"]:
    var k = initKey(varList.keySize)
    for i in 0..<row.len:
      k.setValue(varList, VariableIndex(i), row[i].getInt() - 1)
    freqMap.mgetOrPut(k, 0.0) += 1.0

  var tbl = coretable.initContingencyTable(varList.keySize, freqMap.len)
  for k, count in freqMap:
    tbl.add(k, count)
  tbl.sort()
  tbl.normalize()
  (varList, tbl)


# Global storage for parallel results
var gVarList: VariableList
var gInputTable: coretable.Table
var gResults: seq[float64]

proc evaluateModelAt(idx: int; model: Model) {.gcsafe.} =
  ## Evaluate single model in parallel
  {.cast(gcsafe).}:
    var mgr = initVBManager(gVarList, gInputTable)
    gResults[idx] = mgr.computeAIC(model)


proc main() =
  echo ""
  echo "=" .repeat(70)
  echo "MODEL-LEVEL PARALLELIZATION TEST"
  echo "=" .repeat(70)
  echo ""
  echo "CPU cores: ", countProcessors()
  echo ""

  let dataFile = "data/primes_R3_R17.json"
  if not fileExists(dataFile):
    echo "Dataset not found"
    quit(1)

  echo "Loading dataset..."
  (gVarList, gInputTable) = loadPrimesDataset(dataFile)
  echo "State space: ", gInputTable.len
  echo ""

  # Generate models to evaluate
  var mgr = initVBManager(gVarList, gInputTable)
  let bottomModel = mgr.bottomRefModel
  let search = initLooplessSearch(mgr, 10, 10)
  var models: seq[Model] = @[bottomModel]

  # Generate multiple levels of models
  var currentSeeds = @[bottomModel]
  for level in 1..3:
    var newModels: seq[Model]
    for seed in currentSeeds:
      let neighbors = search.generateNeighbors(seed)
      for n in neighbors:
        if models.len < 50:
          models.add(n)
          newModels.add(n)
    currentSeeds = newModels
    if models.len >= 50: break

  echo "Models to evaluate: ", models.len
  echo ""

  # Sequential evaluation (wall clock)
  echo "Sequential evaluation..."
  let seqStart = getMonoTime()
  var seqResults: seq[float64] = @[]
  for model in models:
    seqResults.add(mgr.computeAIC(model))
  let seqMs = (getMonoTime() - seqStart).inMilliseconds.float64
  echo &"  Time: {seqMs:.0f}ms ({seqMs/float64(models.len):.1f}ms per model)"

  # Parallel evaluation (wall clock)
  echo ""
  echo "Parallel evaluation (malebolgia)..."
  gResults = newSeq[float64](models.len)
  let parStart = getMonoTime()
  var m = createMaster()
  m.awaitAll:
    for i, model in models:
      m.spawn evaluateModelAt(i, model)
  let parMs = (getMonoTime() - parStart).inMilliseconds.float64
  echo &"  Time: {parMs:.0f}ms ({parMs/float64(models.len):.1f}ms per model)"

  # Verify results match
  var match = true
  for i in 0..<models.len:
    if abs(seqResults[i] - gResults[i]) > 0.001:
      match = false
      break
  echo ""
  echo "Results match: ", match

  let speedup = seqMs / parMs
  echo ""
  echo "=" .repeat(70)
  echo &"Sequential: {seqMs:.0f}ms"
  echo &"Parallel:   {parMs:.0f}ms"
  echo &"Speedup:    {speedup:.2f}x"
  echo "=" .repeat(70)
  echo ""

  if speedup > 1.5:
    echo "Model-level parallelization provides significant speedup!"
  elif speedup > 1.0:
    echo "Model-level parallelization provides marginal speedup."
  else:
    echo "Model-level parallelization does not provide speedup."
    echo "The overhead of creating VBManagers per model dominates."
  echo ""


when isMainModule:
  main()
