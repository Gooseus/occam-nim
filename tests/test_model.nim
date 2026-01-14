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
    discard varList.add(initVariable("Alpha", "A", Cardinality(3)))
    discard varList.add(initVariable("Beta", "B", Cardinality(2)))
    discard varList.add(initVariable("Gamma", "C", Cardinality(4)))

  test "create empty model":
    let m = initModel()
    check m.relationCount == 0

  test "create model with single relation":
    let r = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let m = initModel(@[r])
    check m.relationCount == 1

  test "create model with multiple relations":
    let r1 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let r2 = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let m = initModel(@[r1, r2])
    check m.relationCount == 2

suite "Model naming":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("Alpha", "A", Cardinality(3)))
    discard varList.add(initVariable("Beta", "B", Cardinality(2)))
    discard varList.add(initVariable("Gamma", "C", Cardinality(4)))

  test "print name for single relation":
    let r = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let m = initModel(@[r])
    check m.printName(varList) == "AB"

  test "print name for multiple relations":
    let r1 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let r2 = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let m = initModel(@[r1, r2])
    check m.printName(varList) == "AB:BC"

  test "relations sorted in name":
    # Relations should be sorted lexicographically
    let r1 = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let r2 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let m = initModel(@[r1, r2])
    check m.printName(varList) == "AB:BC"

  test "empty model name":
    let m = initModel()
    check m.printName(varList) == ""

  test "independence model (single-variable relations)":
    let rA = initRelation(@[VariableIndex(0)])
    let rB = initRelation(@[VariableIndex(1)])
    let rC = initRelation(@[VariableIndex(2)])
    let m = initModel(@[rA, rB, rC])
    check m.printName(varList) == "A:B:C"

  test "saturated model (full relation)":
    let r = initRelation(@[VariableIndex(0), VariableIndex(1), VariableIndex(2)])
    let m = initModel(@[r])
    check m.printName(varList) == "ABC"

suite "Model relation access":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(4)))

  test "access relations by index":
    let r1 = initRelation(@[VariableIndex(0)])
    let r2 = initRelation(@[VariableIndex(1)])
    let m = initModel(@[r1, r2])
    check m[0] == r1
    check m[1] == r2

  test "iterate over relations":
    let r1 = initRelation(@[VariableIndex(0)])
    let r2 = initRelation(@[VariableIndex(1)])
    let m = initModel(@[r1, r2])

    var count = 0
    for r in m:
      count += 1
    check count == 2

suite "Model containment":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(4)))

  test "containsRelation when relation is in model":
    let r = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let m = initModel(@[r])
    check m.containsRelation(r)

  test "containsRelation when subset relation exists":
    # Model has AB, checking for A
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rA = initRelation(@[VariableIndex(0)])
    let m = initModel(@[rAB])
    check m.containsRelation(rA)

  test "containsRelation returns false when not contained":
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rC = initRelation(@[VariableIndex(2)])
    let m = initModel(@[rAB])
    check not m.containsRelation(rC)

  test "containsModel for parent-child":
    # Parent: AB:C (more constrained)
    # Child: ABC (less constrained, single relation)
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rC = initRelation(@[VariableIndex(2)])
    let rABC = initRelation(@[VariableIndex(0), VariableIndex(1), VariableIndex(2)])

    let parent = initModel(@[rAB, rC])
    let child = initModel(@[rABC])

    # The parent is "above" (more constrained than) the child in the lattice
    check parent.containsModel(child)
    check not child.containsModel(parent)

suite "Model comparison":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(4)))

  test "equal models":
    let r1 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let r2 = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let m1 = initModel(@[r1, r2])
    let m2 = initModel(@[r1, r2])
    check m1 == m2

  test "equal models with different relation order":
    let r1 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let r2 = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let m1 = initModel(@[r1, r2])
    let m2 = initModel(@[r2, r1])
    check m1 == m2  # Should be equal after sorting

  test "unequal models":
    let r1 = initRelation(@[VariableIndex(0)])
    let r2 = initRelation(@[VariableIndex(1)])
    let m1 = initModel(@[r1])
    let m2 = initModel(@[r2])
    check m1 != m2

  test "models can be sorted":
    let m1 = initModel(@[initRelation(@[VariableIndex(1)])])
    let m2 = initModel(@[initRelation(@[VariableIndex(0)])])
    var models = @[m1, m2]
    models.sort()
    check models[0].printName(varList) == "A"
    check models[1].printName(varList) == "B"

suite "Model variables":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(4)))
    discard varList.add(initVariable("Z", "Z", Cardinality(2), isDependent = true))

  test "all variables in model":
    let r1 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let r2 = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let m = initModel(@[r1, r2])
    let vars = m.allVariables
    check vars.len == 3
    check VariableIndex(0) in vars
    check VariableIndex(1) in vars
    check VariableIndex(2) in vars

  test "model with dependent variable":
    let r1 = initRelation(@[VariableIndex(0), VariableIndex(3)])
    let m = initModel(@[r1])
    check m.containsDependent(varList)

  test "model without dependent variable":
    let r1 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let m = initModel(@[r1])
    check not m.containsDependent(varList)

suite "Model progenitor":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))

  test "default progenitor is none":
    let m = initModel()
    check m.progenitor.isNone

  test "set and get progenitor":
    let r1 = initRelation(@[VariableIndex(0)])
    let r2 = initRelation(@[VariableIndex(0), VariableIndex(1)])

    var parent = initModel(@[r1])
    var child = initModel(@[r2])
    child.setProgenitor(parent)

    check child.progenitor.isSome

suite "Model ID":
  test "default ID is 0":
    let m = initModel()
    check m.id == 0

  test "set and get ID":
    var m = initModel()
    m.id = 42
    check m.id == 42

suite "Special models":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(4)))

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
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(4)))
    discard varList.add(initVariable("D", "D", Cardinality(2)))

  test "should detect no loops in independence model (A:B:C)":
    let rA = initRelation(@[VariableIndex(0)])
    let rB = initRelation(@[VariableIndex(1)])
    let rC = initRelation(@[VariableIndex(2)])
    let m = initModel(@[rA, rB, rC])

    check not hasLoops(m, varList)

  test "should detect no loops in chain model (AB:BC:CD)":
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let rCD = initRelation(@[VariableIndex(2), VariableIndex(3)])
    let chain = initModel(@[rAB, rBC, rCD])

    check not hasLoops(chain, varList)

  test "should detect no loops in star model (AB:AC:AD)":
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rAC = initRelation(@[VariableIndex(0), VariableIndex(2)])
    let rAD = initRelation(@[VariableIndex(0), VariableIndex(3)])
    let star = initModel(@[rAB, rAC, rAD])

    check not hasLoops(star, varList)

  test "should detect loops in triangle model (AB:BC:AC)":
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let rAC = initRelation(@[VariableIndex(0), VariableIndex(2)])
    let triangle = initModel(@[rAB, rBC, rAC])

    check hasLoops(triangle, varList)

  test "should detect loops in 4-cycle model (AB:BC:CD:AD)":
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let rCD = initRelation(@[VariableIndex(2), VariableIndex(3)])
    let rAD = initRelation(@[VariableIndex(0), VariableIndex(3)])
    let cycle4 = initModel(@[rAB, rBC, rCD, rAD])

    check hasLoops(cycle4, varList)

  test "should detect no loops in saturated model":
    let sat = createSaturatedModel(varList)
    check not hasLoops(sat, varList)

  test "should handle disconnected components without loops":
    # A:BC (two disconnected components)
    let rA = initRelation(@[VariableIndex(0)])
    let rBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let disconnected = initModel(@[rA, rBC])

    check not hasLoops(disconnected, varList)

  test "should handle empty model":
    let empty = initModel()
    check not hasLoops(empty, varList)

  test "should handle single relation model":
    let rABC = initRelation(@[VariableIndex(0), VariableIndex(1), VariableIndex(2)])
    let single = initModel(@[rABC])
    check not hasLoops(single, varList)


suite "Model edge cases":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))

  test "should handle createIndependenceModel with empty varList":
    let empty = initVariableList()
    let indep = createIndependenceModel(empty)
    check indep.relationCount == 0

  test "should handle model equality for identical models":
    let r1 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let m1 = initModel(@[r1])
    let m2 = initModel(@[r1])
    check m1 == m2

  test "should handle model containment reflexively":
    let r1 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let m = initModel(@[r1])
    check m.containsModel(m)

  test "should detect when model contains another in lattice":
    # In the model lattice, A:B (independence) is above AB (joint)
    # A:B "contains" AB because every constraint in AB is satisfied by A:B
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rA = initRelation(@[VariableIndex(0)])
    let rB = initRelation(@[VariableIndex(1)])
    let mAB = initModel(@[rAB])      # Single relation: AB
    let mAindepB = initModel(@[rA, rB])  # Independence: A:B

    # A:B is above AB in the lattice (more constrained)
    check mAindepB.containsModel(mAB)
    check not mAB.containsModel(mAindepB)

