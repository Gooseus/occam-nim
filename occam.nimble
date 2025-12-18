# Package: occam (Core Library)
#
# This is the core OCCAM library. For CLI, web server, or MCP server,
# see the corresponding occam_*.nimble files.

version       = "0.1.0"
author        = "Shawn Marincas"
description   = "Reconstructability Analysis toolkit - discrete multivariate modeling with entropy methods"
license       = "GPL-3.0"
srcDir        = "src"

# Library installation - only install the occam library
installDirs   = @["occam"]
installFiles  = @["occam.nim"]
skipDirs      = @["cli_lib", "web_lib", "mcp_lib"]

# Core library dependencies (minimal)
requires "nim >= 2.0.0"
requires "distributions >= 0.1.0"
requires "jsony >= 1.1.0"
requires "malebolgia >= 0.1.0"

# Build switches - enable threads for parallelization
switch("threads", "on")

# Tasks

task test, "Run tests":
  exec "nim c -r --threads:on tests/test_all.nim"

task benchmark, "Run benchmarks with release mode":
  exec "nim c -d:release -r --threads:on tests/benchmark_ipf_vs_bp.nim"

# Convenience tasks for building other packages

task cli, "Build CLI (convenience - uses packages/occam_cli)":
  exec "nim c -d:release --threads:on -o:bin/cli src/cli.nim"

task web, "Build web server (requires packages/occam_web deps)":
  exec "nim c -d:release -d:logging --threads:on -o:bin/web src/web.nim"

task mcp, "Build MCP server (requires packages/occam_mcp deps)":
  exec "nim c -d:release -d:logging --threads:on -o:bin/mcp src/mcp.nim"
