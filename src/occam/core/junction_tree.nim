## Junction Tree for Decomposable Models
##
## A junction tree (clique tree) represents the factorization structure
## of a decomposable (loopless) graphical model. For such models:
##
##   P(X) = ∏ P(Cᵢ) / ∏ P(Sⱼ)
##
## where Cᵢ are cliques (relations) and Sⱼ are separators (intersections).
##
## The junction tree has the Running Intersection Property (RIP):
## For any variable v, the cliques containing v form a connected subtree.

{.push raises: [].}

import std/[algorithm, sets, options, deques]
import types
import variable
import relation
import model

type
  Separator* = object
    ## Separator between two adjacent cliques in junction tree
    variables*: seq[VariableIndex]  # Variables in the separator
    cliqueA*: int                   # Index of first clique
    cliqueB*: int                   # Index of second clique

  JunctionTree* = object
    ## Junction tree structure for a decomposable model
    cliques*: seq[Relation]         # Cliques (relations from the model)
    separators*: seq[Separator]     # Separators between adjacent cliques
    adjacency*: seq[seq[int]]       # adjacency[i] = indices of cliques adjacent to i
    parent*: seq[int]               # parent[i] = parent clique index (-1 for root)
    children*: seq[seq[int]]        # children[i] = child clique indices
    root*: int                      # Root clique index

  JunctionTreeResult* = object
    ## Result of junction tree construction
    tree*: JunctionTree
    valid*: bool                    # True if model is decomposable
    errorMsg*: string               # Error message if not valid


func intersectionSize(a, b: Relation): int =
  ## Count variables in intersection of two relations
  var count = 0
  for va in a.varIndices:
    if b.containsVariable(va):
      count += 1
  count


func getIntersection(a, b: Relation): seq[VariableIndex] =
  ## Get variables in intersection of two relations
  var intersection: seq[VariableIndex] = @[]
  for va in a.varIndices:
    if b.containsVariable(va):
      intersection.add(va)
  intersection.sort(proc(x, y: VariableIndex): int = cmp(x.toInt, y.toInt))
  intersection


proc buildJunctionTree*(model: Model; varList: VariableList): JunctionTreeResult =
  ## Build a junction tree from a decomposable model
  ##
  ## Uses the maximum weight spanning tree algorithm on the clique graph,
  ## where edge weights are the size of separators (intersections).
  ##
  ## For decomposable models, this produces a valid junction tree.
  ## For non-decomposable models, result.valid = false.

  result.valid = false
  result.tree.root = 0

  let n = model.relationCount
  if n == 0:
    result.errorMsg = "Empty model"
    return

  # Single clique is trivially a junction tree
  if n == 1:
    result.valid = true
    result.tree.cliques = @[model.relations[0]]
    result.tree.separators = @[]
    result.tree.adjacency = @[@[]]
    result.tree.parent = @[-1]
    result.tree.children = @[@[]]
    result.tree.root = 0
    return

  # Copy cliques from model
  result.tree.cliques = model.relations

  # Build weighted edge list for clique graph
  # Edge weight = |intersection| (separator size)
  type Edge = tuple[weight: int, i, j: int]
  var edges: seq[Edge] = @[]

  for i in 0..<n:
    for j in (i+1)..<n:
      let sepSize = intersectionSize(model.relations[i], model.relations[j])
      if sepSize > 0:
        # Negative weight for max spanning tree via min spanning tree
        edges.add((-sepSize, i, j))

  # Sort edges by weight (ascending = max weights first due to negation)
  edges.sort(proc(a, b: Edge): int = cmp(a.weight, b.weight))

  # Kruskal's algorithm for maximum spanning tree
  # Using union-find for cycle detection
  var parent = newSeq[int](n)
  var rank = newSeq[int](n)
  for i in 0..<n:
    parent[i] = i
    rank[i] = 0

  proc find(x: int): int =
    var curr = x
    while parent[curr] != curr:
      parent[curr] = parent[parent[curr]]  # Path compression
      curr = parent[curr]
    curr

  proc union(x, y: int): bool =
    let px = find(x)
    let py = find(y)
    if px == py:
      return false  # Already connected (would create cycle)
    # Union by rank
    if rank[px] < rank[py]:
      parent[px] = py
    elif rank[px] > rank[py]:
      parent[py] = px
    else:
      parent[py] = px
      rank[px] += 1
    true

  # Build spanning tree
  var treeEdges: seq[(int, int)] = @[]
  result.tree.adjacency = newSeq[seq[int]](n)
  for i in 0..<n:
    result.tree.adjacency[i] = @[]

  for edge in edges:
    let (_, i, j) = edge
    if union(i, j):
      treeEdges.add((i, j))
      result.tree.adjacency[i].add(j)
      result.tree.adjacency[j].add(i)
      if treeEdges.len == n - 1:
        break  # Tree complete

  # Check if we got a spanning tree (all cliques connected)
  if treeEdges.len != n - 1:
    result.errorMsg = "Model cliques are not all connected"
    return

  # Build separators from tree edges
  result.tree.separators = @[]
  for (i, j) in treeEdges:
    let sepVars = getIntersection(model.relations[i], model.relations[j])
    result.tree.separators.add(Separator(
      variables: sepVars,
      cliqueA: i,
      cliqueB: j
    ))

  # Root the tree (BFS from clique 0)
  result.tree.parent = newSeq[int](n)
  result.tree.children = newSeq[seq[int]](n)
  for i in 0..<n:
    result.tree.parent[i] = -1
    result.tree.children[i] = @[]

  result.tree.root = 0
  var visited = newSeq[bool](n)
  var queue = initDeque[int]()
  queue.addLast(0)
  visited[0] = true

  while queue.len > 0:
    let curr = queue.popFirst()

    for neighbor in result.tree.adjacency[curr]:
      if not visited[neighbor]:
        visited[neighbor] = true
        result.tree.parent[neighbor] = curr
        result.tree.children[curr].add(neighbor)
        queue.addLast(neighbor)

  # Verify RIP (Running Intersection Property)
  # For each variable, the cliques containing it must form a connected subtree
  var allVars: HashSet[int]
  for clique in result.tree.cliques:
    for v in clique.varIndices:
      allVars.incl(v.toInt)

  for vInt in allVars:
    let v = VariableIndex(vInt)
    # Find all cliques containing this variable
    var containingCliques: seq[int] = @[]
    for i, clique in result.tree.cliques:
      if clique.containsVariable(v):
        containingCliques.add(i)

    if containingCliques.len <= 1:
      continue  # Trivially connected

    # Check connectivity via BFS restricted to containing cliques
    let cliqueSet = containingCliques.toHashSet()
    var visitedRIP = initHashSet[int]()
    var queueRIP = initDeque[int]()
    queueRIP.addLast(containingCliques[0])
    visitedRIP.incl(containingCliques[0])

    while queueRIP.len > 0:
      let curr = queueRIP.popFirst()

      for neighbor in result.tree.adjacency[curr]:
        if neighbor in cliqueSet and neighbor notin visitedRIP:
          visitedRIP.incl(neighbor)
          queueRIP.addLast(neighbor)

    if visitedRIP.len != containingCliques.len:
      result.errorMsg = "RIP violation: variable " & $vInt & " cliques not connected"
      return

  result.valid = true


func isLeaf*(jt: JunctionTree; cliqueIdx: int): bool =
  ## Check if a clique is a leaf in the junction tree
  jt.children[cliqueIdx].len == 0


func leafCliques*(jt: JunctionTree): seq[int] =
  ## Get indices of all leaf cliques
  var leaves: seq[int] = @[]
  for i in 0..<jt.cliques.len:
    if jt.isLeaf(i):
      leaves.add(i)
  leaves


func getSeparator*(jt: JunctionTree; cliqueA, cliqueB: int): Option[Separator] =
  ## Get separator between two adjacent cliques
  for sep in jt.separators:
    if (sep.cliqueA == cliqueA and sep.cliqueB == cliqueB) or
       (sep.cliqueA == cliqueB and sep.cliqueB == cliqueA):
      return some(sep)
  none(Separator)


func postOrder*(jt: JunctionTree): seq[int] =
  ## Get cliques in post-order (children before parents)
  ## Useful for collect phase of belief propagation
  var order: seq[int] = @[]
  var visited = newSeq[bool](jt.cliques.len)
  var stack: seq[(int, bool)] = @[(jt.root, false)]  # (node, processed)

  while stack.len > 0:
    let (idx, processed) = stack.pop()

    if processed:
      order.add(idx)
      continue

    if visited[idx]:
      continue

    visited[idx] = true
    stack.add((idx, true))  # Add back with processed=true

    # Add children in reverse order so they're processed left-to-right
    for i in countdown(jt.children[idx].len - 1, 0):
      let child = jt.children[idx][i]
      if not visited[child]:
        stack.add((child, false))

  order


func preOrder*(jt: JunctionTree): seq[int] =
  ## Get cliques in pre-order (parents before children)
  ## Useful for distribute phase of belief propagation
  var order: seq[int] = @[]
  var visited = newSeq[bool](jt.cliques.len)
  var stack = @[jt.root]

  while stack.len > 0:
    let idx = stack.pop()

    if visited[idx]:
      continue

    visited[idx] = true
    order.add(idx)

    # Add children in reverse order so they're processed left-to-right
    for i in countdown(jt.children[idx].len - 1, 0):
      let child = jt.children[idx][i]
      if not visited[child]:
        stack.add(child)

  order


# Export types
export JunctionTree, JunctionTreeResult, Separator
export buildJunctionTree, isLeaf, leafCliques, getSeparator
export postOrder, preOrder
