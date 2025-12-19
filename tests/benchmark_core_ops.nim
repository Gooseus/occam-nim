## Micro-benchmarks for core table and key operations
##
## These benchmarks measure the performance of hot-path operations:
## - Key: getValue, setValue, applyMask, matches
## - Table: project, sumInto, find, add
##
## Run with: nim c -r -d:release tests/benchmark_core_ops.nim

import std/[times, monotimes, strformat, strutils, options]
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table as coretable

const
  WarmupRuns = 10
  BenchmarkRuns = 100


type
  BenchResult = object
    name: string
    opsPerRun: int
    totalMs: float64
    avgNsPerOp: float64


proc formatNs(ns: float64): string =
  if ns < 1000:
    fmt"{ns:.1f} ns"
  elif ns < 1_000_000:
    fmt"{ns / 1000:.2f} us"
  else:
    fmt"{ns / 1_000_000:.2f} ms"


proc runBenchmark(name: string; opsPerRun: int; warmup, runs: int;
                  body: proc()): BenchResult =
  result.name = name
  result.opsPerRun = opsPerRun

  # Warmup
  for _ in 0..<warmup:
    body()

  # Benchmark (wall clock)
  let start = getMonoTime()
  for _ in 0..<runs:
    body()
  let elapsedNs = inNanoseconds(getMonoTime() - start)

  result.totalMs = float64(elapsedNs) / 1_000_000.0
  result.avgNsPerOp = float64(elapsedNs) / float64(runs * opsPerRun)


proc printResults(results: seq[BenchResult]) =
  echo ""
  echo '='.repeat(80)
  echo "MICRO-BENCHMARK RESULTS: Core Operations"
  echo '='.repeat(80)
  echo ""

  let col1 = 40
  let col2 = 15
  let col3 = 15

  echo ' '.repeat(col1) & "Total Time".center(col2) & "Per Operation".center(col3)
  echo '-'.repeat(80)

  for r in results:
    let nameCol = if r.name.len > col1 - 2: r.name[0..<col1-2] else: r.name
    let totalStr = fmt"{r.totalMs:.2f} ms"
    let perOpStr = formatNs(r.avgNsPerOp)
    echo nameCol.alignLeft(col1) & totalStr.center(col2) & perOpStr.center(col3)

  echo '-'.repeat(80)
  echo ""


proc makeTestVarList(n: int; cardinality = 4): VariableList =
  result = initVariableList()
  for i in 0..<n:
    let name = $chr(ord('A') + i)
    discard result.add(newVariable(name, name, Cardinality(cardinality)))


proc makeTestTable(varList: VariableList; seed: int = 42): coretable.Table =
  var totalStates = 1
  for i in 0..<varList.len:
    totalStates *= varList[VariableIndex(i)].cardinality.toInt

  result = coretable.initTable(varList.keySize, totalStates)

  var rng = seed
  proc nextRand(): float64 =
    rng = (rng * 1103515245 + 12345) mod (1 shl 31)
    float64(rng) / float64(1 shl 31)

  var indices = newSeq[int](varList.len)
  var done = false
  while not done:
    var keyPairs: seq[(VariableIndex, int)]
    for i in 0..<varList.len:
      keyPairs.add((VariableIndex(i), indices[i]))
    let key = varList.buildKey(keyPairs)
    result.add(key, nextRand())

    var carry = true
    for i in 0..<varList.len:
      if carry:
        indices[i] += 1
        if indices[i] >= varList[VariableIndex(i)].cardinality.toInt:
          indices[i] = 0
        else:
          carry = false
    if carry:
      done = true

  result.sort()


proc benchmarkKeyOps() =
  echo "=== Key Operations ==="
  echo ""

  var results: seq[BenchResult]

  # Setup: 6 variables, cardinality 4 each
  let varList = makeTestVarList(6, 4)
  let keySize = varList.keySize

  # Benchmark Key.getValue
  block:
    var k = newKey(keySize)
    for i in 0..<6:
      k.setValue(varList, VariableIndex(i), i mod 4)

    var sum = 0
    let ops = 6 * 10000
    let r = runBenchmark("Key.getValue", ops, WarmupRuns, BenchmarkRuns) do ():
      for _ in 0..<10000:
        for i in 0..<6:
          sum += k.getValue(varList, VariableIndex(i))

    results.add(r)
    discard sum  # Prevent optimization

  # Benchmark Key.setValue
  block:
    var k = newKey(keySize)
    let ops = 6 * 10000
    let r = runBenchmark("Key.setValue", ops, WarmupRuns, BenchmarkRuns) do ():
      for iter in 0..<10000:
        for i in 0..<6:
          k.setValue(varList, VariableIndex(i), (iter + i) mod 4)

    results.add(r)

  # Benchmark Key.applyMask (project to 3 variables)
  block:
    var k = newKey(keySize)
    for i in 0..<6:
      k.setValue(varList, VariableIndex(i), i mod 4)
    let mask = varList.buildMask(@[VariableIndex(0), VariableIndex(2), VariableIndex(4)])

    var projected: Key
    let ops = 10000
    let r = runBenchmark("Key.applyMask (3 vars)", ops, WarmupRuns, BenchmarkRuns) do ():
      for _ in 0..<ops:
        projected = k.applyMask(mask)

    results.add(r)
    discard projected

  # Benchmark Key.matches
  block:
    var k1 = newKey(keySize)
    var k2 = newKey(keySize)
    for i in 0..<6:
      k1.setValue(varList, VariableIndex(i), i mod 4)
      k2.setValue(varList, VariableIndex(i), i mod 4)

    var matchCount = 0
    let ops = 10000
    let r = runBenchmark("Key.matches (exact)", ops, WarmupRuns, BenchmarkRuns) do ():
      for _ in 0..<ops:
        if k1.matches(k2):
          matchCount += 1

    results.add(r)
    discard matchCount

  # Benchmark Key comparison (<)
  block:
    var k1 = newKey(keySize)
    var k2 = newKey(keySize)
    for i in 0..<6:
      k1.setValue(varList, VariableIndex(i), 1)
      k2.setValue(varList, VariableIndex(i), 2)

    var lessCount = 0
    let ops = 10000
    let r = runBenchmark("Key comparison (<)", ops, WarmupRuns, BenchmarkRuns) do ():
      for _ in 0..<ops:
        if k1 < k2:
          lessCount += 1

    results.add(r)
    discard lessCount

  # Benchmark buildKey
  block:
    let ops = 1000
    var k: Key
    let r = runBenchmark("buildKey (6 pairs)", ops, WarmupRuns, BenchmarkRuns) do ():
      for _ in 0..<ops:
        k = varList.buildKey(@[
          (VariableIndex(0), 1), (VariableIndex(1), 2), (VariableIndex(2), 3),
          (VariableIndex(3), 0), (VariableIndex(4), 1), (VariableIndex(5), 2)
        ])

    results.add(r)
    discard k

  printResults(results)


proc benchmarkTableOps() =
  echo "=== Table Operations ==="
  echo ""

  var results: seq[BenchResult]

  # Setup: 4 variables, cardinality 4 each (256 states)
  let varList4 = makeTestVarList(4, 4)
  let table4 = makeTestTable(varList4)

  # Setup: 6 variables, cardinality 3 each (729 states)
  let varList6 = makeTestVarList(6, 3)
  let table6 = makeTestTable(varList6)

  # Benchmark Table.project (4 vars -> 2 vars)
  block:
    let ops = 100
    var proj: coretable.Table
    let r = runBenchmark("Table.project (256->16)", ops, WarmupRuns, BenchmarkRuns) do ():
      for _ in 0..<ops:
        proj = table4.project(varList4, @[VariableIndex(0), VariableIndex(2)])

    results.add(r)
    discard proj

  # Benchmark Table.project (6 vars -> 2 vars)
  block:
    let ops = 50
    var proj: coretable.Table
    let r = runBenchmark("Table.project (729->9)", ops, WarmupRuns, BenchmarkRuns) do ():
      for _ in 0..<ops:
        proj = table6.project(varList6, @[VariableIndex(0), VariableIndex(3)])

    results.add(r)
    discard proj

  # Benchmark Table.sumInto
  block:
    let ops = 100
    let r = runBenchmark("Table.sumInto (256 tuples)", ops, WarmupRuns, BenchmarkRuns) do ():
      for _ in 0..<ops:
        var t = coretable.initTable(varList4.keySize, 512)
        # Add duplicate keys
        for tup in table4:
          t.add(tup)
          t.add(tup)
        t.sort()
        t.sumInto()

    results.add(r)

  # Benchmark Table.find (binary search)
  block:
    let testKeys: seq[Key] = block:
      var keys: seq[Key]
      for i, tup in table4:
        if i mod 16 == 0:  # Sample every 16th key
          keys.add(tup.key)
      keys

    let ops = testKeys.len * 100
    var found = 0
    let r = runBenchmark("Table.find (binary search)", ops, WarmupRuns, BenchmarkRuns) do ():
      for _ in 0..<100:
        for key in testKeys:
          if table4.find(key).isSome:
            found += 1

    results.add(r)
    discard found

  # Benchmark Table.add
  block:
    let keySize = varList4.keySize
    let ops = 256
    let r = runBenchmark("Table.add (256 tuples)", ops, WarmupRuns, BenchmarkRuns) do ():
      var t = coretable.initTable(keySize, 256)
      for tup in table4:
        t.add(tup.key, tup.value)

    results.add(r)

  # Benchmark Table.normalize
  block:
    let ops = 100
    let r = runBenchmark("Table.normalize (256)", ops, WarmupRuns, BenchmarkRuns) do ():
      for _ in 0..<ops:
        var t = table4
        t.normalize()

    results.add(r)

  # Benchmark Table.sum
  block:
    let ops = 1000
    var total = 0.0
    let r = runBenchmark("Table.sum (256 tuples)", ops, WarmupRuns, BenchmarkRuns) do ():
      for _ in 0..<ops:
        total += table4.sum()

    results.add(r)
    discard total

  # Benchmark Table iteration
  block:
    let ops = 500
    var count = 0
    let r = runBenchmark("Table iteration (256)", ops, WarmupRuns, BenchmarkRuns) do ():
      for _ in 0..<ops:
        for tup in table4:
          count += 1
          discard tup.value

    results.add(r)
    discard count

  printResults(results)


proc benchmarkCombinedOps() =
  echo "=== Combined Operations (IPF-like) ==="
  echo ""

  var results: seq[BenchResult]

  # Setup: simulate IPF-style operations
  let varList = makeTestVarList(5, 3)  # 243 states
  let table = makeTestTable(varList)

  # Benchmark: project + scale (IPF inner loop pattern)
  block:
    let mask = varList.buildMask(@[VariableIndex(0), VariableIndex(1), VariableIndex(2)])
    let marginal = table.project(varList, @[VariableIndex(0), VariableIndex(1), VariableIndex(2)])

    let ops = 50
    let r = runBenchmark("Project + lookup (IPF pattern)", ops, WarmupRuns, BenchmarkRuns) do ():
      for _ in 0..<ops:
        var scaled = coretable.initTable(varList.keySize, table.len)
        for tup in table:
          let projKey = tup.key.applyMask(mask)
          let idx = marginal.find(projKey)
          var scale = 1.0
          if idx.isSome:
            scale = marginal[idx.get].value
          scaled.add(tup.key, tup.value * scale)

    results.add(r)

  # Benchmark: full projection chain (6 vars -> 3 -> 2 -> 1)
  block:
    let varList6 = makeTestVarList(6, 2)  # 64 states
    let table6 = makeTestTable(varList6)

    let ops = 100
    let r = runBenchmark("Projection chain (64->8->4->2)", ops, WarmupRuns, BenchmarkRuns) do ():
      for _ in 0..<ops:
        let p1 = table6.project(varList6, @[VariableIndex(0), VariableIndex(2), VariableIndex(4)])
        let p2 = p1.project(varList6, @[VariableIndex(0), VariableIndex(4)])
        discard p2.project(varList6, @[VariableIndex(0)])

    results.add(r)

  printResults(results)


proc main() =
  echo ""
  echo "Running micro-benchmarks for core operations..."
  echo fmt"Warmup: {WarmupRuns} runs, Benchmark: {BenchmarkRuns} runs"
  echo ""

  benchmarkKeyOps()
  benchmarkTableOps()
  benchmarkCombinedOps()

  echo "Benchmarks complete."
  echo ""


when isMainModule:
  main()
