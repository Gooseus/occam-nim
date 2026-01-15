## Iterative Proportional Fitting (IPF) algorithm for OCCAM
## Used to fit models with loops (non-decomposable models)
##
## The IPF algorithm iteratively adjusts a probability distribution
## to match a set of marginal constraints (relations).

{.push raises: [].}

import std/[options, tables, monotimes, times]
import ../core/types
import ../core/variable
import ../core/key
import ../core/table as coretable
import ../core/relation
import ../core/errors
import ../core/iterators

type
  IPFProgressCallback* = proc(iteration: int; maxIterations: int; error: float64;
                               stateCount: int; relationCount: int) {.gcsafe.}
    ## Callback for IPF progress reporting
    ## Called every N iterations (controlled by progressInterval)
    ##
    ## Parameters:
    ##   iteration: Current iteration number (1-based)
    ##   maxIterations: Maximum iterations allowed
    ##   error: Current convergence error
    ##   stateCount: Number of states in fit table
    ##   relationCount: Number of relations in model

  IPFResult* = object
    ## Result of IPF algorithm
    fitTable*: coretable.ContingencyTable    # Fitted probability distribution
    iterations*: int              # Iterations to converge
    error*: float64               # Final maximum error
    converged*: bool              # Whether convergence was achieved
    # Timing information (populated when recordIterationTimes = true)
    totalTimeNs*: int64           # Total wall-clock time in nanoseconds
    iterationTimesNs*: seq[int64] # Time per iteration in nanoseconds
    errorHistory*: seq[float64]   # Error at each iteration

  IPFConfig* = object
    ## Configuration for IPF algorithm
    maxIterations*: int             # Maximum iterations (default: 1000)
    convergenceThreshold*: float64  # Convergence threshold (default: 1e-7)
    raiseOnNonConvergence*: bool    # Raise ConvergenceError if not converged (default: false)
    recordIterationTimes*: bool     # Record per-iteration timing (default: false)
    progressCallback*: IPFProgressCallback  # Optional progress callback
    progressInterval*: int          # Call progress every N iterations (default: 100)

const
  DefaultMaxIterations* = 1000
  DefaultConvergenceThreshold* = 1e-7
  IPFEpsilon* = 1e-15  # Small value to avoid division by zero


func initIPFConfig*(maxIterations = DefaultMaxIterations;
                    convergenceThreshold = DefaultConvergenceThreshold;
                    raiseOnNonConvergence = false;
                    recordIterationTimes = false;
                    progressCallback: IPFProgressCallback = nil;
                    progressInterval = 100): IPFConfig =
  IPFConfig(
    maxIterations: maxIterations,
    convergenceThreshold: convergenceThreshold,
    raiseOnNonConvergence: raiseOnNonConvergence,
    recordIterationTimes: recordIterationTimes,
    progressCallback: progressCallback,
    progressInterval: progressInterval
  )


func makeOrthoExpansion*(inputTable: coretable.ContingencyTable;
                         rel: Relation;
                         varList: VariableList): coretable.ContingencyTable =
  ## Create orthogonal expansion of a relation
  ## This initializes the fit table with the marginal distribution of the first relation
  ## expanded to the full state space

  # Project input to get marginal for this relation
  let marginal = inputTable.project(varList, rel.varIndices)

  # If the relation covers all variables, just return the input
  if rel.variableCount == varList.len:
    return inputTable

  # Create full state space table initialized from marginal
  # For simplicity, we'll start with the marginal and expand to full space
  # by assuming uniform distribution over variables not in the relation

  # Get variables not in the relation
  var otherVars: seq[VariableIndex]
  for i in 0..<varList.len:
    let vi = VariableIndex(i)
    if not rel.containsVariable(vi):
      otherVars.add(vi)

  # Compute size of "other" space
  var otherSize = 1
  for v in otherVars:
    otherSize *= varList[v].cardinality.toInt

  # Expand marginal to full space
  var expanded = initContingencyTable(varList.keySize, marginal.len * otherSize)

  # Build cardinalities for other variables
  var otherCardinalities: seq[int]
  for v in otherVars:
    otherCardinalities.add(varList[v].cardinality.toInt)

  # For each tuple in marginal, create all combinations with other variables
  for margTup in marginal:
    let margVal = margTup.value / float64(otherSize)  # Distribute uniformly

    # Enumerate all combinations of other variables using iterator
    for otherIndices in stateEnumeration(otherCardinalities):
      # Build full key combining marginal key with other values
      var keyPairs: seq[(VariableIndex, int)]

      # Add variables from the relation
      for vi in rel.varIndices:
        keyPairs.add((vi, margTup.key.getValue(varList, vi)))

      # Add other variables
      for i, vi in otherVars:
        keyPairs.add((vi, otherIndices[i]))

      let fullKey = varList.buildKey(keyPairs)
      expanded.add(fullKey, margVal)

  expanded.sort()
  expanded.sumInto()
  expanded


proc scaleByMarginal*(fitTable: var coretable.ContingencyTable;
                      inputTable: coretable.ContingencyTable;
                      rel: Relation;
                      varList: VariableList) =
  ## Scale fitTable values so that its projection onto rel matches inputTable's projection

  # Get input marginal
  let inputMarginal = inputTable.project(varList, rel.varIndices)

  # Get current fit marginal
  let fitMarginal = fitTable.project(varList, rel.varIndices)

  # Build a lookup table for scaling factors using Key directly as hash key
  # This is more efficient than converting to strings
  var scaleFactors = initTable[Key, float64]()

  # For each cell in input marginal, compute scale factor
  for inputTup in inputMarginal:
    let idx = fitMarginal.find(inputTup.key)
    var fitVal = 0.0
    if idx.isSome:
      fitVal = fitMarginal[idx.get].value

    var scale = 1.0
    if fitVal > IPFEpsilon:
      scale = inputTup.value / fitVal
    elif inputTup.value > IPFEpsilon:
      # Fit has zero but input has value - this is problematic
      # Use a large scale to try to correct
      scale = inputTup.value / IPFEpsilon

    # Store scale factor keyed by projected key (Key has hash and == implemented)
    scaleFactors[inputTup.key] = scale

  # Build mask for projection
  let mask = varList.buildMask(rel.varIndices)

  # Create new fit table with scaled values
  var newTuples: seq[coretable.Tuple]
  for tup in fitTable:
    let projKey = tup.key.applyMask(mask)

    var scale = 1.0
    try:
      if projKey in scaleFactors:
        scale = scaleFactors[projKey]
    except KeyError:
      discard  # Keep scale = 1.0

    let newVal = tup.value * scale
    newTuples.add(coretable.Tuple(key: tup.key, value: newVal))

  # Update fitTable in place
  fitTable = initContingencyTable(varList.keySize, newTuples.len)
  for tup in newTuples:
    fitTable.add(tup)
  fitTable.sort()


func computeMarginalError*(fitTable: coretable.ContingencyTable;
                           inputTable: coretable.ContingencyTable;
                           relations: seq[Relation];
                           varList: VariableList): float64 =
  ## Compute the maximum error across all marginals
  ## This is the max difference between input and fit marginals for all relations
  var maxErr = 0.0
  for rel in relations:
    let inputMarginal = inputTable.project(varList, rel.varIndices)
    let fitMarginal = fitTable.project(varList, rel.varIndices)

    for inputTup in inputMarginal:
      let idx = fitMarginal.find(inputTup.key)
      var fitVal = 0.0
      if idx.isSome:
        fitVal = fitMarginal[idx.get].value
      let err = abs(inputTup.value - fitVal)
      if err > maxErr:
        maxErr = err
  maxErr


proc ipf*(inputTable: coretable.ContingencyTable;
          relations: seq[Relation];
          varList: VariableList;
          config = initIPFConfig()): IPFResult {.raises: [ConvergenceError].} =
  ## Iterative Proportional Fitting algorithm
  ##
  ## Arguments:
  ##   inputTable: Observed data (normalized to probabilities)
  ##   relations: Model relations defining marginal constraints
  ##   varList: Variable list
  ##   config: IPF configuration
  ##
  ## Returns:
  ##   IPFResult with fitted table, iterations, error, and convergence status
  ##   When config.recordIterationTimes is true, also includes:
  ##   - totalTimeNs: Total wall-clock time
  ##   - iterationTimesNs: Time per iteration
  ##   - errorHistory: Error at each iteration

  let startTime = getMonoTime()

  result.iterations = 0
  result.error = 0.0
  result.converged = false
  result.totalTimeNs = 0
  result.iterationTimesNs = @[]
  result.errorHistory = @[]

  if relations.len == 0:
    result.fitTable = inputTable
    result.converged = true
    result.totalTimeNs = inNanoseconds(getMonoTime() - startTime)
    return

  # Check if single relation covers all variables (saturated model)
  if relations.len == 1 and relations[0].variableCount == varList.len:
    result.fitTable = inputTable
    result.converged = true
    result.totalTimeNs = inNanoseconds(getMonoTime() - startTime)
    return

  # Initialize fit table with orthogonal expansion of first relation
  var fitTable = makeOrthoExpansion(inputTable, relations[0], varList)

  # Diagnostic logging for expensive IPF operations
  if fitTable.len > 10000:
    try:
      stderr.writeLine("[IPF] Large fit table: " & $fitTable.len & " states, " & $relations.len & " relations")
    except IOError:
      discard

  # If only one relation and it's not saturated, we're already done
  if relations.len == 1:
    result.fitTable = fitTable
    result.converged = true
    result.totalTimeNs = inNanoseconds(getMonoTime() - startTime)
    return

  # Compute initial error before any iterations
  var prevError = computeMarginalError(fitTable, inputTable, relations, varList)

  # Pre-allocate timing arrays if recording
  if config.recordIterationTimes:
    result.iterationTimesNs = newSeqOfCap[int64](config.maxIterations)
    result.errorHistory = newSeqOfCap[float64](config.maxIterations)

  # IPF iteration loop
  for iter in 0..<config.maxIterations:
    let iterStart = getMonoTime()

    result.iterations = iter + 1

    # Cycle through all relations, scaling to match marginals
    for rel in relations:
      scaleByMarginal(fitTable, inputTable, rel, varList)

    # Compute error after this iteration (across ALL marginals)
    let currentError = computeMarginalError(fitTable, inputTable, relations, varList)
    result.error = currentError

    # Record timing and error history if configured
    if config.recordIterationTimes:
      result.iterationTimesNs.add(inNanoseconds(getMonoTime() - iterStart))
      result.errorHistory.add(currentError)

    # Call progress callback if configured
    if config.progressCallback != nil and
       (result.iterations mod config.progressInterval == 0 or result.iterations == 1):
      {.cast(raises: []).}:
        try:
          config.progressCallback(result.iterations, config.maxIterations, currentError,
                                   fitTable.len, relations.len)
        except:
          discard  # Don't let callback errors interrupt IPF

    # Check convergence
    if currentError < config.convergenceThreshold:
      result.converged = true
      break

    # Also check if we've stopped improving
    if abs(currentError - prevError) < config.convergenceThreshold * 0.1:
      result.converged = true
      break

    prevError = currentError

  result.fitTable = fitTable

  # Ensure normalization
  let total = result.fitTable.sum()
  if total > 0.0 and abs(total - 1.0) > 1e-10:
    result.fitTable.normalize()

  # Record total time
  result.totalTimeNs = inNanoseconds(getMonoTime() - startTime)

  # Diagnostic logging for slow IPF
  let totalMs = result.totalTimeNs.float / 1_000_000.0
  if totalMs > 1000.0:
    try:
      stderr.writeLine("[IPF] SLOW: " & $result.iterations & " iters, " & $fitTable.len & " states, " &
                       $relations.len & " relations, " & $(totalMs.int) & "ms, converged=" & $result.converged)
    except IOError:
      discard

  # Raise error if configured and not converged
  if config.raiseOnNonConvergence and not result.converged:
    raise newConvergenceError(
      "IPF failed to converge after " & $result.iterations & " iterations",
      result.iterations,
      config.convergenceThreshold,
      result.error
    )
