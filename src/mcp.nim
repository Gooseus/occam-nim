## OCCAM MCP Server
##
## Model Context Protocol server for OCCAM.
## Communicates via JSON-RPC 2.0 over stdio.
##
## Usage:
##   nim c -d:release src/mcp.nim
##   ./mcp  # Reads JSON-RPC from stdin, writes to stdout
##
## MCP Configuration (add to claude_desktop_config.json):
##   {
##     "mcpServers": {
##       "occam": {
##         "command": "/path/to/occam-nim/bin/mcp"
##       }
##     }
##   }

import std/[json, strutils]
import jsony

when defined(logging):
  import chronicles

import mcp_lib/[jsonrpc, protocol]

proc main() =
  when defined(logging):
    info "OCCAM MCP server starting"

  # Process messages from stdin
  while true:
    try:
      let line = stdin.readLine()

      # Skip empty lines
      if line.strip().len == 0:
        continue

      when defined(logging):
        debug "Received message", length = line.len

      # Parse the request
      var request: JsonRpcRequest
      try:
        request = line.fromJson(JsonRpcRequest)
      except:
        # Send parse error
        let response = parseError()
        stdout.writeLine(response.toJson())
        stdout.flushFile()
        continue

      # Handle the message
      let response = handleMessage(request)

      # Send response (skip for notifications with null id)
      if response.id.kind != JNull or response.error.kind != JNull:
        stdout.writeLine(response.toJson())
        stdout.flushFile()

      when defined(logging):
        debug "Sent response", methodName = request.`method`

    except IOError:
      # stdin closed, exit gracefully
      when defined(logging):
        info "stdin closed, shutting down"
      break

    except Exception as e:
      # Unexpected error, send internal error and continue
      when defined(logging):
        error "Unexpected error", message = e.msg

      let response = internalError(newJNull(), e.msg)
      stdout.writeLine(response.toJson())
      stdout.flushFile()


when isMainModule:
  main()
