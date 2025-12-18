## E2E tests for UCI Zoo dataset
## Dataset: 101 instances, 16 binary features + legs (int) + type (7 classes)
## Tests: loading, binary variables, small-scale lattice, full search

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
import ../../src/occam/search/lattice


suite "UCI Zoo - Data Loading":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: Table

  setup:
    let jsonPath = ensureDataset("zoo")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)

  test "dataset loads with correct dimensions":
    # 17 features after dropping name column
    check spec.variables.len == 17
    check inputTable.sum == 101
    echo "  Zoo: ", spec.variables.len, " variables, ", int(inputTable.sum), " instances"

  test "has 7-class dependent variable":
    check varList.isDirected
    let dvIdx = varList.dependentIndex
    check dvIdx.isSome

    # 7 animal types
    let dvVar = varList[dvIdx.get]
    check dvVar.cardinality.int == 7

    echo "  DV: type with ", dvVar.cardinality.int, " classes"

  test "most variables are binary":
    var binaryCount = 0
    for i, v in varList:
      if v.cardinality.int == 2:
        binaryCount += 1

    # Most features should be binary (0/1)
    echo "  Binary variables: ", binaryCount, " of ", varList.len
    check binaryCount >= 14  # At least 14 of 17 should be binary


suite "UCI Zoo - Reference Models":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: Table
  var mgr: VBManager

  setup:
    let jsonPath = ensureDataset("zoo")
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


suite "UCI Zoo - Loopless Search":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: Table
  var mgr: VBManager

  setup:
    let jsonPath = ensureDataset("zoo")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)
    mgr = newVBManager(varList, inputTable)

  test "search from independence":
    mgr.setSearchDirection(Direction.Ascending)
    var search = initLooplessSearch(mgr, width = 5, maxLevels = 4)

    let startModel = mgr.bottomRefModel
    let startBic = mgr.computeBIC(startModel)

    var bestModel = startModel
    var bestBic = startBic
    var currentLevel = @[startModel]
    var modelsExplored = 0

    for level in 1..4:
      var nextLevel: seq[(Model, float64)]
      for model in currentLevel:
        for neighbor in search.generateNeighbors(model):
          modelsExplored += 1
          let bic = mgr.computeBIC(neighbor)
          nextLevel.add((neighbor, bic))
          if bic < bestBic:
            bestBic = bic
            bestModel = neighbor

      nextLevel.sort(proc(a, b: (Model, float64)): int = cmp(a[1], b[1]))
      if nextLevel.len > 0:
        currentLevel = nextLevel[0..min(4, nextLevel.len-1)].mapIt(it[0])

    echo "  Loopless search:"
    echo "    Models explored: ", modelsExplored
    echo "    Start BIC: ", formatFloat(startBic, ffDecimal, 2)
    echo "    Best BIC: ", formatFloat(bestBic, ffDecimal, 2)
    echo "    Best model: ", bestModel.printName(varList)


suite "UCI Zoo - Full Search (with loops)":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: Table
  var mgr: VBManager

  setup:
    let jsonPath = ensureDataset("zoo")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)
    mgr = newVBManager(varList, inputTable)

  test "full search allows more models":
    mgr.setSearchDirection(Direction.Ascending)
    var looplessSearch = initLooplessSearch(mgr, width = 5, maxLevels = 2)
    var fullSearch = initFullSearch(mgr, width = 5, maxLevels = 2)

    let startModel = mgr.bottomRefModel

    # Count neighbors from loopless vs full
    var looplessNeighbors = 0
    var fullNeighbors = 0

    for _ in looplessSearch.generateNeighbors(startModel):
      looplessNeighbors += 1

    for _ in fullSearch.generateNeighbors(startModel):
      fullNeighbors += 1

    echo "  Neighbors from bottom:"
    echo "    Loopless: ", looplessNeighbors
    echo "    Full: ", fullNeighbors

    # Full search should have at least as many neighbors
    check fullNeighbors >= looplessNeighbors


suite "UCI Zoo - Model Fitting":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: Table
  var mgr: VBManager

  setup:
    let jsonPath = ensureDataset("zoo")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)
    mgr = newVBManager(varList, inputTable)

  test "compute statistics for independence model":
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

  test "compute statistics for saturated model":
    let model = mgr.topRefModel
    let df = mgr.computeDF(model)
    let h = mgr.computeH(model)
    let bic = mgr.computeBIC(model)

    check df > 0

    echo "  Saturated model:"
    echo "    DF: ", df
    echo "    H: ", formatFloat(h, ffDecimal, 4)
    echo "    BIC: ", formatFloat(bic, ffDecimal, 2)


suite "UCI Zoo - Entropy Analysis":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: Table
  var mgr: VBManager

  setup:
    let jsonPath = ensureDataset("zoo")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)
    mgr = newVBManager(varList, inputTable)

  test "binary variable entropies":
    var normTable = inputTable
    normTable.normalize()

    echo "  Binary variable entropies (max=1.0 for binary):"
    for i, v in varList:
      if v.cardinality.int == 2:
        let marginal = normTable.project(varList, @[VariableIndex(i)])
        let h = entropy(marginal)
        # For binary, entropy close to 1.0 means 50-50 split
        # Entropy close to 0 means one value dominates
        echo "    ", v.abbrev, ": ", formatFloat(h, ffDecimal, 3)

  test "type (DV) entropy":
    var normTable = inputTable
    normTable.normalize()

    let dvIdx = varList.dependentIndex.get
    let marginal = normTable.project(varList, @[dvIdx])
    let h = entropy(marginal)
    let hMax = log2(7.0)  # 7 classes

    echo "  Type (DV) entropy:"
    echo "    H: ", formatFloat(h, ffDecimal, 4)
    echo "    H_max: ", formatFloat(hMax, ffDecimal, 4)
    echo "    Efficiency: ", formatFloat(h / hMax * 100, ffDecimal, 1), "%"

    check h > 0
    check h <= hMax
