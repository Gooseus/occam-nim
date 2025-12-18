## Fitting computation for OCCAM
## Pure functions for model fitting that don't depend on VBManager
##
## These functions operate on Model, VariableList, and Table directly

{.push raises: [].}

import std/options
import ../core/types
import ../core/variable
import ../core/key
import ../core/table as coretable
import ../core/relation
import ../core/model
import ../core/junction_tree
import ../core/results
import ../core/errors
import ../core/iterators
import ../math/entropy
import ../math/statistics as mathstats
import ../math/ipf
import ../math/belief_propagation as bp


# ============ Independence Model Fitting ============

proc fitIndependenceModel*(data: coretable.ContingencyTable; varList: VariableList): coretable.ContingencyTable =
  ## Compute fitted distribution for independence model
  ## P(X1, X2, ...) = P(X1) * P(X2) * ...
  result = coretable.initTable(varList.keySize)

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
  FitInfo* = object
    ## Information about the fitting process
    fitTable*: coretable.ContingencyTable
    iterations*: int
    error*: float64
    usedIPF*: bool
    jtFailed*: bool  # True if junction tree construction failed

  FitConfig* = object
    ## Configuration for model fitting
    raiseOnJTFailure*: bool       # Raise JunctionTreeError if JT build fails (default: false)
    raiseOnNonConvergence*: bool  # Raise ConvergenceError if IPF doesn't converge (default: false)


proc initFitConfig*(raiseOnJTFailure = false; raiseOnNonConvergence = false): FitConfig =
  result.raiseOnJTFailure = raiseOnJTFailure
  result.raiseOnNonConvergence = raiseOnNonConvergence


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

  # For saturated model, return input data
  if model.isSaturatedModel(varList):
    result.fitTable = data
    result.iterations = 0
    result.error = 0.0
    result.usedIPF = false
    result.jtFailed = false
    return

  # For independence model, compute product of marginals
  if model.isIndependenceModel(varList):
    result.fitTable = fitIndependenceModel(data, varList)
    result.iterations = 0
    result.error = 0.0
    result.usedIPF = false
    result.jtFailed = false
    return

  # Check if model has loops
  if hasLoops(model, varList):
    # Use IPF for loop models (non-decomposable)
    let ipfConfig = ipf.initIPFConfig(raiseOnNonConvergence = config.raiseOnNonConvergence)
    let ipfResult = ipf.ipf(data, model.relations, varList, ipfConfig)
    result.fitTable = ipfResult.fitTable
    result.iterations = ipfResult.iterations
    result.error = ipfResult.error
    result.usedIPF = true
    result.jtFailed = false
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
    else:
      # Junction tree construction failed
      result.jtFailed = true
      if config.raiseOnJTFailure:
        raise newException(JunctionTreeError,
          "Failed to build junction tree for model: " & $model)
      # Fallback to IPF if junction tree construction fails
      let ipfConfig = ipf.initIPFConfig(raiseOnNonConvergence = config.raiseOnNonConvergence)
      let ipfResult = ipf.ipf(data, model.relations, varList, ipfConfig)
      result.fitTable = ipfResult.fitTable
      result.iterations = ipfResult.iterations
      result.error = ipfResult.error
      result.usedIPF = true


proc computeResiduals*(observed: coretable.ContingencyTable; fitted: coretable.ContingencyTable;
                       varList: VariableList): coretable.ContingencyTable =
  ## Compute residuals (observed - fitted) for each cell
  result = coretable.initTable(varList.keySize)

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
export FitInfo, FitConfig
export initFitConfig, fitIndependenceModel, fitModelTable, computeResiduals
