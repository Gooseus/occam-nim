## Regression Benchmark Suite for OCCAM-Nim
##
## Tracks baseline timings and detects performance degradation.
## Run with: nim c -r -d:release --threads:on tests/benchmark_regression.nim
##
## Usage:
##   ./tests/benchmark_regression            # Run regression tests
##   ./tests/benchmark_regression --update   # Update baselines
##
## Output: benchmarks/regression_YYYYMMDD_HHMMSS.json

import std/[times, monotimes, json, os, strformat, strutils, algorithm, parseopt, math]
import ../src/occam/core/timing
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table as coretable
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/manager/vb
import ../src/occam/search/parallel
import ../src/occam/math/ipf
import ../src/occam/math/entropy

const
  BaselineFile = "benchmarks/baseline.json"
  RegressionThreshold = 1.15  # 15% slower = regression
  WarmupRuns = 3
  BenchmarkRuns = 20


proc makeTestVarList(n: int; cardinality = 3): VariableList =
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


type
  RegressionTest = object
    name: string
    category: string
    warmupRuns: int
    benchmarkRuns: int

  RegressionResult = object
    name: string
    category: string
    medianNs: int64
    baselineNs: int64
    ratio: float64
    isRegression: bool
    allTimesNs: seq[int64]


proc loadBaseline(): JsonNode =
  if fileExists(BaselineFile):
    try:
      parseJson(readFile(BaselineFile))
    except:
      newJObject()
  else:
    newJObject()


proc saveBaseline(results: seq[RegressionResult]) =
  var obj = newJObject()
  obj["timestamp"] = %($now())
  obj["results"] = newJObject()
  for r in results:
    obj["results"][r.name] = %r.medianNs

  createDir("benchmarks")
  writeFile(BaselineFile, pretty(obj))


proc runBenchmark(name: string; warmup, runs: int; baseline: JsonNode;
                  body: proc()): RegressionResult =
  result.name = name
  result.allTimesNs = newSeq[int64](runs)

  # Warmup
  for _ in 0..<warmup:
    body()

  # Benchmark
  for i in 0..<runs:
    let start = getMonoTime()
    body()
    result.allTimesNs[i] = (getMonoTime() - start).inNanoseconds

  result.allTimesNs.sort()
  result.medianNs = result.allTimesNs[runs div 2]

  # Compare to baseline
  if baseline.hasKey("results") and baseline["results"].hasKey(name):
    result.baselineNs = baseline["results"][name].getBiggestInt()
    result.ratio = float64(result.medianNs) / float64(result.baselineNs)
    result.isRegression = result.ratio > RegressionThreshold
  else:
    result.baselineNs = 0
    result.ratio = 0.0
    result.isRegression = false


proc runAllTests(baseline: JsonNode): seq[RegressionResult] =
  result = @[]

  echo "Running regression tests..."
  echo ""

  # Test 1: Table projection (core operation)
  echo "  [1/8] Table projection (729->9)..."
  block:
    let varList = makeTestVarList(6, 3)
    let table = makeRandomTable(varList)

    let r = runBenchmark("projection_729_to_9", WarmupRuns, BenchmarkRuns, baseline) do ():
      for _ in 0..<100:
        discard table.project(varList, @[VariableIndex(0), VariableIndex(3)])

    result.add(r)

  # Test 2: Key operations
  echo "  [2/8] Key operations..."
  block:
    let varList = makeTestVarList(6, 4)
    var k = initKey(varList.keySize)
    for i in 0..<6:
      k.setValue(varList, VariableIndex(i), i mod 4)

    let r = runBenchmark("key_getValue_setValue", WarmupRuns, BenchmarkRuns, baseline) do ():
      var sum = 0
      for _ in 0..<10000:
        for i in 0..<6:
          sum += k.getValue(varList, VariableIndex(i))
          k.setValue(varList, VariableIndex(i), (sum + i) mod 4)
      discard sum

    result.add(r)

  # Test 3: Entropy computation
  echo "  [3/8] Entropy computation..."
  block:
    let varList = makeTestVarList(5, 3)
    let table = makeRandomTable(varList)

    let r = runBenchmark("entropy_243_states", WarmupRuns, BenchmarkRuns, baseline) do ():
      for _ in 0..<100:
        discard entropy(table)

    result.add(r)

  # Test 4: Loopless model fit (BP)
  echo "  [4/8] Loopless model fit (BP)..."
  block:
    let varList = makeTestVarList(5, 3)
    let table = makeRandomTable(varList)
    var mgr = initVBManager(varList, table)

    # Chain model: AB:BC:CD:DE
    let model = mgr.makeModel("AB:BC:CD:DE")

    let r = runBenchmark("fit_loopless_5var_card3", WarmupRuns, BenchmarkRuns, baseline) do ():
      discard mgr.computeAIC(model)

    result.add(r)

  # Test 5: Loop model fit (IPF)
  echo "  [5/8] Loop model fit (IPF)..."
  block:
    let varList = makeTestVarList(4, 3)
    let table = makeRandomTable(varList)
    var mgr = initVBManager(varList, table)

    # Triangle model: AB:BC:AC
    let model = mgr.makeModel("AB:BC:AC")

    let r = runBenchmark("fit_loop_4var_card3", WarmupRuns, BenchmarkRuns, baseline) do ():
      discard mgr.computeAIC(model)

    result.add(r)

  # Test 6: Search level (many models)
  echo "  [6/8] Search level evaluation..."
  block:
    let varList = makeTestVarList(6, 2)
    let table = makeRandomTable(varList)
    var mgr = initVBManager(varList, table)
    let bottomModel = mgr.bottomRefModel()

    let r = runBenchmark("search_level_6var", WarmupRuns, 10, baseline) do ():
      discard searchLevelSequential(
        varList, table, @[bottomModel],
        SearchLoopless, SearchAIC, 5
      )

    result.add(r)

  # Test 7: VBManager creation
  echo "  [7/8] VBManager creation..."
  block:
    let varList = makeTestVarList(6, 3)
    let table = makeRandomTable(varList)

    let r = runBenchmark("vbmanager_creation_6var", WarmupRuns, BenchmarkRuns, baseline) do ():
      var mgr = initVBManager(varList, table)
      discard mgr.bottomRefModel()

    result.add(r)

  # Test 8: Full model statistics
  echo "  [8/8] Full model statistics..."
  block:
    let varList = makeTestVarList(5, 3)
    let table = makeRandomTable(varList)
    var mgr = initVBManager(varList, table)
    let model = mgr.makeModel("AB:BC:CD")

    let r = runBenchmark("full_stats_5var", WarmupRuns, BenchmarkRuns, baseline) do ():
      discard mgr.computeH(model)
      discard mgr.computeDF(model)
      discard mgr.computeLR(model)
      discard mgr.computeAIC(model)
      discard mgr.computeBIC(model)

    result.add(r)


proc printResults(results: seq[RegressionResult]) =
  echo ""
  echo "=" .repeat(80)
  echo "REGRESSION TEST RESULTS"
  echo "=" .repeat(80)
  echo ""

  let col1 = 35
  let col2 = 15
  let col3 = 15
  let col4 = 10

  echo "Test Name".alignLeft(col1) & "Current".center(col2) & "Baseline".center(col3) & "Status".center(col4)
  echo "-" .repeat(80)

  var regressionCount = 0
  var newCount = 0

  for r in results:
    let currentStr = formatDuration(r.medianNs)
    let baselineStr = if r.baselineNs > 0: formatDuration(r.baselineNs) else: "N/A"
    let statusStr = if r.baselineNs == 0:
      newCount += 1
      "NEW"
    elif r.isRegression:
      regressionCount += 1
      fmt"FAIL ({r.ratio:.2f}x)"
    else:
      fmt"OK ({r.ratio:.2f}x)"

    let nameCol = if r.name.len > col1 - 2: r.name[0..<col1-2] else: r.name
    echo nameCol.alignLeft(col1) & currentStr.center(col2) & baselineStr.center(col3) & statusStr.center(col4)

  echo "-" .repeat(80)
  echo ""

  if regressionCount > 0:
    echo fmt"WARNING: {regressionCount} regression(s) detected!"
  elif newCount == results.len:
    echo "All tests are new (no baseline). Run with --update to establish baselines."
  else:
    echo "All tests passed."

  echo ""


proc saveResults(results: seq[RegressionResult]) =
  createDir("benchmarks")
  let timestamp = now().format("yyyyMMdd'_'HHmmss")
  let filename = fmt"benchmarks/regression_{timestamp}.json"

  var arr = newJArray()
  for r in results:
    arr.add(%*{
      "name": r.name,
      "category": r.category,
      "medianNs": r.medianNs,
      "medianFormatted": formatDuration(r.medianNs),
      "baselineNs": r.baselineNs,
      "ratio": r.ratio,
      "isRegression": r.isRegression,
      "allTimesNs": r.allTimesNs
    })

  let output = %*{
    "timestamp": $now(),
    "regressionThreshold": RegressionThreshold,
    "results": arr
  }

  writeFile(filename, pretty(output))
  echo fmt"Results saved to: {filename}"


proc main() =
  var updateBaseline = false

  # Parse command line
  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      if p.key == "update" or p.key == "u":
        updateBaseline = true
    of cmdArgument:
      discard

  echo ""
  echo "=" .repeat(80)
  echo "REGRESSION BENCHMARK SUITE"
  echo "=" .repeat(80)
  echo ""
  echo fmt"Warmup: {WarmupRuns} runs, Benchmark: {BenchmarkRuns} runs"
  let thresholdPct = int(round((RegressionThreshold - 1.0) * 100.0))
  echo fmt"Regression threshold: {thresholdPct}% slower"
  echo ""

  let baseline = loadBaseline()
  if baseline.hasKey("timestamp"):
    let baselineTime = baseline["timestamp"].getStr()
    echo fmt"Baseline from: {baselineTime}"
  else:
    echo "No baseline found. Run with --update to establish baselines."
  echo ""

  let results = runAllTests(baseline)
  printResults(results)
  saveResults(results)

  if updateBaseline:
    saveBaseline(results)
    echo fmt"Baseline updated: {BaselineFile}"
    echo ""

  # Exit with error code if regressions detected
  var hasRegression = false
  for r in results:
    if r.isRegression:
      hasRegression = true
      break

  if hasRegression:
    quit(1)


when isMainModule:
  main()
