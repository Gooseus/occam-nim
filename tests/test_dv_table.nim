## Test suite for Conditional DV Table and Confusion Matrix
## Tests for directed system analysis output

import std/[math, sequtils]
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/math/entropy
import ../src/occam/manager/vb

# Helper to create a directed variable list (IVs + DV)
proc createDirectedVarList(): VariableList =
  result = initVariableList()
  discard result.add(newVariable("A", "A", Cardinality(2), isDependent = false))
  discard result.add(newVariable("B", "B", Cardinality(2), isDependent = false))
  discard result.add(newVariable("Z", "Z", Cardinality(2), isDependent = true))


# Helper to create test data with known structure
# This data has Z dependent on A and B with specific probabilities
proc createTestData(varList: VariableList): Table =
  result = initContingencyTable(varList.keySize)

  # Create data where Z=1 is more likely when A=1 or B=1
  # State (A,B,Z) -> count
  # (0,0,0) -> 80, (0,0,1) -> 20  -- P(Z=1|A=0,B=0) = 0.2
  # (0,1,0) -> 40, (0,1,1) -> 60  -- P(Z=1|A=0,B=1) = 0.6
  # (1,0,0) -> 50, (1,0,1) -> 50  -- P(Z=1|A=1,B=0) = 0.5
  # (1,1,0) -> 10, (1,1,1) -> 90  -- P(Z=1|A=1,B=1) = 0.9

  let states = @[
    (@[0, 0, 0], 80.0),
    (@[0, 0, 1], 20.0),
    (@[0, 1, 0], 40.0),
    (@[0, 1, 1], 60.0),
    (@[1, 0, 0], 50.0),
    (@[1, 0, 1], 50.0),
    (@[1, 1, 0], 10.0),
    (@[1, 1, 1], 90.0)
  ]

  for (state, count) in states:
    var pairs: seq[(VariableIndex, int)]
    for i, v in state:
      pairs.add((VariableIndex(i), v))
    let key = varList.buildKey(pairs)
    result.add(key, count)

  result.sort()


suite "Conditional DV Table":
  setup:
    let varList = createDirectedVarList()
    var data = createTestData(varList)
    var mgr = initVBManager(varList, data)

  test "compute P(DV|IV) for each IV state":
    # Fit a model that includes all IVs predicting Z
    let model = mgr.makeModel("ABZ")
    let dvTable = mgr.computeConditionalDV(model)

    # Should have 4 IV state combinations (2x2)
    check dvTable.ivStates.len == 4

    # Check probabilities for state (0,0): P(Z=0)=0.8, P(Z=1)=0.2
    check dvTable.dvProbs[0].len == 2
    check abs(dvTable.dvProbs[0][0] - 0.8) < 0.01  # P(Z=0|A=0,B=0)
    check abs(dvTable.dvProbs[0][1] - 0.2) < 0.01  # P(Z=1|A=0,B=0)

  test "prediction rule (max probability state)":
    let model = mgr.makeModel("ABZ")
    let dvTable = mgr.computeConditionalDV(model)

    # Predictions should be the DV value with highest probability
    # State (0,0): P(Z=0)=0.8 > P(Z=1)=0.2, predict Z=0
    check dvTable.predictions[0] == 0

    # State (0,1): P(Z=0)=0.4 < P(Z=1)=0.6, predict Z=1
    check dvTable.predictions[1] == 1

    # State (1,0): P(Z=0)=0.5 = P(Z=1)=0.5, could be either (tie)
    # Usually defaults to lower index
    check dvTable.predictions[2] in [0, 1]

    # State (1,1): P(Z=0)=0.1 < P(Z=1)=0.9, predict Z=1
    check dvTable.predictions[3] == 1

  test "percent correct calculation":
    let model = mgr.makeModel("ABZ")
    let dvTable = mgr.computeConditionalDV(model)

    # Calculate expected correct predictions:
    # (0,0): predict 0, correct = 80 out of 100
    # (0,1): predict 1, correct = 60 out of 100
    # (1,0): predict 0 or 1, correct = 50 out of 100 (tie)
    # (1,1): predict 1, correct = 90 out of 100
    # Total = (80 + 60 + 50 + 90) / 400 = 280/400 = 0.70

    check dvTable.percentCorrect > 0.65
    check dvTable.percentCorrect < 0.75

  test "IV states are in correct order":
    let model = mgr.makeModel("ABZ")
    let dvTable = mgr.computeConditionalDV(model)

    # IV states should be in lexicographic order: (0,0), (0,1), (1,0), (1,1)
    check dvTable.ivStates[0] == @[0, 0]
    check dvTable.ivStates[1] == @[0, 1]
    check dvTable.ivStates[2] == @[1, 0]
    check dvTable.ivStates[3] == @[1, 1]

  test "simpler model (single IV)":
    # Model with just A predicting Z
    let model = mgr.makeModel("AZ:B")
    let dvTable = mgr.computeConditionalDV(model)

    # Still should have 4 IV states, but probabilities depend only on A
    check dvTable.ivStates.len == 4

    # P(Z|A=0,B=*) should be the same for B=0 and B=1
    # Marginalizing: A=0 has 200 samples, Z=1 count = 20+60 = 80
    # P(Z=1|A=0) = 80/200 = 0.4
    let p_z1_given_a0_b0 = dvTable.dvProbs[0][1]
    let p_z1_given_a0_b1 = dvTable.dvProbs[1][1]
    check abs(p_z1_given_a0_b0 - p_z1_given_a0_b1) < 0.01


suite "Confusion Matrix":
  setup:
    let varList = createDirectedVarList()
    var data = createTestData(varList)
    var mgr = initVBManager(varList, data)

  test "2x2 confusion matrix for binary DV":
    let model = mgr.makeModel("ABZ")
    let cm = mgr.computeConfusionMatrix(model)

    # Should be 2x2 matrix
    check cm.matrix.len == 2
    check cm.matrix[0].len == 2
    check cm.matrix[1].len == 2

  test "confusion matrix row/column labels":
    let model = mgr.makeModel("ABZ")
    let cm = mgr.computeConfusionMatrix(model)

    # Labels should be DV values
    check cm.labels.len == 2
    check cm.labels[0] == "0"
    check cm.labels[1] == "1"

  test "confusion matrix counts sum to total":
    let model = mgr.makeModel("ABZ")
    let cm = mgr.computeConfusionMatrix(model)

    var total = 0
    for row in cm.matrix:
      for cell in row:
        total += cell

    # Total should equal sample size (400)
    check total == 400

  test "accuracy calculation":
    let model = mgr.makeModel("ABZ")
    let cm = mgr.computeConfusionMatrix(model)

    # Accuracy = (TP + TN) / total
    # From our predictions:
    # (0,0): actual mostly Z=0, predict 0 -> 80 correct
    # (0,1): actual mostly Z=1, predict 1 -> 60 correct
    # (1,0): tie, predict 0 or 1 -> 50 correct
    # (1,1): actual mostly Z=1, predict 1 -> 90 correct

    check cm.accuracy > 0.65
    check cm.accuracy < 0.75

  test "per-class precision":
    let model = mgr.makeModel("ABZ")
    let cm = mgr.computeConfusionMatrix(model)

    # Precision = TP / (TP + FP)
    check cm.perClassPrecision.len == 2
    check cm.perClassPrecision[0] > 0.0  # Precision for Z=0
    check cm.perClassPrecision[1] > 0.0  # Precision for Z=1

  test "per-class recall":
    let model = mgr.makeModel("ABZ")
    let cm = mgr.computeConfusionMatrix(model)

    # Recall = TP / (TP + FN)
    check cm.perClassRecall.len == 2
    check cm.perClassRecall[0] > 0.0  # Recall for Z=0
    check cm.perClassRecall[1] > 0.0  # Recall for Z=1


suite "Confusion Matrix - Multi-class":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2), isDependent = false))
    discard varList.add(newVariable("Z", "Z", Cardinality(3), isDependent = true))  # 3-class DV

  test "3x3 confusion matrix":
    # Create data with 3-class DV
    var data = initContingencyTable(varList.keySize)
    # A=0 -> mostly Z=0
    data.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)]), 70.0)
    data.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 1)]), 20.0)
    data.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 2)]), 10.0)
    # A=1 -> mostly Z=2
    data.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 0)]), 15.0)
    data.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)]), 25.0)
    data.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 2)]), 60.0)
    data.sort()

    var mgr = initVBManager(varList, data)
    let model = mgr.makeModel("AZ")
    let cm = mgr.computeConfusionMatrix(model)

    # Should be 3x3 matrix
    check cm.matrix.len == 3
    check cm.matrix[0].len == 3
    check cm.matrix[1].len == 3
    check cm.matrix[2].len == 3

    # Labels should have 3 values
    check cm.labels.len == 3

  test "NxN confusion matrix accuracy":
    var data = initContingencyTable(varList.keySize)
    data.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)]), 70.0)
    data.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 1)]), 20.0)
    data.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 2)]), 10.0)
    data.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 0)]), 15.0)
    data.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)]), 25.0)
    data.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 2)]), 60.0)
    data.sort()

    var mgr = initVBManager(varList, data)
    let model = mgr.makeModel("AZ")
    let cm = mgr.computeConfusionMatrix(model)

    # Predictions:
    # A=0: P(Z=0)=0.7, P(Z=1)=0.2, P(Z=2)=0.1 -> predict 0
    #   Correct: 70 of 100
    # A=1: P(Z=0)=0.15, P(Z=1)=0.25, P(Z=2)=0.6 -> predict 2
    #   Correct: 60 of 100
    # Total accuracy = (70+60)/200 = 0.65

    check cm.accuracy > 0.60
    check cm.accuracy < 0.70


suite "Conditional DV - Edge Cases":
  test "single IV variable":
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2), isDependent = false))
    discard varList.add(newVariable("Z", "Z", Cardinality(2), isDependent = true))

    var data = initContingencyTable(varList.keySize)
    data.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)]), 80.0)
    data.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 1)]), 20.0)
    data.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 0)]), 30.0)
    data.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)]), 70.0)
    data.sort()

    var mgr = initVBManager(varList, data)
    let model = mgr.makeModel("AZ")
    let dvTable = mgr.computeConditionalDV(model)

    # Should have 2 IV states
    check dvTable.ivStates.len == 2
    check dvTable.ivStates[0] == @[0]
    check dvTable.ivStates[1] == @[1]

    # Check predictions
    check dvTable.predictions[0] == 0  # A=0 -> predict Z=0
    check dvTable.predictions[1] == 1  # A=1 -> predict Z=1

  test "three IV variables":
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2), isDependent = false))
    discard varList.add(newVariable("B", "B", Cardinality(2), isDependent = false))
    discard varList.add(newVariable("C", "C", Cardinality(2), isDependent = false))
    discard varList.add(newVariable("Z", "Z", Cardinality(2), isDependent = true))

    # Create minimal data
    var data = initContingencyTable(varList.keySize)
    # Just a few states for testing
    for a in 0..1:
      for b in 0..1:
        for c in 0..1:
          let zProb = if a + b + c >= 2: 0.9 else: 0.1
          data.add(varList.buildKey(@[
            (VariableIndex(0), a),
            (VariableIndex(1), b),
            (VariableIndex(2), c),
            (VariableIndex(3), 0)
          ]), 100.0 * (1.0 - zProb))
          data.add(varList.buildKey(@[
            (VariableIndex(0), a),
            (VariableIndex(1), b),
            (VariableIndex(2), c),
            (VariableIndex(3), 1)
          ]), 100.0 * zProb)
    data.sort()

    var mgr = initVBManager(varList, data)
    let model = mgr.makeModel("ABCZ")
    let dvTable = mgr.computeConditionalDV(model)

    # Should have 8 IV states (2^3)
    check dvTable.ivStates.len == 8
