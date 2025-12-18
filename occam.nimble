# Package

version       = "0.1.0"
author        = "Shawn Marincas"
description   = "Reconstructability Analysis toolkit - port of OCCAM to Nim"
license       = "GPL-3.0"
srcDir        = "src"
bin           = @["cli"]
binDir        = "bin"

# Dependencies

requires "nim >= 2.0.0"
requires "cligen >= 1.7.0"
requires "distributions >= 0.1.0"
requires "jsony >= 1.1.0"
requires "primes >= 0.1.0"
requires "malebolgia >= 0.1.0"

# Build switches - enable threads for parallelization
switch("threads", "on")

# Tasks

task build, "Build CLI with release optimizations":
  exec "nim c -d:release --threads:on -o:bin/cli src/cli.nim"

task test, "Run tests":
  exec "nim c -r --threads:on tests/test_all.nim"

task benchmark, "Run benchmarks with release mode":
  exec "nim c -d:release -r --threads:on tests/benchmark_ipf_vs_bp.nim"
