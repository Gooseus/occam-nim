## Test suite for Variable-Based Manager
## Tests VBManager - the coordinator for projections, caching, and statistics

import std/[tables, math]
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/math/entropy
import ../src/occam/math/statistics
import ../src/occam/manager/vb

suite "VBManager creation":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

    # Create sample data - ABC full table
    var inputTable = initContingencyTable(varList.keySize, 8)
    for a in 0..<2:
      for b in 0..<2:
        for c in 0..<2:
          var k = initKey(varList.keySize)
          k.setValue(varList, VariableIndex(0), a)
          k.setValue(varList, VariableIndex(1), b)
          k.setValue(varList, VariableIndex(2), c)
          # Non-uniform counts to test entropy properly
          let count = float64(10 + a*5 + b*10 + c*3)
          inputTable.add(k, count)
    inputTable.sort()

  test "create manager":
    let mgr = initVBManager(varList, inputTable)
    check mgr.varList.len == 3
    check mgr.sampleSize > 0

  test "manager stores sample size":
    let mgr = initVBManager(varList, inputTable)
    check mgr.sampleSize == inputTable.sum

  test "manager provides variable list":
    let mgr = initVBManager(varList, inputTable)
    check mgr.varList[VariableIndex(0)].abbrev == "A"


suite "Reference models":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

    var inputTable = initContingencyTable(varList.keySize, 8)
    for a in 0..<2:
      for b in 0..<2:
        for c in 0..<2:
          var k = initKey(varList.keySize)
          k.setValue(varList, VariableIndex(0), a)
          k.setValue(varList, VariableIndex(1), b)
          k.setValue(varList, VariableIndex(2), c)
          inputTable.add(k, 10.0)
    inputTable.sort()

  test "top reference model is saturated":
    let mgr = initVBManager(varList, inputTable)
    let top = mgr.topRefModel
    check top.relationCount == 1
    # Saturated model has one relation with all variables
    check top.relations[0].variableCount == 3

  test "bottom reference model is independence":
    let mgr = initVBManager(varList, inputTable)
    let bottom = mgr.bottomRefModel
    # Independence model for neutral system has single-variable relations
    check bottom.relationCount == 3
    for i in 0..<3:
      check bottom.relations[i].variableCount == 1


suite "Directed system reference models":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("Z", "Z", Cardinality(2), isDependent = true))

    var inputTable = initContingencyTable(varList.keySize, 8)
    for a in 0..<2:
      for b in 0..<2:
        for z in 0..<2:
          var k = initKey(varList.keySize)
          k.setValue(varList, VariableIndex(0), a)
          k.setValue(varList, VariableIndex(1), b)
          k.setValue(varList, VariableIndex(2), z)
          inputTable.add(k, 10.0)
    inputTable.sort()

  test "directed top model is saturated":
    let mgr = initVBManager(varList, inputTable)
    let top = mgr.topRefModel
    # Saturated model: ABZ (one relation with all variables)
    check top.relationCount == 1
    check top.relations[0].variableCount == 3

  test "directed bottom model has IV and DV relations":
    let mgr = initVBManager(varList, inputTable)
    let bottom = mgr.bottomRefModel
    # Independence model for directed: IV (AB) : Z
    check bottom.relationCount == 2
    # One relation is IV-only (AB), one is DV-only (Z)
    var hasIvOnly = false
    var hasDvOnly = false
    for i in 0..<2:
      let rel = bottom.relations[i]
      if rel.isIndependentOnly(varList):
        hasIvOnly = true
        check rel.variableCount == 2  # AB
      if rel.isDependentOnly(varList):
        hasDvOnly = true
        check rel.variableCount == 1  # Z
    check hasIvOnly
    check hasDvOnly


suite "Relation caching":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

    var inputTable = initContingencyTable(varList.keySize, 8)
    for a in 0..<2:
      for b in 0..<2:
        for c in 0..<2:
          var k = initKey(varList.keySize)
          k.setValue(varList, VariableIndex(0), a)
          k.setValue(varList, VariableIndex(1), b)
          k.setValue(varList, VariableIndex(2), c)
          inputTable.add(k, 10.0)
    inputTable.sort()

  test "getRelation returns cached relation":
    var mgr = initVBManager(varList, inputTable)
    let rel1 = mgr.getRelation(@[VariableIndex(0), VariableIndex(1)])
    let rel2 = mgr.getRelation(@[VariableIndex(0), VariableIndex(1)])
    check rel1 == rel2  # Same object

  test "getRelation with different vars returns different relation":
    var mgr = initVBManager(varList, inputTable)
    let rel1 = mgr.getRelation(@[VariableIndex(0), VariableIndex(1)])
    let rel2 = mgr.getRelation(@[VariableIndex(1), VariableIndex(2)])
    check rel1 != rel2


suite "Projection computation":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

    var inputTable = initContingencyTable(varList.keySize, 8)
    for a in 0..<2:
      for b in 0..<2:
        for c in 0..<2:
          var k = initKey(varList.keySize)
          k.setValue(varList, VariableIndex(0), a)
          k.setValue(varList, VariableIndex(1), b)
          k.setValue(varList, VariableIndex(2), c)
          let count = float64(10 + a*20 + b*10 + c*5)
          inputTable.add(k, count)
    inputTable.sort()

  test "makeProjection creates correct projection":
    var mgr = initVBManager(varList, inputTable)
    var rel = mgr.getRelation(@[VariableIndex(0), VariableIndex(1)])
    mgr.makeProjection(rel)
    check rel.hasProjection
    let proj = rel.projection
    check proj.len == 4  # 2x2 table
    check proj.sum == inputTable.sum  # Same total

  test "projection values are correct":
    var mgr = initVBManager(varList, inputTable)
    var rel = mgr.getRelation(@[VariableIndex(0)])  # Just A
    mgr.makeProjection(rel)
    let proj = rel.projection
    check proj.len == 2
    # Each A value sums over all B and C values


suite "Entropy computation":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))

    # Uniform distribution
    var uniformTable = initContingencyTable(varList.keySize, 4)
    for a in 0..<2:
      for b in 0..<2:
        var k = initKey(varList.keySize)
        k.setValue(varList, VariableIndex(0), a)
        k.setValue(varList, VariableIndex(1), b)
        uniformTable.add(k, 25.0)  # 100 total
    uniformTable.sort()

  test "compute entropy for uniform distribution":
    var mgr = initVBManager(varList, uniformTable)
    let h = mgr.computeH(mgr.topRefModel)
    # H = log2(4) = 2.0 for uniform over 4 states
    check abs(h - 2.0) < 0.001

  test "compute transmission":
    var mgr = initVBManager(varList, uniformTable)
    let t = mgr.computeT(mgr.bottomRefModel)
    # For uniform independent model, T ≈ 0
    check abs(t) < 0.01


suite "Model statistics":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

    var inputTable = initContingencyTable(varList.keySize, 8)
    for a in 0..<2:
      for b in 0..<2:
        for c in 0..<2:
          var k = initKey(varList.keySize)
          k.setValue(varList, VariableIndex(0), a)
          k.setValue(varList, VariableIndex(1), b)
          k.setValue(varList, VariableIndex(2), c)
          inputTable.add(k, 12.5)  # 100 total, uniform
    inputTable.sort()

  test "compute degrees of freedom":
    var mgr = initVBManager(varList, inputTable)
    let top = mgr.topRefModel
    let df = mgr.computeDF(top)
    # Saturated model: DF = 2^3 - 1 = 7
    check df == 7

  test "compute DF for independence model":
    var mgr = initVBManager(varList, inputTable)
    let bottom = mgr.bottomRefModel
    let df = mgr.computeDF(bottom)
    # Independence model A:B:C has DF = (2-1) + (2-1) + (2-1) = 3
    check df == 3

  test "compute delta DF":
    var mgr = initVBManager(varList, inputTable)
    let ddf = mgr.computeDDF(mgr.bottomRefModel)
    # DDF = DF(top) - DF(model) = 7 - 3 = 4
    check ddf == 4


suite "Model creation from string":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

    var inputTable = initContingencyTable(varList.keySize, 8)
    for a in 0..<2:
      for b in 0..<2:
        for c in 0..<2:
          var k = initKey(varList.keySize)
          k.setValue(varList, VariableIndex(0), a)
          k.setValue(varList, VariableIndex(1), b)
          k.setValue(varList, VariableIndex(2), c)
          inputTable.add(k, 10.0)
    inputTable.sort()

  test "create model AB:BC":
    var mgr = initVBManager(varList, inputTable)
    let model = mgr.makeModel("AB:BC")
    check model.relationCount == 2
    check model.printName(varList) == "AB:BC"

  test "create model A:B:C":
    var mgr = initVBManager(varList, inputTable)
    let model = mgr.makeModel("A:B:C")
    check model.relationCount == 3
    check model.printName(varList) == "A:B:C"

  test "create saturated model ABC":
    var mgr = initVBManager(varList, inputTable)
    let model = mgr.makeModel("ABC")
    check model.relationCount == 1
    check model.printName(varList) == "ABC"


suite "Search one level":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

    var inputTable = initContingencyTable(varList.keySize, 8)
    for a in 0..<2:
      for b in 0..<2:
        for c in 0..<2:
          var k = initKey(varList.keySize)
          k.setValue(varList, VariableIndex(0), a)
          k.setValue(varList, VariableIndex(1), b)
          k.setValue(varList, VariableIndex(2), c)
          inputTable.add(k, 10.0)
    inputTable.sort()

  test "search up from bottom generates parents":
    var mgr = initVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)
    let children = mgr.searchOneLevel(mgr.bottomRefModel)
    # From A:B:C, going up should find models like AB:C, AC:B, BC:A
    check children.len > 0

  test "search down from top generates children":
    var mgr = initVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Descending)
    let children = mgr.searchOneLevel(mgr.topRefModel)
    # From ABC, going down should find models like AB:C, etc.
    check children.len > 0


suite "Model caching":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))

    var inputTable = initContingencyTable(varList.keySize, 4)
    for a in 0..<2:
      for b in 0..<2:
        var k = initKey(varList.keySize)
        k.setValue(varList, VariableIndex(0), a)
        k.setValue(varList, VariableIndex(1), b)
        inputTable.add(k, 25.0)
    inputTable.sort()

  test "models are cached":
    var mgr = initVBManager(varList, inputTable)
    let m1 = mgr.makeModel("AB")
    let m2 = mgr.makeModel("AB")
    check m1 == m2  # Same cached model

  test "different models are distinct":
    var mgr = initVBManager(varList, inputTable)
    let m1 = mgr.makeModel("AB")
    let m2 = mgr.makeModel("A:B")
    check m1 != m2

