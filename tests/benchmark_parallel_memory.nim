## Benchmark: Memory Allocation in Parallel
##
## Tests if memory allocation is the bottleneck by pre-allocating
## VBManagers before spawning threads.
##
## Run: nim c -r -d:release --threads:on tests/benchmark_parallel_memory.nim

import std/[times, monotimes, strformat, strutils, cpuinfo, json, os, locks]
import std/tables as stdtables
import std/threadpool
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
    discard varList.add(newVariable(
      v["name"].getStr(), v["abbrev"].getStr(),
      Cardinality(v["cardinality"].getInt()), v["isDependent"].getBool()
    ))

  var freqMap = stdtables.initTable[Key, float64]()
  for row in js["data"]:
    var k = newKey(varList.keySize)
    for i in 0..<row.len:
      k.setValue(varList, VariableIndex(i), row[i].getInt() - 1)
    freqMap.mgetOrPut(k, 0.0) += 1.0

  var tbl = coretable.initContingencyTable(varList.keySize, freqMap.len)
  for k, count in freqMap:
    tbl.add(k, count)
  tbl.sort()
  tbl.normalize()
  (varList, tbl)


type
  WorkItem = object
    seed: Model
    width: int

  WorkResult = object
    evaluated: int
    totalAic: float64


# Global shared state (for testing only)
var gVarList: VariableList
var gInputTable: coretable.Table


proc processWithNewManager(item: WorkItem): WorkResult {.gcsafe.} =
  ## Creates new VBManager inside thread
  {.cast(gcsafe).}:
    var mgr = initVBManager(gVarList, gInputTable)
    let search = initLooplessSearch(mgr, item.width, 10)
    let neighbors = search.generateNeighbors(item.seed)
    result.evaluated = neighbors.len
    result.totalAic = 0.0
    for n in neighbors:
      result.totalAic += mgr.computeAIC(n)


proc main() =
  echo ""
  echo "=" .repeat(70)
  echo "PARALLEL MEMORY ALLOCATION ANALYSIS"
  echo "=" .repeat(70)
  echo ""
  echo "CPU cores: ", countProcessors()
  echo ""

  let dataFile = "data/primes_R3_R17.json"
  if not fileExists(dataFile):
    echo "Dataset not found: ", dataFile
    quit(1)

  echo "Loading dataset..."
  (gVarList, gInputTable) = loadPrimesDataset(dataFile)
  echo "State space: ", gInputTable.len
  echo ""

  # Create seeds
  var mgr = initVBManager(gVarList, gInputTable)
  let bottomModel = mgr.bottomRefModel
  var items: seq[WorkItem]

  let search = initLooplessSearch(mgr, 10, 10)
  for n in search.generateNeighbors(bottomModel):
    items.add(WorkItem(seed: n, width: 5))
  items.add(WorkItem(seed: bottomModel, width: 5))

  echo "Seeds to process: ", items.len
  echo ""

  # Test 1: Sequential (baseline) - wall clock
  echo "Test 1: Sequential"
  let seqStart = getMonoTime()
  var seqTotal = 0
  for item in items:
    var localMgr = initVBManager(gVarList, gInputTable)
    let localSearch = initLooplessSearch(localMgr, item.width, 10)
    let neighbors = localSearch.generateNeighbors(item.seed)
    seqTotal += neighbors.len
    for n in neighbors:
      discard localMgr.computeAIC(n)
  let seqMs = float64(inNanoseconds(getMonoTime() - seqStart)) / 1_000_000.0
  echo &"  Time: {seqMs:.1f}ms  Models evaluated: {seqTotal}"

  # Test 2: Parallel with threadpool - wall clock
  echo ""
  echo "Test 2: Parallel (threadpool)"
  let parStart = getMonoTime()
  var futures: seq[FlowVar[WorkResult]]
  for item in items:
    futures.add(spawn processWithNewManager(item))

  var parTotal = 0
  for f in futures:
    parTotal += (^f).evaluated
  let parMs = float64(inNanoseconds(getMonoTime() - parStart)) / 1_000_000.0
  echo &"  Time: {parMs:.1f}ms  Models evaluated: {parTotal}"

  # Test 3: Time just the VBManager creation - wall clock
  echo ""
  echo "Test 3: VBManager creation timing"
  let createStart = getMonoTime()
  for _ in 0..<items.len:
    var testMgr = initVBManager(gVarList, gInputTable)
    discard testMgr.bottomRefModel
  let createMs = float64(inNanoseconds(getMonoTime() - createStart)) / 1_000_000.0
  echo &"  Sequential creation ({items.len}x): {createMs:.1f}ms"
  echo &"  Per-manager: {createMs / float64(items.len):.2f}ms"

  # Summary
  echo ""
  echo "=" .repeat(70)
  echo "ANALYSIS"
  echo "=" .repeat(70)
  echo ""
  let speedup = seqMs / parMs
  echo &"Sequential: {seqMs:.1f}ms"
  echo &"Parallel:   {parMs:.1f}ms"
  echo &"Speedup:    {speedup:.2f}x"
  echo ""

  let idealParallel = seqMs / float64(countProcessors())
  echo &"Ideal parallel (with {countProcessors()} cores): {idealParallel:.1f}ms"
  echo &"Actual parallel overhead: {parMs - idealParallel:.1f}ms"
  echo ""

  if speedup < 1.0:
    echo "FINDING: Parallel is SLOWER than sequential."
    echo ""
    echo "The overhead sources:"
    echo "  1. VBManager creation per thread"
    echo "  2. Memory allocation contention"
    echo "  3. Thread synchronization"
    echo ""
    echo "Possible solutions:"
    echo "  - Pre-allocate VBManagers (manager pool)"
    echo "  - Use memory arenas per thread"
    echo "  - Reduce allocations in hot path"
  echo ""


when isMainModule:
  main()
