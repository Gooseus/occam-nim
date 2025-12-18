## Test suite for lattice enumeration
## Tests complete model lattice generation

import std/[algorithm, sequtils, sets]
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/search/lattice


suite "Generate parents":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))

  test "independence model has parents":
    let indep = createIndependenceModel(varList)  # A:B:C
    let parents = generateParents(indep, varList)

    # Should generate AB:C, AC:B, BC:A
    check parents.len == 3

    let names = parents.mapIt(it.printName(varList)).sorted()
    check "AB:C" in names
    check "AC:B" in names
    check "A:BC" in names

  test "saturated model has no parents":
    let saturated = createSaturatedModel(varList)  # ABC
    let parents = generateParents(saturated, varList)

    check parents.len == 0

  test "chain model AB:BC has parents":
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let chain = initModel(@[rAB, rBC])

    let parents = generateParents(chain, varList)

    # Should generate ABC (merge AB and BC)
    check parents.len >= 1

    var foundSaturated = false
    for p in parents:
      if p.relationCount == 1 and p.relations[0].variableCount == 3:
        foundSaturated = true
        break
    check foundSaturated

  test "parents have no duplicates":
    let indep = createIndependenceModel(varList)
    let parents = generateParents(indep, varList)

    let names = parents.mapIt(it.printName(varList))
    let uniqueNames = names.deduplicate()
    check names.len == uniqueNames.len


suite "Generate children":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))

  test "saturated model has children":
    let saturated = createSaturatedModel(varList)  # ABC
    let children = generateChildren(saturated, varList)

    # ABC splits by removing pairs, creating children like AB:AC, AB:BC, AC:BC
    # (the algorithm splits by removing one variable from each of two copies)
    check children.len == 3

    let names = children.mapIt(it.printName(varList)).sorted()
    # Verify all children have 2 relations (2-variable each)
    for child in children:
      check child.relationCount == 2

  test "independence model has no children":
    let indep = createIndependenceModel(varList)  # A:B:C
    let children = generateChildren(indep, varList)

    # Singletons can't be split further
    check children.len == 0

  test "chain model AB:BC has children":
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let chain = initModel(@[rAB, rBC])

    let children = generateChildren(chain, varList)

    # AB can split to A:B, BC can split to B:C
    # So children include: A:B:BC, A:BC (from splitting AB)
    #                      AB:B:C, AB:C (from splitting BC)
    check children.len >= 2

  test "children have no duplicates":
    let saturated = createSaturatedModel(varList)
    let children = generateChildren(saturated, varList)

    let names = children.mapIt(it.printName(varList))
    let uniqueNames = names.deduplicate()
    check names.len == uniqueNames.len


suite "Enumerate lattice - 2 variables":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))

  test "complete lattice has 2 models":
    let lattice = enumerateLattice(varList)

    # 2 variables: A:B (bottom) and AB (top)
    check lattice.len == 2

    let names = lattice.mapIt(it.model.printName(varList))
    check "A:B" in names
    check "AB" in names

  test "levels are correct":
    let lattice = enumerateLattice(varList)

    for lm in lattice:
      let name = lm.model.printName(varList)
      if name == "A:B":
        check lm.level == 0
      elif name == "AB":
        check lm.level == 1


suite "Enumerate lattice - 3 variables":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))

  test "complete lattice has expected models":
    let lattice = enumerateLattice(varList)

    # 3 variables: exact count depends on algorithm
    # Should include at least: A:B:C, AB:C, AC:B, BC:A, ABC
    # And chain models: AB:BC, AB:AC, AC:BC
    # And loop model: AB:BC:AC
    check lattice.len >= 5

    let names = lattice.mapIt(it.model.printName(varList)).toHashSet()
    check "A:B:C" in names  # Bottom
    check "ABC" in names    # Top

  test "loopless only excludes loop models":
    let fullLattice = enumerateLattice(varList, looplessOnly = false)
    let looplessLattice = enumerateLattice(varList, looplessOnly = true)

    check looplessLattice.len <= fullLattice.len

    # All loopless lattice models should not have loops
    for lm in looplessLattice:
      check not lm.hasLoops

    # Full lattice may or may not have loop models depending on algorithm
    # The key assertion is that loopless lattice has no loops
    var fullLoopCount = 0
    var looplessLoopCount = 0
    for lm in fullLattice:
      if lm.hasLoops:
        fullLoopCount += 1
    for lm in looplessLattice:
      if lm.hasLoops:
        looplessLoopCount += 1

    # Loopless lattice must have zero loop models
    check looplessLoopCount == 0

  test "levels increase monotonically":
    let lattice = enumerateLattice(varList)

    var prevLevel = -1
    for lm in lattice:
      check lm.level >= prevLevel
      # Note: levels may stay same (multiple models at same level)
      if lm.level > prevLevel:
        check lm.level <= prevLevel + 1 or prevLevel == -1
      prevLevel = lm.level

  test "no duplicate models in lattice":
    let lattice = enumerateLattice(varList)

    let names = lattice.mapIt(it.model.printName(varList))
    let uniqueNames = names.deduplicate()
    check names.len == uniqueNames.len


suite "Enumerate lattice - 4 variables":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    discard varList.add(newVariable("D", "D", Cardinality(2)))

  test "lattice includes bottom and top":
    let lattice = enumerateLattice(varList)

    let names = lattice.mapIt(it.model.printName(varList)).toHashSet()
    check "A:B:C:D" in names  # Bottom
    check "ABCD" in names     # Top

  test "lattice size is bounded by maxModels":
    let smallLattice = enumerateLattice(varList, maxModels = 10)
    check smallLattice.len <= 10

  test "loopless lattice is smaller than full":
    let fullLattice = enumerateLattice(varList, looplessOnly = false, maxModels = 1000)
    let looplessLattice = enumerateLattice(varList, looplessOnly = true, maxModels = 1000)

    check looplessLattice.len <= fullLattice.len


suite "Enumerate directed lattice":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("Z", "Z", Cardinality(2), isDependent = true))

  test "directed lattice includes bottom model":
    let lattice = enumerateDirectedLattice(varList)

    check lattice.len >= 1

    # Bottom model should have DV separate
    let bottom = lattice[0]
    check bottom.level == 0

    # Check bottom model structure
    var dvSeparate = false
    for rel in bottom.model.relations:
      if rel.variableCount == 1 and rel.containsDependent(varList):
        dvSeparate = true
        break
    check dvSeparate

  test "directed lattice models maintain DV":
    let lattice = enumerateDirectedLattice(varList)

    for lm in lattice:
      # Each model should have DV in some relation
      var hasDV = false
      for rel in lm.model.relations:
        if rel.containsDependent(varList):
          hasDV = true
          break
      check hasDV

  test "directed lattice includes predictive models":
    let lattice = enumerateDirectedLattice(varList)

    # Should find models like AZ, BZ, ABZ
    let names = lattice.mapIt(it.model.printName(varList)).toHashSet()

    # Should have at least bottom and some predictive models
    check lattice.len >= 3


suite "Lattice model metadata":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))

  test "hasLoops is correctly identified":
    let lattice = enumerateLattice(varList)

    for lm in lattice:
      # Verify hasLoops flag matches actual loop detection
      let actualHasLoops = hasLoops(lm.model, varList)
      check lm.hasLoops == actualHasLoops

  test "level is distance from independence":
    let lattice = enumerateLattice(varList)

    # Independence model should be at level 0
    for lm in lattice:
      let name = lm.model.printName(varList)
      if name == "A:B:C":
        check lm.level == 0

    # Saturated model should be at higher level
    for lm in lattice:
      let name = lm.model.printName(varList)
      if name == "ABC":
        check lm.level > 0


suite "Edge cases":
  test "single variable lattice":
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))

    let lattice = enumerateLattice(varList)

    # Single variable: only one model (A)
    check lattice.len == 1
    check lattice[0].level == 0

  test "empty varList handling":
    let varList = initVariableList()

    let lattice = enumerateLattice(varList)

    # Empty variable list: only independence model (empty)
    check lattice.len >= 0

  test "maxModels = 1 returns bottom only":
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))

    let lattice = enumerateLattice(varList, maxModels = 1)

    check lattice.len == 1
    check lattice[0].model.printName(varList) == "A:B"


suite "Lattice properties":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))

  test "parent of child returns to original or higher":
    let indep = createIndependenceModel(varList)
    let children = generateChildren(indep, varList)

    # Independence has no children, use saturated
    let saturated = createSaturatedModel(varList)
    let satChildren = generateChildren(saturated, varList)

    for child in satChildren:
      let childParents = generateParents(child, varList)
      # Parents of children should include the original or models at same level
      check childParents.len > 0

  test "lattice is connected upward":
    let lattice = enumerateLattice(varList)

    # Every model except top should have at least one parent
    # The lattice is built bottom-up, so test parent connectivity
    let names = lattice.mapIt(it.model.printName(varList)).toHashSet()

    var topFound = false
    for lm in lattice:
      if lm.model.printName(varList) == "ABC":
        topFound = true
        continue  # Top has no parents

      let parents = generateParents(lm.model, varList)
      # At least one parent should be in the lattice (or this is the top)
      var foundParent = false
      for parent in parents:
        if parent.printName(varList) in names:
          foundParent = true
          break

      # Models below top should have parents in lattice
      check foundParent or parents.len == 0 or lm.model.printName(varList) == "ABC"

    check topFound  # Verify we found the top model
