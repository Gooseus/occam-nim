# Package

version       = "0.1.0"
author        = "Shawn Marincas"
description   = "Reconstructability Analysis toolkit - discrete multivariate modeling with entropy methods"
license       = "GPL-3.0"
srcDir        = "src"

# Library installation - only install the occam library, not CLI code
installDirs   = @["occam"]
installFiles  = @["occam.nim"]
skipDirs      = @["cli_lib"]

# CLI binary (optional - built separately with `nimble build`)
bin           = @["cli"]
binDir        = "bin"

# Keywords for nimble.directory
# namedBin not supported, using standard bin

# Core library dependencies
requires "nim >= 2.0.0"
requires "distributions >= 0.1.0"
requires "jsony >= 1.1.0"
requires "malebolgia >= 0.1.0"

# Optional dependencies (document in README)
# - primes: Only needed for sequence generation features
# - cligen: Only needed if building CLI
requires "primes >= 0.1.0"
requires "cligen >= 1.7.0"

# Build switches - enable threads for parallelization
switch("threads", "on")

# Tasks

task build, "Build CLI with release optimizations":
  exec "nim c -d:release --threads:on -o:bin/cli src/cli.nim"

task test, "Run tests":
  exec "nim c -r --threads:on tests/test_all.nim"

task benchmark, "Run benchmarks with release mode":
  exec "nim c -d:release -r --threads:on tests/benchmark_ipf_vs_bp.nim"
