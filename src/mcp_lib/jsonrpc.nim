## JSON-RPC 2.0 Implementation
##
## This module provides types and utilities for JSON-RPC 2.0 message handling.
## Reference: https://www.jsonrpc.org/specification

import std/json
import jsony

type
  JsonRpcRequest* = object
    ## JSON-RPC 2.0 Request
    jsonrpc*: string
    `method`*: string
    params*: JsonNode
    id*: JsonNode  # Can be string, int, or null

  JsonRpcResponse* = object
    ## JSON-RPC 2.0 Response
    jsonrpc*: string
    id*: JsonNode
    `result`*: JsonNode
    error*: JsonNode

  JsonRpcError* = object
    ## JSON-RPC 2.0 Error object
    code*: int
    message*: string
    data*: JsonNode

# Standard JSON-RPC 2.0 error codes
const
  PARSE_ERROR* = -32700
  INVALID_REQUEST* = -32600
  METHOD_NOT_FOUND* = -32601
  INVALID_PARAMS* = -32602
  INTERNAL_ERROR* = -32603

# Custom hooks for jsony to handle optional fields

proc parseHook*(s: string, i: var int, v: var JsonRpcRequest) =
  var node: JsonNode
  parseHook(s, i, node)

  v.jsonrpc = node.getOrDefault("jsonrpc").getStr("2.0")
  v.`method` = node.getOrDefault("method").getStr("")
  v.params = node.getOrDefault("params")
  if v.params.isNil:
    v.params = newJObject()
  v.id = node.getOrDefault("id")
  if v.id.isNil:
    v.id = newJNull()

proc dumpHook*(s: var string, v: JsonRpcResponse) =
  var obj = newJObject()
  obj["jsonrpc"] = newJString(v.jsonrpc)
  obj["id"] = v.id

  if not v.`result`.isNil and v.`result`.kind != JNull:
    obj["result"] = v.`result`

  if not v.error.isNil and v.error.kind != JNull:
    obj["error"] = v.error

  s.add($obj)

# Response constructors

proc successResponse*(id: JsonNode; resultData: JsonNode): JsonRpcResponse =
  ## Create a success response
  JsonRpcResponse(
    jsonrpc: "2.0",
    id: id,
    `result`: resultData,
    error: newJNull()
  )

proc errorResponse*(id: JsonNode; code: int; message: string; data: JsonNode = newJNull()): JsonRpcResponse =
  ## Create an error response
  var errorObj = %*{
    "code": code,
    "message": message
  }
  if data.kind != JNull:
    errorObj["data"] = data

  JsonRpcResponse(
    jsonrpc: "2.0",
    id: id,
    `result`: newJNull(),
    error: errorObj
  )

# Standard error responses

proc parseError*(): JsonRpcResponse =
  ## Invalid JSON was received
  errorResponse(newJNull(), PARSE_ERROR, "Parse error")

proc invalidRequest*(id: JsonNode): JsonRpcResponse =
  ## The JSON sent is not a valid Request object
  errorResponse(id, INVALID_REQUEST, "Invalid Request")

proc methodNotFound*(id: JsonNode): JsonRpcResponse =
  ## The method does not exist / is not available
  errorResponse(id, METHOD_NOT_FOUND, "Method not found")

proc invalidParams*(id: JsonNode): JsonRpcResponse =
  ## Invalid method parameter(s)
  errorResponse(id, INVALID_PARAMS, "Invalid params")

proc internalError*(id: JsonNode; detail: string = ""): JsonRpcResponse =
  ## Internal JSON-RPC error
  if detail.len > 0:
    errorResponse(id, INTERNAL_ERROR, "Internal error", %*{"detail": detail})
  else:
    errorResponse(id, INTERNAL_ERROR, "Internal error")
