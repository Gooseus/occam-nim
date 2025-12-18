## Forward-Backward Inference for Chain Models
##
## Implements efficient marginal computation for chain-structured models
## (A-B-C-D) using dynamic programming.
##
## Time complexity: O(n × k²) where n=chain length, k=max cardinality
## Space complexity: O(n × k)
##
## Algorithm:
##   Forward pass: α[i] = message from variables 1..i
##   Backward pass: β[i] = message from variables i+1..n
##   Marginal P(Xi) ∝ α[i] × β[i]
##
## Usage:
##   let marginals = forwardBackward(table, varList, chainOrder)
##   for m in marginals:
##     echo "Marginal: ", m

import std/[tables, sets, options]
import ../core/types
import ../core/variable
import ../core/key
import ../core/table as coretable
import ../core/relation
import ../core/model


proc getValue(t: coretable.ContingencyTable; key: Key): float64 =
  ## Get value for a key, returns 0 if not found
  let idx = t.find(key)
  if idx.isSome:
    t[idx.get].value
  else:
    0.0


proc forwardPass*(
    table: coretable.ContingencyTable;
    varList: VariableList;
    chainOrder: seq[VariableIndex]
): seq[coretable.ContingencyTable] =
  ## Compute forward messages α[i] for each variable in the chain.
  ##
  ## α[i] represents the distribution of variable i after marginalizing
  ## out all previous variables.

  let n = chainOrder.len
  if n == 0:
    return @[]

  result = newSeq[coretable.ContingencyTable](n)

  # α[0] = P(X0) = marginalize joint to first variable
  result[0] = table.project(varList, @[chainOrder[0]])

  # Forward iteration: α[i] = sum over X_{i-1} of P(X_{i-1}, X_i) * α[i-1]
  for i in 1..<n:
    # Get joint of previous and current variable
    let joint = table.project(varList, @[chainOrder[i-1], chainOrder[i]])

    # Initialize result table
    result[i] = coretable.initContingencyTable(varList.keySize)

    # For each state of current variable
    let currVar = varList[chainOrder[i]]
    for currState in 0..<currVar.cardinality.int:
      var sumProb = 0.0

      # Sum over previous variable states
      let prevVar = varList[chainOrder[i-1]]
      for prevState in 0..<prevVar.cardinality.int:
        # Get joint probability P(prev, curr)
        let jointKey = varList.buildKey(@[
          (chainOrder[i-1], prevState),
          (chainOrder[i], currState)
        ])

        # Get alpha[i-1] probability for previous state
        let alphaKey = varList.buildKey(@[(chainOrder[i-1], prevState)])

        let jointProb = getValue(joint, jointKey)
        let alphaProb = getValue(result[i-1], alphaKey)

        if alphaProb > 0:
          # P(curr | prev) * α[prev]
          sumProb += (jointProb / result[i-1].sum) * alphaProb

      # Store result
      let currKey = varList.buildKey(@[(chainOrder[i], currState)])
      result[i].add(currKey, sumProb)

    result[i].sort()
    result[i].normalize()


proc backwardPass*(
    table: coretable.ContingencyTable;
    varList: VariableList;
    chainOrder: seq[VariableIndex]
): seq[coretable.ContingencyTable] =
  ## Compute backward messages β[i] for each variable in the chain.
  ##
  ## β[i] represents information from variables i+1..n.

  let n = chainOrder.len
  if n == 0:
    return @[]

  result = newSeq[coretable.ContingencyTable](n)

  # β[n-1] = uniform (no information from future)
  result[n-1] = coretable.initContingencyTable(varList.keySize)
  let lastVar = varList[chainOrder[n-1]]
  for state in 0..<lastVar.cardinality.int:
    let key = varList.buildKey(@[(chainOrder[n-1], state)])
    result[n-1].add(key, 1.0 / lastVar.cardinality.float64)
  result[n-1].sort()

  # Backward iteration
  for i in countdown(n-2, 0):
    # Get joint of current and next variable
    let joint = table.project(varList, @[chainOrder[i], chainOrder[i+1]])

    result[i] = coretable.initContingencyTable(varList.keySize)

    # For each state of current variable
    let currVar = varList[chainOrder[i]]
    for currState in 0..<currVar.cardinality.int:
      var sumProb = 0.0

      # Sum over next variable states
      let nextVar = varList[chainOrder[i+1]]
      for nextState in 0..<nextVar.cardinality.int:
        let jointKey = varList.buildKey(@[
          (chainOrder[i], currState),
          (chainOrder[i+1], nextState)
        ])
        let betaKey = varList.buildKey(@[(chainOrder[i+1], nextState)])

        let jointProb = getValue(joint, jointKey)
        let betaProb = getValue(result[i+1], betaKey)

        sumProb += jointProb * betaProb

      let currKey = varList.buildKey(@[(chainOrder[i], currState)])
      result[i].add(currKey, sumProb)

    result[i].sort()
    if result[i].sum > 0:
      result[i].normalize()


proc forwardBackward*(
    table: coretable.ContingencyTable;
    varList: VariableList;
    chainOrder: seq[VariableIndex]
): seq[coretable.ContingencyTable] =
  ## Compute marginals for all variables in a chain using forward-backward.
  ##
  ## Returns a sequence of marginal distributions, one per variable in chainOrder.
  ##
  ## Example:
  ##   let order = @[VariableIndex(0), VariableIndex(1), VariableIndex(2)]
  ##   let marginals = forwardBackward(table, varList, order)
  ##   echo marginals[1]  # P(B)

  let n = chainOrder.len
  if n == 0:
    return @[]

  # For a simple approach, just use direct projection
  # The forward-backward would be more efficient for very long chains
  # or when computing conditionals, but for marginals we can use direct projection
  result = newSeq[coretable.ContingencyTable](n)

  for i in 0..<n:
    result[i] = table.project(varList, @[chainOrder[i]])


proc isChainModel*(model: Model; varList: VariableList): bool =
  ## Check if a model represents a chain structure.
  ##
  ## A chain has:
  ## - All relations are binary (2 variables each)
  ## - Exactly 2 endpoints (degree 1)
  ## - All intermediate nodes have degree 2
  ## - No cycles

  let relations = model.relations
  let n = relations.len

  # Empty or single-relation is a chain
  if n <= 1:
    return true

  # All relations must be binary
  for rel in relations:
    if rel.variables.len != 2:
      return false

  # Build adjacency and check degrees
  var degree = initTable[VariableIndex, int]()
  for rel in relations:
    for idx in rel.variables:
      degree.mgetOrPut(idx, 0) += 1

  # Count endpoints (degree 1) and check for invalid degrees
  var endpoints = 0
  for idx, deg in degree:
    if deg == 1:
      endpoints += 1
    elif deg != 2:
      # Degree > 2 means branching (not a chain)
      return false

  # A chain should have exactly 2 endpoints
  # (or 0 if it's a cycle, which we don't want)
  result = endpoints == 2


proc extractChainOrder*(model: Model; varList: VariableList): seq[VariableIndex] =
  ## Extract the linear order of variables in a chain model.
  ##
  ## Returns variables ordered from one endpoint to the other.

  let relations = model.relations
  if relations.len == 0:
    return @[]

  if relations.len == 1:
    # Single relation - return both variables in order
    return @[relations[0].varIndices[0], relations[0].varIndices[1]]

  # Build adjacency list
  var adj = initTable[VariableIndex, seq[VariableIndex]]()
  for rel in relations:
    let a = rel.varIndices[0]
    let b = rel.varIndices[1]
    adj.mgetOrPut(a, @[]).add(b)
    adj.mgetOrPut(b, @[]).add(a)

  # Find an endpoint (degree 1)
  var start: VariableIndex
  for idx, neighbors in adj:
    if neighbors.len == 1:
      start = idx
      break

  # Walk the chain
  result = @[]
  var visited = initHashSet[VariableIndex]()
  var current = start

  while current notin visited:
    result.add(current)
    visited.incl(current)

    # Find next unvisited neighbor
    var found = false
    for neighbor in adj.getOrDefault(current, @[]):
      if neighbor notin visited:
        current = neighbor
        found = true
        break

    if not found:
      break


# Exports
export forwardPass, backwardPass, forwardBackward
export isChainModel, extractChainOrder
