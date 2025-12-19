## Progress Reporting Module
##
## Provides a callback-based mechanism for reporting progress during
## long-running operations like model search and IPF iterations.
##
## Usage:
##   var callCount = 0
##   let config = initProgressConfig(
##     callback = proc(e: ProgressEvent) {.gcsafe.} =
##       echo "Level ", e.currentLevel, "/", e.totalLevels
##   )
##   config.emit(makeSearchStartEvent(7, "BIC"))

import std/times

type
  ProgressKind* = enum
    ## Type of progress event
    pkSearchStarted    ## Search operation has started
    pkSearchLevel      ## A search level has been completed
    pkModelEvaluated   ## Models evaluated (batch update, optional)
    pkIPFIteration     ## IPF iteration completed (optional)
    pkSearchComplete   ## Search has finished

  ProgressEvent* = object
    ## A progress event emitted during long-running operations
    kind*: ProgressKind
    timestamp*: float64

    # Search context
    currentLevel*: int
    totalLevels*: int
    modelsEvaluated*: int        ## Models in current batch
    modelsInLevel*: int          ## Total models in current level
    totalModelsEvaluated*: int   ## Cumulative count

    # Loop/loopless breakdown (critical for understanding performance!)
    looplessModels*: int         ## Models without loops (fast BP)
    loopModels*: int             ## Models with loops (slow IPF)
    currentModelName*: string    ## Model currently being evaluated (for IPF progress)

    # Best result info
    bestModelName*: string
    bestStatistic*: float64
    statisticName*: string       ## "BIC", "AIC", "DDF"

    # IPF context (for pkIPFIteration)
    ipfIteration*: int
    ipfMaxIterations*: int
    ipfError*: float64
    ipfConverged*: bool
    ipfModelName*: string        ## Which model is running IPF
    ipfStateCount*: int          ## Number of states in fit table
    ipfRelationCount*: int       ## Number of relations in model

    # Timing and ETA (for runtime estimation)
    elapsedNs*: int64            ## Time elapsed since search started
    estimatedRemainingNs*: int64 ## Estimated time remaining
    estimatedTotalNs*: int64     ## Estimated total time
    avgModelTimeNs*: float64     ## Average time per model evaluation
    levelTimeNs*: int64          ## Time for current level
    cacheHitRate*: float64       ## Cache hit rate (0.0 to 1.0)

    # General message
    message*: string

  ProgressCallback* = proc(event: ProgressEvent) {.gcsafe, closure.}
    ## Callback type for receiving progress events.
    ## Must be gcsafe for thread safety.

  ProgressConfig* = object
    ## Configuration for progress reporting
    callback*: ProgressCallback
    reportInterval*: int         ## Report every N models (0 = level-only)
    reportIPFInterval*: int      ## Report every N IPF iterations (0 = off)
    enabled*: bool


proc initProgressConfig*(
    callback: ProgressCallback = nil;
    reportInterval: int = 0;
    reportIPFInterval: int = 0
): ProgressConfig =
  ## Create a progress configuration.
  ##
  ## Parameters:
  ##   callback - Function to receive progress events (nil = disabled)
  ##   reportInterval - Report every N models (0 = level boundaries only)
  ##   reportIPFInterval - Report every N IPF iterations (0 = off)
  ##
  ## Example:
  ##   let config = initProgressConfig(
  ##     callback = proc(e: ProgressEvent) {.gcsafe.} =
  ##       echo "Progress: ", e.currentLevel, "/", e.totalLevels
  ##   )
  result = ProgressConfig(
    callback: callback,
    reportInterval: reportInterval,
    reportIPFInterval: reportIPFInterval,
    enabled: callback != nil
  )


proc emit*(config: ProgressConfig; event: ProgressEvent) {.inline.} =
  ## Emit a progress event if a callback is registered and enabled.
  ##
  ## This is designed to have minimal overhead when disabled:
  ## just a boolean check.
  if config.enabled and config.callback != nil:
    config.callback(event)


proc makeSearchStartEvent*(totalLevels: int; statName: string): ProgressEvent =
  ## Create a search started event.
  ##
  ## Example:
  ##   let event = makeSearchStartEvent(7, "BIC")
  ProgressEvent(
    kind: pkSearchStarted,
    timestamp: epochTime(),
    totalLevels: totalLevels,
    statisticName: statName
  )


proc makeLevelEvent*(
    level: int;
    totalLevels: int;
    modelsEvaluated: int;
    bestName: string;
    bestStat: float64;
    statName: string
): ProgressEvent =
  ## Create a level completed event.
  ##
  ## Example:
  ##   let event = makeLevelEvent(3, 7, 45, "AB:BC", -23.5, "BIC")
  ProgressEvent(
    kind: pkSearchLevel,
    timestamp: epochTime(),
    currentLevel: level,
    totalLevels: totalLevels,
    totalModelsEvaluated: modelsEvaluated,
    bestModelName: bestName,
    bestStatistic: bestStat,
    statisticName: statName
  )


proc makeLevelEventWithTiming*(
    level: int;
    totalLevels: int;
    modelsEvaluated: int;
    bestName: string;
    bestStat: float64;
    statName: string;
    elapsedNs: int64;
    estimatedRemainingNs: int64;
    levelTimeNs: int64;
    avgModelTimeNs: float64;
    cacheHitRate: float64;
    looplessCount: int = 0;
    loopCount: int = 0
): ProgressEvent =
  ## Create a level completed event with timing, ETA, and loop breakdown.
  ##
  ## Example:
  ##   let event = makeLevelEventWithTiming(3, 7, 45, "AB:BC", -23.5, "BIC",
  ##                                        5_000_000_000, 10_000_000_000,
  ##                                        1_500_000_000, 33_000_000.0, 0.85,
  ##                                        40, 5)  # 40 loopless, 5 loops
  ProgressEvent(
    kind: pkSearchLevel,
    timestamp: epochTime(),
    currentLevel: level,
    totalLevels: totalLevels,
    totalModelsEvaluated: modelsEvaluated,
    looplessModels: looplessCount,
    loopModels: loopCount,
    bestModelName: bestName,
    bestStatistic: bestStat,
    statisticName: statName,
    elapsedNs: elapsedNs,
    estimatedRemainingNs: estimatedRemainingNs,
    estimatedTotalNs: elapsedNs + estimatedRemainingNs,
    levelTimeNs: levelTimeNs,
    avgModelTimeNs: avgModelTimeNs,
    cacheHitRate: cacheHitRate
  )


proc makeLevelEventWithLoops*(
    level: int;
    totalLevels: int;
    modelsEvaluated: int;
    looplessModels: int;
    loopModels: int;
    bestName: string;
    bestStat: float64;
    statName: string;
    elapsedNs: int64 = 0;
    levelTimeNs: int64 = 0
): ProgressEvent =
  ## Create a level completed event with loop/loopless breakdown.
  ##
  ## This is critical for understanding why searches are slow -
  ## loop models require IPF which is 100-1000x slower than BP.
  ##
  ## Example:
  ##   let event = makeLevelEventWithLoops(3, 7, 45, 40, 5, "AB:BC", -23.5, "BIC")
  ##   # Shows: Level 3/7: 45 models (40 loopless, 5 loops)
  ProgressEvent(
    kind: pkSearchLevel,
    timestamp: epochTime(),
    currentLevel: level,
    totalLevels: totalLevels,
    totalModelsEvaluated: modelsEvaluated,
    looplessModels: looplessModels,
    loopModels: loopModels,
    bestModelName: bestName,
    bestStatistic: bestStat,
    statisticName: statName,
    elapsedNs: elapsedNs,
    levelTimeNs: levelTimeNs
  )


proc makeModelBatchEvent*(
    modelsEvaluated: int;
    modelsInLevel: int;
    totalEvaluated: int
): ProgressEvent =
  ## Create a model batch progress event.
  ##
  ## Used for fine-grained progress when reportInterval > 0.
  ProgressEvent(
    kind: pkModelEvaluated,
    timestamp: epochTime(),
    modelsEvaluated: modelsEvaluated,
    modelsInLevel: modelsInLevel,
    totalModelsEvaluated: totalEvaluated
  )


proc makeIPFProgressEvent*(
    modelName: string;
    iteration: int;
    maxIterations: int;
    error: float64;
    converged: bool;
    stateCount: int = 0;
    relationCount: int = 0
): ProgressEvent =
  ## Create an IPF iteration event with model context.
  ##
  ## Emitted during long-running IPF to show progress.
  ##
  ## Example:
  ##   let event = makeIPFProgressEvent("AB:BC:AC", 50, 1000, 1.5e-5, false, 21600, 9)
  ##   # Shows: IPF on AB:BC:AC: iter 50/1000, error=1.5e-5, 21600 states
  ProgressEvent(
    kind: pkIPFIteration,
    timestamp: epochTime(),
    ipfModelName: modelName,
    ipfIteration: iteration,
    ipfMaxIterations: maxIterations,
    ipfError: error,
    ipfConverged: converged,
    ipfStateCount: stateCount,
    ipfRelationCount: relationCount
  )


proc makeIPFEvent*(
    iteration: int;
    maxIterations: int;
    error: float64;
    converged: bool;
    stateCount: int = 0;
    relationCount: int = 0
): ProgressEvent =
  ## Create an IPF iteration event.
  ##
  ## Example:
  ##   let event = makeIPFEvent(10, 1000, 1.5e-9, false, 21600, 9)
  ProgressEvent(
    kind: pkIPFIteration,
    timestamp: epochTime(),
    ipfIteration: iteration,
    ipfMaxIterations: maxIterations,
    ipfError: error,
    ipfConverged: converged,
    ipfStateCount: stateCount,
    ipfRelationCount: relationCount
  )


proc makeCompleteEvent*(
    totalModels: int;
    bestName: string;
    bestStat: float64;
    statName: string
): ProgressEvent =
  ## Create a search completed event.
  ##
  ## Example:
  ##   let event = makeCompleteEvent(127, "AB:BC", -28.7, "BIC")
  ProgressEvent(
    kind: pkSearchComplete,
    timestamp: epochTime(),
    totalModelsEvaluated: totalModels,
    bestModelName: bestName,
    bestStatistic: bestStat,
    statisticName: statName
  )


proc makeCompleteEventWithTiming*(
    totalModels: int;
    bestName: string;
    bestStat: float64;
    statName: string;
    totalTimeNs: int64;
    avgModelTimeNs: float64;
    cacheHitRate: float64
): ProgressEvent =
  ## Create a search completed event with timing summary.
  ##
  ## Example:
  ##   let event = makeCompleteEventWithTiming(127, "AB:BC", -28.7, "BIC",
  ##                                           15_000_000_000, 118_000_000.0, 0.82)
  ProgressEvent(
    kind: pkSearchComplete,
    timestamp: epochTime(),
    totalModelsEvaluated: totalModels,
    bestModelName: bestName,
    bestStatistic: bestStat,
    statisticName: statName,
    elapsedNs: totalTimeNs,
    estimatedRemainingNs: 0,
    estimatedTotalNs: totalTimeNs,
    avgModelTimeNs: avgModelTimeNs,
    cacheHitRate: cacheHitRate
  )
