# Package: occam_mcp (MCP Server)
#
# Model Context Protocol server for OCCAM.
# Install: cd packages/occam_mcp && nimble install
# Build: nimble build

version       = "0.1.0"
author        = "Shawn Marincas"
description   = "OCCAM MCP Server - Model Context Protocol integration for AI tools"
license       = "GPL-3.0"
srcDir        = "../../src"
bin           = @["mcp"]
binDir        = "../../bin"

# Dependencies
requires "nim >= 2.0.0"
requires "chronicles >= 0.10.0"
requires "distributions >= 0.1.0"
requires "jsony >= 1.1.0"
requires "malebolgia >= 0.1.0"

# Build switches
switch("threads", "on")

# Tasks

task build, "Build MCP server with release optimizations":
  exec "nim c -d:release -d:logging --threads:on -o:../../bin/mcp ../../src/mcp.nim"
