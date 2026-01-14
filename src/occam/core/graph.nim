## Graph algorithms for OCCAM
##
## Provides graph-based algorithms for model analysis, including:
## - Primal graph construction from models
## - Maximum Cardinality Search (MCS) for chordality testing
## - Alpha-acyclicity testing for hypergraph decomposability
##
## These algorithms enable efficient O(n²) loop detection compared to
## the brute-force O(n × 2^n) approach of trying all RIP orderings.
##
## Background: A model (hypergraph) is alpha-acyclic (decomposable) iff:
## 1. Its primal graph (2-section) is chordal
## 2. Every maximal clique of the primal graph is contained in some hyperedge
##
## The primal graph has:
## - Nodes: variables
## - Edges: pairs of variables that appear together in some relation
##
## Reference: Beeri et al. (1983), Tarjan & Yannakakis (1984)

{.push raises: [].}

import std/[algorithm, sets, options]
import types
import relation

type
  Graph* = object
    ## Undirected graph using adjacency list representation
    nodeCount*: int
    adjList*: seq[seq[int]]  # adjList[i] contains neighbors of node i

  IntersectionGraph* = object
    ## Intersection graph of a model's relations
    ## Nodes are relation indices, edges connect relations sharing variables
    graph*: Graph
    sharedVars*: seq[seq[HashSet[int]]]  # sharedVars[i][j] = vars shared by i and j's neighbor


func initGraph*(nodeCount: int): Graph =
  ## Create an empty graph with the given number of nodes
  result.nodeCount = nodeCount
  result.adjList = newSeq[seq[int]](nodeCount)
  for i in 0..<nodeCount:
    result.adjList[i] = @[]

proc addEdge*(g: var Graph; u, v: int) =
  ## Add an undirected edge between u and v
  ## Does not check for duplicates
  if u != v:  # No self-loops
    g.adjList[u].add(v)
    g.adjList[v].add(u)


func hasEdge*(g: Graph; u, v: int): bool =
  ## Check if edge exists between u and v
  v in g.adjList[u]


func degree*(g: Graph; node: int): int =
  ## Return the degree of a node
  g.adjList[node].len


func neighbors*(g: Graph; node: int): seq[int] =
  ## Return neighbors of a node
  g.adjList[node]


func buildIntersectionGraph*(relations: openArray[Relation]): IntersectionGraph =
  ## Build the intersection graph for a set of relations
  ##
  ## In the intersection graph:
  ## - Each relation becomes a node (indexed 0..n-1)
  ## - Two nodes have an edge if the relations share at least one variable
  ## - We also track which variables are shared for each edge
  let n = relations.len
  result.graph = initGraph(n)
  result.sharedVars = newSeq[seq[HashSet[int]]](n)
  for i in 0..<n:
    result.sharedVars[i] = newSeq[HashSet[int]](0)

  # Build variable sets for each relation
  var varSets: seq[HashSet[int]]
  for rel in relations:
    var s: HashSet[int]
    for v in rel.varIndices:
      s.incl(v.toInt)
    varSets.add(s)

  # Find all pairs of relations that share variables
  for i in 0..<n:
    for j in (i+1)..<n:
      let shared = varSets[i] * varSets[j]  # intersection
      if shared.len > 0:
        result.graph.addEdge(i, j)
        # Store shared vars for this edge
        result.sharedVars[i].add(shared)
        result.sharedVars[j].add(shared)


func buildPrimalGraph*(relations: openArray[Relation]): (Graph, seq[int]) =
  ## Build the primal graph (2-section) of a hypergraph
  ##
  ## The primal graph has:
  ## - Nodes: variables (re-indexed 0..n-1)
  ## - Edges: pairs of variables that appear together in some relation
  ##
  ## Returns (graph, varMapping) where varMapping[i] is the original variable index

  # Collect all unique variables and create mapping
  var allVars: HashSet[int]
  for rel in relations:
    for v in rel.varIndices:
      allVars.incl(v.toInt)

  var varMapping: seq[int]  # New index -> original variable index
  var reverseMap: seq[int]  # Original index -> new index (sparse, -1 if not present)

  # Find max variable index for reverse map size
  var maxVar = 0
  for v in allVars:
    if v > maxVar:
      maxVar = v

  reverseMap = newSeq[int](maxVar + 1)
  for i in 0..maxVar:
    reverseMap[i] = -1

  for v in allVars:
    reverseMap[v] = varMapping.len
    varMapping.add(v)

  # Build primal graph
  var g = initGraph(varMapping.len)

  for rel in relations:
    # Add edge between every pair of variables in this relation
    let vars = rel.varIndices
    for i in 0..<vars.len:
      for j in (i+1)..<vars.len:
        let u = reverseMap[vars[i].toInt]
        let v = reverseMap[vars[j].toInt]
        if not g.hasEdge(u, v):
          g.addEdge(u, v)

  (g, varMapping)


type
  MCSNode = object
    ## Node for MCS priority queue (max-heap by weight)
    node: int
    weight: int

proc `<`(a, b: MCSNode): bool =
  ## For max-heap: higher weight has higher priority
  a.weight > b.weight  # Note: reversed for max behavior


func maximumCardinalitySearch*(g: Graph): seq[int] =
  ## Maximum Cardinality Search algorithm
  ##
  ## Returns nodes in perfect elimination ordering (PEO).
  ## For a chordal graph, this ordering has the property that for each node,
  ## its neighbors that come LATER in the ordering form a clique.
  ##
  ## Algorithm:
  ## 1. Initialize all weights to 0
  ## 2. Repeatedly select the unvisited node with maximum weight
  ## 3. For each unvisited neighbor, increment its weight
  ## 4. Return the REVERSE of the visit order (this gives the PEO)
  ##
  ## Time complexity: O(n + m) with proper data structures
  ## This implementation is O(n²) for simplicity
  if g.nodeCount == 0:
    return @[]

  var visitOrder: seq[int]
  var visited = newSeq[bool](g.nodeCount)
  var weights = newSeq[int](g.nodeCount)

  # Use a simple approach: scan for max weight each iteration
  # This is O(n²) but simple and correct. Can optimize later if needed.
  for iteration in 0..<g.nodeCount:
    # Find unvisited node with maximum weight
    var maxWeight = -1
    var maxNode = -1
    for node in 0..<g.nodeCount:
      if not visited[node] and weights[node] > maxWeight:
        maxWeight = weights[node]
        maxNode = node

    if maxNode == -1:
      # Find any unvisited node (disconnected component)
      for node in 0..<g.nodeCount:
        if not visited[node]:
          maxNode = node
          break

    # Visit this node
    visited[maxNode] = true
    visitOrder.add(maxNode)

    # Increment weights of unvisited neighbors
    for neighbor in g.adjList[maxNode]:
      if not visited[neighbor]:
        weights[neighbor] += 1

  # Return reverse order - this is the perfect elimination ordering
  var peo: seq[int]
  for i in countdown(visitOrder.len - 1, 0):
    peo.add(visitOrder[i])
  peo


func isPerfectEliminationOrdering*(g: Graph; ordering: seq[int]): bool =
  ## Check if the given ordering is a Perfect Elimination Ordering (PEO)
  ##
  ## An ordering v1, v2, ..., vn is a PEO if for each vi, the neighbors
  ## of vi that come later in the ordering form a clique.
  ##
  ## Equivalently: for each vi, among its later neighbors, the first one
  ## (vj) must be adjacent to all other later neighbors of vi.
  ##
  ## This is the key property of chordal graphs.
  if g.nodeCount <= 2:
    return true

  # Build position map: position[node] = index in ordering
  var position = newSeq[int](g.nodeCount)
  for i, node in ordering:
    position[node] = i

  # For each node, check the "clique property" of its later neighbors
  for i in 0..<ordering.len:
    let v = ordering[i]

    # Find neighbors that come later in ordering
    var laterNeighbors: seq[int]
    for neighbor in g.adjList[v]:
      if position[neighbor] > i:
        laterNeighbors.add(neighbor)

    if laterNeighbors.len <= 1:
      continue  # 0 or 1 later neighbors trivially form a clique

    # Sort by position to find the "first" later neighbor
    laterNeighbors.sort(proc(a, b: int): int = cmp(position[a], position[b]))

    # The first later neighbor must be adjacent to all others
    let first = laterNeighbors[0]
    for j in 1..<laterNeighbors.len:
      let other = laterNeighbors[j]
      if not g.hasEdge(first, other):
        return false  # Not a clique → not chordal

  true


func isChordal*(g: Graph): bool =
  ## Check if graph is chordal using MCS + PEO verification
  ##
  ## A graph is chordal if and only if MCS produces a PEO.
  ## Time complexity: O(n + m)
  if g.nodeCount <= 3:
    return true  # All graphs with ≤3 nodes are chordal

  let ordering = maximumCardinalitySearch(g)
  isPerfectEliminationOrdering(g, ordering)


func hasRedundantRelation*(relations: openArray[Relation]): bool =
  ## Check if any relation is a subset of another
  ##
  ## Redundant relations (e.g., AB in model AB:ABC) indicate a non-decomposable
  ## model because the same information is represented multiple times.
  for i in 0..<relations.len:
    for j in 0..<relations.len:
      if i != j:
        if relations[i].isSubsetOf(relations[j]):
          return true
  false


func findMaximalCliques*(g: Graph; ordering: seq[int]): seq[HashSet[int]] =
  ## Find all maximal cliques of a chordal graph given a perfect elimination ordering
  ##
  ## For chordal graphs, each node v forms a clique with its neighbors that come
  ## later in the PEO. A clique is maximal if it's not contained in another clique.
  ##
  ## Returns cliques as sets of node indices.
  if g.nodeCount == 0:
    return @[]

  # Build position map
  var position = newSeq[int](g.nodeCount)
  for i, node in ordering:
    position[node] = i

  # For each node, compute the clique it forms with later neighbors
  var cliques: seq[HashSet[int]]

  for i in 0..<ordering.len:
    let v = ordering[i]

    # Clique is v plus all neighbors that come later
    var clique: HashSet[int]
    clique.incl(v)

    for neighbor in g.adjList[v]:
      if position[neighbor] > i:
        clique.incl(neighbor)

    # Check if this clique is maximal (not contained in a previous clique)
    var isMaximal = true
    for existing in cliques:
      if clique <= existing:  # clique is subset of existing
        isMaximal = false
        break

    if isMaximal:
      # Also remove any existing cliques that are subsets of this one
      var newCliques: seq[HashSet[int]]
      for existing in cliques:
        if not (existing <= clique):
          newCliques.add(existing)
      newCliques.add(clique)
      cliques = newCliques

  cliques


func hasLoopsViaGraph*(relations: openArray[Relation]): bool =
  ## Check if a model has loops using graph algorithms
  ##
  ## A model (hypergraph) is alpha-acyclic (decomposable) if and only if:
  ## 1. No relation is a subset of another (no redundancy)
  ## 2. The primal graph is chordal
  ## 3. Every maximal clique of the primal graph is contained in some relation
  ##
  ## This is O(n² + v²) where n = number of relations, v = number of variables
  if relations.len <= 1:
    return false

  # Check for redundant relations first (quick check)
  if hasRedundantRelation(relations):
    return true

  # Build primal graph
  let (primalGraph, varMapping) = buildPrimalGraph(relations)

  if primalGraph.nodeCount == 0:
    return false

  # Check if primal graph is chordal
  let ordering = maximumCardinalitySearch(primalGraph)
  if not isPerfectEliminationOrdering(primalGraph, ordering):
    return true  # Not chordal → has loops

  # Find maximal cliques of the primal graph
  let maximalCliques = findMaximalCliques(primalGraph, ordering)

  # Create reverse map: origIdx -> newIdx
  var maxOrigVar = 0
  for origIdx in varMapping:
    if origIdx > maxOrigVar:
      maxOrigVar = origIdx

  var origToNew = newSeq[int](maxOrigVar + 1)
  for newIdx, origIdx in varMapping:
    origToNew[origIdx] = newIdx

  # Convert relations to sets of new variable indices
  var relationSets: seq[HashSet[int]]
  for rel in relations:
    var s: HashSet[int]
    for v in rel.varIndices:
      s.incl(origToNew[v.toInt])
    relationSets.add(s)

  # Check that every maximal clique is contained in some relation
  for clique in maximalCliques:
    var covered = false
    for relSet in relationSets:
      if clique <= relSet:  # clique is subset of relation
        covered = true
        break
    if not covered:
      return true  # Maximal clique not covered → has loops

  false  # All conditions satisfied → no loops


func findPerfectEliminationOrdering*(g: Graph): Option[seq[int]] =
  ## Find a perfect elimination ordering if one exists (graph is chordal)
  ## Returns none if graph is not chordal
  let ordering = maximumCardinalitySearch(g)
  if isPerfectEliminationOrdering(g, ordering):
    some(ordering)
  else:
    none(seq[int])


func findRIPOrdering*(relations: openArray[Relation]): Option[seq[int]] =
  ## Find a valid Running Intersection Property ordering for the relations
  ##
  ## Returns the ordering of relation indices that satisfies RIP,
  ## or none if no such ordering exists (model has loops).
  ##
  ## Note: This checks if a valid RIP ordering exists. If the model is
  ## alpha-acyclic (loopless), we return a valid ordering based on
  ## the junction tree structure.
  if relations.len == 0:
    return some(newSeq[int]())
  if relations.len == 1:
    return some(@[0])

  # Use the same algorithm as hasLoopsViaGraph
  if hasLoopsViaGraph(relations):
    return none(seq[int])

  # If no loops, we can find a valid RIP ordering using the intersection graph
  # The intersection graph is chordal when the hypergraph is acyclic
  let ig = buildIntersectionGraph(relations)
  let ordering = maximumCardinalitySearch(ig.graph)

  # Verify this is a valid PEO (should always be true if hasLoopsViaGraph is false)
  if isPerfectEliminationOrdering(ig.graph, ordering):
    some(ordering)
  else:
    none(seq[int])
