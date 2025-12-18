## Parallel Model Evaluation using taskpools
##
## Modern parallel evaluation using nim-taskpools (work-stealing scheduler).
## Replaces the deprecated std/threadpool.
##
## PERFORMANCE NOTE:
## Benchmarking shows taskpools provides similar performance to std/threadpool,
## meaning NO speedup for typical workloads. The Belief Propagation algorithm
## is too fast (~0.1-3ms per model) for thread overhead to be amortized.
##
## This module exists for:
## - Future use when workloads become large enough to benefit
## - API compatibility with modern Nim threading best practices
##
## Install: nimble install taskpools
## Compile: nim c -r -d:release --threads:on yourfile.nim

import std/[cpuinfo, algorithm, math]
import taskpools
import ../core/types
import ../core/variable
import ../core/table as coretable
import ../core/relation
import ../core/model
import ../manager/vb

type
  Statistic* = enum
    StatAIC
    StatBIC
    StatH
    StatLR
    StatDF
    StatDDF

  # Simple result type that's GC-safe for channel passing
  SimpleResult* = object
    value*: float64
    index*: int32


# Global taskpool (lazily initialized)
var globalPool {.threadvar.}: Taskpool


proc getPool(): Taskpool =
  ## Get or create the global taskpool
  if globalPool.isNil:
    globalPool = Taskpool.new(numThreads = countProcessors())
  globalPool


proc shutdownPool*() =
  ## Shutdown the global pool (call at program end)
  if not globalPool.isNil:
    globalPool.shutdown()
    globalPool = nil


# Worker function - evaluate single model, return float64 (GC-safe)
proc evaluateModelWorker(
    varList: VariableList;
    inputTable: coretable.ContingencyTable;
    model: Model;
    statistic: Statistic
): float64 {.gcsafe, raises: [].} =
  ## Evaluate a single model - runs in worker thread
  ## Returns just the float64 value to avoid GC issues with channels
  {.cast(gcsafe).}:
    try:
      var mgr = newVBManager(varList, inputTable)

      case statistic
      of StatAIC: mgr.computeAIC(model)
      of StatBIC: mgr.computeBIC(model)
      of StatH: mgr.computeH(model)
      of StatLR: mgr.computeLR(model)
      of StatDF: float64(mgr.computeDF(model))
      of StatDDF: float64(mgr.computeDDF(model))
    except:
      NaN


proc parallelEvaluateTP*(
    varList: VariableList;
    inputTable: coretable.ContingencyTable;
    models: seq[Model];
    statistic = StatAIC;
    minBatchSize = 8
): seq[SimpleResult] =
  ## Evaluate models in parallel using taskpools
  ##
  ## Uses one task per model for work-stealing efficiency

  if models.len == 0:
    return @[]

  let pool = getPool()
  let numWorkers = countProcessors()

  # For small workloads, just run sequentially
  if models.len < numWorkers * minBatchSize:
    var mgr = newVBManager(varList, inputTable)
    result = newSeq[SimpleResult](models.len)
    for i, model in models:
      var value: float64
      case statistic
      of StatAIC: value = mgr.computeAIC(model)
      of StatBIC: value = mgr.computeBIC(model)
      of StatH: value = mgr.computeH(model)
      of StatLR: value = mgr.computeLR(model)
      of StatDF: value = float64(mgr.computeDF(model))
      of StatDDF: value = float64(mgr.computeDDF(model))
      result[i] = SimpleResult(value: value, index: int32(i))
    return

  # Spawn one task per model
  var futures: seq[Flowvar[float64]]
  for i in 0..<models.len:
    let m = models[i]
    futures.add(pool.spawn evaluateModelWorker(
      varList, inputTable, m, statistic
    ))

  # Collect results
  result = newSeq[SimpleResult](models.len)
  for i, future in futures:
    let value = sync(future)
    result[i] = SimpleResult(value: value, index: int32(i))


proc parallelComputeAIC_TP*(
    varList: VariableList;
    inputTable: coretable.ContingencyTable;
    models: seq[Model]
): seq[float64] =
  ## Convenience: compute AIC for all models in parallel
  let results = parallelEvaluateTP(varList, inputTable, models, StatAIC)
  result = newSeq[float64](models.len)
  for r in results:
    result[r.index] = r.value


proc parallelComputeBIC_TP*(
    varList: VariableList;
    inputTable: coretable.ContingencyTable;
    models: seq[Model]
): seq[float64] =
  ## Convenience: compute BIC for all models in parallel
  let results = parallelEvaluateTP(varList, inputTable, models, StatBIC)
  result = newSeq[float64](models.len)
  for r in results:
    result[r.index] = r.value


proc parallelComputeH_TP*(
    varList: VariableList;
    inputTable: coretable.ContingencyTable;
    models: seq[Model]
): seq[float64] =
  ## Convenience: compute entropy for all models in parallel
  let results = parallelEvaluateTP(varList, inputTable, models, StatH)
  result = newSeq[float64](models.len)
  for r in results:
    result[r.index] = r.value


# Export
export Statistic, SimpleResult
export parallelEvaluateTP, parallelComputeAIC_TP, parallelComputeBIC_TP, parallelComputeH_TP
export shutdownPool
