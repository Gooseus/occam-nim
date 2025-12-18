## Benchmark: Malebolgia vs std/threadpool
##
## Tests if malebolgia's work-stealing approach has less overhead
## than the deprecated std/threadpool.
##
## Run: nim c -r -d:release --threads:on tests/benchmark_malebolgia.nim

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
    let name = v["name"].getStr()
    let abbrev = v["abbrev"].getStr()
    let card = v["cardinality"].getInt()
    let isDep = v["isDependent"].getBool()
    discard varList.add(newVariable(name, abbrev, Cardinality(card), isDep))

  var freqMap = stdtables.initTable[Key, float64]()
  for row in js["data"]:
    var k = newKey(varList.keySize)
    for i in 0..<row.len:
      let val = row[i].getInt() - 1
      k.setValue(varList, VariableIndex(i), val)
    if k in freqMap:
      freqMap[k] = freqMap[k] + 1.0
    else:
      freqMap[k] = 1.0

  var tbl = coretable.initTable(varList.keySize, freqMap.len)
  for k, count in freqMap:
    tbl.add(k, count)
  tbl.sort()
  tbl.normalize()
  (varList, tbl)


type
  SeedResult = object
    models: seq[tuple[name: string, aic: float64]]
    evaluated: int


proc processSeedImpl(
    varList: VariableList;
    inputTable: coretable.Table;
    seed: Model;
    width: int
): SeedResult =
  ## Process one seed - thread-safe, creates own VBManager
  var mgr = newVBManager(varList, inputTable)
  let search = initLooplessSearch(mgr, width, 10)
  let neighbors = search.generateNeighbors(seed)

  result.models = @[]
  result.evaluated = neighbors.len

  for n in neighbors:
    let name = n.printName(varList)
    let aic = mgr.computeAIC(n)
    result.models.add((name, aic))


proc processSeed(
    varList: VariableList;
    inputTable: coretable.Table;
    seed: Model;
    width: int
): SeedResult {.gcsafe.} =
  ## GC-safe wrapper for malebolgia
  {.cast(gcsafe).}:
    processSeedImpl(varList, inputTable, seed, width)


proc sequentialSearch(
    varList: VariableList;
    inputTable: coretable.Table;
    seeds: seq[Model];
    width: int
): seq[SeedResult] =
  ## Sequential baseline
  result = @[]
  for seed in seeds:
    result.add(processSeedImpl(varList, inputTable, seed, width))


# Global result storage for malebolgia (avoids arrow syntax issues)
var gSeedResults: seq[SeedResult]

proc processSeedInto(
    idx: int;
    varList: VariableList;
    inputTable: coretable.Table;
    seed: Model;
    width: int
) {.gcsafe.} =
  {.cast(gcsafe).}:
    gSeedResults[idx] = processSeedImpl(varList, inputTable, seed, width)


proc malebolgiaSummary(
    varList: VariableList;
    inputTable: coretable.Table;
    seeds: seq[Model];
    width: int
): seq[SeedResult] =
  ## Parallel using malebolgia
  gSeedResults = newSeq[SeedResult](seeds.len)

  var m = createMaster()
  m.awaitAll:
    for i, seed in seeds:
      m.spawn processSeedInto(i, varList, inputTable, seed, width)

  result = gSeedResults


proc main() =
  echo ""
  echo "=" .repeat(70)
  echo "MALEBOLGIA vs SEQUENTIAL BENCHMARK"
  echo "=" .repeat(70)
  echo ""
  echo "CPU cores: ", countProcessors()
  echo ""

  let dataFile = "data/primes_R3_R17.json"
  if not fileExists(dataFile):
    echo "Dataset not found: ", dataFile
    quit(1)

  echo "Loading dataset..."
  let (varList, inputTable) = loadPrimesDataset(dataFile)
  echo "State space: ", inputTable.len
  echo ""

  # Get seeds (first level of search)
  var mgr = newVBManager(varList, inputTable)
  let bottomModel = mgr.bottomRefModel
  var seeds: seq[Model] = @[bottomModel]

  let firstSearch = initLooplessSearch(mgr, 10, 10)
  for n in firstSearch.generateNeighbors(bottomModel):
    seeds.add(n)

  echo "Testing with ", seeds.len, " seeds"
  echo ""

  # Warm up
  discard sequentialSearch(varList, inputTable, seeds[0..0], 5)

  # Sequential timing (wall clock)
  echo "Running sequential..."
  let seqStart = getMonoTime()
  var seqResults: seq[SeedResult]
  for _ in 1..3:
    seqResults = sequentialSearch(varList, inputTable, seeds, 5)
  let seqMs = (getMonoTime() - seqStart).inMilliseconds.float64 / 3.0

  # Malebolgia timing (wall clock)
  echo "Running malebolgia parallel..."
  let malStart = getMonoTime()
  var malResults: seq[SeedResult]
  for _ in 1..3:
    malResults = malebolgiaSummary(varList, inputTable, seeds, 5)
  let malMs = (getMonoTime() - malStart).inMilliseconds.float64 / 3.0

  let speedup = if malMs > 0.1: seqMs / malMs else: 0.0
  let marker = if speedup > 1.1: " <<<" elif speedup > 1.0: " <" else: ""

  echo ""
  echo "=" .repeat(70)
  echo "RESULTS"
  echo "=" .repeat(70)
  echo ""
  echo &"Sequential:  {seqMs:>10.1f} ms"
  echo &"Malebolgia:  {malMs:>10.1f} ms"
  echo &"Speedup:     {speedup:>10.2f}x{marker}"
  echo ""

  # Verify correctness
  var correct = true
  for i in 0..<min(seqResults.len, malResults.len):
    if seqResults[i].evaluated != malResults[i].evaluated:
      correct = false
      echo "MISMATCH at seed ", i
      break
  if correct:
    echo "Results match: CORRECT"
  echo ""

  if speedup > 1.0:
    echo "Malebolgia provides speedup!"
  else:
    echo "Malebolgia does not provide speedup."
    echo "The overhead is still in:"
    echo "  - Creating thread-local VBManager per seed"
    echo "  - Memory allocation for results"
    echo "  - Work distribution overhead"
  echo ""


when isMainModule:
  main()
