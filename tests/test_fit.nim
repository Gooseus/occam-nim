## Test suite for fit functionality
## Tests model fitting with both loopless and loop models

import std/[math, options]
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/math/entropy
import ../src/occam/manager/vb

# Helper to create test data
proc setupTestData(): (VariableList, Table) =
  var varList = initVariableList()
  discard varList.add(newVariable("A", "A", Cardinality(2)))
  discard varList.add(newVariable("B", "B", Cardinality(2)))
  discard varList.add(newVariable("C", "C", Cardinality(2)))

  # Create test data
  var inputTable = initContingencyTable(varList.keySize)
  inputTable.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0), (VariableIndex(2), 0)]), 20.0)
  inputTable.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0), (VariableIndex(2), 1)]), 10.0)
  inputTable.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 1), (VariableIndex(2), 0)]), 15.0)
  inputTable.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 1), (VariableIndex(2), 1)]), 5.0)
  inputTable.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 0), (VariableIndex(2), 0)]), 10.0)
  inputTable.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 0), (VariableIndex(2), 1)]), 20.0)
  inputTable.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1), (VariableIndex(2), 0)]), 10.0)
  inputTable.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1), (VariableIndex(2), 1)]), 10.0)
  inputTable.sort()

  (varList, inputTable)


suite "Fit - Saturated Model":
  test "saturated model fit equals input data":
    let (varList, inputTable) = setupTestData()
    var mgr = initVBManager(varList, inputTable)

    let model = mgr.makeModel("ABC")
    let fitResult = mgr.fitModel(model)

    check not fitResult.hasLoops
    check abs(fitResult.lr) < 1e-6  # LR should be ~0 for saturated

  test "saturated model entropy equals data entropy":
    let (varList, inputTable) = setupTestData()
    var mgr = initVBManager(varList, inputTable)

    let model = mgr.makeModel("ABC")
    let fitResult = mgr.fitModel(model)

    var normalizedInput = inputTable
    normalizedInput.normalize()
    let dataH = entropy(normalizedInput)

    check abs(fitResult.h - dataH) < 1e-10


suite "Fit - Independence Model":
  test "independence model produces product of marginals":
    let (varList, inputTable) = setupTestData()
    var mgr = initVBManager(varList, inputTable)

    let model = mgr.makeModel("A:B:C")
    let fitResult = mgr.fitModel(model)

    check not fitResult.hasLoops
    check fitResult.h >= entropy(mgr.getNormalizedData()) - 1e-6  # H_indep >= H_data

  test "independence model has correct DF":
    let (varList, inputTable) = setupTestData()
    var mgr = initVBManager(varList, inputTable)

    let model = mgr.makeModel("A:B:C")
    let fitResult = mgr.fitModel(model)

    # DF for independence of 2x2x2 = 1+1+1 = 3
    check fitResult.df == 3


suite "Fit - Chain Models (Loopless)":
  test "chain model AB:BC is loopless":
    let (varList, inputTable) = setupTestData()
    var mgr = initVBManager(varList, inputTable)

    let model = mgr.makeModel("AB:BC")
    let fitResult = mgr.fitModel(model)

    check not fitResult.hasLoops

  test "chain model preserves marginals":
    let (varList, inputTable) = setupTestData()
    var mgr = initVBManager(varList, inputTable)

    let model = mgr.makeModel("AB:BC")
    let fitTable = mgr.makeFitTable(model)

    # Check AB marginal
    let inputAB = inputTable.project(varList, @[VariableIndex(0), VariableIndex(1)])
    let fitAB = fitTable.project(varList, @[VariableIndex(0), VariableIndex(1)])

    var normalizedInputAB = inputAB
    normalizedInputAB.normalize()

    for tup in normalizedInputAB:
      let idx = fitAB.find(tup.key)
      check idx.isSome
      check abs(tup.value - fitAB[idx.get].value) < 1e-5


suite "Fit - Loop Models":
  test "triangle model AB:BC:AC has loops":
    let (varList, inputTable) = setupTestData()
    var mgr = initVBManager(varList, inputTable)

    let model = mgr.makeModel("AB:BC:AC")
    let fitResult = mgr.fitModel(model)

    check fitResult.hasLoops
    check fitResult.ipfIterations > 0  # Should use IPF

  test "triangle model preserves all marginals":
    let (varList, inputTable) = setupTestData()
    var mgr = initVBManager(varList, inputTable)

    let model = mgr.makeModel("AB:BC:AC")
    let fitTable = mgr.makeFitTable(model)

    var normalizedInput = inputTable
    normalizedInput.normalize()

    # Check all three marginals
    for rels in [(@[VariableIndex(0), VariableIndex(1)]),
                 (@[VariableIndex(1), VariableIndex(2)]),
                 (@[VariableIndex(0), VariableIndex(2)])]:
      let inputMarg = normalizedInput.project(varList, rels)
      let fitMarg = fitTable.project(varList, rels)

      for tup in inputMarg:
        let idx = fitMarg.find(tup.key)
        check idx.isSome
        check abs(tup.value - fitMarg[idx.get].value) < 1e-5

  test "loop model entropy is between independence and saturated":
    let (varList, inputTable) = setupTestData()
    var mgr = initVBManager(varList, inputTable)

    let saturated = mgr.makeModel("ABC")
    let independence = mgr.makeModel("A:B:C")
    let triangle = mgr.makeModel("AB:BC:AC")

    let hSat = mgr.fitModel(saturated).h
    let hIndep = mgr.fitModel(independence).h
    let hTriangle = mgr.fitModel(triangle).h

    # H_saturated <= H_triangle <= H_independence
    check hSat <= hTriangle + 1e-6
    check hTriangle <= hIndep + 1e-6


suite "Fit - Residuals":
  test "residuals sum to approximately zero":
    let (varList, inputTable) = setupTestData()
    var mgr = initVBManager(varList, inputTable)

    let model = mgr.makeModel("AB:BC")
    let residuals = mgr.computeResiduals(model)

    var totalResidual = 0.0
    for tup in residuals:
      totalResidual += tup.value

    check abs(totalResidual) < 1e-6

  test "saturated model has zero residuals":
    let (varList, inputTable) = setupTestData()
    var mgr = initVBManager(varList, inputTable)

    let model = mgr.makeModel("ABC")
    let residuals = mgr.computeResiduals(model)

    var maxResidual = 0.0
    for tup in residuals:
      if abs(tup.value) > maxResidual:
        maxResidual = abs(tup.value)

    check maxResidual < 1e-10


suite "Fit - Statistics":
  test "LR is non-negative":
    let (varList, inputTable) = setupTestData()
    var mgr = initVBManager(varList, inputTable)

    let model = mgr.makeModel("AB:BC")
    let fitResult = mgr.fitModel(model)

    check fitResult.lr >= -1e-10  # Allow tiny numerical errors

  test "AIC and BIC are computed":
    let (varList, inputTable) = setupTestData()
    var mgr = initVBManager(varList, inputTable)

    let model = mgr.makeModel("AB:BC")
    let fitResult = mgr.fitModel(model)

    # AIC = LR - 2*DF
    check abs(fitResult.aic - (fitResult.lr - 2.0 * float64(fitResult.df))) < 1e-6

  test "alpha is between 0 and 1":
    let (varList, inputTable) = setupTestData()
    var mgr = initVBManager(varList, inputTable)

    let model = mgr.makeModel("AB:BC")
    let fitResult = mgr.fitModel(model)

    check fitResult.alpha >= 0.0
    check fitResult.alpha <= 1.0

  test "transmission equals H_data - H_model":
    let (varList, inputTable) = setupTestData()
    var mgr = initVBManager(varList, inputTable)

    let model = mgr.makeModel("AB:BC")
    let fitResult = mgr.fitModel(model)

    var normalizedInput = inputTable
    normalizedInput.normalize()
    let hData = entropy(normalizedInput)

    let expectedT = hData - fitResult.h
    check abs(fitResult.t - expectedT) < 1e-10


suite "Fit - Directed System":
  test "directed system fit":
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("Z", "Z", Cardinality(2), isDependent = true))

    var inputTable = initContingencyTable(varList.keySize)
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0), (VariableIndex(2), 0)]), 30.0)
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0), (VariableIndex(2), 1)]), 10.0)
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 1), (VariableIndex(2), 0)]), 20.0)
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 1), (VariableIndex(2), 1)]), 20.0)
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 0), (VariableIndex(2), 0)]), 15.0)
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 0), (VariableIndex(2), 1)]), 25.0)
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1), (VariableIndex(2), 0)]), 10.0)
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1), (VariableIndex(2), 1)]), 20.0)
    inputTable.sort()

    var mgr = initVBManager(varList, inputTable)

    # Fit a model where A predicts Z
    let model = mgr.makeModel("B:AZ")
    let fitResult = mgr.fitModel(model)

    check not fitResult.hasLoops
    check fitResult.df > 0


suite "Fit - Model Comparison":
  test "simpler models have higher entropy":
    let (varList, inputTable) = setupTestData()
    var mgr = initVBManager(varList, inputTable)

    let sat = mgr.fitModel(mgr.makeModel("ABC"))
    let chain = mgr.fitModel(mgr.makeModel("AB:BC"))
    let indep = mgr.fitModel(mgr.makeModel("A:B:C"))

    check sat.h <= chain.h + 1e-6
    check chain.h <= indep.h + 1e-6

  test "simpler models have higher LR":
    let (varList, inputTable) = setupTestData()
    var mgr = initVBManager(varList, inputTable)

    let sat = mgr.fitModel(mgr.makeModel("ABC"))
    let chain = mgr.fitModel(mgr.makeModel("AB:BC"))
    let indep = mgr.fitModel(mgr.makeModel("A:B:C"))

    check sat.lr <= chain.lr + 1e-6
    check chain.lr <= indep.lr + 1e-6
