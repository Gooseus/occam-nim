## Wall-clock Timing Utilities for OCCAM
##
## Provides accurate timing using std/monotimes (not cpuTime which is misleading
## for parallel workloads). Includes RuntimeEstimator for progress prediction.
##
## Usage:
##   var estimator = initRuntimeEstimator(totalLevels)
##   estimator.start()
##   for level in 1..totalLevels:
##     let levelStart = wallClock()
##     # ... do work ...
##     estimator.recordUnit(elapsedNs(levelStart, wallClock()))
##     echo "ETA: ", estimator.estimateRemainingFormatted()

{.push raises: [].}

import std/[monotimes, times, json, strformat, strutils, algorithm, os, math]

type
  RuntimeEstimator* = object
    ## Estimates remaining runtime based on observed progress.
    ## Uses a sliding window of recent unit times for adaptive estimation.
    startTime: MonoTime
    totalUnits*: int           ## Total work units (levels, models, etc.)
    completedUnits*: int       ## Completed work units
    unitTimesNs: seq[int64]    ## Sliding window of recent unit times
    windowSize: int            ## Size of sliding window

  TimingResult* = object
    ## Result of a timed operation
    name*: string
    wallClockNs*: int64        ## Nanoseconds elapsed
    iterations*: int           ## Number of iterations (if applicable)

  BenchmarkResult* = object
    ## Complete benchmark result for JSON export
    name*: string
    category*: string
    timestamp*: string         ## ISO 8601
    parameters*: JsonNode      ## Input parameters
    medianNs*: int64
    stdDevNs*: float64
    allTimesNs*: seq[int64]
    metadata*: JsonNode        ## System info, etc.


# ============ Basic Timing Utilities ============

proc wallClock*(): MonoTime {.inline.} =
  ## Get current wall-clock time (monotonic, not affected by system time changes)
  getMonoTime()


proc elapsedNs*(start, stop: MonoTime): int64 {.inline.} =
  ## Calculate elapsed nanoseconds between two time points
  (stop - start).inNanoseconds


proc elapsedMs*(start, stop: MonoTime): float64 {.inline.} =
  ## Calculate elapsed milliseconds between two time points
  float64((stop - start).inNanoseconds) / 1_000_000.0


proc formatDuration*(ns: int64): string =
  ## Format nanoseconds as human-readable duration
  ## Examples: "1.23s", "45.6ms", "789us", "12ns"
  if ns < 1_000:
    fmt"{ns}ns"
  elif ns < 1_000_000:
    fmt"{float64(ns) / 1_000:.1f}us"
  elif ns < 1_000_000_000:
    fmt"{float64(ns) / 1_000_000:.1f}ms"
  elif ns < 60_000_000_000:
    fmt"{float64(ns) / 1_000_000_000:.2f}s"
  else:
    let secs = ns div 1_000_000_000
    let mins = secs div 60
    let remainSecs = secs mod 60
    if mins < 60:
      fmt"{mins}m{remainSecs}s"
    else:
      let hours = mins div 60
      let remainMins = mins mod 60
      fmt"{hours}h{remainMins}m{remainSecs}s"


proc formatDurationMs*(ms: float64): string =
  ## Format milliseconds as human-readable duration
  formatDuration(int64(ms * 1_000_000))


# ============ RuntimeEstimator ============

proc initRuntimeEstimator*(totalUnits: int; windowSize: int = 50): RuntimeEstimator =
  ## Initialize a runtime estimator.
  ##
  ## Parameters:
  ##   totalUnits - Total number of work units to complete
  ##   windowSize - Size of sliding window for time averaging (default 50)
  ##
  ## Example:
  ##   var est = initRuntimeEstimator(10)  # 10 levels to complete
  result.totalUnits = totalUnits
  result.completedUnits = 0
  result.windowSize = windowSize
  result.unitTimesNs = newSeqOfCap[int64](windowSize)


proc start*(est: var RuntimeEstimator) =
  ## Start or restart the estimator timer.
  ## Call this when beginning the work.
  est.startTime = getMonoTime()
  est.completedUnits = 0
  est.unitTimesNs.setLen(0)


proc recordUnit*(est: var RuntimeEstimator; elapsedNs: int64) =
  ## Record completion of one work unit with its elapsed time.
  ## Updates the sliding window for estimation.
  ##
  ## Parameters:
  ##   elapsedNs - Time taken for this unit in nanoseconds
  est.completedUnits += 1
  if est.unitTimesNs.len >= est.windowSize:
    # Shift window: remove oldest, add newest
    for i in 0..<est.windowSize - 1:
      est.unitTimesNs[i] = est.unitTimesNs[i + 1]
    est.unitTimesNs[est.windowSize - 1] = elapsedNs
  else:
    est.unitTimesNs.add(elapsedNs)


proc avgUnitTimeNs*(est: RuntimeEstimator): float64 =
  ## Get average time per unit from the sliding window.
  if est.unitTimesNs.len == 0:
    return 0.0
  var total: int64 = 0
  for t in est.unitTimesNs:
    total += t
  float64(total) / float64(est.unitTimesNs.len)


proc estimateRemainingNs*(est: RuntimeEstimator): int64 =
  ## Estimate remaining time in nanoseconds.
  ## Returns 0 if no data available or work is complete.
  let remaining = est.totalUnits - est.completedUnits
  if remaining <= 0 or est.unitTimesNs.len == 0:
    return 0
  int64(float64(remaining) * est.avgUnitTimeNs())


proc estimateRemainingFormatted*(est: RuntimeEstimator): string =
  ## Get estimated remaining time as formatted string.
  ## Returns "calculating..." if insufficient data.
  if est.unitTimesNs.len == 0:
    return "calculating..."
  formatDuration(est.estimateRemainingNs())


proc estimateTotalNs*(est: RuntimeEstimator): int64 =
  ## Estimate total time for all units in nanoseconds.
  if est.unitTimesNs.len == 0:
    return 0
  int64(float64(est.totalUnits) * est.avgUnitTimeNs())


proc percentComplete*(est: RuntimeEstimator): float64 =
  ## Get completion percentage (0.0 to 100.0).
  if est.totalUnits == 0:
    return 100.0
  float64(est.completedUnits) / float64(est.totalUnits) * 100.0


proc elapsedNs*(est: RuntimeEstimator): int64 =
  ## Get total elapsed time since start() was called.
  (getMonoTime() - est.startTime).inNanoseconds


proc elapsedFormatted*(est: RuntimeEstimator): string =
  ## Get elapsed time as formatted string.
  formatDuration(est.elapsedNs())


proc progressString*(est: RuntimeEstimator): string =
  ## Get a complete progress string with elapsed, ETA, and percentage.
  ##
  ## Example: "3/10 (30.0%) - Elapsed: 1.5s - ETA: 3.5s"
  let pct = est.percentComplete()
  let elapsed = est.elapsedFormatted()
  let eta = est.estimateRemainingFormatted()
  fmt"{est.completedUnits}/{est.totalUnits} ({pct:.1f}%) - Elapsed: {elapsed} - ETA: {eta}"


# ============ Benchmark Result Utilities ============

proc initBenchmarkResult*(name: string; category: string = ""): BenchmarkResult =
  ## Initialize a benchmark result with metadata.
  result.name = name
  result.category = category
  result.timestamp = $now()
  result.parameters = newJObject()
  result.metadata = newJObject()
  result.allTimesNs = @[]


proc computeMedian*(times: seq[int64]): int64 =
  ## Compute median of timing values.
  if times.len == 0:
    return 0
  var sorted = times
  sorted.sort()
  sorted[sorted.len div 2]


proc computeStdDev*(times: seq[int64]): float64 =
  ## Compute standard deviation of timing values.
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


proc finalize*(result: var BenchmarkResult) =
  ## Compute median and stdDev from allTimesNs.
  result.medianNs = computeMedian(result.allTimesNs)
  result.stdDevNs = computeStdDev(result.allTimesNs)


proc toJson*(br: BenchmarkResult): JsonNode =
  ## Convert benchmark result to JSON.
  %*{
    "name": br.name,
    "category": br.category,
    "timestamp": br.timestamp,
    "parameters": br.parameters,
    "medianNs": br.medianNs,
    "medianFormatted": formatDuration(br.medianNs),
    "stdDevNs": br.stdDevNs,
    "runCount": br.allTimesNs.len,
    "allTimesNs": br.allTimesNs,
    "metadata": br.metadata
  }


proc saveBenchmarkResults*(results: seq[BenchmarkResult]; filename: string) {.raises: [IOError, OSError].} =
  ## Save benchmark results to a JSON file.
  ## Creates parent directories if needed.
  let dir = parentDir(filename)
  if dir.len > 0 and not dirExists(dir):
    createDir(dir)

  var arr = newJArray()
  for r in results:
    arr.add(r.toJson())

  let output = %*{
    "timestamp": $now(),
    "results": arr
  }

  writeFile(filename, $output)


proc loadBenchmarkResults*(filename: string): seq[BenchmarkResult] {.raises: [IOError, OSError, JsonParsingError, KeyError, ValueError].} =
  ## Load benchmark results from a JSON file.
  if not fileExists(filename):
    return @[]

  let content = readFile(filename)
  let js = parseJson(content)

  result = @[]
  for item in js["results"]:
    var br = BenchmarkResult(
      name: item["name"].getStr(),
      category: item.getOrDefault("category").getStr(""),
      timestamp: item["timestamp"].getStr(),
      medianNs: item["medianNs"].getBiggestInt(),
      stdDevNs: item.getOrDefault("stdDevNs").getFloat(0.0)
    )
    if item.hasKey("parameters"):
      br.parameters = item["parameters"]
    if item.hasKey("metadata"):
      br.metadata = item["metadata"]
    if item.hasKey("allTimesNs"):
      for t in item["allTimesNs"]:
        br.allTimesNs.add(t.getBiggestInt())
    result.add(br)


# ============ Timing Macros/Templates ============

template timeBlock*(name: string; body: untyped): int64 =
  ## Time a block of code and return elapsed nanoseconds.
  ##
  ## Example:
  ##   let elapsed = timeBlock("myOperation"):
  ##     doSomething()
  ##   echo "Took: ", formatDuration(elapsed)
  let startTime = wallClock()
  body
  elapsedNs(startTime, wallClock())


template timeBlockMs*(name: string; body: untyped): float64 =
  ## Time a block of code and return elapsed milliseconds.
  let startTime = wallClock()
  body
  elapsedMs(startTime, wallClock())


# ============ System Info ============

proc getSystemInfo*(): JsonNode =
  ## Get system information for benchmark metadata.
  %*{
    "platform": hostOS,
    "cpuArch": hostCPU,
    "nimVersion": NimVersion,
    "compileTime": CompileDate & " " & CompileTime
  }


# Exports
export RuntimeEstimator, TimingResult, BenchmarkResult
export wallClock, elapsedNs, elapsedMs, formatDuration, formatDurationMs
export initRuntimeEstimator, start, recordUnit, avgUnitTimeNs
export estimateRemainingNs, estimateRemainingFormatted, estimateTotalNs
export percentComplete, elapsedFormatted, progressString
export initBenchmarkResult, computeMedian, computeStdDev, finalize
export toJson, saveBenchmarkResults, loadBenchmarkResults
export timeBlock, timeBlockMs, getSystemInfo
