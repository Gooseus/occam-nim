## E2E tests for UCI Tic-Tac-Toe Endgame dataset
## Dataset: 958 instances, 9 board positions (x/o/b) + 1 binary target
## Tests: loading, search, directed system prediction

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


suite "UCI Tic-Tac-Toe - Data Loading":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: Table

  setup:
    let jsonPath = ensureDataset("tictactoe")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)

  test "dataset loads with correct dimensions":
    check spec.variables.len == 10  # 9 positions + class
    check inputTable.sum == 958
    echo "  Tic-Tac-Toe: ", spec.variables.len, " variables, ", int(inputTable.sum), " instances"

  test "has binary dependent variable":
    check varList.isDirected
    let dvIdx = varList.dependentIndex
    check dvIdx.isSome

    # DV should have 2 values (positive/negative)
    let dvVar = varList[dvIdx.get]
    check dvVar.cardinality.int == 2

    echo "  DV: ", spec.variables[dvIdx.get.int].name
    echo "  Values: ", spec.variables[dvIdx.get.int].values.join(", ")

  test "all position variables have 3 values":
    # Each position can be: x, o, or b (blank)
    for i in 0..<9:
      check varList[VariableIndex(i)].cardinality.int == 3

    echo "  Position cardinalities: all 3 (x, o, b)"

  test "state space vs actual data":
    # Full state space would be 3^9 * 2 = 39366
    # But only 958 are valid endgame states
    var fullStateSpace = 1
    for v in varList:
      fullStateSpace *= v.cardinality.int

    let coverage = inputTable.sum / float64(fullStateSpace) * 100

    echo "  Full state space: ", fullStateSpace
    echo "  Actual instances: ", int(inputTable.sum)
    echo "  Coverage: ", formatFloat(coverage, ffDecimal, 2), "%"

    # Coverage should be low (only valid endgame states)
    check coverage < 5.0


suite "UCI Tic-Tac-Toe - Reference Models":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: Table
  var mgr: VBManager

  setup:
    let jsonPath = ensureDataset("tictactoe")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)
    mgr = newVBManager(varList, inputTable)

  test "directed reference models":
    # For directed system, bottom should be IVZ model (all IVs independent, each with DV)
    let bottom = mgr.bottomRefModel
    let top = mgr.topRefModel

    let dfBottom = mgr.computeDF(bottom)
    let dfTop = mgr.computeDF(top)

    check dfTop > dfBottom

    echo "  Bottom model: ", bottom.printName(varList)
    echo "    DF: ", dfBottom
    echo "  Top model: ", top.printName(varList)
    echo "    DF: ", dfTop

  test "BIC comparison":
    let bottom = mgr.bottomRefModel
    let top = mgr.topRefModel

    let bicBottom = mgr.computeBIC(bottom)
    let bicTop = mgr.computeBIC(top)

    echo "  BIC comparison:"
    echo "    Bottom: ", formatFloat(bicBottom, ffDecimal, 2)
    echo "    Top: ", formatFloat(bicTop, ffDecimal, 2)


suite "UCI Tic-Tac-Toe - Directed Search":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: Table
  var mgr: VBManager

  setup:
    let jsonPath = ensureDataset("tictactoe")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)
    mgr = newVBManager(varList, inputTable)

  test "search finds predictive structure":
    mgr.setSearchDirection(Direction.Ascending)
    var search = initLooplessSearch(mgr, width = 5, maxLevels = 3)

    let startModel = mgr.bottomRefModel
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

    echo "  Search results:"
    echo "    Start BIC: ", formatFloat(startBic, ffDecimal, 2)
    echo "    Best BIC: ", formatFloat(bestBic, ffDecimal, 2)
    echo "    Improvement: ", formatFloat(startBic - bestBic, ffDecimal, 2)
    echo "    Best model: ", bestModel.printName(varList)


suite "UCI Tic-Tac-Toe - Symmetry Analysis":
  var spec: DataSpec
  var varList: VariableList
  var inputTable: Table
  var mgr: VBManager

  setup:
    let jsonPath = ensureDataset("tictactoe")
    spec = loadDataSpec(jsonPath)
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)
    mgr = newVBManager(varList, inputTable)

  test "marginal entropies of positions":
    # Due to game symmetry, corner positions should have similar entropy
    # Center position might be different
    var normTable = inputTable
    normTable.normalize()

    var entropies: seq[(string, float64)]
    for i in 0..<9:
      let marginal = normTable.project(varList, @[VariableIndex(i)])
      let h = entropy(marginal)
      entropies.add((varList[VariableIndex(i)].abbrev, h))

    echo "  Position entropies:"
    for (name, h) in entropies:
      echo "    ", name, ": ", formatFloat(h, ffDecimal, 4)

    # Center (position 4, index E) often has different stats
    # Corners (A, C, G, I) and edges (B, D, F, H) may show patterns

  test "transmission with target by position":
    # Measure how much each position tells us about the outcome
    var normTable = inputTable
    normTable.normalize()

    let dvIdx = varList.dependentIndex.get
    let dvMarginal = normTable.project(varList, @[dvIdx])
    let hDV = entropy(dvMarginal)

    echo "  Transmission (MI with DV) by position:"
    var transmissions: seq[(string, float64)]

    for i in 0..<9:
      let joint = normTable.project(varList, @[VariableIndex(i), dvIdx])
      let ivMarginal = normTable.project(varList, @[VariableIndex(i)])
      let hJoint = entropy(joint)
      let hIV = entropy(ivMarginal)
      let mi = hIV + hDV - hJoint  # Mutual information

      transmissions.add((varList[VariableIndex(i)].abbrev, mi))
      echo "    ", varList[VariableIndex(i)].abbrev, ": ", formatFloat(mi, ffDecimal, 4)

    # Center position should have high predictive value
