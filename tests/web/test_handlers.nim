## Tests for web API handlers
##
## These tests verify the handler logic without running a server.
## We test the request/response types and processing logic.

import std/[unittest, json, strutils]
import jsony

# Import handler types and logic (not the HTTP layer)
import ../../src/web_lib/models
import ../../src/web_lib/logic

suite "Web API Request/Response Models":
  test "FitRequest parses from JSON":
    let jsonStr = """{"data": "{\"name\":\"test\"}", "model": "AB:BC"}"""
    let req = jsonStr.fromJson(FitRequest)
    check req.model == "AB:BC"
    check req.data.len > 0

  test "FitResponse serializes to JSON":
    let resp = FitResponse(
      model: "AB:BC",
      h: 1.234,
      aic: 5.678,
      bic: 9.012,
      hasLoops: false
    )
    let jsonStr = resp.toJson()
    let parsed = parseJson(jsonStr)
    check parsed["model"].getStr == "AB:BC"
    check parsed["h"].getFloat > 1.0
    check parsed["hasLoops"].getBool == false

  test "SearchRequest initializes with defaults":
    let req = initSearchRequest()
    check req.direction == "up"
    check req.filter == "loopless"
    check req.width == 3
    check req.levels == 7

  test "HealthResponse indicates server status":
    let resp = HealthResponse(status: "ok", version: "0.1.0")
    let jsonStr = resp.toJson()
    check jsonStr.contains("ok")

suite "Web API Logic":
  test "processHealthCheck returns ok status":
    let resp = processHealthCheck()
    check resp.status == "ok"
    check resp.version.len > 0

  test "processDataInfo returns variable info":
    # Create minimal test data
    let testData = """{
      "name": "test",
      "variables": [
        {"name": "A", "abbrev": "A", "cardinality": 2},
        {"name": "B", "abbrev": "B", "cardinality": 2}
      ],
      "data": [["0", "0"], ["0", "1"], ["1", "0"], ["1", "1"]],
      "counts": [10, 20, 30, 40]
    }"""
    let resp = processDataInfo(testData)
    check resp.name == "test"
    check resp.variableCount == 2
    check resp.sampleSize == 100.0

  test "processFitModel returns statistics":
    let testData = """{
      "name": "test",
      "variables": [
        {"name": "A", "abbrev": "A", "cardinality": 2},
        {"name": "B", "abbrev": "B", "cardinality": 2}
      ],
      "data": [["0", "0"], ["0", "1"], ["1", "0"], ["1", "1"]],
      "counts": [10, 20, 30, 40]
    }"""
    let req = FitRequest(data: testData, model: "AB")
    let resp = processFitModel(req)
    check resp.model == "AB"
    check resp.h >= 0.0
    check resp.hasLoops == false  # AB is a single relation, no loops

  test "processFitModel detects loop models":
    let testData = """{
      "name": "test",
      "variables": [
        {"name": "A", "abbrev": "A", "cardinality": 2},
        {"name": "B", "abbrev": "B", "cardinality": 2},
        {"name": "C", "abbrev": "C", "cardinality": 2}
      ],
      "data": [["0", "0", "0"], ["1", "1", "1"]],
      "counts": [50, 50]
    }"""
    let req = FitRequest(data: testData, model: "AB:BC:AC")
    let resp = processFitModel(req)
    check resp.model == "AB:BC:AC"
    check resp.hasLoops == true  # Triangle is a loop model
