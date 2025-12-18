## Test suite for model module
## Tests Model type representing a collection of relations

import std/[algorithm, options]
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/relation
import ../src/occam/core/model

suite "Model creation":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("Alpha", "A", Cardinality(3)))
    discard varList.add(newVariable("Beta", "B", Cardinality(2)))
    discard varList.add(newVariable("Gamma", "C", Cardinality(4)))

  test "create empty model":
    let m = newModel()
    check m.relationCount == 0

  test "create model with single relation":
    let r = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let m = newModel(@[r])
    check m.relationCount == 1

  test "create model with multiple relations":
    let r1 = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let r2 = newRelation(varList, @[VariableIndex(1), VariableIndex(2)])
    let m = newModel(@[r1, r2])
    check m.relationCount == 2

suite "Model naming":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("Alpha", "A", Cardinality(3)))
    discard varList.add(newVariable("Beta", "B", Cardinality(2)))
    discard varList.add(newVariable("Gamma", "C", Cardinality(4)))

  test "print name for single relation":
    let r = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let m = newModel(@[r])
    check m.printName(varList) == "AB"

  test "print name for multiple relations":
    let r1 = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let r2 = newRelation(varList, @[VariableIndex(1), VariableIndex(2)])
    let m = newModel(@[r1, r2])
    check m.printName(varList) == "AB:BC"

  test "relations sorted in name":
    # Relations should be sorted lexicographically
    let r1 = newRelation(varList, @[VariableIndex(1), VariableIndex(2)])
    let r2 = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let m = newModel(@[r1, r2])
    check m.printName(varList) == "AB:BC"

  test "empty model name":
    let m = newModel()
    check m.printName(varList) == ""

  test "independence model (single-variable relations)":
    let rA = newRelation(varList, @[VariableIndex(0)])
    let rB = newRelation(varList, @[VariableIndex(1)])
    let rC = newRelation(varList, @[VariableIndex(2)])
    let m = newModel(@[rA, rB, rC])
    check m.printName(varList) == "A:B:C"

  test "saturated model (full relation)":
    let r = newRelation(varList, @[VariableIndex(0), VariableIndex(1), VariableIndex(2)])
    let m = newModel(@[r])
    check m.printName(varList) == "ABC"

suite "Model relation access":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(3)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(4)))

  test "access relations by index":
    let r1 = newRelation(varList, @[VariableIndex(0)])
    let r2 = newRelation(varList, @[VariableIndex(1)])
    let m = newModel(@[r1, r2])
    check m[0] == r1
    check m[1] == r2

  test "iterate over relations":
    let r1 = newRelation(varList, @[VariableIndex(0)])
    let r2 = newRelation(varList, @[VariableIndex(1)])
    let m = newModel(@[r1, r2])

    var count = 0
    for r in m:
      count += 1
    check count == 2

suite "Model containment":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(3)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(4)))

  test "containsRelation when relation is in model":
    let r = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let m = newModel(@[r])
    check m.containsRelation(r)

  test "containsRelation when subset relation exists":
    # Model has AB, checking for A
    let rAB = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let rA = newRelation(varList, @[VariableIndex(0)])
    let m = newModel(@[rAB])
    check m.containsRelation(rA)

  test "containsRelation returns false when not contained":
    let rAB = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let rC = newRelation(varList, @[VariableIndex(2)])
    let m = newModel(@[rAB])
    check not m.containsRelation(rC)

  test "containsModel for parent-child":
    # Parent: AB:C (more constrained)
    # Child: ABC (less constrained, single relation)
    let rAB = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let rC = newRelation(varList, @[VariableIndex(2)])
    let rABC = newRelation(varList, @[VariableIndex(0), VariableIndex(1), VariableIndex(2)])

    let parent = newModel(@[rAB, rC])
    let child = newModel(@[rABC])

    # The parent is "above" (more constrained than) the child in the lattice
    check parent.containsModel(child)
    check not child.containsModel(parent)

suite "Model comparison":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(3)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(4)))

  test "equal models":
    let r1 = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let r2 = newRelation(varList, @[VariableIndex(1), VariableIndex(2)])
    let m1 = newModel(@[r1, r2])
    let m2 = newModel(@[r1, r2])
    check m1 == m2

  test "equal models with different relation order":
    let r1 = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let r2 = newRelation(varList, @[VariableIndex(1), VariableIndex(2)])
    let m1 = newModel(@[r1, r2])
    let m2 = newModel(@[r2, r1])
    check m1 == m2  # Should be equal after sorting

  test "unequal models":
    let r1 = newRelation(varList, @[VariableIndex(0)])
    let r2 = newRelation(varList, @[VariableIndex(1)])
    let m1 = newModel(@[r1])
    let m2 = newModel(@[r2])
    check m1 != m2

  test "models can be sorted":
    let m1 = newModel(@[newRelation(varList, @[VariableIndex(1)])])
    let m2 = newModel(@[newRelation(varList, @[VariableIndex(0)])])
    var models = @[m1, m2]
    models.sort()
    check models[0].printName(varList) == "A"
    check models[1].printName(varList) == "B"

suite "Model variables":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(3)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(4)))
    discard varList.add(newVariable("Z", "Z", Cardinality(2), isDependent = true))

  test "all variables in model":
    let r1 = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let r2 = newRelation(varList, @[VariableIndex(1), VariableIndex(2)])
    let m = newModel(@[r1, r2])
    let vars = m.allVariables
    check vars.len == 3
    check VariableIndex(0) in vars
    check VariableIndex(1) in vars
    check VariableIndex(2) in vars

  test "model with dependent variable":
    let r1 = newRelation(varList, @[VariableIndex(0), VariableIndex(3)])
    let m = newModel(@[r1])
    check m.containsDependent(varList)

  test "model without dependent variable":
    let r1 = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let m = newModel(@[r1])
    check not m.containsDependent(varList)

suite "Model progenitor":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(3)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))

  test "default progenitor is none":
    let m = newModel()
    check m.progenitor.isNone

  test "set and get progenitor":
    let r1 = newRelation(varList, @[VariableIndex(0)])
    let r2 = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])

    var parent = newModel(@[r1])
    var child = newModel(@[r2])
    child.setProgenitor(parent)

    check child.progenitor.isSome

suite "Model ID":
  test "default ID is 0":
    let m = newModel()
    check m.id == 0

  test "set and get ID":
    var m = newModel()
    m.id = 42
    check m.id == 42

suite "Special models":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(3)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(4)))

  test "create independence model":
    let m = createIndependenceModel(varList)
    check m.relationCount == 3
    check m.printName(varList) == "A:B:C"

  test "create saturated model":
    let m = createSaturatedModel(varList)
    check m.relationCount == 1
    check m.printName(varList) == "ABC"

  test "isIndependence model check":
    let indep = createIndependenceModel(varList)
    let sat = createSaturatedModel(varList)
    check indep.isIndependenceModel(varList)
    check not sat.isIndependenceModel(varList)

  test "isSaturated model check":
    let indep = createIndependenceModel(varList)
    let sat = createSaturatedModel(varList)
    check not indep.isSaturatedModel(varList)
    check sat.isSaturatedModel(varList)


suite "Model loop detection":
  ## Tests for hasLoops function - critical for selecting IPF vs algebraic methods
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(3)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(4)))
    discard varList.add(newVariable("D", "D", Cardinality(2)))

  test "should detect no loops in independence model (A:B:C)":
    let rA = newRelation(varList, @[VariableIndex(0)])
    let rB = newRelation(varList, @[VariableIndex(1)])
    let rC = newRelation(varList, @[VariableIndex(2)])
    let m = newModel(@[rA, rB, rC])

    check not hasLoops(m, varList)

  test "should detect no loops in chain model (AB:BC:CD)":
    let rAB = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let rBC = newRelation(varList, @[VariableIndex(1), VariableIndex(2)])
    let rCD = newRelation(varList, @[VariableIndex(2), VariableIndex(3)])
    let chain = newModel(@[rAB, rBC, rCD])

    check not hasLoops(chain, varList)

  test "should detect no loops in star model (AB:AC:AD)":
    let rAB = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let rAC = newRelation(varList, @[VariableIndex(0), VariableIndex(2)])
    let rAD = newRelation(varList, @[VariableIndex(0), VariableIndex(3)])
    let star = newModel(@[rAB, rAC, rAD])

    check not hasLoops(star, varList)

  test "should detect loops in triangle model (AB:BC:AC)":
    let rAB = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let rBC = newRelation(varList, @[VariableIndex(1), VariableIndex(2)])
    let rAC = newRelation(varList, @[VariableIndex(0), VariableIndex(2)])
    let triangle = newModel(@[rAB, rBC, rAC])

    check hasLoops(triangle, varList)

  test "should detect loops in 4-cycle model (AB:BC:CD:AD)":
    let rAB = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let rBC = newRelation(varList, @[VariableIndex(1), VariableIndex(2)])
    let rCD = newRelation(varList, @[VariableIndex(2), VariableIndex(3)])
    let rAD = newRelation(varList, @[VariableIndex(0), VariableIndex(3)])
    let cycle4 = newModel(@[rAB, rBC, rCD, rAD])

    check hasLoops(cycle4, varList)

  test "should detect no loops in saturated model":
    let sat = createSaturatedModel(varList)
    check not hasLoops(sat, varList)

  test "should handle disconnected components without loops":
    # A:BC (two disconnected components)
    let rA = newRelation(varList, @[VariableIndex(0)])
    let rBC = newRelation(varList, @[VariableIndex(1), VariableIndex(2)])
    let disconnected = newModel(@[rA, rBC])

    check not hasLoops(disconnected, varList)

  test "should handle empty model":
    let empty = newModel()
    check not hasLoops(empty, varList)

  test "should handle single relation model":
    let rABC = newRelation(varList, @[VariableIndex(0), VariableIndex(1), VariableIndex(2)])
    let single = newModel(@[rABC])
    check not hasLoops(single, varList)


suite "Model edge cases":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(3)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))

  test "should handle createIndependenceModel with empty varList":
    let empty = initVariableList()
    let indep = createIndependenceModel(empty)
    check indep.relationCount == 0

  test "should handle model equality for identical models":
    let r1 = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let m1 = newModel(@[r1])
    let m2 = newModel(@[r1])
    check m1 == m2

  test "should handle model containment reflexively":
    let r1 = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let m = newModel(@[r1])
    check m.containsModel(m)

  test "should detect when model contains another in lattice":
    # In the model lattice, A:B (independence) is above AB (joint)
    # A:B "contains" AB because every constraint in AB is satisfied by A:B
    let rAB = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let rA = newRelation(varList, @[VariableIndex(0)])
    let rB = newRelation(varList, @[VariableIndex(1)])
    let mAB = newModel(@[rAB])      # Single relation: AB
    let mAindepB = newModel(@[rA, rB])  # Independence: A:B

    # A:B is above AB in the lattice (more constrained)
    check mAindepB.containsModel(mAB)
    check not mAB.containsModel(mAindepB)

