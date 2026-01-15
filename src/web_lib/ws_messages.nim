## WebSocket Message Types for OCCAM Web Server
##
## Defines JSON message protocol for WebSocket communication:
## - Client → Server: search_start, search_cancel
## - Server → Client: progress, result, error

import std/json

type
  WSMessageKind* = enum
    wsmSearchStart    ## Client requests search start
    wsmSearchCancel   ## Client requests search cancellation
    wsmUnknown        ## Unknown or invalid message

  WSSearchPayload* = object
    ## Payload for search_start message
    data*: string           ## JSON data string
    direction*: string      ## "up" or "down"
    filter*: string         ## "loopless", "full", "disjoint", "chain"
    width*: int             ## Search width
    levels*: int            ## Max search levels
    sortBy*: string         ## "bic", "aic", "ddf"
    referenceModel*: string ## Custom reference model (e.g., "AB:BC"), empty for default

  WSClientMessage* = object
    ## Parsed message from WebSocket client
    kind*: WSMessageKind
    requestId*: string
    payload*: WSSearchPayload

  WSProgressData* = object
    ## Data for progress events
    currentLevel*: int
    totalLevels*: int
    modelsEvaluated*: int
    totalModelsEvaluated*: int   ## Used in search_complete event
    looplessModels*: int         ## Models without loops (fast BP)
    loopModels*: int             ## Models with loops (slow IPF)
    bestModelName*: string
    bestStatistic*: float64
    statisticName*: string
    timestamp*: float64
    # Timing info
    levelTimeMs*: float64        ## Time for this level in milliseconds
    elapsedMs*: float64          ## Total elapsed time in milliseconds
    avgModelTimeMs*: float64     ## Average time per model in milliseconds
    # IPF progress info (for ipf_progress event)
    ipfIteration*: int           ## Current IPF iteration
    ipfMaxIterations*: int       ## Max IPF iterations
    ipfError*: float64           ## Current IPF convergence error
    ipfStateCount*: int          ## Number of states in fit table
    ipfRelationCount*: int       ## Number of relations in model

  WSProgressMessage* = object
    ## Server → Client progress message
    msgType*: string        ## Always "progress"
    requestId*: string
    event*: string          ## "search_started", "level_complete", "search_complete"
    data*: WSProgressData

  WSResultItem* = object
    ## Single result item
    model*: string
    h*: float64
    aic*: float64
    bic*: float64
    ddf*: float64
    hasLoops*: bool

  WSResultData* = object
    ## Data for result message
    totalEvaluated*: int
    results*: seq[WSResultItem]

  WSResultMessage* = object
    ## Server → Client result message
    msgType*: string        ## Always "result"
    requestId*: string
    data*: WSResultData

  WSError* = object
    ## Error details
    code*: string
    message*: string

  WSErrorMessage* = object
    ## Server → Client error message
    msgType*: string        ## Always "error"
    requestId*: string
    error*: WSError


proc parseWSMessage*(jsonStr: string): WSClientMessage =
  ## Parse a JSON message from WebSocket client.
  ## Returns WSClientMessage with kind=wsmUnknown for invalid messages.
  result = WSClientMessage(kind: wsmUnknown, requestId: "")

  try:
    let node = parseJson(jsonStr)

    # Extract requestId
    if node.hasKey("requestId"):
      result.requestId = node["requestId"].getStr()

    # Parse message type
    if node.hasKey("type"):
      let msgType = node["type"].getStr()
      case msgType
      of "search_start":
        result.kind = wsmSearchStart
        if node.hasKey("payload"):
          let payload = node["payload"]
          result.payload = WSSearchPayload(
            data: payload.getOrDefault("data").getStr(""),
            direction: payload.getOrDefault("direction").getStr("up"),
            filter: payload.getOrDefault("filter").getStr("loopless"),
            width: payload.getOrDefault("width").getInt(3),
            levels: payload.getOrDefault("levels").getInt(7),
            sortBy: payload.getOrDefault("sortBy").getStr("bic"),
            referenceModel: payload.getOrDefault("referenceModel").getStr("")
          )
      of "search_cancel":
        result.kind = wsmSearchCancel
      else:
        result.kind = wsmUnknown

  except JsonParsingError:
    result.kind = wsmUnknown


proc toJson*(msg: WSProgressMessage): string =
  ## Serialize progress message to JSON string.
  let node = %*{
    "type": msg.msgType,
    "requestId": msg.requestId,
    "event": msg.event,
    "data": {
      "currentLevel": msg.data.currentLevel,
      "totalLevels": msg.data.totalLevels,
      "modelsEvaluated": msg.data.modelsEvaluated,
      "totalModelsEvaluated": msg.data.totalModelsEvaluated,
      "looplessModels": msg.data.looplessModels,
      "loopModels": msg.data.loopModels,
      "bestModelName": msg.data.bestModelName,
      "bestStatistic": msg.data.bestStatistic,
      "statisticName": msg.data.statisticName,
      "timestamp": msg.data.timestamp,
      "levelTimeMs": msg.data.levelTimeMs,
      "elapsedMs": msg.data.elapsedMs,
      "avgModelTimeMs": msg.data.avgModelTimeMs,
      "ipfIteration": msg.data.ipfIteration,
      "ipfMaxIterations": msg.data.ipfMaxIterations,
      "ipfError": msg.data.ipfError,
      "ipfStateCount": msg.data.ipfStateCount,
      "ipfRelationCount": msg.data.ipfRelationCount
    }
  }
  result = $node


proc toJson*(msg: WSResultMessage): string =
  ## Serialize result message to JSON string.
  var resultsArr = newJArray()
  for item in msg.data.results:
    resultsArr.add(%*{
      "model": item.model,
      "h": item.h,
      "aic": item.aic,
      "bic": item.bic,
      "ddf": item.ddf,
      "hasLoops": item.hasLoops
    })

  let node = %*{
    "type": msg.msgType,
    "requestId": msg.requestId,
    "data": {
      "totalEvaluated": msg.data.totalEvaluated,
      "results": resultsArr
    }
  }
  result = $node


proc toJson*(msg: WSErrorMessage): string =
  ## Serialize error message to JSON string.
  let node = %*{
    "type": msg.msgType,
    "requestId": msg.requestId,
    "error": {
      "code": msg.error.code,
      "message": msg.error.message
    }
  }
  result = $node
