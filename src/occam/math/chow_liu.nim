## Chow-Liu Tree Structure Learning
##
## Implements the Chow-Liu algorithm for finding the optimal tree-structured
## approximation to a joint probability distribution.
##
## The algorithm:
## 1. Compute mutual information I(Xi; Xj) for all variable pairs
## 2. Build maximum weight spanning tree using Kruskal's algorithm
## 3. Result minimizes KL divergence from true distribution
##
## Reference:
## C. Chow and C. Liu, "Approximating discrete probability distributions
## with dependence trees," IEEE Trans. Information Theory, 1968.
##
## Usage:
##   let tree = chowLiu(table, varList)
##   let model = treeToModel(tree, varList)

import std/[algorithm, math]
import ../core/types
import ../core/variable
import ../core/table as coretable
import ../core/relation
import ../core/model
import ./entropy

type
  TreeEdge* = object
    ## Edge in the Chow-Liu tree
    v1*: VariableIndex
    v2*: VariableIndex
    weight*: float64  # Mutual information I(v1; v2)

  ChowLiuTree* = object
    ## Result of Chow-Liu algorithm
    edges*: seq[TreeEdge]
    variables*: seq[VariableIndex]


proc computeMutualInformation*(
    table: coretable.ContingencyTable;
    varList: VariableList;
    v1: VariableIndex;
    v2: VariableIndex
): float64 =
  ## Compute mutual information I(X; Y) = H(X) + H(Y) - H(X,Y)
  ##
  ## MI measures the amount of information one variable contains about another.
  ## Returns 0 for independent variables, positive for associated variables.

  # Get marginal tables
  let marginalV1 = table.project(varList, @[v1])
  let marginalV2 = table.project(varList, @[v2])
  let joint = table.project(varList, @[v1, v2])

  # Compute entropies
  let h1 = entropy(marginalV1)
  let h2 = entropy(marginalV2)
  let hJoint = entropy(joint)

  # MI = H(X) + H(Y) - H(X,Y)
  result = h1 + h2 - hJoint

  # Ensure non-negative (can be slightly negative due to floating point)
  if result < 0:
    result = 0.0


proc computeAllMI(
    table: coretable.ContingencyTable;
    varList: VariableList
): seq[TreeEdge] =
  ## Compute mutual information for all variable pairs.
  ## Returns edges sorted by MI (highest first).

  result = @[]
  let n = varList.len

  for i in 0..<n:
    for j in (i+1)..<n:
      let mi = computeMutualInformation(table, varList, VariableIndex(i), VariableIndex(j))
      result.add(TreeEdge(
        v1: VariableIndex(i),
        v2: VariableIndex(j),
        weight: mi
      ))

  # Sort by weight descending (greedy maximum spanning tree)
  result.sort(proc(a, b: TreeEdge): int = cmp(b.weight, a.weight))


proc find(parent: var seq[int]; i: int): int =
  ## Union-Find: find with path compression
  if parent[i] != i:
    parent[i] = find(parent, parent[i])
  parent[i]


proc union(parent: var seq[int]; rank: var seq[int]; x, y: int) =
  ## Union-Find: union by rank
  let rootX = find(parent, x)
  let rootY = find(parent, y)

  if rootX != rootY:
    if rank[rootX] < rank[rootY]:
      parent[rootX] = rootY
    elif rank[rootX] > rank[rootY]:
      parent[rootY] = rootX
    else:
      parent[rootY] = rootX
      rank[rootX] += 1


proc chowLiu*(
    table: coretable.ContingencyTable;
    varList: VariableList
): ChowLiuTree =
  ## Find the optimal tree-structured approximation using Chow-Liu algorithm.
  ##
  ## Returns a tree with n-1 edges for n variables, where each edge represents
  ## a direct dependency between two variables.
  ##
  ## Example:
  ##   let tree = chowLiu(table, varList)
  ##   echo "Tree has ", tree.edges.len, " edges"
  ##   for edge in tree.edges:
  ##     echo varList[edge.v1].abbrev, " -- ", varList[edge.v2].abbrev, " (MI=", edge.weight, ")"

  let n = varList.len

  if n < 2:
    result.variables = @[]
    if n == 1:
      result.variables.add(VariableIndex(0))
    return

  # Compute all pairwise MI values
  let allEdges = computeAllMI(table, varList)

  # Kruskal's algorithm for maximum spanning tree
  var parent = newSeq[int](n)
  var rank = newSeq[int](n)
  for i in 0..<n:
    parent[i] = i
    rank[i] = 0

  result.edges = @[]
  result.variables = @[]
  for i in 0..<n:
    result.variables.add(VariableIndex(i))

  # Greedily add edges (already sorted by MI descending)
  for edge in allEdges:
    let v1 = edge.v1.int
    let v2 = edge.v2.int

    if find(parent, v1) != find(parent, v2):
      result.edges.add(edge)
      union(parent, rank, v1, v2)

      # Stop when we have n-1 edges (spanning tree complete)
      if result.edges.len == n - 1:
        break


proc treeToModel*(tree: ChowLiuTree; varList: VariableList): Model =
  ## Convert a Chow-Liu tree to an OCCAM model.
  ##
  ## Each edge in the tree becomes a binary relation in the model.
  ##
  ## Example:
  ##   let tree = chowLiu(table, varList)
  ##   let model = treeToModel(tree, varList)
  ##   echo model.printName(varList)  # e.g., "AB:BC"

  var relations: seq[Relation]

  for edge in tree.edges:
    # Create binary relation for this edge
    let rel = initRelation(@[edge.v1, edge.v2])
    relations.add(rel)

  initModel(relations)


# Exports
export TreeEdge, ChowLiuTree
export computeMutualInformation, chowLiu, treeToModel
