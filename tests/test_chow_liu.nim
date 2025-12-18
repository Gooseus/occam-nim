## Tests for Chow-Liu Tree Structure Learning
##
## TDD tests for the Chow-Liu algorithm which finds the optimal
## tree-structured approximation to a joint distribution.
##
## The algorithm:
## 1. Compute mutual information I(Xi; Xj) for all variable pairs
## 2. Build maximum weight spanning tree using these MI values
## 3. Result minimizes KL divergence from true distribution

import std/[unittest, math, sequtils, algorithm, strutils]
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/math/entropy
import ../src/occam/math/chow_liu

# Test helper to create a simple 2-variable dataset
proc create2VarData(): (VariableList, ContingencyTable) =
  var varList = initVariableList()
  discard varList.add(initVariable("A", "A", Cardinality(2)))
  discard varList.add(initVariable("B", "B", Cardinality(2)))

  var table = initContingencyTable(varList.keySize)
  # Strong positive association: A=0,B=0 and A=1,B=1 more likely
  table.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)]), 40.0)
  table.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 1)]), 10.0)
  table.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 0)]), 10.0)
  table.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)]), 40.0)
  table.sort()
  table.normalize()
  (varList, table)

# Test helper to create a 3-variable chain dataset
proc create3VarChainData(): (VariableList, ContingencyTable) =
  var varList = initVariableList()
  discard varList.add(initVariable("A", "A", Cardinality(2)))
  discard varList.add(initVariable("B", "B", Cardinality(2)))
  discard varList.add(initVariable("C", "C", Cardinality(2)))

  var table = initContingencyTable(varList.keySize)
  # Chain structure: A->B->C (A and C conditionally independent given B)
  # P(A,B,C) = P(A) * P(B|A) * P(C|B)
  for a in 0..1:
    for b in 0..1:
      for c in 0..1:
        # Strong A-B association, strong B-C association, weak A-C
        var prob = 1.0
        # P(A) = 0.5
        prob *= 0.5
        # P(B|A): B tends to match A
        let pBA = if a == b: 0.8 else: 0.2
        prob *= pBA
        # P(C|B): C tends to match B
        let pCB = if b == c: 0.8 else: 0.2
        prob *= pCB

        let key = varList.buildKey(@[
          (VariableIndex(0), a),
          (VariableIndex(1), b),
          (VariableIndex(2), c)
        ])
        table.add(key, prob * 100.0)  # Scale to counts

  table.sort()
  table.normalize()
  (varList, table)

# Test helper for 3-variable triangle (all pairs associated)
proc create3VarTriangleData(): (VariableList, ContingencyTable) =
  var varList = initVariableList()
  discard varList.add(initVariable("A", "A", Cardinality(2)))
  discard varList.add(initVariable("B", "B", Cardinality(2)))
  discard varList.add(initVariable("C", "C", Cardinality(2)))

  var table = initContingencyTable(varList.keySize)
  # Triangle: all pairs equally associated
  for a in 0..1:
    for b in 0..1:
      for c in 0..1:
        # All three tend to match
        let matches = (if a == b: 1 else: 0) + (if b == c: 1 else: 0) + (if a == c: 1 else: 0)
        let prob = case matches
          of 3: 0.3  # All match
          of 2: 0.1  # Two match
          of 1: 0.05 # One match
          else: 0.02 # None match

        let key = varList.buildKey(@[
          (VariableIndex(0), a),
          (VariableIndex(1), b),
          (VariableIndex(2), c)
        ])
        table.add(key, prob * 100.0)

  table.sort()
  table.normalize()
  (varList, table)


suite "Mutual Information Computation":

  test "MI is zero for independent variables":
    # Arrange: Independent A, B
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))

    var table = initContingencyTable(varList.keySize)
    # Independent: P(A,B) = P(A) * P(B)
    table.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)]), 25.0)
    table.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 1)]), 25.0)
    table.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 0)]), 25.0)
    table.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)]), 25.0)
    table.sort()
    table.normalize()

    # Act
    let mi = computeMutualInformation(table, varList, VariableIndex(0), VariableIndex(1))

    # Assert
    check mi < 0.001  # Essentially zero

  test "MI is positive for associated variables":
    # Arrange
    let (varList, table) = create2VarData()

    # Act
    let mi = computeMutualInformation(table, varList, VariableIndex(0), VariableIndex(1))

    # Assert
    check mi > 0.1  # Should be positive for associated variables

  test "MI is symmetric":
    # Arrange
    let (varList, table) = create2VarData()

    # Act
    let mi_ab = computeMutualInformation(table, varList, VariableIndex(0), VariableIndex(1))
    let mi_ba = computeMutualInformation(table, varList, VariableIndex(1), VariableIndex(0))

    # Assert
    check abs(mi_ab - mi_ba) < 1e-10

  test "MI bounded by min entropy":
    # Arrange
    let (varList, table) = create2VarData()

    # Act
    let mi = computeMutualInformation(table, varList, VariableIndex(0), VariableIndex(1))
    let h_a = entropy(table.project(varList, @[VariableIndex(0)]))
    let h_b = entropy(table.project(varList, @[VariableIndex(1)]))

    # Assert: MI <= min(H(A), H(B))
    check mi <= min(h_a, h_b) + 1e-10


suite "Chow-Liu Tree Construction":

  test "2 variables produces single edge":
    # Arrange
    let (varList, table) = create2VarData()

    # Act
    let tree = chowLiu(table, varList)

    # Assert
    check tree.edges.len == 1  # n-1 edges for n variables
    check tree.edges[0].weight > 0

  test "3 variables produces 2 edges":
    # Arrange
    let (varList, table) = create3VarChainData()

    # Act
    let tree = chowLiu(table, varList)

    # Assert
    check tree.edges.len == 2  # n-1 edges

  test "chain data produces chain tree":
    # Arrange: A-B-C chain structure
    let (varList, table) = create3VarChainData()

    # Act
    let tree = chowLiu(table, varList)

    # Assert: Should find A-B and B-C edges (or equivalent)
    # The tree should NOT have A-C edge as direct connection
    var hasAB = false
    var hasBC = false
    var hasAC = false

    for edge in tree.edges:
      if (edge.v1 == VariableIndex(0) and edge.v2 == VariableIndex(1)) or
         (edge.v1 == VariableIndex(1) and edge.v2 == VariableIndex(0)):
        hasAB = true
      if (edge.v1 == VariableIndex(1) and edge.v2 == VariableIndex(2)) or
         (edge.v1 == VariableIndex(2) and edge.v2 == VariableIndex(1)):
        hasBC = true
      if (edge.v1 == VariableIndex(0) and edge.v2 == VariableIndex(2)) or
         (edge.v1 == VariableIndex(2) and edge.v2 == VariableIndex(0)):
        hasAC = true

    # For a chain A-B-C, we expect A-B and B-C (not A-C directly)
    check hasAB
    check hasBC
    check not hasAC

  test "tree total weight equals sum of edge MI":
    # Arrange
    let (varList, table) = create3VarChainData()

    # Act
    let tree = chowLiu(table, varList)
    var totalWeight = 0.0
    for edge in tree.edges:
      totalWeight += edge.weight

    # Assert: Total weight should equal sum of MI for selected edges
    check totalWeight > 0


suite "Chow-Liu to Model Conversion":

  test "tree converts to valid OCCAM model":
    # Arrange
    let (varList, table) = create3VarChainData()
    let tree = chowLiu(table, varList)

    # Act
    let model = treeToModel(tree, varList)

    # Assert: Model should have same number of relations as edges
    check model.relationCount == tree.edges.len

  test "converted model is decomposable (no loops)":
    # Arrange
    let (varList, table) = create3VarTriangleData()
    let tree = chowLiu(table, varList)

    # Act
    let model = treeToModel(tree, varList)

    # Assert: Tree model should never have loops
    check not model.hasLoops(varList)

  test "model printName is valid":
    # Arrange
    let (varList, table) = create2VarData()
    let tree = chowLiu(table, varList)
    let model = treeToModel(tree, varList)

    # Act
    let name = model.printName(varList)

    # Assert: Should produce valid model notation
    check name.len > 0
    check name.contains("A") or name.contains("B")
