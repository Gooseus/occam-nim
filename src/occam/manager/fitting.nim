## Fitting computation for OCCAM
## Pure functions for model fitting that don't depend on VBManager
##
## These functions operate on Model, VariableList, and Table directly

{.push raises: [].}

import std/[options, monotimes, times]
import ../core/types
import ../core/variable
import ../core/key
import ../core/table as coretable
import ../core/relation
import ../core/model
import ../core/junction_tree
import ../core/errors
import ../core/iterators
import ../math/ipf
import ../math/belief_propagation as bp


# ============ Independence Model Fitting ============

proc fitIndependenceModel*(data: coretable.ContingencyTable; varList: VariableList): coretable.ContingencyTable =
  ## Compute fitted distribution for independence model
  ## P(X1, X2, ...) = P(X1) * P(X2) * ...
  result = coretable.initContingencyTable(varList.keySize)

  # Get marginals for each variable
  var marginals: seq[coretable.ContingencyTable]
  for i in 0..<varList.len:
    let proj = data.project(varList, @[VariableIndex(i)])
    marginals.add(proj)

  # Build cardinalities sequence for iterator
  var cardinalities: seq[int]
  for i in 0..<varList.len:
    cardinalities.add(varList[VariableIndex(i)].cardinality.toInt)

  # Enumerate all state combinations using iterator
  for stateIndices in stateEnumeration(cardinalities):
    # Compute product of marginal probabilities
    var prob = 1.0
    var keyPairs: seq[(VariableIndex, int)]

    for i in 0..<varList.len:
      keyPairs.add((VariableIndex(i), stateIndices[i]))

      # Find this variable's marginal probability
      let varKey = varList.buildKey(@[(VariableIndex(i), stateIndices[i])])
      let idx = marginals[i].find(varKey)
      if idx.isSome:
        prob *= marginals[i][idx.get].value
      else:
        prob = 0.0
        break

    if prob > ProbMin:
      let fullKey = varList.buildKey(keyPairs)
      result.add(fullKey, prob)

  result.sort()


# ============ General Model Fitting ============

type
  FitType* = enum
    ## Type of fitting algorithm used
    ftSaturated       ## Saturated model - no fitting needed
    ftIndependence    ## Independence model - product of marginals
    ftLoopless        ## Loopless model - belief propagation
    ftIPF             ## Loop model - IPF

  FitInfo* = object
    ## Information about the fitting process
    fitTable*: coretable.ContingencyTable
    iterations*: int
    error*: float64
    usedIPF*: bool
    jtFailed*: bool  # True if junction tree construction failed
    # Timing information
    fitType*: FitType             ## Type of fit performed
    fitTimeNs*: int64             ## Total fit time in nanoseconds
    # BP timing (when fitType == ftLoopless)
    bpCollectNs*: int64           ## BP collect phase time
    bpDistributeNs*: int64        ## BP distribute phase time
    # IPF timing (when fitType == ftIPF, uses recordIterationTimes)
    ipfTotalNs*: int64            ## Total IPF time
    ipfIterTimesNs*: seq[int64]   ## Per-iteration IPF times

  FitConfig* = object
    ## Configuration for model fitting
    raiseOnJTFailure*: bool       # Raise JunctionTreeError if JT build fails (default: false)
    raiseOnNonConvergence*: bool  # Raise ConvergenceError if IPF doesn't converge (default: false)
    recordTiming*: bool           # Record timing information (default: true)
    ipfProgressCallback*: ipf.IPFProgressCallback  # Optional IPF progress callback
    ipfProgressInterval*: int     # IPF progress reporting interval (default: 100)


proc initFitConfig*(raiseOnJTFailure = false; raiseOnNonConvergence = false;
                    recordTiming = true;
                    ipfProgressCallback: ipf.IPFProgressCallback = nil;
                    ipfProgressInterval = 100): FitConfig =
  result.raiseOnJTFailure = raiseOnJTFailure
  result.raiseOnNonConvergence = raiseOnNonConvergence
  result.recordTiming = recordTiming
  result.ipfProgressCallback = ipfProgressCallback
  result.ipfProgressInterval = ipfProgressInterval


proc fitModelTable*(data: coretable.ContingencyTable; model: Model; varList: VariableList;
                    config = initFitConfig()): FitInfo {.raises: [JunctionTreeError, ConvergenceError, ComputationError].} =
  ## Compute fitted distribution for a model
  ## Returns fit table along with fitting information
  ##
  ## Uses algebraic method for loopless models, IPF for models with loops
  ## For saturated model, returns input data directly
  ## For independence model, computes product of marginals
  ##
  ## If config.raiseOnJTFailure is true, raises JunctionTreeError on JT failure
  ## If config.raiseOnNonConvergence is true, raises ConvergenceError on IPF non-convergence
  ## If config.recordTiming is true, captures timing information in FitInfo

  let startTime = getMonoTime()

  # For saturated model, return input data
  if model.isSaturatedModel(varList):
    result.fitTable = data
    result.iterations = 0
    result.error = 0.0
    result.usedIPF = false
    result.jtFailed = false
    result.fitType = ftSaturated
    if config.recordTiming:
      result.fitTimeNs = inNanoseconds(getMonoTime() - startTime)
    return

  # For independence model, compute product of marginals
  if model.isIndependenceModel(varList):
    result.fitTable = fitIndependenceModel(data, varList)
    result.iterations = 0
    result.error = 0.0
    result.usedIPF = false
    result.jtFailed = false
    result.fitType = ftIndependence
    if config.recordTiming:
      result.fitTimeNs = inNanoseconds(getMonoTime() - startTime)
    return

  # Check if model has loops
  if hasLoops(model, varList):
    # Use IPF for loop models (non-decomposable)
    let ipfConfig = ipf.initIPFConfig(
      raiseOnNonConvergence = config.raiseOnNonConvergence,
      recordIterationTimes = config.recordTiming,
      progressCallback = config.ipfProgressCallback,
      progressInterval = config.ipfProgressInterval
    )
    let ipfResult = ipf.ipf(data, model.relations, varList, ipfConfig)
    result.fitTable = ipfResult.fitTable
    result.iterations = ipfResult.iterations
    result.error = ipfResult.error
    result.usedIPF = true
    result.jtFailed = false
    result.fitType = ftIPF
    if config.recordTiming:
      result.fitTimeNs = inNanoseconds(getMonoTime() - startTime)
      result.ipfTotalNs = ipfResult.totalTimeNs
      result.ipfIterTimesNs = ipfResult.iterationTimesNs
  else:
    # Use belief propagation for loopless (decomposable) models
    # Build junction tree and run exact inference
    let jtResult = buildJunctionTree(model, varList)
    if jtResult.valid:
      let bpResult = bp.beliefPropagation(data, jtResult.tree, varList)
      result.fitTable = bp.computeJointFromBP(bpResult, jtResult.tree, varList)
      # BP iterations is always 2 (collect + distribute), error is 0 (exact)
      result.iterations = bpResult.iterations
      result.error = 0.0
      result.usedIPF = false
      result.jtFailed = false
      result.fitType = ftLoopless
      if config.recordTiming:
        result.fitTimeNs = inNanoseconds(getMonoTime() - startTime)
        result.bpCollectNs = bpResult.collectPhaseNs
        result.bpDistributeNs = bpResult.distributePhaseNs
    else:
      # Junction tree construction failed
      result.jtFailed = true
      if config.raiseOnJTFailure:
        raise newException(JunctionTreeError,
          "Failed to build junction tree for model: " & $model)
      # Fallback to IPF if junction tree construction fails
      let ipfConfig = ipf.initIPFConfig(
        raiseOnNonConvergence = config.raiseOnNonConvergence,
        recordIterationTimes = config.recordTiming,
        progressCallback = config.ipfProgressCallback,
        progressInterval = config.ipfProgressInterval
      )
      let ipfResult = ipf.ipf(data, model.relations, varList, ipfConfig)
      result.fitTable = ipfResult.fitTable
      result.iterations = ipfResult.iterations
      result.error = ipfResult.error
      result.usedIPF = true
      result.fitType = ftIPF
      if config.recordTiming:
        result.fitTimeNs = inNanoseconds(getMonoTime() - startTime)
        result.ipfTotalNs = ipfResult.totalTimeNs
        result.ipfIterTimesNs = ipfResult.iterationTimesNs


proc computeResiduals*(observed: coretable.ContingencyTable; fitted: coretable.ContingencyTable;
                       varList: VariableList): coretable.ContingencyTable =
  ## Compute residuals (observed - fitted) for each cell
  result = coretable.initContingencyTable(varList.keySize)

  # For each cell in observed data
  for tup in observed:
    let idx = fitted.find(tup.key)
    var fitVal = 0.0
    if idx.isSome:
      fitVal = fitted[idx.get].value

    let residual = tup.value - fitVal
    result.add(tup.key, residual)

  # Also add cells that are in fit but not in observed (negative residuals)
  for tup in fitted:
    let idx = observed.find(tup.key)
    if idx.isNone:
      result.add(tup.key, -tup.value)

  result.sort()
  result.sumInto()


# Export all pure functions
export FitType, FitInfo, FitConfig
export initFitConfig, fitIndependenceModel, fitModelTable, computeResiduals
