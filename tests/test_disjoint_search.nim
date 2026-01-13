## Test suite for disjoint search algorithm
## Tests disjoint model detection and search strategies

import std/[tables, algorithm, sequtils]
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/manager/vb
import ../src/occam/search/disjoint


suite "Disjoint model detection":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    discard varList.add(newVariable("D", "D", Cardinality(2)))

  test "independence model is disjoint":
    # A:B:C:D - all single-variable relations, no overlap
    let m = createIndependenceModel(varList)
    check isDisjointModel(m, varList)

  test "model AB:CD is disjoint":
    # Two 2-variable relations with no shared variables
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rCD = initRelation(@[VariableIndex(2), VariableIndex(3)])
    let m = initModel(@[rAB, rCD])
    check isDisjointModel(m, varList)

  test "model AB:C:D is disjoint":
    # AB merged, C and D separate
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rC = initRelation(@[VariableIndex(2)])
    let rD = initRelation(@[VariableIndex(3)])
    let m = initModel(@[rAB, rC, rD])
    check isDisjointModel(m, varList)

  test "model AB:BC is NOT disjoint":
    # Chain model - shares B
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let m = initModel(@[rAB, rBC])
    check not isDisjointModel(m, varList)

  test "model ABC is disjoint (single relation)":
    # Single relation with all variables
    let rABC = initRelation(@[VariableIndex(0), VariableIndex(1), VariableIndex(2)])
    let m = initModel(@[rABC])
    check isDisjointModel(m, varList)

  test "saturated model ABCD is disjoint (single relation)":
    let m = createSaturatedModel(varList)
    check isDisjointModel(m, varList)

  test "model AB:AC is NOT disjoint":
    # Star pattern - A appears in both
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rAC = initRelation(@[VariableIndex(0), VariableIndex(2)])
    let m = initModel(@[rAB, rAC])
    check not isDisjointModel(m, varList)


suite "Disjoint search up (neutral)":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    discard varList.add(newVariable("D", "D", Cardinality(2)))

    var inputTable = initContingencyTable(varList.keySize, 16)
    for a in 0..<2:
      for b in 0..<2:
        for c in 0..<2:
          for d in 0..<2:
            var k = newKey(varList.keySize)
            k.setValue(varList, VariableIndex(0), a)
            k.setValue(varList, VariableIndex(1), b)
            k.setValue(varList, VariableIndex(2), c)
            k.setValue(varList, VariableIndex(3), d)
            inputTable.add(k, 10.0)
    inputTable.sort()

  test "search up from bottom finds only disjoint neighbors":
    var mgr = initVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initDisjointSearch(mgr)
    let neighbors = search.generateNeighbors(mgr.bottomRefModel)

    check neighbors.len > 0
    for model in neighbors:
      check isDisjointModel(model, varList)

  test "disjoint up from A:B:C:D yields pairwise merges":
    var mgr = initVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initDisjointSearch(mgr)
    let neighbors = search.generateNeighbors(mgr.bottomRefModel)

    # From independence model, disjoint neighbors should be 2-var merges
    # like AB:C:D, AC:B:D, AD:B:C, BC:A:D, BD:A:C, CD:A:B
    let names = neighbors.mapIt(it.printName(varList)).sorted()
    check names.len == 6  # C(4,2) = 6 pairs


suite "Disjoint search down (neutral)":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    discard varList.add(newVariable("D", "D", Cardinality(2)))

    var inputTable = initContingencyTable(varList.keySize, 16)
    for a in 0..<2:
      for b in 0..<2:
        for c in 0..<2:
          for d in 0..<2:
            var k = newKey(varList.keySize)
            k.setValue(varList, VariableIndex(0), a)
            k.setValue(varList, VariableIndex(1), b)
            k.setValue(varList, VariableIndex(2), c)
            k.setValue(varList, VariableIndex(3), d)
            inputTable.add(k, 10.0)
    inputTable.sort()

  test "search down from top finds only disjoint neighbors":
    var mgr = initVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Descending)
    let search = initDisjointSearch(mgr)
    let neighbors = search.generateNeighbors(mgr.topRefModel)

    check neighbors.len > 0
    for model in neighbors:
      check isDisjointModel(model, varList)

  test "disjoint down from AB:CD yields single splits":
    var mgr = initVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Descending)
    let search = initDisjointSearch(mgr)

    # Create AB:CD model
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rCD = initRelation(@[VariableIndex(2), VariableIndex(3)])
    let startModel = initModel(@[rAB, rCD])

    let neighbors = search.generateNeighbors(startModel)

    # Should split AB to A:B or CD to C:D, maintaining disjointness
    check neighbors.len >= 1
    for model in neighbors:
      check isDisjointModel(model, varList)


suite "Disjoint search directed":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    discard varList.add(newVariable("Z", "Z", Cardinality(2), isDependent = true))

    var inputTable = initContingencyTable(varList.keySize, 16)
    for a in 0..<2:
      for b in 0..<2:
        for c in 0..<2:
          for z in 0..<2:
            var k = newKey(varList.keySize)
            k.setValue(varList, VariableIndex(0), a)
            k.setValue(varList, VariableIndex(1), b)
            k.setValue(varList, VariableIndex(2), c)
            k.setValue(varList, VariableIndex(3), z)
            inputTable.add(k, 10.0)
    inputTable.sort()

  test "directed disjoint search up maintains DV":
    var mgr = initVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initDisjointSearch(mgr)
    let neighbors = search.generateNeighbors(mgr.bottomRefModel)

    check neighbors.len > 0
    for model in neighbors:
      check model.containsDependent(varList)
      check isDisjointModel(model, varList)

  test "directed disjoint search down maintains DV":
    var mgr = initVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Descending)
    let search = initDisjointSearch(mgr)
    let neighbors = search.generateNeighbors(mgr.topRefModel)

    check neighbors.len > 0
    for model in neighbors:
      check model.containsDependent(varList)
      check isDisjointModel(model, varList)


suite "Full disjoint search traversal":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    discard varList.add(newVariable("D", "D", Cardinality(2)))

    var inputTable = initContingencyTable(varList.keySize, 16)
    for a in 0..<2:
      for b in 0..<2:
        for c in 0..<2:
          for d in 0..<2:
            var k = newKey(varList.keySize)
            k.setValue(varList, VariableIndex(0), a)
            k.setValue(varList, VariableIndex(1), b)
            k.setValue(varList, VariableIndex(2), c)
            k.setValue(varList, VariableIndex(3), d)
            inputTable.add(k, 10.0)
    inputTable.sort()

  test "multi-level disjoint search up explores all disjoint models":
    var mgr = initVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initDisjointSearch(mgr)

    # Start from independence model
    var currentLevel = @[mgr.bottomRefModel]
    var allModels: seq[Model] = @[mgr.bottomRefModel]
    var foundModels: seq[string] = @[mgr.bottomRefModel.printName(varList)]

    for level in 0..<5:
      var nextLevel: seq[Model]
      for model in currentLevel:
        for neighbor in search.generateNeighbors(model):
          let name = neighbor.printName(varList)
          if name notin foundModels:
            foundModels.add(name)
            nextLevel.add(neighbor)
            allModels.add(neighbor)
      if nextLevel.len == 0:
        break
      currentLevel = nextLevel

    # All found models should be disjoint
    for model in allModels:
      check isDisjointModel(model, varList)

    # Should find more than just the starting model
    check allModels.len > 1
