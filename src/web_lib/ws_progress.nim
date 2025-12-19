## WebSocket Progress Callback for OCCAM Web Server
##
## Factory for creating progress callbacks that convert ProgressEvents
## to JSON messages and send them via WebSocket.

import std/strformat
import ../occam/core/progress
import ws_messages

type
  WSSendFn* = proc(msg: string) {.gcsafe.}
    ## Function type for sending messages over WebSocket.
    ## Must be gcsafe for use in progress callbacks.


proc makeWSProgressCallback*(requestId: string; sendFn: WSSendFn): ProgressCallback =
  ## Create a progress callback for WebSocket streaming.
  ##
  ## The callback converts ProgressEvents to JSON messages and sends them
  ## via the provided send function.
  ##
  ## Events handled:
  ## - pkSearchStarted → {"type": "progress", "event": "search_started", ...}
  ## - pkSearchLevel → {"type": "progress", "event": "level_complete", ...}
  ## - pkSearchComplete → {"type": "progress", "event": "search_complete", ...}
  ##
  ## Events skipped (too fine-grained for WebSocket):
  ## - pkModelEvaluated
  ## - pkIPFIteration

  result = proc(event: ProgressEvent) {.gcsafe.} =
    {.cast(gcsafe).}:
      case event.kind
      of pkSearchStarted:
        echo "[Progress] Search started - ", event.totalLevels, " levels, stat: ", event.statisticName
        let msg = WSProgressMessage(
          msgType: "progress",
          requestId: requestId,
          event: "search_started",
          data: WSProgressData(
            totalLevels: event.totalLevels,
            statisticName: event.statisticName,
            timestamp: event.timestamp
          )
        )
        sendFn(msg.toJson())

      of pkSearchLevel:
        # Calculate timing in milliseconds
        let levelTimeMs = float64(event.levelTimeNs) / 1_000_000.0
        let elapsedMs = float64(event.elapsedNs) / 1_000_000.0
        let avgModelTimeMs = event.avgModelTimeNs / 1_000_000.0

        # Show loop breakdown and timing in console log
        let levelTotal = event.looplessModels + event.loopModels
        let loopInfo = if event.loopModels > 0:
          $event.looplessModels & " loopless + " & $event.loopModels & " loops (IPF!)"
        elif event.looplessModels > 0:
          $event.looplessModels & " loopless"
        else:
          "0 models"

        echo &"[Progress] Level {event.currentLevel}/{event.totalLevels} - {loopInfo} = {levelTotal} models, {levelTimeMs:.1f}ms (total: {elapsedMs:.1f}ms, avg: {avgModelTimeMs:.2f}ms/model)"
        echo &"           Best: {event.bestModelName}"

        let msg = WSProgressMessage(
          msgType: "progress",
          requestId: requestId,
          event: "level_complete",
          data: WSProgressData(
            currentLevel: event.currentLevel,
            totalLevels: event.totalLevels,
            modelsEvaluated: event.totalModelsEvaluated,
            looplessModels: event.looplessModels,
            loopModels: event.loopModels,
            bestModelName: event.bestModelName,
            bestStatistic: event.bestStatistic,
            statisticName: event.statisticName,
            timestamp: event.timestamp,
            levelTimeMs: levelTimeMs,
            elapsedMs: elapsedMs,
            avgModelTimeMs: avgModelTimeMs
          )
        )
        sendFn(msg.toJson())

      of pkSearchComplete:
        let elapsedMs = float64(event.elapsedNs) / 1_000_000.0
        let avgModelTimeMs = event.avgModelTimeNs / 1_000_000.0
        echo &"[Progress] Search complete - {event.totalModelsEvaluated} models in {elapsedMs:.1f}ms ({avgModelTimeMs:.2f}ms/model)"
        echo &"           Best: {event.bestModelName}"
        let msg = WSProgressMessage(
          msgType: "progress",
          requestId: requestId,
          event: "search_complete",
          data: WSProgressData(
            totalModelsEvaluated: event.totalModelsEvaluated,
            bestModelName: event.bestModelName,
            bestStatistic: event.bestStatistic,
            statisticName: event.statisticName,
            timestamp: event.timestamp,
            elapsedMs: elapsedMs,
            avgModelTimeMs: avgModelTimeMs
          )
        )
        sendFn(msg.toJson())

      of pkModelEvaluated:
        # Skip fine-grained model events - too noisy for WebSocket
        discard

      of pkIPFIteration:
        # IPF iteration progress - show in console and send to client
        echo &"[IPF] iter {event.ipfIteration}/{event.ipfMaxIterations}: error={event.ipfError:.2e}, {event.ipfStateCount} states"
        let msg = WSProgressMessage(
          msgType: "progress",
          requestId: requestId,
          event: "ipf_progress",
          data: WSProgressData(
            ipfIteration: event.ipfIteration,
            ipfMaxIterations: event.ipfMaxIterations,
            ipfError: event.ipfError,
            ipfStateCount: event.ipfStateCount,
            ipfRelationCount: event.ipfRelationCount,
            timestamp: event.timestamp
          )
        )
        sendFn(msg.toJson())
        discard
