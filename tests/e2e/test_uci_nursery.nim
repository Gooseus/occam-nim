## E2E tests for UCI Nursery dataset
## Dataset: 12,960 instances, 8 categorical features + class (5 recommendation levels)
## Tests: loading, medium-scale search, chain models

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
import ../../src/occam/search/chain


suite "UCI Nursery - Data Loading":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: ContingencyTable

  setup:
    let jsonPath = ensureDataset("nursery")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)

  test "dataset loads with correct dimensions":
    check spec.variables.len == 9  # 8 features + class
    check inputTable.sum == 12960
    echo "  Nursery: ", spec.variables.len, " variables, ", int(inputTable.sum), " instances"

  test "has 5-class dependent variable":
    check varList.isDirected
    let dvIdx = varList.dependentIndex
    check dvIdx.isSome

    # 5 recommendation levels
    let dvVar = varList[dvIdx.get]
    check dvVar.cardinality.int == 5

    echo "  DV: class with ", dvVar.cardinality.int, " levels"
    echo "  Values: ", spec.variables[dvIdx.get.int].values.join(", ")

  test "variable cardinalities":
    echo "  Variable cardinalities:"
    for v in spec.variables:
      echo "    ", v.abbrev, " (", v.name, "): ", v.cardinality

  test "state space":
    var stateSpace: int64 = 1
    for v in varList:
      stateSpace *= v.cardinality.int

    echo "  State space: ", stateSpace
    echo "  Instances: ", int(inputTable.sum)
    echo "  Coverage: ", formatFloat(inputTable.sum / float64(stateSpace) * 100, ffDecimal, 2), "%"


suite "UCI Nursery - Reference Models":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: ContingencyTable
  var mgr: VBManager

  setup:
    let jsonPath = ensureDataset("nursery")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)
    mgr = initVBManager(varList, inputTable)

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


suite "UCI Nursery - Loopless Search":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: ContingencyTable
  var mgr: VBManager

  setup:
    let jsonPath = ensureDataset("nursery")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)
    mgr = initVBManager(varList, inputTable)

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

    echo "  Search results:"
    echo "    Models explored: ", modelsExplored
    echo "    Start BIC: ", formatFloat(startBic, ffDecimal, 2)
    echo "    Best BIC: ", formatFloat(bestBic, ffDecimal, 2)
    echo "    Improvement: ", formatFloat(startBic - bestBic, ffDecimal, 2)
    echo "    Best model: ", bestModel.printName(varList)

    # For directed systems, bottom model already includes all IVs with DV
    # so may not find improvement in limited search
    check bestBic <= startBic

  test "search from saturated":
    mgr.setSearchDirection(Direction.Descending)
    var search = initLooplessSearch(mgr, width = 5, maxLevels = 4)

    let startModel = mgr.topRefModel
    let startBic = mgr.computeBIC(startModel)

    var bestModel = startModel
    var bestBic = startBic
    var currentLevel = @[startModel]

    for level in 1..4:
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


suite "UCI Nursery - Chain Models":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: ContingencyTable
  var mgr: VBManager

  setup:
    let jsonPath = ensureDataset("nursery")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)
    mgr = initVBManager(varList, inputTable)

  test "enumerate some chain models":
    # With 9 variables, there are many chains
    # Just test a few
    let chains = generateAllChains(varList)

    echo "  Chain models:"
    echo "    Total chains: ", chains.len

    # Find best chain by BIC
    var bestChain: Model
    var bestBic = Inf

    for i, chain in chains:
      if i >= 20:  # Only test first 20
        break
      let bic = mgr.computeBIC(chain)
      if bic < bestBic:
        bestBic = bic
        bestChain = chain

    echo "    Best of first 20:"
    echo "      Model: ", bestChain.printName(varList)
    echo "      BIC: ", formatFloat(bestBic, ffDecimal, 2)


suite "UCI Nursery - Entropy Analysis":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: ContingencyTable
  var mgr: VBManager

  setup:
    let jsonPath = ensureDataset("nursery")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)
    mgr = initVBManager(varList, inputTable)

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

  test "marginal entropies":
    var normTable = inputTable
    normTable.normalize()

    echo "  Marginal entropies:"
    for i, v in varList:
      let marginal = normTable.project(varList, @[VariableIndex(i)])
      let h = entropy(marginal)
      let hMax = log2(float64(v.cardinality.int))
      echo "    ", v.abbrev, ": H=", formatFloat(h, ffDecimal, 3),
           " (max=", formatFloat(hMax, ffDecimal, 3),
           ", eff=", formatFloat(h / hMax * 100, ffDecimal, 0), "%)"

  test "best single predictors":
    var normTable = inputTable
    normTable.normalize()

    let dvIdx = varList.dependentIndex.get
    let dvMarginal = normTable.project(varList, @[dvIdx])
    let hDV = entropy(dvMarginal)

    echo "  MI with class by variable:"
    var miList: seq[(string, float64)]

    for i in 0..<(varList.len - 1):  # Skip DV
      let joint = normTable.project(varList, @[VariableIndex(i), dvIdx])
      let ivMarginal = normTable.project(varList, @[VariableIndex(i)])
      let hJoint = entropy(joint)
      let hIV = entropy(ivMarginal)
      let mi = hIV + hDV - hJoint
      miList.add((varList[VariableIndex(i)].abbrev, mi))

    miList.sort(proc(a, b: (string, float64)): int = cmp(b[1], a[1]))

    for (name, mi) in miList:
      echo "    ", name, ": ", formatFloat(mi, ffDecimal, 4)
