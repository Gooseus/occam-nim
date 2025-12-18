## MCP Progress Notification Support
##
## Implements MCP protocol progress notifications per
## https://modelcontextprotocol.io/specification/2024-11-05/basic/utilities/progress
##
## Progress notifications are sent via stdout as JSON-RPC notifications.

import std/[json, strformat]
import ../occam/core/progress

type
  MCPProgressContext* = ref object
    ## Context for tracking progress in an MCP request.
    progressToken*: JsonNode
    lastProgress*: int  # Track monotonically increasing progress

proc sendProgressNotification*(token: JsonNode; progress: int; total: int;
                               message: string) =
  ## Send an MCP progress notification to stdout.
  ##
  ## Per MCP spec:
  ## - progressToken identifies the request
  ## - progress must monotonically increase
  ## - total may be 0 if unknown
  ## - message is optional human-readable status
  let notification = %*{
    "jsonrpc": "2.0",
    "method": "notifications/progress",
    "params": {
      "progressToken": token,
      "progress": progress,
      "total": total,
      "message": message
    }
  }
  stdout.writeLine($notification)
  stdout.flushFile()


proc makeMCPProgressCallback*(ctx: MCPProgressContext): ProgressCallback =
  ## Create a progress callback for MCP notifications.
  ##
  ## The callback sends JSON-RPC notifications with the progress token
  ## from the original request.
  ##
  ## Example:
  ##   var ctx = MCPProgressContext(progressToken: token, lastProgress: 0)
  ##   let config = initProgressConfig(callback = makeMCPProgressCallback(ctx))
  ##   parallelSearch(..., progress = config)

  result = proc(event: ProgressEvent) {.gcsafe.} =
    {.cast(gcsafe).}:
      var progress = ctx.lastProgress
      var total = 0
      var message = ""

      case event.kind
      of pkSearchStarted:
        progress = 0
        total = event.totalLevels
        message = &"Starting search (max {event.totalLevels} levels, optimizing {event.statisticName})"

      of pkSearchLevel:
        progress = event.currentLevel
        total = event.totalLevels
        if event.bestModelName != "":
          message = &"Level {event.currentLevel}/{event.totalLevels}: " &
                    &"{event.totalModelsEvaluated} models, " &
                    &"best {event.statisticName}={event.bestStatistic:.4f} ({event.bestModelName})"
        else:
          message = &"Level {event.currentLevel}/{event.totalLevels}: " &
                    &"{event.totalModelsEvaluated} models evaluated"

      of pkIPFIteration:
        # Don't increment progress for IPF, just update message
        message = &"IPF iteration {event.ipfIteration}: error={event.ipfError:.2e}"
        # Send without updating progress
        if ctx.progressToken.kind != JNull:
          sendProgressNotification(ctx.progressToken, ctx.lastProgress, event.totalLevels, message)
        return

      of pkSearchComplete:
        progress = event.totalLevels
        total = event.totalLevels
        message = &"Search complete: {event.totalModelsEvaluated} models, best={event.bestModelName}"

      of pkModelEvaluated:
        return  # Skip fine-grained updates for MCP

      # Ensure progress monotonically increases
      if progress > ctx.lastProgress and ctx.progressToken.kind != JNull:
        ctx.lastProgress = progress
        sendProgressNotification(ctx.progressToken, progress, total, message)
