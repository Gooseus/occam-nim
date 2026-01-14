## Test suite for analysis module
## Tests conditional DV tables and confusion matrices for directed systems

import std/[math, sequtils]
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/core/results
import ../src/occam/manager/vb
import ../src/occam/manager/analysis


proc makeDirectedVarList(ivCount: int): VariableList =
  ## Create a directed variable list with binary IVs and DV
  result = initVariableList()
  for i in 0..<ivCount:
    let name = $chr(ord('A') + i)
    discard result.add(initVariable(name, name, Cardinality(2)))
  discard result.add(initVariable("Z", "Z", Cardinality(2), isDependent = true))


proc makeUniformData(varList: VariableList): Table =
  ## Create uniform distribution over all variables
  let n = varList.len
  var totalStates = 1
  for i in 0..<n:
    totalStates *= varList[VariableIndex(i)].cardinality.toInt

  result = initContingencyTable(varList.keySize, totalStates)

  var indices = newSeq[int](n)
  var done = false
  while not done:
    var keyPairs: seq[(VariableIndex, int)]
    for i in 0..<n:
      keyPairs.add((VariableIndex(i), indices[i]))
    let key = varList.buildKey(keyPairs)
    result.add(key, 10.0)

    var carry = true
    for i in 0..<n:
      if carry:
        indices[i] += 1
        if indices[i] >= varList[VariableIndex(i)].cardinality.toInt:
          indices[i] = 0
        else:
          carry = false
    if carry:
      done = true

  result.sort()


proc makePerfectPredictorData(varList: VariableList): Table =
  ## Create data where first IV perfectly predicts DV (Z = A)
  let n = varList.len
  var totalStates = 1
  for i in 0..<n:
    totalStates *= varList[VariableIndex(i)].cardinality.toInt

  result = initContingencyTable(varList.keySize, totalStates)

  var indices = newSeq[int](n)
  var done = false
  while not done:
    var keyPairs: seq[(VariableIndex, int)]
    for i in 0..<n:
      keyPairs.add((VariableIndex(i), indices[i]))
    let key = varList.buildKey(keyPairs)

    # Count is high only when A == Z (first IV equals DV)
    let a = indices[0]
    let z = indices[n - 1]  # DV is last variable
    let count = if a == z: 100.0 else: 1.0
    result.add(key, count)

    var carry = true
    for i in 0..<n:
      if carry:
        indices[i] += 1
        if indices[i] >= varList[VariableIndex(i)].cardinality.toInt:
          indices[i] = 0
        else:
          carry = false
    if carry:
      done = true

  result.sort()


suite "Conditional DV table - basic":
  setup:
    let varList = makeDirectedVarList(2)  # A, B, Z
    let inputTable = makeUniformData(varList)

  test "computes correct number of IV states":
    var mgr = initVBManager(varList, inputTable)

    # Bottom model: AB:Z
    let dvTable = mgr.computeConditionalDV(mgr.bottomRefModel)

    # 2 binary IVs -> 4 IV states
    check dvTable.ivStates.len == 4
    check dvTable.ivIndices.len == 2

  test "computes DV probabilities for each state":
    var mgr = initVBManager(varList, inputTable)
    let dvTable = mgr.computeConditionalDV(mgr.bottomRefModel)

    # Each IV state should have DV probabilities
    check dvTable.dvProbs.len == dvTable.ivStates.len

    # Each DV prob vector should have 2 entries (binary DV)
    for probs in dvTable.dvProbs:
      check probs.len == 2
      # Probabilities should sum to ~1
      check abs(probs[0] + probs[1] - 1.0) < 1e-6

  test "produces predictions for each IV state":
    var mgr = initVBManager(varList, inputTable)
    let dvTable = mgr.computeConditionalDV(mgr.bottomRefModel)

    check dvTable.predictions.len == dvTable.ivStates.len

    # Predictions should be valid DV values (0 or 1)
    for pred in dvTable.predictions:
      check pred >= 0
      check pred < 2


suite "Conditional DV table - accuracy":
  setup:
    let varList = makeDirectedVarList(1)  # A, Z (one IV)
    let inputTable = makePerfectPredictorData(varList)

  test "perfect predictor has high percent correct":
    var mgr = initVBManager(varList, inputTable)

    # Model AZ should have perfect prediction
    let rAZ = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let model = initModel(@[rAZ])

    let dvTable = mgr.computeConditionalDV(model)

    # With A perfectly predicting Z, percent correct should be high
    check dvTable.percentCorrect > 0.9

  test "counts match predictions":
    var mgr = initVBManager(varList, inputTable)

    let rAZ = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let model = initModel(@[rAZ])

    let dvTable = mgr.computeConditionalDV(model)

    # Total counts should sum to data size
    let totalCount = dvTable.totalCounts.foldl(a + b, 0)
    check totalCount > 0

    # Correct counts should not exceed total counts
    for i in 0..<dvTable.ivStates.len:
      check dvTable.correctCounts[i] <= dvTable.totalCounts[i]


suite "Confusion matrix - basic":
  setup:
    let varList = makeDirectedVarList(2)  # A, B, Z
    let inputTable = makeUniformData(varList)

  test "creates NxN matrix for N-class DV":
    var mgr = initVBManager(varList, inputTable)
    let cm = mgr.computeConfusionMatrix(mgr.bottomRefModel)

    # Binary DV -> 2x2 matrix
    check cm.matrix.len == 2
    check cm.matrix[0].len == 2
    check cm.matrix[1].len == 2

  test "computes accuracy":
    var mgr = initVBManager(varList, inputTable)
    let cm = mgr.computeConfusionMatrix(mgr.bottomRefModel)

    # Accuracy should be between 0 and 1
    check cm.accuracy >= 0.0
    check cm.accuracy <= 1.0

  test "computes per-class precision and recall":
    var mgr = initVBManager(varList, inputTable)
    let cm = mgr.computeConfusionMatrix(mgr.bottomRefModel)

    check cm.perClassPrecision.len == 2
    check cm.perClassRecall.len == 2

    # All values should be between 0 and 1
    for p in cm.perClassPrecision:
      check p >= 0.0
      check p <= 1.0
    for r in cm.perClassRecall:
      check r >= 0.0
      check r <= 1.0


suite "Confusion matrix - perfect predictor":
  setup:
    let varList = makeDirectedVarList(1)  # A, Z
    let inputTable = makePerfectPredictorData(varList)

  test "diagonal dominates for perfect predictor":
    var mgr = initVBManager(varList, inputTable)

    let rAZ = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let model = initModel(@[rAZ])

    let cm = mgr.computeConfusionMatrix(model)

    # Diagonal elements should be much larger than off-diagonal
    let diagonal = cm.matrix[0][0] + cm.matrix[1][1]
    let offDiagonal = cm.matrix[0][1] + cm.matrix[1][0]

    check diagonal > offDiagonal

  test "high accuracy for perfect predictor":
    var mgr = initVBManager(varList, inputTable)

    let rAZ = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let model = initModel(@[rAZ])

    let cm = mgr.computeConfusionMatrix(model)

    check cm.accuracy > 0.9


suite "Confusion matrix - labels":
  test "uses variable value labels when available":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    var dvVar = initVariable("Z", "Z", Cardinality(2), isDependent = true)
    dvVar.valueMap = @["No", "Yes"]
    discard varList.add(dvVar)

    let inputTable = makeUniformData(varList)
    var mgr = initVBManager(varList, inputTable)

    let cm = mgr.computeConfusionMatrix(mgr.bottomRefModel)

    check cm.labels.len == 2
    check cm.labels[0] == "No"
    check cm.labels[1] == "Yes"

  test "uses default labels when none provided":
    let varList = makeDirectedVarList(1)
    let inputTable = makeUniformData(varList)
    var mgr = initVBManager(varList, inputTable)

    let cm = mgr.computeConfusionMatrix(mgr.bottomRefModel)

    check cm.labels.len == 2
    check cm.labels[0] == "0"
    check cm.labels[1] == "1"


suite "Analysis with different models":
  setup:
    let varList = makeDirectedVarList(2)  # A, B, Z
    let inputTable = makePerfectPredictorData(varList)

  test "saturated model computes correctly":
    var mgr = initVBManager(varList, inputTable)

    # Saturated model: ABZ
    let dvTable = mgr.computeConditionalDV(mgr.topRefModel)

    check dvTable.ivStates.len == 4  # 2x2 = 4 IV states
    check dvTable.percentCorrect > 0.0

  test "different models have different predictions":
    var mgr = initVBManager(varList, inputTable)

    let bottomDvTable = mgr.computeConditionalDV(mgr.bottomRefModel)
    let topDvTable = mgr.computeConditionalDV(mgr.topRefModel)

    # Both should have same number of IV states
    check bottomDvTable.ivStates.len == topDvTable.ivStates.len

    # But predictions may differ (depending on model structure)
    # This just verifies both compute without error
    check bottomDvTable.predictions.len > 0
    check topDvTable.predictions.len > 0


suite "Analysis edge cases":
  test "single IV variable":
    let varList = makeDirectedVarList(1)  # A, Z
    let inputTable = makeUniformData(varList)
    var mgr = initVBManager(varList, inputTable)

    let dvTable = mgr.computeConditionalDV(mgr.bottomRefModel)

    # 1 binary IV -> 2 IV states
    check dvTable.ivStates.len == 2
    check dvTable.ivIndices.len == 1

  test "three IV variables":
    let varList = makeDirectedVarList(3)  # A, B, C, Z
    let inputTable = makeUniformData(varList)
    var mgr = initVBManager(varList, inputTable)

    let dvTable = mgr.computeConditionalDV(mgr.bottomRefModel)

    # 3 binary IVs -> 8 IV states
    check dvTable.ivStates.len == 8
    check dvTable.ivIndices.len == 3

  test "precision and recall are correct for diagonal matrix":
    # Create data where all predictions are correct
    let varList = makeDirectedVarList(1)  # A, Z

    # Create perfect predictor data
    var inputTable = initContingencyTable(varList.keySize, 4)
    # A=0, Z=0: high count
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)]), 100.0)
    # A=0, Z=1: zero count
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 1)]), 0.0)
    # A=1, Z=0: zero count
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 0)]), 0.0)
    # A=1, Z=1: high count
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)]), 100.0)
    inputTable.sort()

    var mgr = initVBManager(varList, inputTable)
    let rAZ = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let model = initModel(@[rAZ])

    let cm = mgr.computeConfusionMatrix(model)

    # With perfect prediction, accuracy should be 1.0
    check cm.accuracy >= 0.99

    # Precision and recall should be 1.0 for both classes
    for p in cm.perClassPrecision:
      check p >= 0.99
    for r in cm.perClassRecall:
      check r >= 0.99
