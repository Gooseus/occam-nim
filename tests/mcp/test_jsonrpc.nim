## Tests for MCP JSON-RPC 2.0 implementation
##
## These tests verify the JSON-RPC parsing and response generation.

import std/[unittest, json]
import jsony

import ../../src/mcp_lib/jsonrpc

suite "JSON-RPC 2.0 Message Parsing":
  test "parse request with params":
    let msg = """{"jsonrpc": "2.0", "method": "tools/call", "params": {"name": "test"}, "id": 1}"""
    let req = msg.fromJson(JsonRpcRequest)
    check req.jsonrpc == "2.0"
    check req.`method` == "tools/call"
    check req.id.kind == JInt
    check req.id.getInt == 1
    check req.params["name"].getStr == "test"

  test "parse request without params":
    let msg = """{"jsonrpc": "2.0", "method": "initialize", "id": "abc"}"""
    let req = msg.fromJson(JsonRpcRequest)
    check req.`method` == "initialize"
    check req.id.kind == JString
    check req.id.getStr == "abc"

  test "parse notification (no id)":
    let msg = """{"jsonrpc": "2.0", "method": "notifications/cancelled"}"""
    let req = msg.fromJson(JsonRpcRequest)
    check req.`method` == "notifications/cancelled"
    check req.id.kind == JNull

suite "JSON-RPC 2.0 Response Generation":
  test "success response":
    let resp = successResponse(newJInt(1), %*{"status": "ok"})
    let json = resp.toJson().parseJson()
    check json["jsonrpc"].getStr == "2.0"
    check json["id"].getInt == 1
    check json["result"]["status"].getStr == "ok"
    check not json.hasKey("error")

  test "error response":
    let resp = errorResponse(newJInt(2), -32600, "Invalid Request")
    let json = resp.toJson().parseJson()
    check json["jsonrpc"].getStr == "2.0"
    check json["id"].getInt == 2
    check json["error"]["code"].getInt == -32600
    check json["error"]["message"].getStr == "Invalid Request"
    check not json.hasKey("result")

  test "error response with data":
    let resp = errorResponse(newJInt(3), -32000, "Server error", %*{"detail": "oops"})
    let json = resp.toJson().parseJson()
    check json["error"]["data"]["detail"].getStr == "oops"

suite "JSON-RPC 2.0 Standard Errors":
  test "parse error":
    let resp = parseError()
    let json = resp.toJson().parseJson()
    check json["error"]["code"].getInt == -32700

  test "invalid request":
    let resp = invalidRequest(newJInt(1))
    let json = resp.toJson().parseJson()
    check json["error"]["code"].getInt == -32600

  test "method not found":
    let resp = methodNotFound(newJInt(1))
    let json = resp.toJson().parseJson()
    check json["error"]["code"].getInt == -32601

  test "invalid params":
    let resp = invalidParams(newJInt(1))
    let json = resp.toJson().parseJson()
    check json["error"]["code"].getInt == -32602
