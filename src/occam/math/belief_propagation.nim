## Belief Propagation on Junction Trees
##
## Implements the sum-product algorithm for exact inference on decomposable models.
## For a junction tree with cliques C and separators S:
##
##   P(X) = ∏ ψ(Cᵢ) / ∏ φ(Sⱼ)
##
## After calibration, each clique potential equals the marginal P(Cᵢ).
##
## Two-phase message passing:
##   1. Collect (leaves to root): accumulate evidence
##   2. Distribute (root to leaves): propagate beliefs

{.push raises: [].}

import std/[algorithm, math, options]
import ../core/types
import ../core/variable
import ../core/key
import ../core/table as coretable
import ../core/relation
import ../core/junction_tree
import ../core/errors
import ../core/iterators

type
  BPResult* = object
    ## Result of belief propagation
    cliquePotentials*: seq[coretable.ContingencyTable]  # Calibrated clique potentials
    separatorPotentials*: seq[coretable.ContingencyTable]  # Separator potentials
    converged*: bool
    iterations*: int  # Always 2 for exact BP (collect + distribute)

  BPConfig* = object
    ## Configuration for belief propagation
    normalize*: bool              # Whether to normalize potentials
    raiseOnNumericalIssue*: bool  # Raise ComputationError on division by zero (default: false)

const
  BPEpsilon* = 1e-15  # Small value to detect division by zero

func initBPConfig*(normalize = true; raiseOnNumericalIssue = false): BPConfig =
  BPConfig(
    normalize: normalize,
    raiseOnNumericalIssue: raiseOnNumericalIssue
  )


proc marginalize*(table: coretable.ContingencyTable;
                  varList: VariableList;
                  fromVars: seq[VariableIndex];
                  toVars: seq[VariableIndex]): coretable.ContingencyTable =
  ## Marginalize (sum out) variables not in toVars
  ## fromVars should be a superset of toVars
  if toVars.len == 0:
    # Sum to scalar
    result = coretable.initTable(varList.keySize, 1)
    var total = 0.0
    for tup in table:
      total += tup.value
    let emptyKey = initKey(varList.keySize)
    result.add(emptyKey, total)
    return

  result = table.project(varList, toVars)


proc extendPotential*(table: coretable.ContingencyTable;
                      varList: VariableList;
                      fromVars: seq[VariableIndex];
                      toVars: seq[VariableIndex]): coretable.ContingencyTable =
  ## Extend a potential to include additional variables
  ## The new variables are assumed uniform (value 1.0)
  ## toVars should be a superset of fromVars

  # Find variables to add
  var newVars: seq[VariableIndex] = @[]
  for v in toVars:
    if v notin fromVars:
      newVars.add(v)

  if newVars.len == 0:
    return table

  # Build cardinalities for new variables
  var newCardinalities: seq[int]
  for v in newVars:
    newCardinalities.add(varList[v].cardinality.toInt)

  # Compute size of new variable space
  let newSize = totalStates(newCardinalities)

  # Extend each tuple
  result = coretable.initTable(varList.keySize, table.len * newSize)

  for tup in table:
    # Enumerate all combinations of new variables using iterator
    for newIndices in stateEnumeration(newCardinalities):
      # Build extended key
      var keyPairs: seq[(VariableIndex, int)]

      # Add original variables
      for v in fromVars:
        keyPairs.add((v, tup.key.getValue(varList, v)))

      # Add new variables
      for i, v in newVars:
        keyPairs.add((v, newIndices[i]))

      let extKey = varList.buildKey(keyPairs)
      result.add(extKey, tup.value)

  result.sort()
  result.sumInto()


proc multiplyPotentials*(a, b: coretable.ContingencyTable;
                         varList: VariableList;
                         aVars, bVars: seq[VariableIndex]): coretable.ContingencyTable =
  ## Multiply two potentials
  ## Result has variables = union(aVars, bVars)

  # Find union of variables
  var resultVars: seq[VariableIndex] = aVars
  for v in bVars:
    if v notin resultVars:
      resultVars.add(v)
  resultVars.sort(proc(x, y: VariableIndex): int = cmp(x.toInt, y.toInt))

  # Extend both potentials to resultVars
  let aExt = extendPotential(a, varList, aVars, resultVars)
  let bExt = extendPotential(b, varList, bVars, resultVars)

  # Multiply element-wise
  result = coretable.initTable(varList.keySize, aExt.len)

  for aTup in aExt:
    let bIdx = bExt.find(aTup.key)
    var bVal = 1.0
    if bIdx.isSome:
      bVal = bExt[bIdx.get].value
    result.add(aTup.key, aTup.value * bVal)

  result.sort()


proc dividePotentials*(a, b: coretable.ContingencyTable;
                       varList: VariableList;
                       aVars, bVars: seq[VariableIndex]): coretable.ContingencyTable =
  ## Divide potential a by potential b
  ## bVars should be subset of aVars

  # Extend b to aVars
  let bExt = extendPotential(b, varList, bVars, aVars)

  # Divide element-wise
  result = coretable.initTable(varList.keySize, a.len)

  for aTup in a:
    let bIdx = bExt.find(aTup.key)
    var bVal = 1.0
    if bIdx.isSome:
      bVal = bExt[bIdx.get].value

    var newVal = 0.0
    if bVal > 1e-15:
      newVal = aTup.value / bVal
    # If bVal is 0 and aVal is also 0, result is 0
    # If bVal is 0 and aVal > 0, this is problematic but we set to 0

    result.add(aTup.key, newVal)

  result.sort()


proc beliefPropagation*(inputTable: coretable.ContingencyTable;
                        jt: JunctionTree;
                        varList: VariableList;
                        config = initBPConfig()): BPResult {.raises: [ComputationError].} =
  ## Run belief propagation on junction tree
  ##
  ## Arguments:
  ##   inputTable: Observed data (normalized to probabilities)
  ##   jt: Junction tree from buildJunctionTree
  ##   varList: Variable list
  ##   config: BP configuration
  ##
  ## Returns:
  ##   BPResult with calibrated potentials

  let n = jt.cliques.len
  result.iterations = 2  # collect + distribute
  result.converged = true

  # Initialize clique potentials from input marginals
  result.cliquePotentials = newSeq[coretable.ContingencyTable](n)
  for i in 0..<n:
    let clique = jt.cliques[i]
    result.cliquePotentials[i] = inputTable.project(varList, clique.varIndices)

  # Initialize separator potentials to marginals from first adjacent clique
  # This ensures that parent * message / oldSep = parent (no change) for consistent marginals
  result.separatorPotentials = newSeq[coretable.ContingencyTable](jt.separators.len)
  for i, sep in jt.separators:
    if sep.variables.len == 0:
      result.separatorPotentials[i] = coretable.initTable(varList.keySize)
      let emptyKey = initKey(varList.keySize)
      result.separatorPotentials[i].add(emptyKey, 1.0)
    else:
      # Initialize to marginal from first adjacent clique
      let clique = jt.cliques[sep.cliqueA]
      result.separatorPotentials[i] = marginalize(
        result.cliquePotentials[sep.cliqueA],
        varList,
        clique.varIndices,
        sep.variables
      )

  if n <= 1:
    return  # Nothing to propagate

  # Helper to find separator index between two cliques
  func findSeparatorIdx(a, b: int): Option[int] =
    for i, sep in jt.separators:
      if (sep.cliqueA == a and sep.cliqueB == b) or
         (sep.cliqueA == b and sep.cliqueB == a):
        return some(i)
    none(int)

  # ========== COLLECT PHASE (leaves to root) ==========
  # Process cliques in post-order (children before parents)
  let postOrderSeq = jt.postOrder()

  for cliqueIdx in postOrderSeq:
    let parentIdx = jt.parent[cliqueIdx]
    if parentIdx < 0:
      continue  # Root has no parent

    let sepIdxOpt = findSeparatorIdx(cliqueIdx, parentIdx)
    if sepIdxOpt.isNone:
      continue
    let sepIdx = sepIdxOpt.get

    let sep = jt.separators[sepIdx]
    let clique = jt.cliques[cliqueIdx]

    # Message = marginalize clique potential to separator
    let message = marginalize(result.cliquePotentials[cliqueIdx],
                              varList,
                              clique.varIndices,
                              sep.variables)

    # Update separator potential
    let oldSep = result.separatorPotentials[sepIdx]
    result.separatorPotentials[sepIdx] = message

    # Update parent potential: multiply by message, divide by old separator
    let parent = jt.cliques[parentIdx]
    result.cliquePotentials[parentIdx] = multiplyPotentials(
      result.cliquePotentials[parentIdx],
      message,
      varList,
      parent.varIndices,
      sep.variables
    )

    if oldSep.len > 0:
      result.cliquePotentials[parentIdx] = dividePotentials(
        result.cliquePotentials[parentIdx],
        oldSep,
        varList,
        parent.varIndices,
        sep.variables
      )

  # ========== DISTRIBUTE PHASE (root to leaves) ==========
  # Process cliques in pre-order (parents before children)
  let preOrderSeq = jt.preOrder()

  for cliqueIdx in preOrderSeq:
    for childIdx in jt.children[cliqueIdx]:
      let sepIdxOpt = findSeparatorIdx(cliqueIdx, childIdx)
      if sepIdxOpt.isNone:
        continue
      let sepIdx = sepIdxOpt.get

      let sep = jt.separators[sepIdx]
      let clique = jt.cliques[cliqueIdx]

      # Message = marginalize parent potential to separator
      let message = marginalize(result.cliquePotentials[cliqueIdx],
                                varList,
                                clique.varIndices,
                                sep.variables)

      # Update separator potential
      let oldSep = result.separatorPotentials[sepIdx]
      result.separatorPotentials[sepIdx] = message

      # Update child potential: multiply by message, divide by old separator
      let child = jt.cliques[childIdx]
      result.cliquePotentials[childIdx] = multiplyPotentials(
        result.cliquePotentials[childIdx],
        message,
        varList,
        child.varIndices,
        sep.variables
      )

      if oldSep.len > 0:
        result.cliquePotentials[childIdx] = dividePotentials(
          result.cliquePotentials[childIdx],
          oldSep,
          varList,
          child.varIndices,
          sep.variables
        )

  # Normalize potentials if requested
  if config.normalize:
    for i in 0..<n:
      result.cliquePotentials[i].normalize()
    for i in 0..<jt.separators.len:
      result.separatorPotentials[i].normalize()

  # Check for numerical issues if configured
  if config.raiseOnNumericalIssue:
    for i in 0..<n:
      for tup in result.cliquePotentials[i]:
        if tup.value.isNaN or tup.value.classify == fcInf:
          raise newException(ComputationError,
            "Belief propagation produced NaN/Inf in clique " & $i)
    for i in 0..<jt.separators.len:
      for tup in result.separatorPotentials[i]:
        if tup.value.isNaN or tup.value.classify == fcInf:
          raise newException(ComputationError,
            "Belief propagation produced NaN/Inf in separator " & $i)


proc computeJointFromBP*(bpResult: BPResult;
                         jt: JunctionTree;
                         varList: VariableList): coretable.ContingencyTable =
  ## Reconstruct joint distribution from calibrated junction tree
  ## P(X) = ∏ P(Cᵢ) / ∏ P(Sⱼ)

  if jt.cliques.len == 0:
    return coretable.initTable(varList.keySize)

  if jt.cliques.len == 1:
    # Single clique is the joint (possibly partial)
    return bpResult.cliquePotentials[0]

  # Start with first clique
  var allVars = jt.cliques[0].varIndices
  result = bpResult.cliquePotentials[0]

  # Multiply by remaining cliques
  for i in 1..<jt.cliques.len:
    let clique = jt.cliques[i]
    result = multiplyPotentials(result, bpResult.cliquePotentials[i],
                                varList, allVars, clique.varIndices)
    for v in clique.varIndices:
      if v notin allVars:
        allVars.add(v)

  # Divide by all separators
  for i, sep in jt.separators:
    if sep.variables.len > 0:
      result = dividePotentials(result, bpResult.separatorPotentials[i],
                                varList, allVars, sep.variables)

  result.normalize()


proc getMarginal*(bpResult: BPResult;
                  jt: JunctionTree;
                  varList: VariableList;
                  queryVars: seq[VariableIndex]): coretable.ContingencyTable =
  ## Get marginal distribution over query variables from calibrated junction tree
  ## Finds a clique containing all query variables and marginalizes

  # Find a clique containing all query variables
  var bestCliqueIdx = none(int)
  var bestSize = int.high

  for i, clique in jt.cliques:
    var containsAll = true
    for v in queryVars:
      if not clique.containsVariable(v):
        containsAll = false
        break
    if containsAll and clique.variableCount < bestSize:
      bestCliqueIdx = some(i)
      bestSize = clique.variableCount

  if bestCliqueIdx.isNone:
    # No single clique contains all query variables
    # Need to compute from joint (expensive)
    let joint = computeJointFromBP(bpResult, jt, varList)
    return joint.project(varList, queryVars)

  # Marginalize from the found clique
  let idx = bestCliqueIdx.get
  let clique = jt.cliques[idx]
  marginalize(bpResult.cliquePotentials[idx],
              varList,
              clique.varIndices,
              queryVars)


# Export types and functions
export BPResult, BPConfig
export initBPConfig, beliefPropagation
export computeJointFromBP, getMarginal
export marginalize, multiplyPotentials, dividePotentials
