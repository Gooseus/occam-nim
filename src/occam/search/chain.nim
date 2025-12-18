## Chain search algorithm for OCCAM
## Generates all possible chain (path) models

{.push raises: [].}

import std/[algorithm, tables, sequtils]
import ../core/types
import ../core/variable
import ../core/relation
import ../core/model

proc isChainModel*(model: Model): bool =
  ## Check if model has chain structure
  ## A chain model:
  ## - All relations are binary (2 variables)
  ## - Relations form a single connected path
  ## - Each internal variable appears in exactly 2 relations
  ## - End variables appear in exactly 1 relation
  ## - No cycles (exactly 2 endpoints)

  if model.relationCount == 0:
    return false

  # All relations must be binary
  for rel in model.relations:
    if rel.variableCount != 2:
      return false

  # Count how many times each variable appears
  var varCounts: Table[int, int]
  for rel in model.relations:
    for v in rel.varIndices:
      varCounts[v.toInt] = varCounts.getOrDefault(v.toInt, 0) + 1

  # Count endpoints (variables appearing exactly once) and internal nodes (appearing twice)
  var endpoints = 0
  var internalNodes = 0
  for v, count in varCounts:
    if count == 1:
      endpoints += 1
    elif count == 2:
      internalNodes += 1
    else:
      # Variable appears more than twice - not a chain (star or more complex)
      return false

  # A valid chain has exactly 2 endpoints
  # (unless it's a single relation, which has 2 endpoints and 0 internal nodes)
  if endpoints != 2:
    return false

  # Verify connectivity: all variables should be reachable from an endpoint
  if varCounts.len == 0:
    return false

  # Find an endpoint to start traversal
  var startVar = -1
  for v, count in varCounts:
    if count == 1:
      startVar = v
      break

  if startVar < 0:
    return false

  # BFS/DFS to check connectivity
  var visited: Table[int, bool]
  var toVisit = @[startVar]
  while toVisit.len > 0:
    let current = toVisit.pop()
    if visited.getOrDefault(current, false):
      continue
    visited[current] = true

    # Find all neighbors through relations
    for rel in model.relations:
      if rel.containsVariable(VariableIndex(current)):
        for v in rel.varIndices:
          if v.toInt != current and not visited.getOrDefault(v.toInt, false):
            toVisit.add(v.toInt)

  # Check all variables are visited
  for v in varCounts.keys:
    if not visited.getOrDefault(v, false):
      return false

  true


proc permute(items: seq[VariableIndex]; n: int; result: var seq[seq[VariableIndex]]) =
  ## Generate all permutations using Heap's algorithm
  var arr = items
  var c = newSeq[int](n)

  result.add(arr)

  var i = 0
  while i < n:
    if c[i] < i:
      if i mod 2 == 0:
        swap(arr[0], arr[i])
      else:
        swap(arr[c[i]], arr[i])
      result.add(arr)
      c[i] += 1
      i = 0
    else:
      c[i] = 0
      i += 1


proc generateAllChains*(varList: VariableList): seq[Model] =
  ## Generate all possible chain permutations for given variables
  ## For n variables, generates n!/2 unique chains (since A-B-C == C-B-A)
  result = @[]

  let n = varList.len
  if n < 2:
    return  # Need at least 2 variables for a chain

  # Get all variable indices
  var varIndices: seq[VariableIndex]
  for i in 0..<n:
    varIndices.add(VariableIndex(i))

  # Generate all permutations
  var perms: seq[seq[VariableIndex]]
  permute(varIndices, n, perms)

  # For each permutation, create a chain model
  # But deduplicate: A-B-C-D is same as D-C-B-A (reversed)
  var seenNames: Table[string, bool]

  for perm in perms:
    # Create chain relations from this ordering
    var relations: seq[Relation]
    for i in 0..<(n-1):
      relations.add(initRelation(@[perm[i], perm[i+1]]))

    let model = initModel(relations)
    let name = model.printName(varList)

    # Check for duplicate (including reversed)
    if name notin seenNames:
      # Also mark the reverse as seen
      var reversed: seq[Relation]
      for i in countdown(n-2, 0):
        reversed.add(initRelation(@[perm[i+1], perm[i]]))
      let reversedModel = initModel(reversed)
      let reversedName = reversedModel.printName(varList)

      seenNames[name] = true
      seenNames[reversedName] = true
      result.add(model)


proc generateAllChains*(varIndices: seq[VariableIndex]; varList: VariableList): seq[Model] =
  ## Generate all chains for a specific subset of variables
  result = @[]

  let n = varIndices.len
  if n < 2:
    return

  var perms: seq[seq[VariableIndex]]
  permute(varIndices, n, perms)

  var seenNames: Table[string, bool]

  for perm in perms:
    var relations: seq[Relation]
    for i in 0..<(n-1):
      relations.add(initRelation(@[perm[i], perm[i+1]]))

    let model = initModel(relations)
    let name = model.printName(varList)

    if name notin seenNames:
      var reversed: seq[Relation]
      for i in countdown(n-2, 0):
        reversed.add(initRelation(@[perm[i+1], perm[i]]))
      let reversedModel = initModel(reversed)
      let reversedName = reversedModel.printName(varList)

      seenNames[name] = true
      seenNames[reversedName] = true
      result.add(model)


# Export functions
export isChainModel, generateAllChains
