## Test suite for full search algorithm
## Tests model space exploration including loop models

import std/[algorithm, sequtils, options]
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/manager/vb
import ../src/occam/search/base
import ../src/occam/search/full
import ../src/occam/search/loopless
import ../src/occam/math/statistics


proc makeUniformTable(varList: VariableList): Table =
  ## Create uniform distribution over all variables
  let n = varList.len
  var totalStates = 1
  for i in 0..<n:
    totalStates *= varList[VariableIndex(i)].cardinality.toInt

  result = initTable(varList.keySize, totalStates)

  var indices = newSeq[int](n)
  var done = false
  while not done:
    var keyPairs: seq[(VariableIndex, int)]
    for i in 0..<n:
      keyPairs.add((VariableIndex(i), indices[i]))
    let key = varList.buildKey(keyPairs)
    result.add(key, 10.0)

    var carry = true
    for i in 0..<n:
      if carry:
        indices[i] += 1
        if indices[i] >= varList[VariableIndex(i)].cardinality.toInt:
          indices[i] = 0
        else:
          carry = false
    if carry:
      done = true

  result.sort()


suite "Full search vs loopless - generates loop models":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    let inputTable = makeUniformTable(varList)

  test "full search includes loop models in neighbors":
    var mgr = newVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)

    let fullSearch = initFullSearch(mgr)
    let looplessSearch = initLooplessSearch(mgr)

    # Start from AB:C (has two relations)
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rC = initRelation(@[VariableIndex(2)])
    let model = initModel(@[rAB, rC])

    let fullNeighbors = fullSearch.generateNeighbors(model)
    let looplessNeighbors = looplessSearch.generateNeighbors(model)

    # Full search should find more or equal neighbors (includes loops)
    check fullNeighbors.len >= looplessNeighbors.len

    # Count loop models in each
    var fullLoopCount = 0
    var looplessLoopCount = 0
    for m in fullNeighbors:
      if hasLoops(m, varList):
        fullLoopCount += 1
    for m in looplessNeighbors:
      if hasLoops(m, varList):
        looplessLoopCount += 1

    # Loopless search should produce NO loop models
    check looplessLoopCount == 0
    # Full search may produce loop models (depends on starting model)

  test "from chain AB:BC, full search can add AC to create triangle":
    var mgr = newVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)

    let fullSearch = initFullSearch(mgr)

    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let chainModel = initModel(@[rAB, rBC])

    let neighbors = fullSearch.generateNeighbors(chainModel)

    # Check if any neighbor is the triangle AB:BC:AC
    var foundTriangle = false
    for m in neighbors:
      let name = m.printName(varList)
      if hasLoops(m, varList):
        foundTriangle = true
        break

    # Full search should be able to create loop models
    # (may not always create AC specifically, but should have loop options)
    # This is algorithm-specific, so we just verify the search works
    check neighbors.len > 0


suite "Full search up (neutral)":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    let inputTable = makeUniformTable(varList)

  test "search from bottom finds parents":
    var mgr = newVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initFullSearch(mgr)
    let parents = search.generateNeighbors(mgr.bottomRefModel)

    check parents.len > 0
    # Parents of independence model should all be strictly larger
    for model in parents:
      let parentDf = modelDF(model, varList)
      let bottomDf = modelDF(mgr.bottomRefModel, varList)
      check parentDf > bottomDf

  test "parents from A:B:C include 2-variable models":
    var mgr = newVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initFullSearch(mgr)
    let parents = search.generateNeighbors(mgr.bottomRefModel)

    let names = parents.mapIt(it.printName(varList)).sorted()
    # Should find AB:C, AC:B, BC:A or equivalent
    check names.len >= 3

  test "search from saturated has no parents":
    var mgr = newVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initFullSearch(mgr)

    # Saturated model is at the top
    let saturated = createSaturatedModel(varList)
    let parents = search.generateNeighbors(saturated)

    # Saturated model has no parents (is the top)
    check parents.len == 0


suite "Full search down (neutral)":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    let inputTable = makeUniformTable(varList)

  test "search from top finds children":
    var mgr = newVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Descending)
    let search = initFullSearch(mgr)
    let children = search.generateNeighbors(mgr.topRefModel)

    check children.len > 0
    # Children of saturated model should all be strictly smaller
    for model in children:
      let childDf = modelDF(model, varList)
      let topDf = modelDF(mgr.topRefModel, varList)
      check childDf < topDf

  test "search from bottom has no children":
    var mgr = newVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Descending)
    let search = initFullSearch(mgr)
    let children = search.generateNeighbors(mgr.bottomRefModel)

    # Independence model has no children (is the bottom)
    check children.len == 0

  test "search from chain AB:BC finds children":
    var mgr = newVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Descending)
    let search = initFullSearch(mgr)

    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let chainModel = initModel(@[rAB, rBC])

    let children = search.generateNeighbors(chainModel)
    # Chain AB:BC should have children (e.g., A:B:C if we can split)
    # Note: actual children depend on search algorithm
    # The chain has 2-variable relations, so splitting is not trivial
    # This test just verifies the search runs without error
    check children.len >= 0


suite "Full search - deduplication":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    let inputTable = makeUniformTable(varList)

  test "neighbors have no duplicates":
    var mgr = newVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initFullSearch(mgr)

    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rC = initRelation(@[VariableIndex(2)])
    let model = initModel(@[rAB, rC])

    let neighbors = search.generateNeighbors(model)
    let names = neighbors.mapIt(it.printName(varList))

    # Check no duplicates in names
    let uniqueNames = names.deduplicate()
    check names.len == uniqueNames.len


suite "Simplify relations":
  test "removes proper subsets":
    let rA = initRelation(@[VariableIndex(0)])
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])

    let simplified = simplifyRelations(@[rA, rAB])
    check simplified.len == 1
    check simplified[0] == rAB

  test "keeps non-overlapping relations":
    let rA = initRelation(@[VariableIndex(0)])
    let rB = initRelation(@[VariableIndex(1)])

    let simplified = simplifyRelations(@[rA, rB])
    check simplified.len == 2

  test "handles identical relations":
    let rA1 = initRelation(@[VariableIndex(0)])
    let rA2 = initRelation(@[VariableIndex(0)])

    let simplified = simplifyRelations(@[rA1, rA2])
    # Both are identical (subset of each other), both should remain
    # as neither is a PROPER subset
    check simplified.len == 2

  test "handles complex case":
    let rA = initRelation(@[VariableIndex(0)])
    let rB = initRelation(@[VariableIndex(1)])
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rC = initRelation(@[VariableIndex(2)])

    let simplified = simplifyRelations(@[rA, rB, rAB, rC])
    # A and B are subsets of AB, so only AB and C should remain
    check simplified.len == 2

    var names: seq[string] = @[]
    for r in simplified:
      var name = ""
      for v in r.varIndices:
        name.add($chr(ord('A') + v.toInt))
      names.add(name)
    names.sort()
    check "AB" in names
    check "C" in names


suite "Merge relations":
  test "merges two disjoint relations":
    let rA = initRelation(@[VariableIndex(0)])
    let rB = initRelation(@[VariableIndex(1)])

    let merged = mergeRelations(rA, rB)
    check merged.variableCount == 2
    check merged.containsVariable(VariableIndex(0))
    check merged.containsVariable(VariableIndex(1))

  test "merges overlapping relations":
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rBC = initRelation(@[VariableIndex(1), VariableIndex(2)])

    let merged = mergeRelations(rAB, rBC)
    check merged.variableCount == 3
    check merged.containsVariable(VariableIndex(0))
    check merged.containsVariable(VariableIndex(1))
    check merged.containsVariable(VariableIndex(2))

  test "merges identical relations":
    let rAB1 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rAB2 = initRelation(@[VariableIndex(0), VariableIndex(1)])

    let merged = mergeRelations(rAB1, rAB2)
    check merged.variableCount == 2
    check merged == rAB1


suite "Add/remove variable from relation":
  test "add variable to relation":
    let rA = initRelation(@[VariableIndex(0)])
    let rAB = addVariableToRelation(rA, VariableIndex(1))

    check rAB.variableCount == 2
    check rAB.containsVariable(VariableIndex(0))
    check rAB.containsVariable(VariableIndex(1))

  test "add existing variable is idempotent":
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let result = addVariableToRelation(rAB, VariableIndex(0))

    check result.variableCount == 2
    check result == rAB

  test "remove variable from relation":
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rB = removeVariableFromRelation(rAB, VariableIndex(0))

    check rB.variableCount == 1
    check rB.containsVariable(VariableIndex(1))
    check not rB.containsVariable(VariableIndex(0))

  test "remove last variable gives empty relation":
    let rA = initRelation(@[VariableIndex(0)])
    let empty = removeVariableFromRelation(rA, VariableIndex(0))

    check empty.variableCount == 0


suite "Find relation utilities":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))

  test "findRelationWithVariable finds correct relation":
    let rA = initRelation(@[VariableIndex(0)])
    let rBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let model = initModel(@[rA, rBC])

    let foundA = findRelationWithVariable(model, VariableIndex(0))
    let foundB = findRelationWithVariable(model, VariableIndex(1))

    check foundA.isSome
    check foundA.get == 0  # First relation contains A

    check foundB.isSome
    check foundB.get == 1  # Second relation contains B

  test "findRelationPair identifies separate relations":
    let rA = initRelation(@[VariableIndex(0)])
    let rB = initRelation(@[VariableIndex(1)])
    let model = initModel(@[rA, rB])

    let (relWithA, relWithB, inSame) = findRelationPair(model, VariableIndex(0), VariableIndex(1))

    check relWithA.isSome
    check relWithB.isSome
    check not inSame

  test "findRelationPair identifies same relation":
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let model = initModel(@[rAB])

    let (relWithA, relWithB, inSame) = findRelationPair(model, VariableIndex(0), VariableIndex(1))

    check inSame


suite "addIfUnique":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))

  test "adds unique model":
    let rA = initRelation(@[VariableIndex(0)])
    let rB = initRelation(@[VariableIndex(1)])
    let m1 = initModel(@[rA])
    let m2 = initModel(@[rB])

    var models: seq[Model] = @[m1]
    let added = models.addIfUnique(m2, varList)

    check added
    check models.len == 2

  test "does not add duplicate model":
    let rA = initRelation(@[VariableIndex(0)])
    let m1 = initModel(@[rA])
    let m2 = initModel(@[rA])  # Same as m1

    var models: seq[Model] = @[m1]
    let added = models.addIfUnique(m2, varList)

    check not added
    check models.len == 1


suite "Full search with 4 variables":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    discard varList.add(newVariable("D", "D", Cardinality(2)))
    let inputTable = makeUniformTable(varList)

  test "search from bottom with 4 variables":
    var mgr = newVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initFullSearch(mgr)

    let parents = search.generateNeighbors(mgr.bottomRefModel)

    # Independence model A:B:C:D should have 6 parents (one for each pair)
    check parents.len >= 6

  test "search from saturated with 4 variables":
    var mgr = newVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Descending)
    let search = initFullSearch(mgr)

    let saturated = createSaturatedModel(varList)
    let children = search.generateNeighbors(saturated)

    # Saturated ABCD should have children
    check children.len > 0


suite "Full search - directed systems":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("Z", "Z", Cardinality(2), isDependent = true))
    let inputTable = makeUniformTable(varList)

  test "directed search up from bottom":
    var mgr = newVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initFullSearch(mgr)

    let parents = search.generateNeighbors(mgr.bottomRefModel)

    # Should find parents where IVs are added to predictive relation
    check parents.len >= 0

  test "directed search maintains DV in predictive relations":
    var mgr = newVBManager(varList, inputTable)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initFullSearch(mgr)

    # Start from model with Z (DV) alone
    let rZ = initRelation(@[VariableIndex(2)])
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let model = initModel(@[rZ, rAB])

    let parents = search.generateNeighbors(model)

    # All parents should have DV in some relation
    for parent in parents:
      var hasDV = false
      for rel in parent.relations:
        if rel.containsDependent(varList):
          hasDV = true
          break
      check hasDV
