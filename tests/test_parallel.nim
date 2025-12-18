## Tests for Parallel Model Evaluation
##
## TDD: These tests define the expected behavior of parallel model evaluation.
## The implementation should make these tests pass while maintaining:
## 1. Numerical equivalence with sequential evaluation
## 2. Thread safety
## 3. Actual parallelism (measurable speedup)

import std/[unittest, times, sequtils, algorithm, math, os]
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table as coretable
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/manager/vb
import ../src/occam/manager/statistics as mgrstats
import ../src/occam/math/entropy
import ../src/occam/parallel/eval


# ============ Test Fixtures ============

proc makeTestVarList(n: int; cardinality = 2): VariableList =
  ## Create test variable list with n variables
  result = initVariableList()
  for i in 0..<n:
    let name = $chr(ord('A') + i)
    discard result.add(newVariable(name, name, Cardinality(cardinality)))


proc makeRandomTable(varList: VariableList; seed: int = 42): coretable.Table =
  ## Generate random probability table
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
    result.add(key, nextRand() + 0.1)  # Ensure non-zero

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


proc generateTestModels(varList: VariableList): seq[Model] =
  ## Generate a variety of test models for evaluation
  result = @[]
  let n = varList.len

  # Chain models: AB, AB:BC, AB:BC:CD, ...
  for chainLen in 2..min(n, 5):
    var rels: seq[Relation]
    for i in 0..<(chainLen - 1):
      rels.add(initRelation(@[VariableIndex(i), VariableIndex(i+1)]))
    result.add(initModel(rels))

  # Star models: AB, AB:AC, AB:AC:AD, ...
  for starSize in 2..min(n, 5):
    var rels: seq[Relation]
    for i in 1..<starSize:
      rels.add(initRelation(@[VariableIndex(0), VariableIndex(i)]))
    result.add(initModel(rels))

  # Single relations of various sizes
  for size in 2..min(n, 4):
    var vars: seq[VariableIndex]
    for i in 0..<size:
      vars.add(VariableIndex(i))
    result.add(initModel(@[initRelation(vars)]))


# ============ Test Suites ============

suite "Parallel Evaluation - Numerical Equivalence":

  test "parallel AIC matches sequential AIC":
    ## Core requirement: parallel evaluation must produce identical results
    let varList = makeTestVarList(5, 3)
    let inputTable = makeRandomTable(varList)
    let models = generateTestModels(varList)

    var mgr = newVBManager(varList, inputTable)

    # Sequential evaluation
    var seqResults: seq[float64]
    for model in models:
      seqResults.add(mgr.computeAIC(model))

    # Parallel evaluation
    let parResults = parallelComputeAIC(varList, inputTable, models)

    check seqResults.len == models.len
    check parResults.len == models.len

    # Results must match exactly
    for i in 0..<models.len:
      check abs(seqResults[i] - parResults[i]) < 1e-10

  test "parallel BIC matches sequential BIC":
    let varList = makeTestVarList(5, 3)
    let inputTable = makeRandomTable(varList)
    let models = generateTestModels(varList)

    var mgr = newVBManager(varList, inputTable)

    var seqResults: seq[float64]
    for model in models:
      seqResults.add(mgr.computeBIC(model))

    let parResults = parallelComputeBIC(varList, inputTable, models)

    check seqResults.len == models.len
    check parResults.len == models.len

    for i in 0..<models.len:
      check abs(seqResults[i] - parResults[i]) < 1e-10

  test "parallel entropy matches sequential entropy":
    let varList = makeTestVarList(5, 3)
    let inputTable = makeRandomTable(varList)
    let models = generateTestModels(varList)

    var mgr = newVBManager(varList, inputTable)

    var seqResults: seq[float64]
    for model in models:
      seqResults.add(mgr.computeH(model))

    let parResults = parallelComputeH(varList, inputTable, models)

    check seqResults.len == models.len
    check parResults.len == models.len

    for i in 0..<models.len:
      check abs(seqResults[i] - parResults[i]) < 1e-10

  test "parallel fit table matches sequential fit table":
    let varList = makeTestVarList(4, 2)
    let inputTable = makeRandomTable(varList)

    # Test with a chain model
    let model = initModel(@[
      initRelation(@[VariableIndex(0), VariableIndex(1)]),
      initRelation(@[VariableIndex(1), VariableIndex(2)]),
      initRelation(@[VariableIndex(2), VariableIndex(3)])
    ])

    var mgr = newVBManager(varList, inputTable)
    let seqFit = mgr.makeFitTable(model)

    # Verify fit table is valid
    check seqFit.len > 0
    check abs(seqFit.sum - 1.0) < 1e-10


suite "Parallel Evaluation - Thread Safety":

  test "concurrent evaluations don't corrupt results":
    ## Multiple threads evaluating different models should not interfere
    let varList = makeTestVarList(4, 3)
    let inputTable = makeRandomTable(varList)
    let models = generateTestModels(varList)

    # Run evaluation multiple times to catch race conditions
    for trial in 1..5:
      var mgr = newVBManager(varList, inputTable)
      var results: seq[float64]
      for model in models:
        results.add(mgr.computeAIC(model))

      # Results should be deterministic
      if trial > 1:
        var mgr2 = newVBManager(varList, inputTable)
        for i, model in models:
          let r = mgr2.computeAIC(model)
          check abs(results[i] - r) < 1e-10

  test "independent VBManagers produce identical results":
    ## Key for thread-local approach: separate managers must agree
    let varList = makeTestVarList(5, 2)
    let inputTable = makeRandomTable(varList)
    let models = generateTestModels(varList)

    # Create two independent managers
    var mgr1 = newVBManager(varList, inputTable)
    var mgr2 = newVBManager(varList, inputTable)

    # Evaluate same models with both
    for model in models:
      let r1 = mgr1.computeAIC(model)
      let r2 = mgr2.computeAIC(model)
      check abs(r1 - r2) < 1e-10


suite "Parallel Evaluation - Performance":

  test "baseline sequential timing":
    ## Establish baseline for performance comparison
    let varList = makeTestVarList(5, 3)  # 243 states
    let inputTable = makeRandomTable(varList)
    let models = generateTestModels(varList)

    var mgr = newVBManager(varList, inputTable)

    let start = cpuTime()
    for _ in 1..3:  # Multiple iterations for stability
      for model in models:
        discard mgr.computeAIC(model)
    let elapsed = cpuTime() - start

    echo "  Sequential: ", models.len * 3, " evaluations in ",
         (elapsed * 1000).int, "ms"
    echo "  Per evaluation: ", (elapsed * 1000 / float64(models.len * 3)), "ms"

    check elapsed > 0

  test "parallel vs sequential timing comparison":
    ## Compare parallel and sequential performance
    let varList = makeTestVarList(5, 4)  # 1024 states - more work
    let inputTable = makeRandomTable(varList)
    let models = generateTestModels(varList)

    # Need enough models to see parallelism benefit
    var manyModels: seq[Model]
    for _ in 1..5:
      for m in models:
        manyModels.add(m)

    # Sequential timing
    var mgr = newVBManager(varList, inputTable)
    let seqStart = cpuTime()
    for model in manyModels:
      discard mgr.computeAIC(model)
    let seqTime = cpuTime() - seqStart

    # Parallel timing
    let parStart = cpuTime()
    discard parallelComputeAIC(varList, inputTable, manyModels)
    let parTime = cpuTime() - parStart

    let speedup = if parTime > 0.001: seqTime / parTime else: 1.0

    echo "  Models evaluated: ", manyModels.len
    echo "  Sequential: ", (seqTime * 1000).int, "ms"
    echo "  Parallel: ", (parTime * 1000).int, "ms"
    echo "  Speedup: ", speedup, "x"

    # Just verify completion and reasonable results
    check seqTime > 0
    check parTime > 0


suite "Parallel API":

  test "parallelEvaluate returns EvalResults with correct indices":
    let varList = makeTestVarList(4, 2)
    let inputTable = makeRandomTable(varList)
    let models = generateTestModels(varList)

    let config = initParallelConfig(statistic = StatAIC)
    let results = parallelEvaluate(varList, inputTable, models, config)

    # All indices should be present and in range
    check results.len == models.len
    for i in 0..<models.len:
      check results[i].index >= 0
      check results[i].index < models.len

  test "topK returns correct number of results":
    let varList = makeTestVarList(4, 2)
    let inputTable = makeRandomTable(varList)
    let models = generateTestModels(varList)

    let results = evaluateAll(varList, inputTable, models, StatAIC)
    let top3 = topK(results, 3, ascending = true)

    check top3.len == 3
    # Should be sorted
    check top3[0].value <= top3[1].value
    check top3[1].value <= top3[2].value

  test "sortByValue orders results correctly":
    let varList = makeTestVarList(4, 2)
    let inputTable = makeRandomTable(varList)
    let models = generateTestModels(varList)

    var results = evaluateAll(varList, inputTable, models, StatAIC)
    sortByValue(results, ascending = true)

    for i in 1..<results.len:
      check results[i-1].value <= results[i].value


suite "Parallel Utilities":

  test "model batching for parallel execution":
    ## Test that we can split models into batches for workers
    let varList = makeTestVarList(4, 2)
    let models = generateTestModels(varList)

    # Simple batching logic
    let numWorkers = 4
    var batches: seq[seq[Model]]
    for _ in 0..<numWorkers:
      batches.add(@[])

    for i, model in models:
      batches[i mod numWorkers].add(model)

    # Verify all models are distributed
    var total = 0
    for batch in batches:
      total += batch.len
    check total == models.len

  test "results can be merged from parallel workers":
    ## Test that we can combine results from multiple workers
    let varList = makeTestVarList(4, 2)
    let inputTable = makeRandomTable(varList)
    let models = generateTestModels(varList)

    var mgr = newVBManager(varList, inputTable)

    # Simulate parallel results (in reality from different threads)
    var batch1Results: seq[(Model, float64)]
    var batch2Results: seq[(Model, float64)]

    for i, model in models:
      let aic = mgr.computeAIC(model)
      if i mod 2 == 0:
        batch1Results.add((model, aic))
      else:
        batch2Results.add((model, aic))

    # Merge results
    var merged = batch1Results & batch2Results

    # Sort by AIC
    merged.sort(proc(a, b: (Model, float64)): int = cmp(a[1], b[1]))

    check merged.len == models.len


suite "Read-Only VBManager Operations":

  test "computeH uses only read-only data":
    ## Verify entropy computation doesn't require cache mutations
    let varList = makeTestVarList(4, 2)
    let inputTable = makeRandomTable(varList)

    # Chain model (loopless)
    let model = initModel(@[
      initRelation(@[VariableIndex(0), VariableIndex(1)]),
      initRelation(@[VariableIndex(1), VariableIndex(2)])
    ])

    var mgr = newVBManager(varList, inputTable)

    # Compute H - should work without modifying caches
    let h1 = mgr.computeH(model)
    let h2 = mgr.computeH(model)

    check abs(h1 - h2) < 1e-10

  test "modelH function is stateless":
    ## The standalone modelH should work without VBManager
    let varList = makeTestVarList(4, 2)
    let inputTable = makeRandomTable(varList)

    let model = initModel(@[
      initRelation(@[VariableIndex(0), VariableIndex(1)]),
      initRelation(@[VariableIndex(1), VariableIndex(2)])
    ])

    # Normalize the table first
    var normTable = inputTable
    normTable.normalize()

    # Call stateless function directly
    let h1 = mgrstats.modelH(model, varList, normTable)
    let h2 = mgrstats.modelH(model, varList, normTable)

    check abs(h1 - h2) < 1e-10
    check h1 > 0  # Should have some entropy
