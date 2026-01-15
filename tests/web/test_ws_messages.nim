## Tests for WebSocket Message Types
##
## TDD tests for JSON message serialization/deserialization.
## These tests define the WebSocket protocol contract.

import std/[unittest, json]

# Import will fail until implementation exists
import ../../src/web_lib/ws_messages

suite "WebSocket Client Messages - Parsing":

  test "parseWSMessage parses search_start message":
    # Arrange
    let jsonStr = """{
      "type": "search_start",
      "requestId": "test-123",
      "payload": {
        "data": "{\"name\":\"test\"}",
        "direction": "up",
        "filter": "loopless",
        "width": 3,
        "levels": 7,
        "sortBy": "bic"
      }
    }"""

    # Act
    let msg = parseWSMessage(jsonStr)

    # Assert
    check msg.kind == wsmSearchStart
    check msg.requestId == "test-123"
    check msg.payload.direction == "up"
    check msg.payload.filter == "loopless"
    check msg.payload.width == 3
    check msg.payload.levels == 7
    check msg.payload.sortBy == "bic"

  test "parseWSMessage parses search_cancel message":
    # Arrange
    let jsonStr = """{
      "type": "search_cancel",
      "requestId": "test-456"
    }"""

    # Act
    let msg = parseWSMessage(jsonStr)

    # Assert
    check msg.kind == wsmSearchCancel
    check msg.requestId == "test-456"

  test "parseWSMessage handles unknown message type":
    # Arrange
    let jsonStr = """{
      "type": "unknown_type",
      "requestId": "test-789"
    }"""

    # Act
    let msg = parseWSMessage(jsonStr)

    # Assert
    check msg.kind == wsmUnknown
    check msg.requestId == "test-789"

  test "parseWSMessage handles malformed JSON gracefully":
    # Arrange
    let jsonStr = "not valid json"

    # Act
    let msg = parseWSMessage(jsonStr)

    # Assert
    check msg.kind == wsmUnknown
    check msg.requestId == ""


suite "WebSocket Server Messages - Serialization":

  test "WSProgressMessage serializes to valid JSON":
    # Arrange
    let msg = WSProgressMessage(
      msgType: "progress",
      requestId: "test-123",
      event: "search_started",
      data: WSProgressData(
        totalLevels: 7,
        statisticName: "BIC",
        timestamp: 1234567890.123
      )
    )

    # Act
    let jsonStr = msg.toJson()
    let parsed = parseJson(jsonStr)

    # Assert
    check parsed["type"].getStr() == "progress"
    check parsed["requestId"].getStr() == "test-123"
    check parsed["event"].getStr() == "search_started"
    check parsed["data"]["totalLevels"].getInt() == 7
    check parsed["data"]["statisticName"].getStr() == "BIC"

  test "WSProgressMessage with level_complete event":
    # Arrange
    let msg = WSProgressMessage(
      msgType: "progress",
      requestId: "test-123",
      event: "level_complete",
      data: WSProgressData(
        currentLevel: 3,
        totalLevels: 7,
        modelsEvaluated: 45,
        bestModelName: "AB:BC",
        bestStatistic: -23.5,
        statisticName: "BIC",
        timestamp: 1234567890.456
      )
    )

    # Act
    let jsonStr = msg.toJson()
    let parsed = parseJson(jsonStr)

    # Assert
    check parsed["event"].getStr() == "level_complete"
    check parsed["data"]["currentLevel"].getInt() == 3
    check parsed["data"]["modelsEvaluated"].getInt() == 45
    check parsed["data"]["bestModelName"].getStr() == "AB:BC"
    check parsed["data"]["bestStatistic"].getFloat() == -23.5

  test "WSResultMessage serializes to valid JSON":
    # Arrange
    let msg = WSResultMessage(
      msgType: "result",
      requestId: "test-123",
      data: WSResultData(
        totalEvaluated: 127,
        results: @[
          WSResultItem(
            model: "AB:BC",
            h: 1.234,
            aic: 5.678,
            bic: -23.5,
            ddf: 12.0,
            hasLoops: false
          )
        ]
      )
    )

    # Act
    let jsonStr = msg.toJson()
    let parsed = parseJson(jsonStr)

    # Assert
    check parsed["type"].getStr() == "result"
    check parsed["requestId"].getStr() == "test-123"
    check parsed["data"]["totalEvaluated"].getInt() == 127
    check parsed["data"]["results"].len == 1
    check parsed["data"]["results"][0]["model"].getStr() == "AB:BC"
    check parsed["data"]["results"][0]["bic"].getFloat() == -23.5

  test "WSErrorMessage serializes to valid JSON":
    # Arrange
    let msg = WSErrorMessage(
      msgType: "error",
      requestId: "test-123",
      error: WSError(
        code: "search_error",
        message: "Invalid model notation"
      )
    )

    # Act
    let jsonStr = msg.toJson()
    let parsed = parseJson(jsonStr)

    # Assert
    check parsed["type"].getStr() == "error"
    check parsed["requestId"].getStr() == "test-123"
    check parsed["error"]["code"].getStr() == "search_error"
    check parsed["error"]["message"].getStr() == "Invalid model notation"


suite "WebSocket Client Messages - Reference Model":

  test "parseWSMessage parses search_start with referenceModel":
    # Arrange
    let jsonStr = """{
      "type": "search_start",
      "requestId": "test-ref",
      "payload": {
        "data": "{\"name\":\"test\"}",
        "direction": "up",
        "filter": "loopless",
        "width": 3,
        "levels": 7,
        "sortBy": "bic",
        "referenceModel": "AB:BC"
      }
    }"""

    # Act
    let msg = parseWSMessage(jsonStr)

    # Assert
    check msg.kind == wsmSearchStart
    check msg.payload.referenceModel == "AB:BC"

  test "parseWSMessage handles empty referenceModel":
    # Arrange
    let jsonStr = """{
      "type": "search_start",
      "requestId": "test-empty",
      "payload": {
        "data": "{}",
        "direction": "up",
        "filter": "loopless",
        "width": 3,
        "levels": 7,
        "sortBy": "bic",
        "referenceModel": ""
      }
    }"""

    # Act
    let msg = parseWSMessage(jsonStr)

    # Assert
    check msg.payload.referenceModel == ""

  test "parseWSMessage handles missing referenceModel (defaults to empty)":
    # Arrange - no referenceModel field in payload
    let jsonStr = """{
      "type": "search_start",
      "requestId": "test-missing",
      "payload": {
        "data": "{}",
        "direction": "up",
        "filter": "loopless",
        "width": 3,
        "levels": 7,
        "sortBy": "bic"
      }
    }"""

    # Act
    let msg = parseWSMessage(jsonStr)

    # Assert
    check msg.payload.referenceModel == ""


suite "WebSocket Message Round-Trip":

  test "search_start payload survives round-trip":
    # Arrange
    let originalPayload = WSSearchPayload(
      data: "{\"variables\":[]}",
      direction: "down",
      filter: "full",
      width: 5,
      levels: 10,
      sortBy: "aic",
      referenceModel: ""
    )

    # Act - serialize then parse back
    let jsonStr = $(%*{
      "type": "search_start",
      "requestId": "round-trip-test",
      "payload": {
        "data": originalPayload.data,
        "direction": originalPayload.direction,
        "filter": originalPayload.filter,
        "width": originalPayload.width,
        "levels": originalPayload.levels,
        "sortBy": originalPayload.sortBy,
        "referenceModel": originalPayload.referenceModel
      }
    })
    let parsed = parseWSMessage(jsonStr)

    # Assert
    check parsed.payload.data == originalPayload.data
    check parsed.payload.direction == originalPayload.direction
    check parsed.payload.filter == originalPayload.filter
    check parsed.payload.width == originalPayload.width
    check parsed.payload.levels == originalPayload.levels
    check parsed.payload.sortBy == originalPayload.sortBy
    check parsed.payload.referenceModel == originalPayload.referenceModel

  test "search_start with referenceModel survives round-trip":
    # Arrange
    let originalPayload = WSSearchPayload(
      data: "{\"variables\":[]}",
      direction: "up",
      filter: "loopless",
      width: 3,
      levels: 7,
      sortBy: "bic",
      referenceModel: "AB:BC:AC"
    )

    # Act - serialize then parse back
    let jsonStr = $(%*{
      "type": "search_start",
      "requestId": "round-trip-ref-test",
      "payload": {
        "data": originalPayload.data,
        "direction": originalPayload.direction,
        "filter": originalPayload.filter,
        "width": originalPayload.width,
        "levels": originalPayload.levels,
        "sortBy": originalPayload.sortBy,
        "referenceModel": originalPayload.referenceModel
      }
    })
    let parsed = parseWSMessage(jsonStr)

    # Assert
    check parsed.payload.referenceModel == "AB:BC:AC"
