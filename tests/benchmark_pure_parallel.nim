## Benchmark: Pure Parallel Test (No OCCAM code)
##
## Tests if Nim's parallelization works correctly without our code.
## This isolates whether the issue is in Nim's threading or our code.

import std/[times, strformat, strutils, cpuinfo, atomics, monotimes]
import malebolgia

var gResults: array[6, Atomic[float64]]

proc heavyComputation(iterations: int): float64 {.gcsafe.} =
  ## Pure CPU work, no allocations, no shared state
  var sum = 0.0
  for i in 0..<iterations:
    sum += float64(i) * 0.001
    sum = sum / 1.00001  # Prevent optimization
  sum


proc heavyComputationInto(idx: int; iterations: int) {.gcsafe.} =
  ## Store result in global array
  let r = heavyComputation(iterations)
  gResults[idx].store(r)


proc main() =
  echo ""
  echo "=" .repeat(60)
  echo "PURE PARALLEL TEST (MALEBOLGIA ONLY)"
  echo "=" .repeat(60)
  echo ""
  echo "CPU cores: ", countProcessors()
  echo ""

  const numTasks = 6
  const iterationsPerTask = 50_000_000  # ~100ms per task

  # Sequential
  echo "Sequential..."
  let seqStart = getMonoTime()
  var seqResults: array[numTasks, float64]
  for i in 0..<numTasks:
    seqResults[i] = heavyComputation(iterationsPerTask)
  let seqMs = (getMonoTime() - seqStart).inMilliseconds.float64
  echo &"  Time: {seqMs:.1f}ms ({seqMs/float64(numTasks):.1f}ms per task)"

  # Parallel with malebolgia (using void proc that stores to global)
  echo ""
  echo "Parallel (malebolgia)..."
  let malStart = getMonoTime()
  var m = createMaster()
  m.awaitAll:
    for i in 0..<numTasks:
      m.spawn heavyComputationInto(i, iterationsPerTask)
  let malMs = (getMonoTime() - malStart).inMilliseconds.float64

  var malResults: array[numTasks, float64]
  for i in 0..<numTasks:
    malResults[i] = gResults[i].load()
  echo &"  Time: {malMs:.1f}ms  Speedup: {seqMs/malMs:.2f}x"

  # Verify results match
  var match = true
  for i in 0..<numTasks:
    if abs(seqResults[i] - malResults[i]) > 0.001:
      match = false
  echo ""
  echo "Results match: ", match

  echo ""
  echo "=" .repeat(60)
  echo "ANALYSIS"
  echo "=" .repeat(60)
  echo ""
  echo &"Sequential:   {seqMs:>8.1f}ms"
  echo &"Malebolgia:   {malMs:>8.1f}ms  ({seqMs/malMs:.2f}x)"
  echo ""
  echo &"Expected parallel time: {seqMs/float64(min(numTasks, countProcessors())):.1f}ms"
  echo &"Actual parallel time:   {malMs:.1f}ms"
  echo ""

  if seqMs/malMs > 2.0:
    echo "RESULT: Parallelization works for pure CPU work."
    echo "The issue is memory/allocation in OCCAM code."
  else:
    echo "RESULT: Parallelization overhead is too high even for pure CPU."
    echo "This suggests a fundamental issue with Nim's threading on this system."
  echo ""


when isMainModule:
  main()
