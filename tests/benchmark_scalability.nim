## Scalability Benchmark Suite for OCCAM-Nim
##
## Systematically varies input parameters to derive empirical runtime models.
## Run with: nim c -r -d:release --threads:on tests/benchmark_scalability.nim
##
## Output: benchmarks/scalability_YYYYMMDD_HHMMSS.json

import std/[times, monotimes, json, os, strformat, strutils, math, algorithm]
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

const
  RunsPerPoint = 5


type
  ScalabilityDimension* = enum
    sdVariables     # Number of variables
    sdCardinality   # Variable cardinality
    sdSearchWidth   # Search beam width
    sdSearchLevels  # Search depth
    sdModelType     # Loopless vs Loop

  ScalabilityPoint* = object
    dimension*: ScalabilityDimension
    paramValue*: int
    paramName*: string
    medianTimeNs*: int64
    stdDevNs*: float64
    allTimesNs*: seq[int64]
    modelsEvaluated*: int
    stateSpace*: int

  ScalabilitySeries* = object
    dimension*: ScalabilityDimension
    dimensionName*: string
    baseParams*: JsonNode
    points*: seq[ScalabilityPoint]


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


proc computeStdDev(times: seq[int64]): float64 =
  if times.len < 2:
    return 0.0
  var sum: int64 = 0
  for t in times:
    sum += t
  let mean = float64(sum) / float64(times.len)
  var sumSqDiff = 0.0
  for t in times:
    let diff = float64(t) - mean
    sumSqDiff += diff * diff
  sqrt(sumSqDiff / float64(times.len - 1))


proc stateSpace(numVars, cardinality: int): int =
  var result = 1
  for _ in 0..<numVars:
    result *= cardinality
  result


# ============ Scalability Tests ============

proc benchmarkByVariables(): ScalabilitySeries =
  ## How does runtime scale with number of variables?
  result.dimension = sdVariables
  result.dimensionName = "variables"
  result.baseParams = %*{"cardinality": 3, "width": 3}
  result.points = @[]

  echo "  Scaling by variables (card=3, width=3):"

  for numVars in 3..10:
    let ss = stateSpace(numVars, 3)
    if ss > 100000:
      break  # Skip very large state spaces

    echo fmt"    Variables: {numVars} (state space: {ss})..."

    let varList = makeTestVarList(numVars, 3)
    let table = makeRandomTable(varList)

    var times: seq[int64]
    var totalModels = 0

    for run in 0..<RunsPerPoint:
      var mgr = initVBManager(varList, table)
      let bottomModel = mgr.bottomRefModel()

      let start = getMonoTime()
      let (_, count) = searchLevelSequential(
        varList, table, @[bottomModel],
        SearchLoopless, SearchAIC, 3
      )
      times.add((getMonoTime() - start).inNanoseconds)
      totalModels = count

    times.sort()
    let median = times[RunsPerPoint div 2]

    result.points.add(ScalabilityPoint(
      dimension: sdVariables,
      paramValue: numVars,
      paramName: fmt"{numVars} vars",
      medianTimeNs: median,
      stdDevNs: computeStdDev(times),
      allTimesNs: times,
      modelsEvaluated: totalModels,
      stateSpace: ss
    ))


proc benchmarkByCardinality(): ScalabilitySeries =
  ## How does runtime scale with cardinality?
  result.dimension = sdCardinality
  result.dimensionName = "cardinality"
  result.baseParams = %*{"variables": 5, "width": 3}
  result.points = @[]

  echo "  Scaling by cardinality (vars=5, width=3):"

  for cardinality in 2..6:
    let ss = stateSpace(5, cardinality)
    echo fmt"    Cardinality: {cardinality} (state space: {ss})..."

    let varList = makeTestVarList(5, cardinality)
    let table = makeRandomTable(varList)

    var times: seq[int64]
    var totalModels = 0

    for run in 0..<RunsPerPoint:
      var mgr = initVBManager(varList, table)
      let bottomModel = mgr.bottomRefModel()

      let start = getMonoTime()
      let (_, count) = searchLevelSequential(
        varList, table, @[bottomModel],
        SearchLoopless, SearchAIC, 3
      )
      times.add((getMonoTime() - start).inNanoseconds)
      totalModels = count

    times.sort()
    let median = times[RunsPerPoint div 2]

    result.points.add(ScalabilityPoint(
      dimension: sdCardinality,
      paramValue: cardinality,
      paramName: fmt"card={cardinality}",
      medianTimeNs: median,
      stdDevNs: computeStdDev(times),
      allTimesNs: times,
      modelsEvaluated: totalModels,
      stateSpace: ss
    ))


proc benchmarkBySearchWidth(): ScalabilitySeries =
  ## How does runtime scale with search width?
  result.dimension = sdSearchWidth
  result.dimensionName = "searchWidth"
  result.baseParams = %*{"variables": 6, "cardinality": 2, "levels": 3}
  result.points = @[]

  echo "  Scaling by search width (vars=6, card=2, levels=3):"

  let varList = makeTestVarList(6, 2)
  let table = makeRandomTable(varList)

  for width in [1, 2, 3, 5, 7, 10]:
    echo fmt"    Width: {width}..."

    var times: seq[int64]
    var totalModels = 0

    for run in 0..<RunsPerPoint:
      var mgr = initVBManager(varList, table)
      let bottomModel = mgr.bottomRefModel()

      let start = getMonoTime()
      let candidates = parallelSearch(
        varList, table, bottomModel,
        SearchLoopless, SearchAIC, width, 3,
        useParallel = false
      )
      times.add((getMonoTime() - start).inNanoseconds)
      totalModels = candidates.len

    times.sort()
    let median = times[RunsPerPoint div 2]

    result.points.add(ScalabilityPoint(
      dimension: sdSearchWidth,
      paramValue: width,
      paramName: fmt"width={width}",
      medianTimeNs: median,
      stdDevNs: computeStdDev(times),
      allTimesNs: times,
      modelsEvaluated: totalModels,
      stateSpace: stateSpace(6, 2)
    ))


proc benchmarkBySearchLevels(): ScalabilitySeries =
  ## How does runtime scale with search depth?
  result.dimension = sdSearchLevels
  result.dimensionName = "searchLevels"
  result.baseParams = %*{"variables": 6, "cardinality": 2, "width": 3}
  result.points = @[]

  echo "  Scaling by search levels (vars=6, card=2, width=3):"

  let varList = makeTestVarList(6, 2)
  let table = makeRandomTable(varList)

  for levels in 1..7:
    echo fmt"    Levels: {levels}..."

    var times: seq[int64]
    var totalModels = 0

    for run in 0..<RunsPerPoint:
      var mgr = initVBManager(varList, table)
      let bottomModel = mgr.bottomRefModel()

      let start = getMonoTime()
      let candidates = parallelSearch(
        varList, table, bottomModel,
        SearchLoopless, SearchAIC, 3, levels,
        useParallel = false
      )
      times.add((getMonoTime() - start).inNanoseconds)
      totalModels = candidates.len

    times.sort()
    let median = times[RunsPerPoint div 2]

    result.points.add(ScalabilityPoint(
      dimension: sdSearchLevels,
      paramValue: levels,
      paramName: fmt"L={levels}",
      medianTimeNs: median,
      stdDevNs: computeStdDev(times),
      allTimesNs: times,
      modelsEvaluated: totalModels,
      stateSpace: stateSpace(6, 2)
    ))


proc benchmarkLoopVsLoopless(): ScalabilitySeries =
  ## Compare loop vs loopless model fitting times
  result.dimension = sdModelType
  result.dimensionName = "modelType"
  result.baseParams = %*{"cardinality": 3}
  result.points = @[]

  echo "  Loop vs Loopless comparison (card=3):"

  for numVars in 3..6:
    let ss = stateSpace(numVars, 3)
    echo fmt"    {numVars} variables (state space: {ss})..."

    let varList = makeTestVarList(numVars, 3)
    let table = makeRandomTable(varList)
    var mgr = initVBManager(varList, table)

    # Build chain model name (loopless)
    var chainParts: seq[string]
    for i in 0..<(numVars - 1):
      chainParts.add($chr(ord('A') + i) & $chr(ord('A') + i + 1))
    let chainName = chainParts.join(":")
    let looplessModel = mgr.makeModel(chainName)

    # Build triangle model (loop) - first 3 variables form triangle
    let loopName = chainName & ":A" & $chr(ord('A') + numVars - 1)
    let loopModel = mgr.makeModel(loopName)

    # Benchmark loopless
    var looplessTimes: seq[int64]
    for _ in 0..<RunsPerPoint:
      let start = getMonoTime()
      discard mgr.computeAIC(looplessModel)
      looplessTimes.add((getMonoTime() - start).inNanoseconds)

    looplessTimes.sort()
    result.points.add(ScalabilityPoint(
      dimension: sdModelType,
      paramValue: numVars,
      paramName: fmt"{numVars}v loopless",
      medianTimeNs: looplessTimes[RunsPerPoint div 2],
      stdDevNs: computeStdDev(looplessTimes),
      allTimesNs: looplessTimes,
      stateSpace: ss
    ))

    # Benchmark loop
    var loopTimes: seq[int64]
    for _ in 0..<RunsPerPoint:
      let start = getMonoTime()
      discard mgr.computeAIC(loopModel)
      loopTimes.add((getMonoTime() - start).inNanoseconds)

    loopTimes.sort()
    result.points.add(ScalabilityPoint(
      dimension: sdModelType,
      paramValue: numVars,
      paramName: fmt"{numVars}v loop",
      medianTimeNs: loopTimes[RunsPerPoint div 2],
      stdDevNs: computeStdDev(loopTimes),
      allTimesNs: loopTimes,
      stateSpace: ss
    ))


proc toJson(series: ScalabilitySeries): JsonNode =
  var points = newJArray()
  for p in series.points:
    points.add(%*{
      "paramValue": p.paramValue,
      "paramName": p.paramName,
      "medianTimeNs": p.medianTimeNs,
      "medianFormatted": formatDuration(p.medianTimeNs),
      "stdDevNs": p.stdDevNs,
      "modelsEvaluated": p.modelsEvaluated,
      "stateSpace": p.stateSpace
    })

  %*{
    "dimension": $series.dimension,
    "dimensionName": series.dimensionName,
    "baseParams": series.baseParams,
    "points": points
  }


proc printSummary(series: seq[ScalabilitySeries]) =
  echo ""
  echo "=" .repeat(80)
  echo "SCALABILITY SUMMARY"
  echo "=" .repeat(80)
  echo ""

  for s in series:
    echo fmt"  {s.dimensionName}:"
    for p in s.points:
      let timeStr = formatDuration(p.medianTimeNs)
      let modelsStr = if p.modelsEvaluated > 0: fmt" ({p.modelsEvaluated} models)" else: ""
      echo fmt"    {p.paramName}: {timeStr}{modelsStr}"
    echo ""


proc main() =
  echo ""
  echo "=" .repeat(80)
  echo "SCALABILITY BENCHMARK SUITE"
  echo "=" .repeat(80)
  echo ""
  echo fmt"Runs per data point: {RunsPerPoint}"
  echo ""

  var allSeries: seq[ScalabilitySeries]

  echo "1. Scaling by number of variables..."
  allSeries.add(benchmarkByVariables())

  echo ""
  echo "2. Scaling by cardinality..."
  allSeries.add(benchmarkByCardinality())

  echo ""
  echo "3. Scaling by search width..."
  allSeries.add(benchmarkBySearchWidth())

  echo ""
  echo "4. Scaling by search levels..."
  allSeries.add(benchmarkBySearchLevels())

  echo ""
  echo "5. Loop vs Loopless comparison..."
  allSeries.add(benchmarkLoopVsLoopless())

  printSummary(allSeries)

  # Save results
  createDir("benchmarks")
  let timestamp = now().format("yyyyMMdd'_'HHmmss")
  let filename = fmt"benchmarks/scalability_{timestamp}.json"

  var seriesJson = newJArray()
  for s in allSeries:
    seriesJson.add(s.toJson())

  let output = %*{
    "timestamp": $now(),
    "runsPerPoint": RunsPerPoint,
    "series": seriesJson
  }

  writeFile(filename, pretty(output))
  echo fmt"Results saved to: {filename}"
  echo ""


when isMainModule:
  main()
