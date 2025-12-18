## MCP Protocol Implementation
##
## Implements Model Context Protocol message handling.
## Reference: https://modelcontextprotocol.io/specification/2024-11-05

import std/[json, strformat, strutils]
import jsony

import ../occam
import ../occam/core/progress
import ./jsonrpc
import ./progress as mcpprogress

const
  PROTOCOL_VERSION = "2024-11-05"
  SERVER_NAME = "occam-mcp"
  SERVER_VERSION = "0.1.0"

# Global state for loaded data (simplified for MCP server)
var
  currentData: string = ""
  currentVarList: VariableList
  currentTable: ContingencyTable
  dataLoaded = false

# Tool definitions

type
  ToolDef = object
    name: string
    description: string
    inputSchema: JsonNode

let TOOLS: seq[ToolDef] = @[
  ToolDef(
    name: "occam_load_data",
    description: "Load a dataset from JSON format. The data should include variables definitions and observation counts.",
    inputSchema: %*{
      "type": "object",
      "properties": {
        "data": {
          "type": "string",
          "description": "JSON string containing the dataset with name, variables, data, and counts fields"
        }
      },
      "required": ["data"]
    }
  ),
  ToolDef(
    name: "occam_info",
    description: "Get information about the currently loaded dataset including variable names, cardinalities, and sample size.",
    inputSchema: %*{
      "type": "object",
      "properties": {}
    }
  ),
  ToolDef(
    name: "occam_fit_model",
    description: "Fit a model to the loaded data and compute statistics. Model notation uses variable abbreviations separated by colons for relations, e.g., 'AB:BC' for a model with relations AB and BC.",
    inputSchema: %*{
      "type": "object",
      "properties": {
        "model": {
          "type": "string",
          "description": "Model notation using variable abbreviations (e.g., 'AB:BC:AC')"
        }
      },
      "required": ["model"]
    }
  ),
  ToolDef(
    name: "occam_search",
    description: "Search for optimal models from the currently loaded data. Returns a ranked list of models by information criteria.",
    inputSchema: %*{
      "type": "object",
      "properties": {
        "direction": {
          "type": "string",
          "enum": ["up", "down"],
          "description": "Search direction: 'up' starts from independence, 'down' starts from saturated model",
          "default": "up"
        },
        "filter": {
          "type": "string",
          "enum": ["loopless", "full", "disjoint"],
          "description": "Model filter type",
          "default": "loopless"
        },
        "width": {
          "type": "integer",
          "description": "Beam width for search",
          "default": 3
        },
        "levels": {
          "type": "integer",
          "description": "Maximum search levels",
          "default": 7
        }
      }
    }
  )
]

# Protocol handlers

proc handleInitialize*(id: JsonNode): JsonRpcResponse =
  ## Handle initialize request
  let result = %*{
    "protocolVersion": PROTOCOL_VERSION,
    "serverInfo": {
      "name": SERVER_NAME,
      "version": SERVER_VERSION
    },
    "capabilities": {
      "tools": {}
    }
  }
  successResponse(id, result)


proc handleToolsList*(id: JsonNode): JsonRpcResponse =
  ## Handle tools/list request
  var toolsArray = newJArray()
  for tool in TOOLS:
    toolsArray.add(%*{
      "name": tool.name,
      "description": tool.description,
      "inputSchema": tool.inputSchema
    })

  let result = %*{"tools": toolsArray}
  successResponse(id, result)


proc textContent(text: string): JsonNode =
  ## Create MCP text content response
  %*{
    "content": [
      {"type": "text", "text": text}
    ]
  }


proc toolLoadData(args: JsonNode): JsonRpcResponse =
  ## Load dataset from JSON
  try:
    let dataJson = args["data"].getStr()
    let spec = parseDataSpec(dataJson)
    currentVarList = spec.toVariableList()
    currentTable = spec.toTable(currentVarList)
    currentData = dataJson
    dataLoaded = true

    let info = fmt"Loaded dataset '{spec.name}' with {currentVarList.len} variables and {currentTable.sum.int} observations."
    successResponse(newJNull(), textContent(info))
  except Exception as e:
    errorResponse(newJNull(), -32000, fmt"Failed to load data: {e.msg}")


proc toolInfo(args: JsonNode): JsonRpcResponse =
  ## Get dataset information
  if not dataLoaded:
    return errorResponse(newJNull(), -32000, "No data loaded. Use occam_load_data first.")

  try:
    let spec = parseDataSpec(currentData)
    var info = fmt"Dataset: {spec.name}" & "\n"
    info &= fmt"Sample size: {currentTable.sum.int}" & "\n"
    info &= fmt"Variables ({currentVarList.len}):" & "\n"

    for v in currentVarList:
      let dvStr = if v.isDependent: " (DV)" else: ""
      info &= fmt"  {v.name} ({v.abbrev}): {v.cardinality} levels{dvStr}" & "\n"

    successResponse(newJNull(), textContent(info))
  except Exception as e:
    errorResponse(newJNull(), -32000, fmt"Failed to get info: {e.msg}")


proc toolFitModel(args: JsonNode): JsonRpcResponse =
  ## Fit a model
  if not dataLoaded:
    return errorResponse(newJNull(), -32000, "No data loaded. Use occam_load_data first.")

  try:
    let modelStr = args["model"].getStr()
    var mgr = initVBManager(currentVarList, currentTable)
    let model = mgr.parseModel(modelStr)
    let fit = mgr.fitModel(model)

    var info = fmt"Model: {modelStr}" & "\n"
    info &= fmt"H: {fit.h:.6f}" & "\n"
    info &= fmt"DF: {fit.df}, DDF: {fit.ddf}" & "\n"
    info &= fmt"LR: {fit.lr:.4f}" & "\n"
    info &= fmt"AIC: {fit.aic:.4f}" & "\n"
    info &= fmt"BIC: {fit.bic:.4f}" & "\n"
    info &= fmt"Alpha: {fit.alpha:.6f}" & "\n"
    info &= fmt"Has Loops: {fit.hasLoops}" & "\n"
    if fit.hasLoops:
      info &= fmt"IPF Iterations: {fit.ipfIterations}" & "\n"

    successResponse(newJNull(), textContent(info))
  except Exception as e:
    errorResponse(newJNull(), -32000, fmt"Failed to fit model: {e.msg}")


proc toolSearch(args: JsonNode; progressToken: JsonNode): JsonRpcResponse =
  ## Run model search with optional progress notifications.
  ##
  ## If progressToken is provided, sends progress notifications as the search
  ## proceeds through levels.
  if not dataLoaded:
    return errorResponse(newJNull(), -32000, "No data loaded. Use occam_load_data first.")

  try:
    var mgr = initVBManager(currentVarList, currentTable)

    # Parse arguments with defaults
    let direction = args.getOrDefault("direction").getStr("up")
    let filterStr = args.getOrDefault("filter").getStr("loopless")
    let width = args.getOrDefault("width").getInt(3)
    let levels = args.getOrDefault("levels").getInt(7)

    # Determine filter
    let filter = case filterStr
      of "full": SearchFull
      of "disjoint": SearchDisjoint
      else: SearchLoopless

    # Get starting model
    let startModel = if direction == "down":
      mgr.topRefModel
    else:
      mgr.bottomRefModel

    # Create progress config with MCP callback if token provided
    var progressCtx = MCPProgressContext(progressToken: progressToken, lastProgress: 0)
    let progressConfig = if progressToken.kind != JNull:
      initProgressConfig(callback = makeMCPProgressCallback(progressCtx))
    else:
      initProgressConfig()

    # Run search with progress
    let candidates = parallelSearch(
      currentVarList, currentTable, startModel,
      filter, SearchBIC, width, levels,
      progress = progressConfig
    )

    var info = fmt"Search Results ({candidates.len} models evaluated):" & "\n"
    info &= fmt"Direction: {direction}, Filter: {filterStr}" & "\n\n"

    var count = 0
    for candidate in candidates:
      if count >= 10:
        info &= fmt"... and {candidates.len - 10} more" & "\n"
        break
      let name = candidate.model.printName(currentVarList)
      let bic = mgr.computeBIC(candidate.model)
      let hasLoops = candidate.model.hasLoops(currentVarList)
      let loopStr = if hasLoops: " [loop]" else: ""
      info &= fmt"{count+1}. {name}: BIC={bic:.4f}{loopStr}" & "\n"
      count += 1

    successResponse(newJNull(), textContent(info))
  except Exception as e:
    errorResponse(newJNull(), -32000, fmt"Search failed: {e.msg}")


proc handleToolsCall*(id: JsonNode; params: JsonNode): JsonRpcResponse =
  ## Handle tools/call request
  let toolName = params["name"].getStr()
  let args = params.getOrDefault("arguments")

  # Extract progressToken from _meta if present (per MCP spec)
  let progressToken = if params.hasKey("_meta") and params["_meta"].hasKey("progressToken"):
    params["_meta"]["progressToken"]
  else:
    newJNull()

  case toolName
  of "occam_load_data":
    toolLoadData(args)
  of "occam_info":
    toolInfo(args)
  of "occam_fit_model":
    toolFitModel(args)
  of "occam_search":
    toolSearch(args, progressToken)
  else:
    errorResponse(id, -32000, fmt"Unknown tool: {toolName}")


proc handleMessage*(msg: JsonRpcRequest): JsonRpcResponse =
  ## Route a JSON-RPC message to the appropriate handler
  case msg.`method`
  of "initialize":
    handleInitialize(msg.id)
  of "initialized":
    # Notification, no response needed
    successResponse(msg.id, newJNull())
  of "tools/list":
    handleToolsList(msg.id)
  of "tools/call":
    handleToolsCall(msg.id, msg.params)
  else:
    methodNotFound(msg.id)
