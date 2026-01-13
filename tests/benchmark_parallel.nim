## Benchmark: Parallel vs Sequential Model Evaluation
##
## Tests various workload sizes to find the crossover point
## where parallelization becomes beneficial.
##
## Run with: nim c -r -d:release --threads:on tests/benchmark_parallel.nim

import std/[times, monotimes, strutils, strformat, algorithm, cpuinfo]
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table as coretable
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/manager/vb
import ../src/occam/parallel/eval


proc makeTestVarList(n: int; cardinality = 2): VariableList =
  result = initVariableList()
  for i in 0..<n:
    let name = $chr(ord('A') + i)
    discard result.add(newVariable(name, name, Cardinality(cardinality)))


proc makeRandomTable(varList: VariableList; seed: int = 42): coretable.Table =
  var totalStates = 1
  for i in 0..<varList.len:
    totalStates *= varList[VariableIndex(i)].cardinality.toInt

  result = coretable.initContingencyTable(varList.keySize, totalStates)

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
    result.add(key, nextRand() + 0.1)

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
  result.normalize()


proc generateModels(varList: VariableList; count: int): seq[Model] =
  ## Generate diverse models for benchmarking
  result = @[]
  let n = varList.len

  while result.len < count:
    # Chain models
    for chainLen in 2..min(n, 4):
      var rels: seq[Relation]
      for i in 0..<(chainLen - 1):
        rels.add(initRelation(@[VariableIndex(i), VariableIndex(i+1)]))
      result.add(initModel(rels))
      if result.len >= count: return

    # Star models
    for starSize in 2..min(n, 4):
      var rels: seq[Relation]
      for i in 1..<starSize:
        rels.add(initRelation(@[VariableIndex(0), VariableIndex(i)]))
      result.add(initModel(rels))
      if result.len >= count: return

    # Single larger relations
    for size in 2..min(n, 3):
      var vars: seq[VariableIndex]
      for i in 0..<size:
        vars.add(VariableIndex(i))
      result.add(initModel(@[initRelation(vars)]))
      if result.len >= count: return


type
  BenchResult = object
    numModels: int
    numVars: int
    cardinality: int
    stateSpace: int
    seqTimeMs: float64
    parTimeMs: float64
    speedup: float64


proc runBenchmark(numVars, cardinality, numModels: int): BenchResult =
  let varList = makeTestVarList(numVars, cardinality)
  let inputTable = makeRandomTable(varList)
  let models = generateModels(varList, numModels)

  result.numModels = models.len
  result.numVars = numVars
  result.cardinality = cardinality
  result.stateSpace = 1
  for i in 0..<numVars:
    result.stateSpace *= cardinality

  # Warm up
  var mgr = initVBManager(varList, inputTable)
  for m in models[0..min(2, models.len-1)]:
    discard mgr.computeAIC(m)
  discard parallelComputeAIC(varList, inputTable, models[0..min(2, models.len-1)])

  # Sequential timing (wall clock)
  let seqStart = getMonoTime()
  for model in models:
    discard mgr.computeAIC(model)
  result.seqTimeMs = float64(inNanoseconds(getMonoTime() - seqStart)) / 1_000_000.0

  # Parallel timing (wall clock)
  let parStart = getMonoTime()
  discard parallelComputeAIC(varList, inputTable, models)
  result.parTimeMs = float64(inNanoseconds(getMonoTime() - parStart)) / 1_000_000.0

  result.speedup = if result.parTimeMs > 0.1: result.seqTimeMs / result.parTimeMs else: 0.0


proc alignRight(s: string; width: int): string =
  if s.len >= width: s else: ' '.repeat(width - s.len) & s


proc main() =
  echo ""
  echo "=" .repeat(90)
  echo "PARALLEL vs SEQUENTIAL BENCHMARK"
  echo "=" .repeat(90)
  echo ""
  echo "CPU cores detected: ", countProcessors()
  echo ""

  var results: seq[BenchResult]

  # Test different configurations
  echo "Running benchmarks..."
  echo ""

  # Small state space, varying model count
  echo "Small state space (5 vars, card=2, 32 states):"
  for numModels in [10, 50, 100, 200, 500]:
    let r = runBenchmark(5, 2, numModels)
    results.add(r)
    echo fmt"  {numModels} models: seq={r.seqTimeMs:.1f}ms, par={r.parTimeMs:.1f}ms, speedup={r.speedup:.2f}x"

  echo ""
  echo "Medium state space (5 vars, card=3, 243 states):"
  for numModels in [10, 50, 100, 200]:
    let r = runBenchmark(5, 3, numModels)
    results.add(r)
    echo fmt"  {numModels} models: seq={r.seqTimeMs:.1f}ms, par={r.parTimeMs:.1f}ms, speedup={r.speedup:.2f}x"

  echo ""
  echo "Larger state space (5 vars, card=4, 1024 states):"
  for numModels in [10, 50, 100]:
    let r = runBenchmark(5, 4, numModels)
    results.add(r)
    echo fmt"  {numModels} models: seq={r.seqTimeMs:.1f}ms, par={r.parTimeMs:.1f}ms, speedup={r.speedup:.2f}x"

  echo ""
  echo "Large state space (6 vars, card=3, 729 states):"
  for numModels in [10, 50, 100]:
    let r = runBenchmark(6, 3, numModels)
    results.add(r)
    echo fmt"  {numModels} models: seq={r.seqTimeMs:.1f}ms, par={r.parTimeMs:.1f}ms, speedup={r.speedup:.2f}x"

  echo ""
  echo "Very large state space (6 vars, card=4, 4096 states):"
  for numModels in [10, 25, 50]:
    let r = runBenchmark(6, 4, numModels)
    results.add(r)
    echo fmt"  {numModels} models: seq={r.seqTimeMs:.1f}ms, par={r.parTimeMs:.1f}ms, speedup={r.speedup:.2f}x"

  echo ""
  echo "Huge state space (7 vars, card=4, 16384 states):"
  for numModels in [10, 25]:
    let r = runBenchmark(7, 4, numModels)
    results.add(r)
    echo fmt"  {numModels} models: seq={r.seqTimeMs:.1f}ms, par={r.parTimeMs:.1f}ms, speedup={r.speedup:.2f}x"

  echo ""
  echo "Massive state space (8 vars, card=3, 6561 states):"
  for numModels in [10, 25]:
    let r = runBenchmark(8, 3, numModels)
    results.add(r)
    echo fmt"  {numModels} models: seq={r.seqTimeMs:.1f}ms, par={r.parTimeMs:.1f}ms, speedup={r.speedup:.2f}x"

  # Summary
  echo ""
  echo "-" .repeat(90)
  echo "SUMMARY"
  echo "-" .repeat(90)

  var beneficialCount = 0
  var totalSpeedup = 0.0
  for r in results:
    if r.speedup > 1.0:
      beneficialCount += 1
      totalSpeedup += r.speedup

  echo fmt"Configurations tested: {results.len}"
  echo fmt"Configs where parallel is faster: {beneficialCount}"
  if beneficialCount > 0:
    echo fmt"Average speedup (when beneficial): {totalSpeedup / float64(beneficialCount):.2f}x"

  # Find crossover points
  echo ""
  echo "OBSERVATIONS:"
  var minBeneficialModels = int.high
  var minBeneficialStates = int.high
  for r in results:
    if r.speedup > 1.1:  # At least 10% improvement
      if r.numModels < minBeneficialModels:
        minBeneficialModels = r.numModels
      if r.stateSpace < minBeneficialStates:
        minBeneficialStates = r.stateSpace

  if minBeneficialModels < int.high:
    echo fmt"- Parallelization helps with ~{minBeneficialModels}+ models"
  if minBeneficialStates < int.high:
    echo fmt"- Parallelization helps with ~{minBeneficialStates}+ state space"
  echo ""


when isMainModule:
  main()
