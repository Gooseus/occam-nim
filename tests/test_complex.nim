## Complex integration tests for OCCAM
## Tests with more variables and mixed cardinalities

import std/[random, math, algorithm, strformat, sequtils, strutils]
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/math/entropy
import ../src/occam/math/statistics
import ../src/occam/io/synthetic
import ../src/occam/manager/vb
import ../src/occam/search/loopless

randomize(54321)


proc createCustomChainModel(varList: VariableList; strength: float64): GraphicalModel =
  ## Create a chain model A→B→C→D→... with given transition strength
  result = initGraphicalModel(varList)

  # First variable is uniform
  let card0 = varList[VariableIndex(0)].cardinality.toInt
  result.setConditional(VariableIndex(0), @[], newSeqWith(card0, 1.0 / float64(card0)))

  # Each subsequent variable depends on previous
  for i in 1..<varList.len:
    result.setParents(VariableIndex(i), @[VariableIndex(i-1)])

    let parentCard = varList[VariableIndex(i-1)].cardinality.toInt
    let childCard = varList[VariableIndex(i)].cardinality.toInt

    for p in 0..<parentCard:
      var dist = newSeq[float64](childCard)
      for c in 0..<childCard:
        if c == p mod childCard:
          dist[c] = strength
        else:
          dist[c] = (1.0 - strength) / float64(childCard - 1)
      result.setConditional(VariableIndex(i), @[p], dist)


proc findBestModelByBIC(mgr: var VBManager; search: LooplessSearch;
                        levels: int = 5; width: int = 5): Model =
  ## Run search and return best model by BIC
  var currentLevel = @[if mgr.searchDirection == Direction.Ascending:
                         mgr.bottomRefModel
                       else:
                         mgr.topRefModel]
  var bestModel = currentLevel[0]
  var bestBic = mgr.computeBIC(bestModel)

  for level in 1..levels:
    if currentLevel.len == 0:
      break

    var nextLevel: seq[(Model, float64)]
    for model in currentLevel:
      for neighbor in search.generateNeighbors(model):
        let bic = mgr.computeBIC(neighbor)
        nextLevel.add((neighbor, bic))
        if bic < bestBic:
          bestBic = bic
          bestModel = neighbor

    nextLevel.sort(proc(a, b: (Model, float64)): int = cmp(a[1], b[1]))
    let kept = min(width, nextLevel.len)
    currentLevel = @[]
    for i in 0..<kept:
      currentLevel.add(nextLevel[i][0])

  bestModel


suite "Four variables - uniform cardinality":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    discard varList.add(newVariable("D", "D", Cardinality(2)))

  test "state space is correct":
    check varList.stateSpace == 16  # 2^4

  test "independence model structure":
    var table = initTable(varList.keySize, 16)
    for i in 0..<16:
      var k = newKey(varList.keySize)
      k.setValue(varList, VariableIndex(0), i and 1)
      k.setValue(varList, VariableIndex(1), (i shr 1) and 1)
      k.setValue(varList, VariableIndex(2), (i shr 2) and 1)
      k.setValue(varList, VariableIndex(3), (i shr 3) and 1)
      table.add(k, 10.0)
    table.sort()

    var mgr = newVBManager(varList, table)

    # Check reference models
    check mgr.bottomRefModel.relationCount == 4  # A:B:C:D
    check mgr.topRefModel.relationCount == 1     # ABCD

    echo "  4-var state space: ", varList.stateSpace
    echo "  Independence DF: ", mgr.computeDF(mgr.bottomRefModel)
    echo "  Saturated DF: ", mgr.computeDF(mgr.topRefModel)

  test "chain model A→B→C→D recovery":
    randomize(111)
    let graphModel = createCustomChainModel(varList, 0.9)
    let samples = graphModel.generateSamples(3000)
    var table = graphModel.samplesToTable(samples)

    var mgr = newVBManager(varList, table)

    # Compare models
    let bicIndep = mgr.computeBIC(mgr.makeModel("A:B:C:D"))
    let bicAB_CD = mgr.computeBIC(mgr.makeModel("AB:CD"))
    let bicAB_BC_CD = mgr.computeBIC(mgr.makeModel("AB:BC:CD"))  # True chain
    let bicSat = mgr.computeBIC(mgr.makeModel("ABCD"))

    echo "  4-var chain BIC comparison:"
    echo "    A:B:C:D (indep): ", formatFloat(bicIndep, ffDecimal, 2)
    echo "    AB:CD: ", formatFloat(bicAB_CD, ffDecimal, 2)
    echo "    AB:BC:CD (true): ", formatFloat(bicAB_BC_CD, ffDecimal, 2)
    echo "    ABCD (sat): ", formatFloat(bicSat, ffDecimal, 2)

    # True model should have better BIC than independence
    check bicAB_BC_CD < bicIndep

  test "search explores 4-variable space":
    randomize(222)
    let graphModel = createCustomChainModel(varList, 0.85)
    let samples = graphModel.generateSamples(2000)
    var table = graphModel.samplesToTable(samples)

    var mgr = newVBManager(varList, table)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initLooplessSearch(mgr, width = 10)

    let best = findBestModelByBIC(mgr, search, levels = 6)
    echo "  4-var search best: ", best.printName(varList)
    echo "    BIC: ", formatFloat(mgr.computeBIC(best), ffDecimal, 2)

    check best.relationCount >= 1


suite "Four variables - mixed cardinality":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))  # Binary
    discard varList.add(newVariable("B", "B", Cardinality(3)))  # Ternary
    discard varList.add(newVariable("C", "C", Cardinality(2)))  # Binary
    discard varList.add(newVariable("D", "D", Cardinality(4)))  # Quaternary

  test "state space with mixed cardinality":
    check varList.stateSpace == 48  # 2*3*2*4

  test "DF calculations with mixed cardinality":
    # Create uniform data
    var table = initTable(varList.keySize, 48)
    for a in 0..<2:
      for b in 0..<3:
        for c in 0..<2:
          for d in 0..<4:
            var k = newKey(varList.keySize)
            k.setValue(varList, VariableIndex(0), a)
            k.setValue(varList, VariableIndex(1), b)
            k.setValue(varList, VariableIndex(2), c)
            k.setValue(varList, VariableIndex(3), d)
            table.add(k, 10.0)
    table.sort()

    var mgr = newVBManager(varList, table)

    # Independence model DF = (2-1) + (3-1) + (2-1) + (4-1) = 1+2+1+3 = 7
    let dfIndep = mgr.computeDF(mgr.bottomRefModel)
    check dfIndep == 7

    # Saturated model DF = 48 - 1 = 47
    let dfSat = mgr.computeDF(mgr.topRefModel)
    check dfSat == 47

    echo "  Mixed cardinality (2,3,2,4):"
    echo "    State space: ", varList.stateSpace
    echo "    Independence DF: ", dfIndep
    echo "    Saturated DF: ", dfSat

  test "chain with mixed cardinality":
    randomize(333)
    let graphModel = createCustomChainModel(varList, 0.85)
    let samples = graphModel.generateSamples(5000)
    var table = graphModel.samplesToTable(samples)

    var mgr = newVBManager(varList, table)

    let bicIndep = mgr.computeBIC(mgr.bottomRefModel)
    let bicChain = mgr.computeBIC(mgr.makeModel("AB:BC:CD"))
    let bicSat = mgr.computeBIC(mgr.topRefModel)

    echo "  Mixed card chain BIC:"
    echo "    Independence: ", formatFloat(bicIndep, ffDecimal, 2)
    echo "    AB:BC:CD: ", formatFloat(bicChain, ffDecimal, 2)
    echo "    Saturated: ", formatFloat(bicSat, ffDecimal, 2)

    check bicChain < bicIndep


suite "Five variables":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    discard varList.add(newVariable("D", "D", Cardinality(2)))
    discard varList.add(newVariable("E", "E", Cardinality(2)))

  test "state space for 5 binary variables":
    check varList.stateSpace == 32  # 2^5

  test "search in 5-variable space":
    randomize(444)
    let graphModel = createCustomChainModel(varList, 0.8)
    let samples = graphModel.generateSamples(5000)
    var table = graphModel.samplesToTable(samples)

    var mgr = newVBManager(varList, table)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initLooplessSearch(mgr, width = 10)

    echo "  5-var search:"
    echo "    Starting from: ", mgr.bottomRefModel.printName(varList)

    let best = findBestModelByBIC(mgr, search, levels = 7)
    echo "    Best found: ", best.printName(varList)
    echo "    BIC: ", formatFloat(mgr.computeBIC(best), ffDecimal, 2)

    check best.relationCount >= 1

  test "compare specific 5-var models":
    randomize(555)
    let graphModel = createCustomChainModel(varList, 0.85)
    let samples = graphModel.generateSamples(8000)
    var table = graphModel.samplesToTable(samples)

    var mgr = newVBManager(varList, table)

    let bicIndep = mgr.computeBIC(mgr.makeModel("A:B:C:D:E"))
    let bicChain = mgr.computeBIC(mgr.makeModel("AB:BC:CD:DE"))
    let bicSat = mgr.computeBIC(mgr.makeModel("ABCDE"))

    echo "  5-var model comparison:"
    echo "    A:B:C:D:E (indep): ", formatFloat(bicIndep, ffDecimal, 2)
    echo "    AB:BC:CD:DE (chain): ", formatFloat(bicChain, ffDecimal, 2)
    echo "    ABCDE (sat): ", formatFloat(bicSat, ffDecimal, 2)

    check bicChain < bicIndep


suite "Larger cardinalities":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(4)))
    discard varList.add(newVariable("B", "B", Cardinality(4)))
    discard varList.add(newVariable("C", "C", Cardinality(4)))

  test "state space for 4x4x4":
    check varList.stateSpace == 64  # 4^3

  test "entropy for high cardinality":
    randomize(666)
    let graphModel = createCustomChainModel(varList, 0.7)
    let samples = graphModel.generateSamples(5000)
    var table = graphModel.samplesToTable(samples)
    table.normalize()

    let h = entropy(table)
    let maxH = log2(64.0)  # Maximum entropy for 64 states

    echo "  4x4x4 entropy:"
    echo "    Observed H: ", formatFloat(h, ffDecimal, 4)
    echo "    Max H (uniform): ", formatFloat(maxH, ffDecimal, 4)
    echo "    Efficiency: ", formatFloat(h / maxH * 100, ffDecimal, 1), "%"

    check h > 0
    check h <= maxH

  test "model comparison for high cardinality":
    randomize(777)
    let graphModel = createCustomChainModel(varList, 0.75)
    let samples = graphModel.generateSamples(10000)
    var table = graphModel.samplesToTable(samples)

    var mgr = newVBManager(varList, table)

    let bicIndep = mgr.computeBIC(mgr.makeModel("A:B:C"))
    let bicChain = mgr.computeBIC(mgr.makeModel("AB:BC"))
    let bicSat = mgr.computeBIC(mgr.makeModel("ABC"))

    echo "  High cardinality (4x4x4) BIC:"
    echo "    A:B:C: ", formatFloat(bicIndep, ffDecimal, 2)
    echo "    AB:BC: ", formatFloat(bicChain, ffDecimal, 2)
    echo "    ABC: ", formatFloat(bicSat, ffDecimal, 2)

    check bicChain < bicIndep


suite "Directed system - multiple IVs":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("X1", "X", Cardinality(2)))
    discard varList.add(newVariable("X2", "Y", Cardinality(2)))
    discard varList.add(newVariable("X3", "W", Cardinality(3)))
    discard varList.add(newVariable("Z", "Z", Cardinality(2), isDependent = true))

  test "directed system structure":
    check varList.isDirected
    check varList.stateSpace == 24  # 2*2*3*2

  test "predictive model search":
    # Create data where Z depends on X1 and X2 (not X3)
    var table = initTable(varList.keySize, 24)
    for x1 in 0..<2:
      for x2 in 0..<2:
        for x3 in 0..<3:
          for z in 0..<2:
            var k = newKey(varList.keySize)
            k.setValue(varList, VariableIndex(0), x1)
            k.setValue(varList, VariableIndex(1), x2)
            k.setValue(varList, VariableIndex(2), x3)
            k.setValue(varList, VariableIndex(3), z)
            # Z = XOR(X1, X2) with noise
            let expected = (x1 + x2) mod 2
            let count = if z == expected: 40.0 else: 10.0
            table.add(k, count)
    table.sort()

    var mgr = newVBManager(varList, table)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initLooplessSearch(mgr, width = 10)

    let best = findBestModelByBIC(mgr, search, levels = 5)
    echo "  Directed (X1,X2→Z) search:"
    echo "    Best model: ", best.printName(varList)
    echo "    BIC: ", formatFloat(mgr.computeBIC(best), ffDecimal, 2)

    # Should find a model with Z dependent on X1 and/or X2
    check best.containsDependent(varList)


suite "Stress test - 6 variables":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    discard varList.add(newVariable("D", "D", Cardinality(2)))
    discard varList.add(newVariable("E", "E", Cardinality(2)))
    discard varList.add(newVariable("F", "F", Cardinality(2)))

  test "6-variable state space":
    check varList.stateSpace == 64  # 2^6

  test "6-variable chain model":
    randomize(888)
    let graphModel = createCustomChainModel(varList, 0.8)
    let samples = graphModel.generateSamples(10000)
    var table = graphModel.samplesToTable(samples)

    var mgr = newVBManager(varList, table)

    let bicIndep = mgr.computeBIC(mgr.bottomRefModel)
    let bicChain = mgr.computeBIC(mgr.makeModel("AB:BC:CD:DE:EF"))
    let bicSat = mgr.computeBIC(mgr.topRefModel)

    echo "  6-var chain model:"
    echo "    Independence BIC: ", formatFloat(bicIndep, ffDecimal, 2)
    echo "    Chain AB:BC:CD:DE:EF BIC: ", formatFloat(bicChain, ffDecimal, 2)
    echo "    Saturated BIC: ", formatFloat(bicSat, ffDecimal, 2)

    check bicChain < bicIndep

  test "6-variable search performance":
    randomize(999)
    let graphModel = createCustomChainModel(varList, 0.75)
    let samples = graphModel.generateSamples(8000)
    var table = graphModel.samplesToTable(samples)

    var mgr = newVBManager(varList, table)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initLooplessSearch(mgr, width = 15)

    echo "  6-var search (width=15, levels=8):"
    let best = findBestModelByBIC(mgr, search, levels = 8)
    echo "    Best found: ", best.printName(varList)
    echo "    Relations: ", best.relationCount
    echo "    BIC: ", formatFloat(mgr.computeBIC(best), ffDecimal, 2)

    check best.relationCount >= 1

