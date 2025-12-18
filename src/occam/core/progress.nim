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

    # Best result info
    bestModelName*: string
    bestStatistic*: float64
    statisticName*: string       ## "BIC", "AIC", "DDF"

    # IPF context (for pkIPFIteration)
    ipfIteration*: int
    ipfMaxIterations*: int
    ipfError*: float64
    ipfConverged*: bool

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


proc makeIPFEvent*(
    iteration: int;
    maxIterations: int;
    error: float64;
    converged: bool
): ProgressEvent =
  ## Create an IPF iteration event.
  ##
  ## Example:
  ##   let event = makeIPFEvent(10, 1000, 1.5e-9, false)
  ProgressEvent(
    kind: pkIPFIteration,
    timestamp: epochTime(),
    ipfIteration: iteration,
    ipfMaxIterations: maxIterations,
    ipfError: error,
    ipfConverged: converged
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
