# Package: occam_cli (Command-Line Interface)
#
# Command-line interface for OCCAM.
# Install: cd packages/occam_cli && nimble install
# Build: nimble build

version       = "0.1.0"
author        = "Shawn Marincas"
description   = "OCCAM CLI - command-line interface for Reconstructability Analysis"
license       = "MIT"
srcDir        = "../../src"
bin           = @["cli"]
binDir        = "../../bin"

# Dependencies
requires "nim >= 2.0.0"
requires "cligen >= 1.7.0"
requires "distributions >= 0.1.0"
requires "jsony >= 1.1.0"
requires "malebolgia >= 0.1.0"
requires "primes >= 0.1.0"

# Build switches
switch("threads", "on")

# Tasks

task build, "Build CLI with release optimizations":
  exec "nim c -d:release --threads:on -o:../../bin/cli ../../src/cli.nim"
