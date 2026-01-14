## Profile: Parallelization Overhead Analysis
##
## Measures where the overhead comes from in parallel search.

import std/[times, monotimes, strformat, strutils, cpuinfo, json, os]
import std/tables as stdtables
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
    let name = v["name"].getStr()
    let abbrev = v["abbrev"].getStr()
    let card = v["cardinality"].getInt()
    let isDep = v["isDependent"].getBool()
    discard varList.add(initVariable(name, abbrev, Cardinality(card), isDep))

  var freqMap = stdtables.initTable[Key, float64]()

  for row in js["data"]:
    var k = initKey(varList.keySize)
    for i in 0..<row.len:
      let val = row[i].getInt() - 1
      k.setValue(varList, VariableIndex(i), val)

    if k in freqMap:
      freqMap[k] = freqMap[k] + 1.0
    else:
      freqMap[k] = 1.0

  var tbl = coretable.initContingencyTable(varList.keySize, freqMap.len)
  for k, count in freqMap:
    tbl.add(k, count)
  tbl.sort()
  tbl.normalize()

  (varList, tbl)


proc main() =
  echo ""
  echo "=" .repeat(70)
  echo "PARALLELIZATION OVERHEAD ANALYSIS"
  echo "=" .repeat(70)
  echo ""

  let dataFile = "data/primes_R3_R17.json"
  if not fileExists(dataFile):
    echo "Dataset not found: ", dataFile
    quit(1)

  echo "Loading dataset: ", dataFile
  let (varList, inputTable) = loadPrimesDataset(dataFile)
  echo "State space: ", inputTable.len
  echo ""

  # Test 1: Single VBManager creation time - wall clock
  echo "Test 1: VBManager creation time"
  let t1Start = getMonoTime()
  for i in 0..<10:
    var mgr = initVBManager(varList, inputTable)
    let bottomModel = mgr.bottomRefModel
    discard mgr.computeAIC(bottomModel)
  let t1Ms = float64(inNanoseconds(getMonoTime() - t1Start)) / 1_000_000.0 / 10.0
  echo &"  Single VBManager creation + one AIC: {t1Ms:.1f}ms"

  # Test 2: AIC computation only (reuse manager) - wall clock
  var mgr = initVBManager(varList, inputTable)
  let bottomModel = mgr.bottomRefModel

  echo ""
  echo "Test 2: AIC computation (reusing VBManager)"
  let t2Start = getMonoTime()
  for i in 0..<100:
    discard mgr.computeAIC(bottomModel)
  let t2Ms = float64(inNanoseconds(getMonoTime() - t2Start)) / 1_000_000.0 / 100.0
  echo &"  Single AIC computation: {t2Ms:.2f}ms"

  # Test 3: Generate neighbors - wall clock
  echo ""
  echo "Test 3: Neighbor generation + evaluation"
  let search = initLooplessSearch(mgr, 5, 10)
  let t3Start = getMonoTime()
  let neighbors = search.generateNeighbors(bottomModel)
  let t3Gen = float64(inNanoseconds(getMonoTime() - t3Start)) / 1_000_000.0
  echo &"  Generated {neighbors.len} neighbors in {t3Gen:.1f}ms"

  let t3EvalStart = getMonoTime()
  for n in neighbors:
    discard mgr.computeAIC(n)
  let t3Eval = float64(inNanoseconds(getMonoTime() - t3EvalStart)) / 1_000_000.0
  echo &"  Evaluated {neighbors.len} neighbors in {t3Eval:.1f}ms"
  echo &"  Per-neighbor eval time: {t3Eval / float64(neighbors.len):.2f}ms"

  # Test 4: Full seed processing WITH new VBManager - wall clock
  echo ""
  echo "Test 4: Full seed processing comparison"

  # With new manager each time
  let t4NewMgrStart = getMonoTime()
  for i in 0..<5:
    var newMgr = initVBManager(varList, inputTable)
    let newSearch = initLooplessSearch(newMgr, 5, 10)
    let newNeighbors = newSearch.generateNeighbors(bottomModel)
    for n in newNeighbors:
      discard newMgr.computeAIC(n)
  let t4NewMgr = float64(inNanoseconds(getMonoTime() - t4NewMgrStart)) / 1_000_000.0 / 5.0
  echo &"  With NEW VBManager per seed: {t4NewMgr:.1f}ms"

  # Reusing manager
  let t4ReuseMgrStart = getMonoTime()
  for i in 0..<5:
    let reuseSearch = initLooplessSearch(mgr, 5, 10)
    let reuseNeighbors = reuseSearch.generateNeighbors(bottomModel)
    for n in reuseNeighbors:
      discard mgr.computeAIC(n)
  let t4ReuseMgr = float64(inNanoseconds(getMonoTime() - t4ReuseMgrStart)) / 1_000_000.0 / 5.0
  echo &"  REUSING VBManager: {t4ReuseMgr:.1f}ms"

  let overhead = t4NewMgr / t4ReuseMgr
  echo ""
  echo &"  VBManager creation overhead: {overhead:.2f}x"
  echo ""

  # Test 5: Multiple seeds - sequential vs isolated - wall clock
  echo ""
  echo "Test 5: Multiple seeds - cache sharing effect"

  # Get multiple starting seeds (first level of search)
  var seeds: seq[Model] = @[bottomModel]
  let firstSearch = initLooplessSearch(mgr, 5, 10)
  for n in firstSearch.generateNeighbors(bottomModel):
    seeds.add(n)
    if seeds.len >= 5: break

  echo &"  Testing with {seeds.len} seeds"

  # Sequential with shared manager (cache persists)
  let t5SharedStart = getMonoTime()
  for seed in seeds:
    let s = initLooplessSearch(mgr, 5, 10)
    for n in s.generateNeighbors(seed):
      discard mgr.computeAIC(n)
  let t5Shared = float64(inNanoseconds(getMonoTime() - t5SharedStart)) / 1_000_000.0
  echo &"  Sequential (shared cache): {t5Shared:.1f}ms"

  # Sequential with NEW manager each seed (simulates parallel)
  let t5IsolatedStart = getMonoTime()
  for seed in seeds:
    var isolatedMgr = initVBManager(varList, inputTable)
    let s = initLooplessSearch(isolatedMgr, 5, 10)
    for n in s.generateNeighbors(seed):
      discard isolatedMgr.computeAIC(n)
  let t5Isolated = float64(inNanoseconds(getMonoTime() - t5IsolatedStart)) / 1_000_000.0
  echo &"  Isolated (new cache each): {t5Isolated:.1f}ms"

  let cacheEffect = t5Isolated / t5Shared
  echo ""
  echo &"  Cache sharing benefit: {cacheEffect:.2f}x"

  echo ""
  echo "=" .repeat(70)
  echo "CONCLUSION"
  echo "=" .repeat(70)
  echo ""
  if cacheEffect > 1.3:
    echo "Projection caching provides significant benefit."
    echo "Parallel mode loses this benefit (each thread has isolated cache)."
    echo "This explains why parallel is slower than sequential."
  else:
    echo "Cache sharing effect is minimal."
    echo "Bottleneck is likely memory bandwidth or thread synchronization."
  echo ""


when isMainModule:
  main()
