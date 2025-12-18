## CLI Progress Handler
##
## Provides progress output for CLI commands.
## Writes progress updates to stdout with formatting.

import std/[strformat, terminal]
import ../occam/core/progress

proc makeCLIProgressCallback*(verbose = true): ProgressCallback =
  ## Create a progress callback for CLI output.
  ##
  ## When verbose=true, shows detailed updates.
  ## When verbose=false, shows minimal progress.
  ##
  ## Example:
  ##   let config = initProgressConfig(callback = makeCLIProgressCallback())
  ##   parallelSearch(..., progress = config)

  result = proc(event: ProgressEvent) {.gcsafe.} =
    {.cast(gcsafe).}:
      case event.kind
      of pkSearchStarted:
        if verbose:
          echo &"Starting search (max {event.totalLevels} levels, optimizing {event.statisticName})..."
          echo ""

      of pkSearchLevel:
        let msg = &"  Level {event.currentLevel}/{event.totalLevels}: " &
                  &"Evaluated {event.totalModelsEvaluated} models"
        if event.bestModelName != "":
          echo &"{msg}, best {event.statisticName}={event.bestStatistic:.4f} ({event.bestModelName})"
        else:
          echo msg

      of pkModelEvaluated:
        # Fine-grained progress - only show if verbose
        if verbose:
          stdout.write(&"\r  Models: {event.modelsEvaluated}/{event.modelsInLevel}")
          stdout.flushFile()

      of pkIPFIteration:
        if verbose:
          let status = if event.ipfConverged: "converged" else: "iterating"
          echo &"    IPF iter {event.ipfIteration}/{event.ipfMaxIterations}: error={event.ipfError:.2e} ({status})"

      of pkSearchComplete:
        echo ""
        echo &"Search complete: {event.totalModelsEvaluated} models evaluated"
        if event.bestModelName != "":
          echo &"Best model: {event.bestModelName} ({event.statisticName}={event.bestStatistic:.4f})"
