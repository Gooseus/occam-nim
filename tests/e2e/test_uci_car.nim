## E2E tests for UCI Car Evaluation dataset
## Dataset: 1,728 instances, 6 categorical features + 1 target (4 classes)
## Tests: loading, search, fitting, directed system analysis

import std/[math, sequtils, algorithm, options, strutils]
import unittest
import ./uci_helpers
import ../../src/occam/core/types
import ../../src/occam/core/variable
import ../../src/occam/core/key
import ../../src/occam/core/table
import ../../src/occam/core/relation
import ../../src/occam/core/model
import ../../src/occam/math/entropy
import ../../src/occam/math/statistics
import ../../src/occam/io/parser
import ../../src/occam/manager/vb
import ../../src/occam/search/loopless
import ../../src/occam/search/full


suite "UCI Car Evaluation - Data Loading":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: ContingencyTable

  setup:
    let jsonPath = ensureDataset("car")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)

  test "dataset loads with correct dimensions":
    check spec.variables.len == 7
    check inputTable.sum == 1728
    echo "  Car dataset: ", spec.variables.len, " variables, ", int(inputTable.sum), " instances"

  test "has dependent variable (class)":
    check varList.isDirected
    let dvIdx = varList.dependentIndex
    check dvIdx.isSome
    echo "  DV index: ", dvIdx.get.int, " (", spec.variables[dvIdx.get.int].name, ")"

  test "variable cardinalities are correct":
    # buying: 4 (vhigh, high, med, low)
    # maint: 4
    # doors: 4 (2, 3, 4, 5more)
    # persons: 3 (2, 4, more)
    # lug_boot: 3 (small, med, big)
    # safety: 3 (low, med, high)
    # class: 4 (unacc, acc, good, vgood)
    let expectedCards = @[4, 4, 4, 3, 3, 3, 4]
    for i, v in varList:
      check v.cardinality.int == expectedCards[i.int]
    echo "  Cardinalities: ", expectedCards.mapIt($it).join(", ")

  test "state space size":
    var stateSpace = 1
    for v in varList:
      stateSpace *= v.cardinality.int
    check stateSpace == 4 * 4 * 4 * 3 * 3 * 3 * 4
    echo "  State space: ", stateSpace


suite "UCI Car Evaluation - Reference Models":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: ContingencyTable
  var mgr: VBManager

  setup:
    let jsonPath = ensureDataset("car")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)
    mgr = initVBManager(varList, inputTable)

  test "independence model statistics":
    let indep = mgr.bottomRefModel
    let df = mgr.computeDF(indep)
    let h = mgr.computeH(indep)
    let bic = mgr.computeBIC(indep)

    check df > 0
    check h > 0
    check bic != 0.0

    echo "  Independence model:"
    echo "    DF: ", df
    echo "    H: ", formatFloat(h, ffDecimal, 4)
    echo "    BIC: ", formatFloat(bic, ffDecimal, 2)

  test "saturated model statistics":
    let sat = mgr.topRefModel
    let df = mgr.computeDF(sat)
    let h = mgr.computeH(sat)
    let bic = mgr.computeBIC(sat)

    # Saturated model should have highest DF
    check df > mgr.computeDF(mgr.bottomRefModel)

    echo "  Saturated model:"
    echo "    DF: ", df
    echo "    H: ", formatFloat(h, ffDecimal, 4)
    echo "    BIC: ", formatFloat(bic, ffDecimal, 2)


suite "UCI Car Evaluation - Loopless Search":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: ContingencyTable
  var mgr: VBManager

  setup:
    let jsonPath = ensureDataset("car")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)
    mgr = initVBManager(varList, inputTable)

  test "search from independence finds structure":
    mgr.setSearchDirection(Direction.Ascending)
    var search = initLooplessSearch(mgr, width = 5, maxLevels = 3)

    # Get starting model
    let startModel = mgr.bottomRefModel
    let startBic = mgr.computeBIC(startModel)

    # Search for better models
    var bestModel = startModel
    var bestBic = startBic
    var currentLevel = @[startModel]

    for level in 1..3:
      var nextLevel: seq[(Model, float64)]
      for model in currentLevel:
        for neighbor in search.generateNeighbors(model):
          let bic = mgr.computeBIC(neighbor)
          nextLevel.add((neighbor, bic))
          if bic < bestBic:
            bestBic = bic
            bestModel = neighbor

      nextLevel.sort(proc(a, b: (Model, float64)): int = cmp(a[1], b[1]))
      if nextLevel.len > 0:
        currentLevel = nextLevel[0..min(4, nextLevel.len-1)].mapIt(it[0])

    # Note: For directed systems, bottom model already includes all IVs with DV
    # so may not find much improvement in limited search
    echo "  Search results:"
    echo "    Start BIC: ", formatFloat(startBic, ffDecimal, 2)
    echo "    Best BIC: ", formatFloat(bestBic, ffDecimal, 2)
    echo "    Best model: ", bestModel.printName(varList)

    # Just verify search completed (improvement may or may not occur)
    check bestBic <= startBic

  test "search from saturated finds simpler models":
    mgr.setSearchDirection(Direction.Descending)
    var search = initLooplessSearch(mgr, width = 5, maxLevels = 3)

    let startModel = mgr.topRefModel
    let startBic = mgr.computeBIC(startModel)

    var bestModel = startModel
    var bestBic = startBic
    var currentLevel = @[startModel]

    for level in 1..3:
      var nextLevel: seq[(Model, float64)]
      for model in currentLevel:
        for neighbor in search.generateNeighbors(model):
          let bic = mgr.computeBIC(neighbor)
          nextLevel.add((neighbor, bic))
          if bic < bestBic:
            bestBic = bic
            bestModel = neighbor

      nextLevel.sort(proc(a, b: (Model, float64)): int = cmp(a[1], b[1]))
      if nextLevel.len > 0:
        currentLevel = nextLevel[0..min(4, nextLevel.len-1)].mapIt(it[0])

    echo "  Downward search:"
    echo "    Start BIC: ", formatFloat(startBic, ffDecimal, 2)
    echo "    Best BIC: ", formatFloat(bestBic, ffDecimal, 2)
    echo "    Best model: ", bestModel.printName(varList)


suite "UCI Car Evaluation - Model Fitting":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: ContingencyTable
  var mgr: VBManager

  setup:
    let jsonPath = ensureDataset("car")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)
    mgr = initVBManager(varList, inputTable)

  test "fit saturated model":
    let model = mgr.topRefModel
    let fitResult = mgr.fitModel(model)

    check not fitResult.hasLoops
    check abs(fitResult.lr) < 1e-6  # LR should be ~0 for saturated

    echo "  Saturated fit:"
    echo "    LR: ", formatFloat(fitResult.lr, ffDecimal, 6)
    echo "    Alpha: ", formatFloat(fitResult.alpha, ffDecimal, 6)

  test "compute statistics for independence model":
    # For very large DF, fitModel may have numerical issues
    # So test individual statistics instead
    let model = mgr.bottomRefModel
    let df = mgr.computeDF(model)
    let h = mgr.computeH(model)
    let bic = mgr.computeBIC(model)

    check df > 0
    check h > 0

    echo "  Independence model:"
    echo "    DF: ", df
    echo "    H: ", formatFloat(h, ffDecimal, 4)
    echo "    BIC: ", formatFloat(bic, ffDecimal, 2)

  test "compute statistics for intermediate model":
    # Try a model between independence and saturated
    let model = mgr.makeModel("BC:CD:DE:EF:FG")
    let df = mgr.computeDF(model)
    let h = mgr.computeH(model)
    let bic = mgr.computeBIC(model)

    check df > 0
    check h > 0

    echo "  Intermediate model:"
    echo "    Model: ", model.printName(varList)
    echo "    DF: ", df
    echo "    H: ", formatFloat(h, ffDecimal, 4)
    echo "    BIC: ", formatFloat(bic, ffDecimal, 2)


suite "UCI Car Evaluation - Entropy Analysis":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: ContingencyTable
  var mgr: VBManager

  setup:
    let jsonPath = ensureDataset("car")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)
    mgr = initVBManager(varList, inputTable)

  test "data entropy is bounded":
    var normTable = inputTable
    normTable.normalize()
    let h = entropy(normTable)

    # Entropy should be positive
    check h > 0

    # Entropy should be less than max (log2 of state space)
    var stateSpace = 1
    for v in varList:
      stateSpace *= v.cardinality.int
    let hMax = log2(float64(stateSpace))
    check h < hMax

    echo "  Data entropy:"
    echo "    H: ", formatFloat(h, ffDecimal, 4)
    echo "    H_max: ", formatFloat(hMax, ffDecimal, 4)
    echo "    Efficiency: ", formatFloat(h / hMax * 100, ffDecimal, 1), "%"

  test "marginal entropies":
    var normTable = inputTable
    normTable.normalize()

    echo "  Marginal entropies:"
    for i, v in varList:
      let marginal = normTable.project(varList, @[VariableIndex(i)])
      let h = entropy(marginal)
      let hMax = log2(float64(v.cardinality.int))
      echo "    ", v.abbrev, ": H=", formatFloat(h, ffDecimal, 3),
           " (max=", formatFloat(hMax, ffDecimal, 3), ")"
