## OCCAM Web Server
##
## Prologue-based REST API server for OCCAM.
## Provides endpoints for model fitting, search, and data analysis.
##
## Usage:
##   nim c -r -d:logging src/web.nim
##   # Server starts on http://localhost:8080
##
## Endpoints:
##   GET  /api/health    - Health check
##   POST /api/data/info - Get dataset information
##   POST /api/model/fit - Fit a model
##   POST /api/search    - Run model search

import std/[json, strutils]
import prologue
import jsony

when defined(logging):
  import chronicles

import web_lib/[models, logic]

# Cast to bypass GC-safe checks for the occam core library
# This is safe because we're running in a single-threaded async context
template gcsafeCall(body: untyped) =
  {.gcsafe.}:
    body

# Request handlers

proc healthHandler(ctx: Context) {.async, gcsafe.} =
  ## Health check endpoint
  when defined(logging):
    debug "Health check requested"

  let resp = processHealthCheck()
  resp jsonResponse(%*{"status": resp.status, "version": resp.version})


proc dataInfoHandler(ctx: Context) {.async, gcsafe.} =
  ## Get information about a dataset
  when defined(logging):
    debug "Data info requested"

  try:
    let body = ctx.request.body
    let dataJson = body.parseJson()["data"].getStr()
    var resp: DataInfoResponse
    gcsafeCall:
      resp = processDataInfo(dataJson)

    resp jsonResponse(%*{
      "name": resp.name,
      "variableCount": resp.variableCount,
      "sampleSize": resp.sampleSize,
      "variables": resp.variables
    })
  except Exception as e:
    when defined(logging):
      error "Data info failed", error = e.msg
    resp jsonResponse(%*{"error": "parse_error", "message": e.msg}, Http400)


proc fitModelHandler(ctx: Context) {.async, gcsafe.} =
  ## Fit a model and return statistics
  when defined(logging):
    debug "Fit model requested"

  try:
    let req = ctx.request.body.fromJson(FitRequest)

    when defined(logging):
      info "Fitting model", model = req.model

    var resp: FitResponse
    gcsafeCall:
      resp = processFitModel(req)

    resp jsonResponse(%*{
      "model": resp.model,
      "h": resp.h,
      "t": resp.t,
      "df": resp.df,
      "ddf": resp.ddf,
      "lr": resp.lr,
      "aic": resp.aic,
      "bic": resp.bic,
      "alpha": resp.alpha,
      "hasLoops": resp.hasLoops,
      "ipfIterations": resp.ipfIterations,
      "ipfError": resp.ipfError
    })
  except Exception as e:
    when defined(logging):
      error "Fit model failed", error = e.msg
    resp jsonResponse(%*{"error": "fit_error", "message": e.msg}, Http400)


proc searchHandler(ctx: Context) {.async, gcsafe.} =
  ## Run model search
  when defined(logging):
    debug "Search requested"

  try:
    # Parse request with defaults
    var req = initSearchRequest()
    let body = ctx.request.body.parseJson()

    if body.hasKey("data"):
      req.data = body["data"].getStr()
    if body.hasKey("direction"):
      req.direction = body["direction"].getStr()
    if body.hasKey("filter"):
      req.filter = body["filter"].getStr()
    if body.hasKey("width"):
      req.width = body["width"].getInt()
    if body.hasKey("levels"):
      req.levels = body["levels"].getInt()
    if body.hasKey("sortBy"):
      req.sortBy = body["sortBy"].getStr()

    when defined(logging):
      info "Running search", direction = req.direction, filter = req.filter, width = req.width

    var resp: SearchResponse
    gcsafeCall:
      resp = processSearch(req)

    resp jsonResponse(%*{
      "totalEvaluated": resp.totalEvaluated,
      "results": resp.results
    })
  except Exception as e:
    when defined(logging):
      error "Search failed", error = e.msg
    resp jsonResponse(%*{"error": "search_error", "message": e.msg}, Http400)


# CORS middleware for React dev server
proc corsMiddleware(): HandlerAsync =
  result = proc(ctx: Context) {.async.} =
    ctx.response.setHeader("Access-Control-Allow-Origin", "*")
    ctx.response.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    ctx.response.setHeader("Access-Control-Allow-Headers", "Content-Type")

    if ctx.request.reqMethod == HttpOptions:
      ctx.response.code = Http200
      resp ""
    else:
      await switch(ctx)


proc main() =
  when defined(logging):
    info "Starting OCCAM web server", port = 8080

  let settings = newSettings(
    port = Port(8080),
    debug = true
  )

  var app = newApp(settings = settings)

  # Add CORS middleware
  app.use(corsMiddleware())

  # API routes
  app.addRoute("/api/health", healthHandler, HttpGet)
  app.addRoute("/api/data/info", dataInfoHandler, HttpPost)
  app.addRoute("/api/model/fit", fitModelHandler, HttpPost)
  app.addRoute("/api/search", searchHandler, HttpPost)

  echo "OCCAM Web Server starting on http://localhost:8080"
  echo "Endpoints:"
  echo "  GET  /api/health    - Health check"
  echo "  POST /api/data/info - Get dataset information"
  echo "  POST /api/model/fit - Fit a model"
  echo "  POST /api/search    - Run model search"

  app.run()


when isMainModule:
  main()
