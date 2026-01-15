## WebSocket Handler for OCCAM Web Server
##
## Handles WebSocket connections for search with progress streaming.
## Protocol:
##   1. Client connects to /api/ws/search
##   2. Client sends search_start message
##   3. Server streams progress events
##   4. Server sends final result
##   5. Connection closes

import std/asyncdispatch
import prologue
import prologue/websocket

import ./ws_messages
import ./ws_progress
import ./logic
import ./models
import ../occam/core/progress

template gcsafeCall(body: untyped) =
  ## Cast a block to gcsafe for calling non-gcsafe OCCAM library functions
  {.gcsafe.}:
    body


proc wsSearchHandler*(ctx: Context) {.async.} =
  ## WebSocket handler for search with progress streaming.
  ##
  ## Accepts WebSocket connection and waits for search_start message.
  ## Runs search with progress callback that streams events.
  ## Sends final result when search completes.
  echo "[WS] New WebSocket connection"
  var ws: WebSocket = await newWebSocket(ctx)

  # Start heartbeat - ping every 30 seconds to keep connection alive
  ws.setupPings(30.0)

  try:
    while ws.readyState == Open:
      let packet: string = await ws.receiveStrPacket()

      if packet.len == 0:
        continue

      echo "[WS] Received message: ", packet.len, " bytes"
      let clientMsg = parseWSMessage(packet)

      case clientMsg.kind
      of wsmSearchStart:
        echo "[WS] Search request - direction: ", clientMsg.payload.direction,
             ", filter: ", clientMsg.payload.filter,
             ", width: ", clientMsg.payload.width,
             ", levels: ", clientMsg.payload.levels
        if clientMsg.payload.referenceModel.len > 0:
          echo "[WS]   reference model: ", clientMsg.payload.referenceModel

        # Create send function that sends via WebSocket
        # Note: We use waitFor to ensure messages are sent immediately
        # rather than queued (since search runs synchronously)
        proc sendMsg(msg: string) {.gcsafe.} =
          {.cast(gcsafe).}:
            waitFor ws.send(msg)

        let callback = makeWSProgressCallback(clientMsg.requestId, sendMsg)
        let progressConfig = initProgressConfig(callback = callback)

        let req = SearchRequest(
          data: clientMsg.payload.data,
          direction: clientMsg.payload.direction,
          filter: clientMsg.payload.filter,
          width: clientMsg.payload.width,
          levels: clientMsg.payload.levels,
          sortBy: clientMsg.payload.sortBy,
          referenceModel: clientMsg.payload.referenceModel
        )

        try:
          var searchResp: SearchResponse
          gcsafeCall:
            searchResp = processSearchWithProgress(req, progressConfig)

          # Convert results to WS format
          var wsResults: seq[WSResultItem] = @[]
          for item in searchResp.results:
            wsResults.add(WSResultItem(
              model: item.model,
              h: item.h,
              aic: item.aic,
              bic: item.bic,
              ddf: item.ddf.float64,
              hasLoops: item.hasLoops
            ))

          # Send final result
          echo "[WS] Search complete - ", searchResp.totalEvaluated, " models evaluated, ",
               wsResults.len, " results"
          let resultMsg = WSResultMessage(
            msgType: "result",
            requestId: clientMsg.requestId,
            data: WSResultData(
              totalEvaluated: searchResp.totalEvaluated,
              results: wsResults
            )
          )
          await ws.send(resultMsg.toJson())

        except CatchableError as e:
          let errorMsg = WSErrorMessage(
            msgType: "error",
            requestId: clientMsg.requestId,
            error: WSError(
              code: "search_error",
              message: e.msg
            )
          )
          await ws.send(errorMsg.toJson())

      of wsmSearchCancel:
        # TODO: Implement cancellation in Phase 2
        let errorMsg = WSErrorMessage(
          msgType: "error",
          requestId: clientMsg.requestId,
          error: WSError(
            code: "not_implemented",
            message: "Search cancellation not yet implemented"
          )
        )
        await ws.send(errorMsg.toJson())

      of wsmUnknown:
        let errorMsg = WSErrorMessage(
          msgType: "error",
          requestId: "",
          error: WSError(
            code: "invalid_message",
            message: "Unknown or malformed message"
          )
        )
        await ws.send(errorMsg.toJson())

  except WebSocketClosedError:
    discard  # Client disconnected - normal termination

  # Prologue requires a response
  resp ""
