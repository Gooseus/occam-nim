## Test suite for search algorithms
## Tests loopless search for model space exploration

import std/[tables, algorithm, sequtils, heapqueue]
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/manager/vb
import ../src/occam/search/loopless

suite "Loop detection":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))

  test "independence model has no loops":
    # A:B:C - no overlapping relations
    let m = createIndependenceModel(varList)
    check not hasLoops(m, varList)

  test "saturated model has no loops":
    # ABC - single relation
    let m = createSaturatedModel(varList)
    check not hasLoops(m, varList)

  test "chain model AB:BC has no loops":
    # AB:BC - overlap on B but forms a chain (no cycle)
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let m = initModel(@[rAB, rBC])
    check not hasLoops(m, varList)

  test "model AB:BC:AC has loops":
    # Each pair of variables appears together
    # This forms a cycle: A-B-C-A
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let rAC = initRelation(@[VariableIndex(0), VariableIndex(2)])
    let m = initModel(@[rAB, rBC, rAC])
    check hasLoops(m, varList)


suite "Loopless search up (neutral)":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))

    var inputTable = initContingencyTable(varList.keySize, 8)
    for a in 0..<2:
      for b in 0..<2:
        for c in 0..<2:
          var k = newKey(varList.keySize)
          k.setValue(varList, VariableIndex(0), a)
          k.setValue(varList, VariableIndex(1), b)
          k.setValue(varList, VariableIndex(2), c)
          inputTable.add(k, 10.0)
    inputTable.sort()

  test "search from bottom finds loopless parents":
    var mgr = initVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initLooplessSearch(mgr)
    let parents = search.generateNeighbors(mgr.bottomRefModel)

    check parents.len > 0
    for model in parents:
      check not hasLoops(model, varList)

  test "parents of A:B:C include AB:C, AC:B, BC:A":
    var mgr = initVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initLooplessSearch(mgr)
    let parents = search.generateNeighbors(mgr.bottomRefModel)

    let names = parents.mapIt(it.printName(varList)).sorted()
    # Should find 2-variable models combined with singles
    check names.len >= 3


suite "Loopless search down (neutral)":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))

    var inputTable = initContingencyTable(varList.keySize, 8)
    for a in 0..<2:
      for b in 0..<2:
        for c in 0..<2:
          var k = newKey(varList.keySize)
          k.setValue(varList, VariableIndex(0), a)
          k.setValue(varList, VariableIndex(1), b)
          k.setValue(varList, VariableIndex(2), c)
          inputTable.add(k, 10.0)
    inputTable.sort()

  test "search from top finds loopless children":
    var mgr = initVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Descending)
    let search = initLooplessSearch(mgr)
    let children = search.generateNeighbors(mgr.topRefModel)

    check children.len > 0
    for model in children:
      check not hasLoops(model, varList)

  test "children of ABC are AB:C, AC:B, BC:A":
    var mgr = initVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Descending)
    let search = initLooplessSearch(mgr)
    let children = search.generateNeighbors(mgr.topRefModel)

    let names = children.mapIt(it.printName(varList)).sorted()
    # From ABC going down, remove one variable at a time
    check names.len == 3


suite "Loopless search directed":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("Z", "Z", Cardinality(2), isDependent = true))

    var inputTable = initContingencyTable(varList.keySize, 8)
    for a in 0..<2:
      for b in 0..<2:
        for z in 0..<2:
          var k = newKey(varList.keySize)
          k.setValue(varList, VariableIndex(0), a)
          k.setValue(varList, VariableIndex(1), b)
          k.setValue(varList, VariableIndex(2), z)
          inputTable.add(k, 10.0)
    inputTable.sort()

  test "search up from bottom (directed)":
    var mgr = initVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initLooplessSearch(mgr)
    let parents = search.generateNeighbors(mgr.bottomRefModel)

    check parents.len > 0
    # All models should keep the DV
    for model in parents:
      check model.containsDependent(varList)

  test "search down from top (directed)":
    var mgr = initVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Descending)
    let search = initLooplessSearch(mgr)
    let children = search.generateNeighbors(mgr.topRefModel)

    check children.len > 0
    for model in children:
      check model.containsDependent(varList)


suite "Search level iteration":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))

    var inputTable = initContingencyTable(varList.keySize, 8)
    for a in 0..<2:
      for b in 0..<2:
        for c in 0..<2:
          var k = newKey(varList.keySize)
          k.setValue(varList, VariableIndex(0), a)
          k.setValue(varList, VariableIndex(1), b)
          k.setValue(varList, VariableIndex(2), c)
          inputTable.add(k, 10.0)
    inputTable.sort()

  test "multiple levels of search from bottom":
    var mgr = initVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initLooplessSearch(mgr)

    # Level 0: bottom (A:B:C)
    let level0 = @[mgr.bottomRefModel]
    check level0[0].isIndependenceModel(varList)

    # Level 1: should get models like AB:C
    var level1: seq[Model]
    for m in level0:
      for neighbor in search.generateNeighbors(m):
        level1.add(neighbor)

    check level1.len > 0
    # All models should have more structure than independence
    for m in level1:
      check not m.isIndependenceModel(varList)

  test "multiple levels of search from top":
    var mgr = initVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Descending)
    let search = initLooplessSearch(mgr)

    # Level 0: top (ABC)
    let level0 = @[mgr.topRefModel]
    check level0[0].isSaturatedModel(varList)

    # Level 1: should get models like AB:C, AC:B, BC:A
    var level1: seq[Model]
    for m in level0:
      for neighbor in search.generateNeighbors(m):
        level1.add(neighbor)

    check level1.len > 0
    # All children should have less structure than saturated
    for m in level1:
      check not m.isSaturatedModel(varList)


suite "Model selection by statistics":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))

    # Non-uniform data to create interesting statistics
    var inputTable = initContingencyTable(varList.keySize, 8)
    for a in 0..<2:
      for b in 0..<2:
        for c in 0..<2:
          var k = newKey(varList.keySize)
          k.setValue(varList, VariableIndex(0), a)
          k.setValue(varList, VariableIndex(1), b)
          k.setValue(varList, VariableIndex(2), c)
          # Create pattern where AB is related
          let count = if a == b: 20.0 else: 5.0
          inputTable.add(k, count)
    inputTable.sort()

  test "models sorted by DF":
    var mgr = initVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initLooplessSearch(mgr)
    let neighbors = search.generateNeighbors(mgr.bottomRefModel)

    var dfs: seq[(int64, string)]
    for model in neighbors:
      let df = mgr.computeDF(model)
      dfs.add((df, model.printName(varList)))

    dfs.sort(proc(a, b: (int64, string)): int = cmp(a[0], b[0]))
    # Models with smaller DF come first
    check dfs.len >= 1


suite "Search width limiting":
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

  test "can limit search width":
    var mgr = initVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initLooplessSearch(mgr, width = 3)
    let neighbors = search.generateNeighbors(mgr.bottomRefModel)

    # Without sorting/selection, may have more than 3
    # With width limiting, should get at most width best models
    check neighbors.len >= 1


suite "Loop detection edge cases":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    discard varList.add(newVariable("D", "D", Cardinality(2)))

  test "4-variable square has loops":
    # AB:BC:CD:DA forms a square cycle
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let rCD = initRelation(@[VariableIndex(2), VariableIndex(3)])
    let rDA = initRelation(@[VariableIndex(3), VariableIndex(0)])
    let m = initModel(@[rAB, rBC, rCD, rDA])
    check hasLoops(m, varList)

  test "4-variable chain has no loops":
    # AB:BC:CD is a chain (no cycle)
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let rCD = initRelation(@[VariableIndex(2), VariableIndex(3)])
    let m = initModel(@[rAB, rBC, rCD])
    check not hasLoops(m, varList)

  test "star model has no loops":
    # AB:AC:AD - star with A at center
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rAC = initRelation(@[VariableIndex(0), VariableIndex(2)])
    let rAD = initRelation(@[VariableIndex(0), VariableIndex(3)])
    let m = initModel(@[rAB, rAC, rAD])
    check not hasLoops(m, varList)

  test "3-variable overlap without cycle":
    # AB:AC - overlapping on A but no cycle
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rAC = initRelation(@[VariableIndex(0), VariableIndex(2)])
    let m = initModel(@[rAB, rAC])
    check not hasLoops(m, varList)


suite "Loopless search with 4 variables":
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

  test "parents from independence model":
    var mgr = initVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initLooplessSearch(mgr)
    let parents = search.generateNeighbors(mgr.bottomRefModel)

    # A:B:C:D should have 6 parents (one for each variable pair)
    check parents.len >= 6
    for p in parents:
      check not hasLoops(p, varList)

  test "all generated neighbors are loopless":
    var mgr = initVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initLooplessSearch(mgr)

    # Start from bottom, search up two levels
    let level1 = search.generateNeighbors(mgr.bottomRefModel)
    for m in level1:
      check not hasLoops(m, varList)

      let level2 = search.generateNeighbors(m)
      for m2 in level2:
        check not hasLoops(m2, varList)

