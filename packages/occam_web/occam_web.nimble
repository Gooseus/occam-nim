# Package: occam_web (Web Server)
#
# Prologue-based REST API server for OCCAM.
# Install: cd packages/occam_web && nimble install
# Build: nimble build

version       = "0.1.0"
author        = "Shawn Marincas"
description   = "OCCAM Web Server - REST API and static file server"
license       = "MIT"
srcDir        = "../../src"
bin           = @["web"]
binDir        = "../../bin"

# Dependencies
requires "nim >= 2.0.0"
requires "prologue >= 0.6.6"
requires "websocketx >= 0.1.2"
requires "chronicles >= 0.10.0"
requires "distributions >= 0.1.0"
requires "jsony >= 1.1.0"
requires "malebolgia >= 0.1.0"

# Build switches
switch("threads", "on")

# Tasks

task build, "Build web server with release optimizations":
  exec "nim c -d:release -d:logging --threads:on -o:../../bin/web ../../src/web.nim"

task dev, "Run in development mode":
  exec "nim c -r -d:logging --threads:on ../../src/web.nim"

task jsbin, "Build JavaScript binning module for browser":
  exec "nim js -d:release -o:../../src/static/public/binning.js ../../src/occam_binning_js.nim"
