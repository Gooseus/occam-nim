## Tests for MCP Protocol Implementation
##
## These tests verify MCP protocol message handling.

import std/[unittest, json, strutils]
import jsony

import ../../src/mcp_lib/jsonrpc
import ../../src/mcp_lib/protocol

suite "MCP Initialize":
  test "initialize response has correct structure":
    let resp = handleInitialize(newJInt(1))
    let json = resp.toJson().parseJson()

    check json["result"]["protocolVersion"].getStr == "2024-11-05"
    check json["result"]["serverInfo"]["name"].getStr == "occam-mcp"
    check json["result"]["capabilities"]["tools"].kind == JObject

suite "MCP Tools List":
  test "tools/list returns available tools":
    let resp = handleToolsList(newJInt(2))
    let json = resp.toJson().parseJson()

    check json["result"]["tools"].kind == JArray
    check json["result"]["tools"].len >= 3  # At least load_data, fit_model, search

  test "tools have required fields":
    let resp = handleToolsList(newJInt(3))
    let json = resp.toJson().parseJson()

    for tool in json["result"]["tools"]:
      check tool.hasKey("name")
      check tool.hasKey("description")
      check tool.hasKey("inputSchema")

suite "MCP Tools Call":
  test "unknown tool returns error":
    let params = %*{"name": "nonexistent_tool", "arguments": {}}
    let resp = handleToolsCall(newJInt(4), params)
    let json = resp.toJson().parseJson()

    check json.hasKey("error")
    check json["error"]["message"].getStr.contains("Unknown tool")

  test "occam_info tool works":
    # First load some data
    let loadParams = %*{
      "name": "occam_load_data",
      "arguments": {
        "data": """{
          "name": "test",
          "variables": [
            {"name": "A", "abbrev": "A", "cardinality": 2},
            {"name": "B", "abbrev": "B", "cardinality": 2}
          ],
          "data": [["0", "0"], ["0", "1"], ["1", "0"], ["1", "1"]],
          "counts": [10, 20, 30, 40]
        }"""
      }
    }
    discard handleToolsCall(newJInt(5), loadParams)

    # Now get info
    let infoParams = %*{"name": "occam_info", "arguments": {}}
    let resp = handleToolsCall(newJInt(6), infoParams)
    let json = resp.toJson().parseJson()

    check json["result"]["content"][0]["text"].getStr.contains("test")

  test "occam_fit_model tool works":
    let loadParams = %*{
      "name": "occam_load_data",
      "arguments": {
        "data": """{
          "name": "fit_test",
          "variables": [
            {"name": "A", "abbrev": "A", "cardinality": 2},
            {"name": "B", "abbrev": "B", "cardinality": 2}
          ],
          "data": [["0", "0"], ["0", "1"], ["1", "0"], ["1", "1"]],
          "counts": [10, 20, 30, 40]
        }"""
      }
    }
    discard handleToolsCall(newJInt(7), loadParams)

    let fitParams = %*{
      "name": "occam_fit_model",
      "arguments": {"model": "AB"}
    }
    let resp = handleToolsCall(newJInt(8), fitParams)
    let json = resp.toJson().parseJson()

    check json["result"]["content"][0]["type"].getStr == "text"
    let text = json["result"]["content"][0]["text"].getStr
    check text.contains("AB")
    check text.contains("H:")
