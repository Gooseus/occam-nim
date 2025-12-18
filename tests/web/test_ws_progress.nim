## Tests for WebSocket Progress Callback
##
## TDD tests for progress callback factory that converts
## ProgressEvents to WebSocket JSON messages.

import std/[unittest, json]
import ../../src/occam/core/progress
import ../../src/web_lib/ws_progress

suite "WebSocket Progress Callback - Factory":

  test "makeWSProgressCallback creates non-nil callback":
    # Arrange
    var sentMessages: seq[string] = @[]
    let sendFn = proc(msg: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        sentMessages.add(msg)

    # Act
    let callback = makeWSProgressCallback("request-123", sendFn)

    # Assert
    check callback != nil

  test "callback is gcsafe":
    # Arrange - verify the callback can be stored in a ProgressConfig
    var sentMessages: seq[string] = @[]
    let sendFn = proc(msg: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        sentMessages.add(msg)

    # Act
    let callback = makeWSProgressCallback("request-123", sendFn)
    let config = initProgressConfig(callback = callback)

    # Assert
    check config.callback != nil
    check config.enabled == true


suite "WebSocket Progress Callback - Event Handling":

  test "sends progress JSON on pkSearchStarted":
    # Arrange
    var sentMessages: seq[string] = @[]
    let sendFn = proc(msg: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        sentMessages.add(msg)

    let callback = makeWSProgressCallback("request-123", sendFn)
    let event = makeSearchStartEvent(7, "BIC")

    # Act
    callback(event)

    # Assert
    check sentMessages.len == 1
    let parsed = parseJson(sentMessages[0])
    check parsed["type"].getStr() == "progress"
    check parsed["requestId"].getStr() == "request-123"
    check parsed["event"].getStr() == "search_started"
    check parsed["data"]["totalLevels"].getInt() == 7
    check parsed["data"]["statisticName"].getStr() == "BIC"

  test "sends progress JSON on pkSearchLevel":
    # Arrange
    var sentMessages: seq[string] = @[]
    let sendFn = proc(msg: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        sentMessages.add(msg)

    let callback = makeWSProgressCallback("request-123", sendFn)
    let event = makeLevelEvent(3, 7, 45, "AB:BC", -23.5, "BIC")

    # Act
    callback(event)

    # Assert
    check sentMessages.len == 1
    let parsed = parseJson(sentMessages[0])
    check parsed["type"].getStr() == "progress"
    check parsed["event"].getStr() == "level_complete"
    check parsed["data"]["currentLevel"].getInt() == 3
    check parsed["data"]["totalLevels"].getInt() == 7
    check parsed["data"]["modelsEvaluated"].getInt() == 45
    check parsed["data"]["bestModelName"].getStr() == "AB:BC"
    check parsed["data"]["bestStatistic"].getFloat() == -23.5

  test "sends progress JSON on pkSearchComplete":
    # Arrange
    var sentMessages: seq[string] = @[]
    let sendFn = proc(msg: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        sentMessages.add(msg)

    let callback = makeWSProgressCallback("request-123", sendFn)
    let event = makeCompleteEvent(127, "AB:BC", -28.7, "BIC")

    # Act
    callback(event)

    # Assert
    check sentMessages.len == 1
    let parsed = parseJson(sentMessages[0])
    check parsed["type"].getStr() == "progress"
    check parsed["event"].getStr() == "search_complete"
    check parsed["data"]["totalModelsEvaluated"].getInt() == 127
    check parsed["data"]["bestModelName"].getStr() == "AB:BC"
    check parsed["data"]["bestStatistic"].getFloat() == -28.7

  test "skips pkModelEvaluated events":
    # Arrange - fine-grained model updates are too noisy for WebSocket
    var sentMessages: seq[string] = @[]
    let sendFn = proc(msg: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        sentMessages.add(msg)

    let callback = makeWSProgressCallback("request-123", sendFn)
    let event = makeModelBatchEvent(10, 100, 1000)

    # Act
    callback(event)

    # Assert - no message should be sent
    check sentMessages.len == 0

  test "skips pkIPFIteration events":
    # Arrange - IPF iterations are too frequent for WebSocket
    var sentMessages: seq[string] = @[]
    let sendFn = proc(msg: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        sentMessages.add(msg)

    let callback = makeWSProgressCallback("request-123", sendFn)
    let event = makeIPFEvent(50, 1000, 0.001, false)

    # Act
    callback(event)

    # Assert - no message should be sent
    check sentMessages.len == 0


suite "WebSocket Progress Callback - Message Format":

  test "progress messages include timestamp":
    # Arrange
    var sentMessages: seq[string] = @[]
    let sendFn = proc(msg: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        sentMessages.add(msg)

    let callback = makeWSProgressCallback("request-123", sendFn)
    let event = makeSearchStartEvent(7, "BIC")

    # Act
    callback(event)

    # Assert
    let parsed = parseJson(sentMessages[0])
    check parsed["data"].hasKey("timestamp")
    check parsed["data"]["timestamp"].getFloat() > 0.0

  test "multiple events send multiple messages":
    # Arrange
    var sentMessages: seq[string] = @[]
    let sendFn = proc(msg: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        sentMessages.add(msg)

    let callback = makeWSProgressCallback("request-123", sendFn)

    # Act - simulate a search lifecycle
    callback(makeSearchStartEvent(3, "BIC"))
    callback(makeLevelEvent(1, 3, 10, "A:B", -5.0, "BIC"))
    callback(makeLevelEvent(2, 3, 25, "AB", -8.0, "BIC"))
    callback(makeLevelEvent(3, 3, 35, "AB", -8.0, "BIC"))
    callback(makeCompleteEvent(35, "AB", -8.0, "BIC"))

    # Assert
    check sentMessages.len == 5

    # Verify event sequence
    check parseJson(sentMessages[0])["event"].getStr() == "search_started"
    check parseJson(sentMessages[1])["event"].getStr() == "level_complete"
    check parseJson(sentMessages[2])["event"].getStr() == "level_complete"
    check parseJson(sentMessages[3])["event"].getStr() == "level_complete"
    check parseJson(sentMessages[4])["event"].getStr() == "search_complete"
