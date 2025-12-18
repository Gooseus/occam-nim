## Benchmark: Parallel Search on Large Prime Dataset
##
## Tests parallelization benefits with real large-scale prime number data.
## Uses the R3-R17 dataset with ~92K state space and ~3M observations.
##
## Run: nim c -r -d:release --threads:on tests/benchmark_primes_parallel.nim

import std/[times, strformat, strutils, cpuinfo, json, os, monotimes]
import std/tables as stdtables
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table as coretable
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/manager/vb
import ../src/occam/search/parallel


proc loadPrimesDataset(filename: string): (VariableList, coretable.Table) =
  ## Load prime dataset JSON into VariableList and Table
  let content = readFile(filename)
  let js = parseJson(content)

  # Build variable list
  var varList = initVariableList()
  for v in js["variables"]:
    let name = v["name"].getStr()
    let abbrev = v["abbrev"].getStr()
    let card = v["cardinality"].getInt()
    let isDep = v["isDependent"].getBool()
    discard varList.add(newVariable(name, abbrev, Cardinality(card), isDep))

  # Build frequency table from data
  # First pass: count frequencies
  var freqMap = stdtables.initTable[Key, float64]()

  for row in js["data"]:
    var k = newKey(varList.keySize)
    for i in 0..<row.len:
      let val = row[i].getInt() - 1  # Convert 1-indexed to 0-indexed
      k.setValue(varList, VariableIndex(i), val)

    if k in freqMap:
      freqMap[k] = freqMap[k] + 1.0
    else:
      freqMap[k] = 1.0

  # Build table from frequencies
  var tbl = coretable.initTable(varList.keySize, freqMap.len)
  for k, count in freqMap:
    tbl.add(k, count)
  tbl.sort()
  tbl.normalize()

  (varList, tbl)


proc formatNum(n: int): string =
  let s = $n
  var formatted = ""
  var count = 0
  for i in countdown(s.len - 1, 0):
    if count > 0 and count mod 3 == 0:
      formatted = "," & formatted
    formatted = s[i] & formatted
    count += 1
  formatted


proc benchmarkDataset(dataFile: string; label: string) =
  if not fileExists(dataFile):
    echo "Dataset not found: ", dataFile
    echo ""
    return

  echo "Loading dataset: ", dataFile
  let loadStart = getMonoTime()
  let (varList, inputTable) = loadPrimesDataset(dataFile)
  let loadTime = (getMonoTime() - loadStart).inMilliseconds.float64 / 1000.0
  echo &"Loaded in {loadTime:.1f}s"
  echo ""

  # Show dataset stats
  var totalStates = 1
  echo "Variables:"
  for i in 0..<varList.len:
    let v = varList[VariableIndex(i)]
    echo &"  {v.name}: cardinality={v.cardinality.toInt}"
    totalStates *= v.cardinality.toInt
  echo ""
  echo "State space: ", formatNum(totalStates)
  echo "Unique states in data: ", formatNum(inputTable.len)
  echo ""

  # Setup search
  var mgr = newVBManager(varList, inputTable)
  let startModel = mgr.bottomRefModel

  echo "Starting model: ", startModel.printName(varList)
  echo ""

  # Warm up
  echo "Warming up..."
  discard parallelSearch(
    varList, inputTable, startModel, SearchLoopless,
    SearchAIC, width = 3, maxLevels = 2, useParallel = false
  )

  # Test different configurations
  echo ""
  echo "SEARCH BENCHMARKS"
  echo ""
  echo "Config                         Width  Levels    Seq(ms)    Par(ms)   Speedup   Models"
  echo "-" .repeat(90)

  for (width, levels) in [(3, 3), (5, 3), (5, 4), (7, 4)]:
    # Sequential timing (wall clock, average of 2 runs)
    let seqStart = getMonoTime()
    var seqResults: seq[SearchCandidate]
    for _ in 1..2:
      seqResults = parallelSearch(
        varList, inputTable, startModel, SearchLoopless,
        SearchAIC, width, levels, useParallel = false
      )
    let seqMs = (getMonoTime() - seqStart).inMilliseconds.float64 / 2.0

    # Parallel timing (wall clock, average of 2 runs)
    let parStart = getMonoTime()
    var parResults: seq[SearchCandidate]
    for _ in 1..2:
      parResults = parallelSearch(
        varList, inputTable, startModel, SearchLoopless,
        SearchAIC, width, levels, useParallel = true
      )
    let parMs = (getMonoTime() - parStart).inMilliseconds.float64 / 2.0

    let speedup = if parMs > 0.1: seqMs / parMs else: 0.0
    let marker = if speedup > 1.1: " <<<" elif speedup > 1.0: " <" else: ""

    echo &"{label:<30} {width:>5} {levels:>7} {seqMs:>10.1f} {parMs:>10.1f} {speedup:>9.2f}x {seqResults.len:>7}{marker}"

  # Show best model found
  echo ""
  echo "Top 5 models by AIC:"
  let finalResults = parallelSearch(
    varList, inputTable, startModel, SearchLoopless,
    SearchAIC, width = 5, maxLevels = 4, useParallel = true
  )

  for i, candidate in finalResults:
    if i >= 5: break
    echo &"  {i+1}. {candidate.name:<40} AIC={candidate.statistic:>12.2f}"
  echo ""


proc main() =
  echo ""
  echo "=" .repeat(90)
  echo "PARALLEL SEARCH BENCHMARK - LARGE PRIME DATASETS"
  echo "=" .repeat(90)
  echo ""
  echo "CPU cores: ", countProcessors()
  echo ""

  # Test R3-R17 dataset (92K states)
  echo "=" .repeat(90)
  echo "DATASET: R3-R17 (~92K state space, ~3M observations)"
  echo "=" .repeat(90)
  echo ""
  benchmarkDataset("data/primes_R3_R17.json", "Loopless (R3-R17)")

  # Test R3-R19 dataset (1.66M states)
  echo "=" .repeat(90)
  echo "DATASET: R3-R19 (~1.66M state space, ~11M observations)"
  echo "=" .repeat(90)
  echo ""
  benchmarkDataset("data/primes_R3_R19.json", "Loopless (R3-R19)")

  echo "=" .repeat(90)
  echo "SUMMARY"
  echo "=" .repeat(90)
  echo ""
  echo "Level-based parallelization using std/threadpool."
  echo "Each seed model is processed in a separate thread."
  echo ""
  echo "Legend: <<< = significant speedup (>1.1x), < = marginal speedup (>1.0x)"
  echo ""
  echo "NOTE: This uses deprecated std/threadpool. For better performance,"
  echo "consider malebolgia which provides ~5x speedup on the same workload."
  echo ""


when isMainModule:
  main()
