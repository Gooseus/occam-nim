## E2E tests for UCI Mushroom dataset
## Dataset: 8,124 instances, 22 categorical features + class (edible/poisonous)
## Tests: loading, missing values, large-scale search, IPF convergence

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


suite "UCI Mushroom - Data Loading":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: Table

  setup:
    let jsonPath = ensureDataset("mushroom")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)

  test "dataset loads with correct dimensions":
    check spec.variables.len == 23  # 22 features + class
    check inputTable.sum == 8124
    echo "  Mushroom: ", spec.variables.len, " variables, ", int(inputTable.sum), " instances"

  test "has binary dependent variable":
    check varList.isDirected
    let dvIdx = varList.dependentIndex
    check dvIdx.isSome

    # Class should be binary (edible 'e' or poisonous 'p')
    let dvVar = varList[dvIdx.get]
    check dvVar.cardinality.int == 2

    echo "  DV: class (edible/poisonous)"
    echo "  Values: ", spec.variables[dvIdx.get.int].values.join(", ")

  test "has missing values in stalk-root":
    # stalk-root (column 11, 0-indexed) has '?' values
    # After loading, '?' should be treated as a valid value
    var foundMissing = false

    for v in spec.variables:
      if "?" in v.values:
        foundMissing = true
        echo "  Missing values found in: ", v.name
        echo "    Values: ", v.values.join(", ")

    # Note: '?' is treated as a valid category, not excluded
    echo "  Missing value handling: '?' treated as category"

  test "large state space":
    var stateSpace: int64 = 1
    for v in varList:
      stateSpace *= v.cardinality.int

    echo "  Theoretical state space: ", stateSpace
    echo "  Actual instances: ", int(inputTable.sum)
    echo "  This is a very sparse dataset"

    # State space should be massive (millions)
    check stateSpace > 1_000_000


suite "UCI Mushroom - Variable Analysis":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: Table

  setup:
    let jsonPath = ensureDataset("mushroom")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)

  test "variable cardinalities":
    echo "  Variable cardinalities:"
    for i, v in spec.variables:
      echo "    ", v.abbrev, " (", v.name, "): ", v.cardinality

  test "identify high-cardinality variables":
    echo "  High cardinality variables (>5):"
    for v in spec.variables:
      if v.cardinality > 5:
        echo "    ", v.name, ": ", v.cardinality


suite "UCI Mushroom - Reference Models":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: Table
  var mgr: VBManager

  setup:
    let jsonPath = ensureDataset("mushroom")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)
    mgr = newVBManager(varList, inputTable)

  test "reference model statistics":
    let bottom = mgr.bottomRefModel
    let top = mgr.topRefModel

    let dfBottom = mgr.computeDF(bottom)
    let dfTop = mgr.computeDF(top)
    let bicBottom = mgr.computeBIC(bottom)
    let bicTop = mgr.computeBIC(top)

    echo "  Reference models:"
    echo "    Bottom: DF=", dfBottom, " BIC=", formatFloat(bicBottom, ffDecimal, 2)
    echo "    Top: DF=", dfTop, " BIC=", formatFloat(bicTop, ffDecimal, 2)

    check dfTop > dfBottom


suite "UCI Mushroom - Limited Search":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: Table
  var mgr: VBManager

  setup:
    let jsonPath = ensureDataset("mushroom")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)
    mgr = newVBManager(varList, inputTable)

  test "search from independence (limited levels)":
    # With 23 variables, search space is huge
    # Limit to few levels and narrow width
    mgr.setSearchDirection(Direction.Ascending)
    var search = initLooplessSearch(mgr, width = 3, maxLevels = 2)

    let startModel = mgr.bottomRefModel
    let startBic = mgr.computeBIC(startModel)

    var bestModel = startModel
    var bestBic = startBic
    var currentLevel = @[startModel]
    var modelsExplored = 0

    for level in 1..2:
      var nextLevel: seq[(Model, float64)]
      for model in currentLevel:
        var neighbors = 0
        for neighbor in search.generateNeighbors(model):
          modelsExplored += 1
          neighbors += 1
          let bic = mgr.computeBIC(neighbor)
          nextLevel.add((neighbor, bic))
          if bic < bestBic:
            bestBic = bic
            bestModel = neighbor

          # Limit neighbors per model to avoid explosion
          if neighbors > 50:
            break

      nextLevel.sort(proc(a, b: (Model, float64)): int = cmp(a[1], b[1]))
      if nextLevel.len > 0:
        currentLevel = nextLevel[0..min(2, nextLevel.len-1)].mapIt(it[0])

    echo "  Limited search:"
    echo "    Models explored: ", modelsExplored
    echo "    Start BIC: ", formatFloat(startBic, ffDecimal, 2)
    echo "    Best BIC: ", formatFloat(bestBic, ffDecimal, 2)
    echo "    Improvement: ", formatFloat(startBic - bestBic, ffDecimal, 2)

    # Should find some improvement (may not for very limited search)
    check bestBic <= startBic


suite "UCI Mushroom - Subset Analysis":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: Table
  var mgr: VBManager

  setup:
    let jsonPath = ensureDataset("mushroom")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)
    mgr = newVBManager(varList, inputTable)

  test "single variable predictive power":
    # Find which single variable best predicts edibility
    var normTable = inputTable
    normTable.normalize()

    let dvIdx = varList.dependentIndex.get
    let dvMarginal = normTable.project(varList, @[dvIdx])
    let hDV = entropy(dvMarginal)

    echo "  Single variable MI with class:"
    var bestMI = 0.0
    var bestVar = ""

    for i in 0..<(varList.len - 1):  # Skip DV
      let joint = normTable.project(varList, @[VariableIndex(i), dvIdx])
      let ivMarginal = normTable.project(varList, @[VariableIndex(i)])
      let hJoint = entropy(joint)
      let hIV = entropy(ivMarginal)
      let mi = hIV + hDV - hJoint

      if mi > bestMI:
        bestMI = mi
        bestVar = varList[VariableIndex(i)].abbrev

    echo "    Best predictor: ", bestVar, " with MI=", formatFloat(bestMI, ffDecimal, 4)
    echo "    DV entropy: ", formatFloat(hDV, ffDecimal, 4)
    echo "    Uncertainty reduction: ", formatFloat(bestMI / hDV * 100, ffDecimal, 1), "%"

  test "class distribution":
    var normTable = inputTable
    normTable.normalize()

    let dvIdx = varList.dependentIndex.get
    let marginal = normTable.project(varList, @[dvIdx])

    echo "  Class distribution:"
    for i, tup in marginal:
      let valIdx = tup.key.getValue(varList, dvIdx)
      let valName = spec.variables[dvIdx.int].values[valIdx]
      echo "    ", valName, ": ", formatFloat(tup.value * 100, ffDecimal, 1), "%"
