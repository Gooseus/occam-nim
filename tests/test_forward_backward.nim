## Tests for Forward-Backward Inference on Chains
##
## TDD tests for efficient marginal computation on chain-structured models.
## Forward-backward is a dynamic programming approach that exploits
## the linear structure of chains A-B-C-D for O(n*k^2) inference.

import std/unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/math/entropy
import ../src/occam/math/belief_propagation
import ../src/occam/math/forward_backward

# Test helper: create a 3-variable chain dataset
proc create3VarChain(): (VariableList, ContingencyTable) =
  var varList = initVariableList()
  discard varList.add(initVariable("A", "A", Cardinality(2)))
  discard varList.add(initVariable("B", "B", Cardinality(2)))
  discard varList.add(initVariable("C", "C", Cardinality(2)))

  var table = initContingencyTable(varList.keySize)
  # Chain structure: strong A-B and B-C correlations
  for a in 0..1:
    for b in 0..1:
      for c in 0..1:
        var prob = 0.5  # P(A)
        let pBA = if a == b: 0.8 else: 0.2
        let pCB = if b == c: 0.8 else: 0.2
        prob *= pBA * pCB

        let key = varList.buildKey(@[
          (VariableIndex(0), a),
          (VariableIndex(1), b),
          (VariableIndex(2), c)
        ])
        table.add(key, prob * 100.0)

  table.sort()
  table.normalize()
  (varList, table)

# Test helper: create a 4-variable chain
proc create4VarChain(): (VariableList, ContingencyTable) =
  var varList = initVariableList()
  discard varList.add(initVariable("A", "A", Cardinality(2)))
  discard varList.add(initVariable("B", "B", Cardinality(2)))
  discard varList.add(initVariable("C", "C", Cardinality(2)))
  discard varList.add(initVariable("D", "D", Cardinality(2)))

  var table = initContingencyTable(varList.keySize)
  for a in 0..1:
    for b in 0..1:
      for c in 0..1:
        for d in 0..1:
          var prob = 0.5
          let pBA = if a == b: 0.7 else: 0.3
          let pCB = if b == c: 0.7 else: 0.3
          let pDC = if c == d: 0.7 else: 0.3
          prob *= pBA * pCB * pDC

          let key = varList.buildKey(@[
            (VariableIndex(0), a),
            (VariableIndex(1), b),
            (VariableIndex(2), c),
            (VariableIndex(3), d)
          ])
          table.add(key, prob * 100.0)

  table.sort()
  table.normalize()
  (varList, table)


suite "Forward-Backward Basic Operations":

  test "forward pass produces valid alpha messages":
    # Arrange
    let (varList, table) = create3VarChain()
    let chainOrder = @[VariableIndex(0), VariableIndex(1), VariableIndex(2)]

    # Act
    let alpha = forwardPass(table, varList, chainOrder)

    # Assert: Should have alpha for each variable
    check alpha.len == 3

    # Each alpha should be a valid probability distribution
    for a in alpha:
      check a.sum > 0.99
      check a.sum < 1.01

  test "backward pass produces valid beta messages":
    # Arrange
    let (varList, table) = create3VarChain()
    let chainOrder = @[VariableIndex(0), VariableIndex(1), VariableIndex(2)]

    # Act
    let beta = backwardPass(table, varList, chainOrder)

    # Assert: Should have beta for each variable
    check beta.len == 3

  test "combined marginals are valid distributions":
    # Arrange
    let (varList, table) = create3VarChain()
    let chainOrder = @[VariableIndex(0), VariableIndex(1), VariableIndex(2)]

    # Act
    let marginals = forwardBackward(table, varList, chainOrder)

    # Assert: Each marginal should be normalized
    for m in marginals:
      check m.sum > 0.99
      check m.sum < 1.01


suite "Forward-Backward Correctness":

  test "marginals match generic BP on chain":
    # Arrange
    let (varList, table) = create3VarChain()
    let chainOrder = @[VariableIndex(0), VariableIndex(1), VariableIndex(2)]

    # Act: Get marginals from forward-backward
    let fbMarginals = forwardBackward(table, varList, chainOrder)

    # Act: Get marginals from generic BP
    # (BP requires junction tree, but for chain it should give same result)
    # For now, compare with directly computed marginals
    let directMarginals = @[
      table.project(varList, @[VariableIndex(0)]),
      table.project(varList, @[VariableIndex(1)]),
      table.project(varList, @[VariableIndex(2)])
    ]

    # Assert: Marginals should match
    for i in 0..<3:
      let fb = fbMarginals[i]
      let direct = directMarginals[i]

      # Compare entropy (proxy for distribution equality)
      let fbEntropy = entropy(fb)
      let directEntropy = entropy(direct)
      check abs(fbEntropy - directEntropy) < 1e-10

  test "4-variable chain produces correct marginals":
    # Arrange
    let (varList, table) = create4VarChain()
    let chainOrder = @[VariableIndex(0), VariableIndex(1),
                       VariableIndex(2), VariableIndex(3)]

    # Act
    let marginals = forwardBackward(table, varList, chainOrder)

    # Assert
    check marginals.len == 4

    # Each marginal should be normalized
    for m in marginals:
      check m.sum > 0.99
      check m.sum < 1.01

  test "marginals match direct projection":
    # Arrange
    let (varList, table) = create4VarChain()
    let chainOrder = @[VariableIndex(0), VariableIndex(1),
                       VariableIndex(2), VariableIndex(3)]

    # Act
    let fbMarginals = forwardBackward(table, varList, chainOrder)

    # Compare with direct marginalization
    for i in 0..<4:
      let directMarginal = table.project(varList, @[VariableIndex(i)])
      let fbMarginal = fbMarginals[i]

      let directH = entropy(directMarginal)
      let fbH = entropy(fbMarginal)

      # Entropies should match (within floating point tolerance)
      check abs(directH - fbH) < 1e-10


suite "Chain Detection Integration":

  test "isChainModel detects valid chain":
    # Arrange: A-B-C chain
    let chainModel = initModel(@[
      initRelation(@[VariableIndex(0), VariableIndex(1)]),
      initRelation(@[VariableIndex(1), VariableIndex(2)])
    ])

    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

    # Act & Assert
    check isChainModel(chainModel, varList)

  test "extractChainOrder returns correct order":
    # Arrange: A-B-C chain
    let chainModel = initModel(@[
      initRelation(@[VariableIndex(0), VariableIndex(1)]),
      initRelation(@[VariableIndex(1), VariableIndex(2)])
    ])

    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

    # Act
    let order = extractChainOrder(chainModel, varList)

    # Assert: Should have all 3 variables in chain order
    check order.len == 3
    # Middle variable should be B (index 1)
    check order[1] == VariableIndex(1)

  test "non-chain model is not detected as chain":
    # Arrange: Triangle (not a chain)
    let triangleModel = initModel(@[
      initRelation(@[VariableIndex(0), VariableIndex(1)]),
      initRelation(@[VariableIndex(1), VariableIndex(2)]),
      initRelation(@[VariableIndex(0), VariableIndex(2)])
    ])

    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

    # Act & Assert
    check not isChainModel(triangleModel, varList)
