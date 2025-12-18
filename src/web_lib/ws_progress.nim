## WebSocket Progress Callback for OCCAM Web Server
##
## Factory for creating progress callbacks that convert ProgressEvents
## to JSON messages and send them via WebSocket.

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
        echo "[Progress] Level ", event.currentLevel, "/", event.totalLevels,
             " - ", event.totalModelsEvaluated, " models, best: ", event.bestModelName
        let msg = WSProgressMessage(
          msgType: "progress",
          requestId: requestId,
          event: "level_complete",
          data: WSProgressData(
            currentLevel: event.currentLevel,
            totalLevels: event.totalLevels,
            modelsEvaluated: event.totalModelsEvaluated,
            bestModelName: event.bestModelName,
            bestStatistic: event.bestStatistic,
            statisticName: event.statisticName,
            timestamp: event.timestamp
          )
        )
        sendFn(msg.toJson())

      of pkSearchComplete:
        echo "[Progress] Search complete - ", event.totalModelsEvaluated, " models, best: ", event.bestModelName
        let msg = WSProgressMessage(
          msgType: "progress",
          requestId: requestId,
          event: "search_complete",
          data: WSProgressData(
            totalModelsEvaluated: event.totalModelsEvaluated,
            bestModelName: event.bestModelName,
            bestStatistic: event.bestStatistic,
            statisticName: event.statisticName,
            timestamp: event.timestamp
          )
        )
        sendFn(msg.toJson())

      of pkModelEvaluated, pkIPFIteration:
        # Skip fine-grained events - too noisy for WebSocket
        discard
