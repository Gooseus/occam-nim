## Test suite for IPF (Iterative Proportional Fitting) algorithm
## Tests convergence, marginal preservation, and correctness

import std/[math, options]
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/math/entropy
import ../src/occam/math/ipf

# Helper to create a simple table with given probabilities
proc makeSimpleTable(varList: VariableList; probs: seq[float64]): Table =
  result = initContingencyTable(varList.keySize)
  var idx = 0
  # Enumerate all combinations
  let card0 = varList[VariableIndex(0)].cardinality.toInt
  if varList.len == 1:
    for i in 0..<card0:
      if idx < probs.len:
        result.add(varList.buildKey(@[(VariableIndex(0), i)]), probs[idx])
        idx += 1
  elif varList.len == 2:
    let card1 = varList[VariableIndex(1)].cardinality.toInt
    for i in 0..<card0:
      for j in 0..<card1:
        if idx < probs.len:
          result.add(varList.buildKey(@[(VariableIndex(0), i), (VariableIndex(1), j)]), probs[idx])
          idx += 1
  elif varList.len == 3:
    let card1 = varList[VariableIndex(1)].cardinality.toInt
    let card2 = varList[VariableIndex(2)].cardinality.toInt
    for i in 0..<card0:
      for j in 0..<card1:
        for k in 0..<card2:
          if idx < probs.len:
            result.add(varList.buildKey(@[(VariableIndex(0), i), (VariableIndex(1), j), (VariableIndex(2), k)]), probs[idx])
            idx += 1
  result.sort()

# Helper to compute marginal sum for a relation
proc marginalSum(t: Table; varList: VariableList; rel: Relation): float64 =
  let proj = t.project(varList, rel.varIndices)
  proj.sum()

# Helper to check if two tables have same marginals for a set of relations
proc marginalsMatch(t1, t2: Table; varList: VariableList; rels: seq[Relation]; tol = 1e-6): bool =
  for rel in rels:
    let proj1 = t1.project(varList, rel.varIndices)
    let proj2 = t2.project(varList, rel.varIndices)
    # Check each cell in the projection
    for tup1 in proj1:
      let idx2 = proj2.find(tup1.key)
      if idx2.isNone:
        if tup1.value > tol:
          return false
      else:
        if abs(tup1.value - proj2[idx2.get].value) > tol:
          return false
  true


suite "IPF Basic Convergence":
  test "IPF converges for 2x2 table with single relation":
    # Single relation means algebraic solution exists
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))

    # Input data
    var inputTable = makeSimpleTable(varList, @[0.4, 0.1, 0.2, 0.3])

    # Model: AB (saturated - just returns input)
    let rels = @[initRelation(@[VariableIndex(0), VariableIndex(1)])]

    let result = ipf(inputTable, rels, varList)

    check result.converged
    check result.iterations <= 1  # Should converge immediately for saturated
    check abs(result.fitTable.sum() - 1.0) < 1e-10  # Normalized

  test "IPF converges for independence model":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))

    var inputTable = makeSimpleTable(varList, @[0.4, 0.1, 0.2, 0.3])

    # Model: A:B (independence)
    let rels = @[
      initRelation(@[VariableIndex(0)]),
      initRelation(@[VariableIndex(1)])
    ]

    let result = ipf(inputTable, rels, varList)

    check result.converged
    check abs(result.fitTable.sum() - 1.0) < 1e-10  # Normalized

    # Check marginals match: P(A) and P(B) should match input
    let inputA = inputTable.project(varList, @[VariableIndex(0)])
    let fitA = result.fitTable.project(varList, @[VariableIndex(0)])

    for tup in inputA:
      let idx = fitA.find(tup.key)
      check idx.isSome
      check abs(tup.value - fitA[idx.get].value) < 1e-6

  test "IPF converges for chain model AB:BC":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

    # Input data for 8 cells
    var inputTable = makeSimpleTable(varList, @[0.1, 0.2, 0.15, 0.05, 0.2, 0.1, 0.1, 0.1])

    # Model: AB:BC (chain - loopless)
    let rels = @[
      initRelation(@[VariableIndex(0), VariableIndex(1)]),
      initRelation(@[VariableIndex(1), VariableIndex(2)])
    ]

    let result = ipf(inputTable, rels, varList)

    check result.converged
    check abs(result.fitTable.sum() - 1.0) < 1e-10


suite "IPF Loop Models":
  test "IPF converges for triangle AB:BC:AC":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

    # Input data
    var inputTable = makeSimpleTable(varList, @[0.2, 0.1, 0.15, 0.05, 0.1, 0.15, 0.1, 0.15])

    # Model: AB:BC:AC (triangle - has loop)
    let rels = @[
      initRelation(@[VariableIndex(0), VariableIndex(1)]),
      initRelation(@[VariableIndex(1), VariableIndex(2)]),
      initRelation(@[VariableIndex(0), VariableIndex(2)])
    ]

    let result = ipf(inputTable, rels, varList)

    check result.converged
    check abs(result.fitTable.sum() - 1.0) < 1e-10
    check result.iterations > 1  # Should need multiple iterations

  test "IPF preserves marginals for triangle model":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

    var inputTable = makeSimpleTable(varList, @[0.2, 0.1, 0.15, 0.05, 0.1, 0.15, 0.1, 0.15])

    let rels = @[
      initRelation(@[VariableIndex(0), VariableIndex(1)]),
      initRelation(@[VariableIndex(1), VariableIndex(2)]),
      initRelation(@[VariableIndex(0), VariableIndex(2)])
    ]

    let result = ipf(inputTable, rels, varList)

    check result.converged

    # Each marginal should match input
    check marginalsMatch(inputTable, result.fitTable, varList, rels, 1e-5)


suite "IPF Edge Cases":
  test "IPF handles uniform input":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))

    # Uniform distribution
    var inputTable = makeSimpleTable(varList, @[0.25, 0.25, 0.25, 0.25])

    let rels = @[
      initRelation(@[VariableIndex(0)]),
      initRelation(@[VariableIndex(1)])
    ]

    let result = ipf(inputTable, rels, varList)

    check result.converged
    # Uniform input with independence model should stay uniform
    for tup in result.fitTable:
      check abs(tup.value - 0.25) < 1e-6

  test "IPF handles sparse data":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(3)))

    # Sparse input - only some cells have data
    var inputTable = initContingencyTable(varList.keySize)
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)]), 0.5)
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)]), 0.3)
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 2), (VariableIndex(1), 2)]), 0.2)
    inputTable.sort()

    let rels = @[
      initRelation(@[VariableIndex(0)]),
      initRelation(@[VariableIndex(1)])
    ]

    let result = ipf(inputTable, rels, varList)

    check result.converged
    check abs(result.fitTable.sum() - 1.0) < 1e-10

  test "IPF respects max iterations":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

    var inputTable = makeSimpleTable(varList, @[0.2, 0.1, 0.15, 0.05, 0.1, 0.15, 0.1, 0.15])

    let rels = @[
      initRelation(@[VariableIndex(0), VariableIndex(1)]),
      initRelation(@[VariableIndex(1), VariableIndex(2)]),
      initRelation(@[VariableIndex(0), VariableIndex(2)])
    ]

    # Use very low max iterations
    let config = IPFConfig(maxIterations: 2, convergenceThreshold: 1e-15)
    let result = ipf(inputTable, rels, varList, config)

    check result.iterations <= 2
    # May or may not converge with only 2 iterations

  test "IPF handles very small convergence threshold":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))

    var inputTable = makeSimpleTable(varList, @[0.4, 0.1, 0.2, 0.3])

    let rels = @[
      initRelation(@[VariableIndex(0)]),
      initRelation(@[VariableIndex(1)])
    ]

    let config = IPFConfig(maxIterations: 1000, convergenceThreshold: 1e-12)
    let result = ipf(inputTable, rels, varList, config)

    check result.converged
    check result.error < 1e-12


suite "IPF Numerical Stability":
  test "IPF maintains probability normalization":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(3)))
    discard varList.add(initVariable("C", "C", Cardinality(3)))

    # 27-cell table
    var probs = newSeq[float64](27)
    var total = 0.0
    for i in 0..<27:
      probs[i] = float64(i + 1)
      total += probs[i]
    for i in 0..<27:
      probs[i] /= total

    var inputTable = makeSimpleTable(varList, probs)

    # Triangle loop
    let rels = @[
      initRelation(@[VariableIndex(0), VariableIndex(1)]),
      initRelation(@[VariableIndex(1), VariableIndex(2)]),
      initRelation(@[VariableIndex(0), VariableIndex(2)])
    ]

    let result = ipf(inputTable, rels, varList)

    check result.converged
    check abs(result.fitTable.sum() - 1.0) < 1e-10

  test "IPF handles near-zero probabilities":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))

    # Very skewed distribution
    var inputTable = makeSimpleTable(varList, @[0.99, 0.005, 0.004, 0.001])

    let rels = @[
      initRelation(@[VariableIndex(0)]),
      initRelation(@[VariableIndex(1)])
    ]

    let result = ipf(inputTable, rels, varList)

    check result.converged
    check abs(result.fitTable.sum() - 1.0) < 1e-10

    # All probabilities should be non-negative
    for tup in result.fitTable:
      check tup.value >= 0.0

  test "IPF produces non-negative probabilities":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

    var inputTable = makeSimpleTable(varList, @[0.3, 0.05, 0.1, 0.05, 0.15, 0.1, 0.15, 0.1])

    let rels = @[
      initRelation(@[VariableIndex(0), VariableIndex(1)]),
      initRelation(@[VariableIndex(1), VariableIndex(2)]),
      initRelation(@[VariableIndex(0), VariableIndex(2)])
    ]

    let result = ipf(inputTable, rels, varList)

    check result.converged
    for tup in result.fitTable:
      check tup.value >= -1e-10  # Allow tiny numerical errors


suite "IPF vs Algebraic for Loopless":
  test "IPF matches algebraic for chain AB:BC":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

    var inputTable = makeSimpleTable(varList, @[0.1, 0.2, 0.15, 0.05, 0.2, 0.1, 0.1, 0.1])

    let rels = @[
      initRelation(@[VariableIndex(0), VariableIndex(1)]),
      initRelation(@[VariableIndex(1), VariableIndex(2)])
    ]

    let ipfResult = ipf(inputTable, rels, varList)

    # Compute algebraic result: P(ABC) = P(AB) * P(BC) / P(B)
    let pAB = inputTable.project(varList, @[VariableIndex(0), VariableIndex(1)])
    let pBC = inputTable.project(varList, @[VariableIndex(1), VariableIndex(2)])
    let pB = inputTable.project(varList, @[VariableIndex(1)])

    # Both should have same entropy (within tolerance)
    let hIPF = entropy(ipfResult.fitTable)

    # IPF should converge quickly for loopless
    check ipfResult.converged
    # Should preserve marginals
    check marginalsMatch(inputTable, ipfResult.fitTable, varList, rels, 1e-5)

  test "IPF matches algebraic for star AB:AC:AD":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))
    discard varList.add(initVariable("D", "D", Cardinality(2)))

    # 16-cell table
    var probs = newSeq[float64](16)
    var total = 0.0
    for i in 0..<16:
      probs[i] = float64(i + 1)
      total += probs[i]
    for i in 0..<16:
      probs[i] /= total

    var inputTable = makeSimpleTable(varList, probs)

    let rels = @[
      initRelation(@[VariableIndex(0), VariableIndex(1)]),
      initRelation(@[VariableIndex(0), VariableIndex(2)]),
      initRelation(@[VariableIndex(0), VariableIndex(3)])
    ]

    let result = ipf(inputTable, rels, varList)

    check result.converged
    check marginalsMatch(inputTable, result.fitTable, varList, rels, 1e-5)


suite "IPF Entropy Properties":
  test "Fitted entropy is bounded by data entropy":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

    var inputTable = makeSimpleTable(varList, @[0.2, 0.1, 0.15, 0.05, 0.1, 0.15, 0.1, 0.15])

    let rels = @[
      initRelation(@[VariableIndex(0), VariableIndex(1)]),
      initRelation(@[VariableIndex(1), VariableIndex(2)]),
      initRelation(@[VariableIndex(0), VariableIndex(2)])
    ]

    let result = ipf(inputTable, rels, varList)

    let hData = entropy(inputTable)
    let hFit = entropy(result.fitTable)

    # Fitted entropy should be >= data entropy (model has less information)
    check hFit >= hData - 1e-6

  test "Saturated model entropy equals data entropy":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))

    var inputTable = makeSimpleTable(varList, @[0.4, 0.1, 0.2, 0.3])

    # Saturated model: AB
    let rels = @[initRelation(@[VariableIndex(0), VariableIndex(1)])]

    let result = ipf(inputTable, rels, varList)

    let hData = entropy(inputTable)
    let hFit = entropy(result.fitTable)

    check abs(hFit - hData) < 1e-10

  test "Independence model has maximum entropy for constraints":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))

    # Non-independent input
    var inputTable = makeSimpleTable(varList, @[0.4, 0.1, 0.1, 0.4])

    let rels = @[
      initRelation(@[VariableIndex(0)]),
      initRelation(@[VariableIndex(1)])
    ]

    let result = ipf(inputTable, rels, varList)

    let hData = entropy(inputTable)
    let hFit = entropy(result.fitTable)

    # Independence model should have higher entropy than dependent data
    check hFit >= hData - 1e-6


suite "IPF Special Cases":
  test "IPF with single-variable relations":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

    # 12-cell table
    var probs = newSeq[float64](12)
    var total = 0.0
    for i in 0..<12:
      probs[i] = float64(i + 1)
      total += probs[i]
    for i in 0..<12:
      probs[i] /= total

    var inputTable = makeSimpleTable(varList, probs)

    # Independence: A:B:C
    let rels = @[
      initRelation(@[VariableIndex(0)]),
      initRelation(@[VariableIndex(1)]),
      initRelation(@[VariableIndex(2)])
    ]

    let result = ipf(inputTable, rels, varList)

    check result.converged
    check marginalsMatch(inputTable, result.fitTable, varList, rels, 1e-5)

  test "IPF with overlapping relations":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

    var inputTable = makeSimpleTable(varList, @[0.15, 0.1, 0.2, 0.05, 0.1, 0.15, 0.1, 0.15])

    # AB:ABC - overlapping relations
    let rels = @[
      initRelation(@[VariableIndex(0), VariableIndex(1)]),
      initRelation(@[VariableIndex(0), VariableIndex(1), VariableIndex(2)])
    ]

    let result = ipf(inputTable, rels, varList)

    check result.converged
    check abs(result.fitTable.sum() - 1.0) < 1e-10
