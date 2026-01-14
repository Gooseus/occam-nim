## Test suite for relation module
## Tests Relation type representing subsets of variables

import std/algorithm
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/relation

suite "Relation creation":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("Alpha", "A", Cardinality(3)))
    discard varList.add(initVariable("Beta", "B", Cardinality(2)))
    discard varList.add(initVariable("Gamma", "C", Cardinality(4)))

  test "create empty relation":
    let r = initRelation(@[])
    check r.variableCount == 0
    check r.printName(varList) == ""

  test "create relation with single variable":
    let r = initRelation(@[VariableIndex(1)])
    check r.variableCount == 1
    check r.hasVariable(VariableIndex(1))
    check not r.hasVariable(VariableIndex(0))

  test "create relation with multiple variables":
    let r = initRelation(@[VariableIndex(0), VariableIndex(2)])
    check r.variableCount == 2
    check r.hasVariable(VariableIndex(0))
    check r.hasVariable(VariableIndex(2))
    check not r.hasVariable(VariableIndex(1))

  test "variables are sorted":
    # Add in reverse order
    let r = initRelation(@[VariableIndex(2), VariableIndex(0), VariableIndex(1)])
    let vars = r.variables
    check vars[0] == VariableIndex(0)
    check vars[1] == VariableIndex(1)
    check vars[2] == VariableIndex(2)

suite "Relation naming":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("Alpha", "A", Cardinality(3)))
    discard varList.add(initVariable("Beta", "B", Cardinality(2)))
    discard varList.add(initVariable("Gamma", "C", Cardinality(4)))

  test "print name from abbreviations":
    let r = initRelation(@[VariableIndex(0), VariableIndex(2)])
    check r.printName(varList) == "AC"

  test "print name order matches sorted variables":
    let r = initRelation(@[VariableIndex(2), VariableIndex(0)])
    check r.printName(varList) == "AC"  # Should be sorted

  test "full relation name":
    let r = initRelation(@[VariableIndex(0), VariableIndex(1), VariableIndex(2)])
    check r.printName(varList) == "ABC"

suite "Relation cardinality":
  setup:
    var varList = initVariableList()
    # A: 3 values, B: 2 values, C: 4 values
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(4)))

  test "NC for single variable":
    let r = initRelation(@[VariableIndex(0)])
    check r.nc(varList) == 3

  test "NC for two variables":
    let r = initRelation(@[VariableIndex(0), VariableIndex(1)])
    check r.nc(varList) == 6  # 3 * 2

  test "NC for all variables":
    let r = initRelation(@[VariableIndex(0), VariableIndex(1), VariableIndex(2)])
    check r.nc(varList) == 24  # 3 * 2 * 4

  test "NC for empty relation":
    let r = initRelation(@[])
    check r.nc(varList) == 1  # Empty product is 1

suite "Relation comparison":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(4)))

  test "equal relations":
    let r1 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let r2 = initRelation(@[VariableIndex(1), VariableIndex(0)])  # Same, different order
    check r1 == r2

  test "unequal relations":
    let r1 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let r2 = initRelation(@[VariableIndex(0), VariableIndex(2)])
    check r1 != r2

  test "subset detection":
    let r1 = initRelation(@[VariableIndex(0)])
    let r2 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    check r1.isSubsetOf(r2)
    check not r2.isSubsetOf(r1)

  test "proper subset":
    let r1 = initRelation(@[VariableIndex(0)])
    let r2 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    check r1.isProperSubsetOf(r2)
    check not r2.isProperSubsetOf(r1)

  test "equal relations are not proper subsets":
    let r1 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let r2 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    check r1.isSubsetOf(r2)
    check not r1.isProperSubsetOf(r2)

  test "overlap detection":
    let r1 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let r2 = initRelation(@[VariableIndex(1), VariableIndex(2)])
    check r1.overlaps(r2)

  test "no overlap":
    let r1 = initRelation(@[VariableIndex(0)])
    let r2 = initRelation(@[VariableIndex(2)])
    check not r1.overlaps(r2)

suite "Relation degrees of freedom":
  setup:
    var varList = initVariableList()
    # A: 3 values, B: 2 values, C: 4 values
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(4)))

  test "df for single variable":
    # DF = (card - 1)
    let r = initRelation(@[VariableIndex(0)])
    check r.degreesOfFreedom(varList) == 2  # 3 - 1

  test "df for two variables":
    # DF = (card1 - 1) * (card2 - 1) + (card1 - 1) + (card2 - 1) = card1*card2 - 1
    # For independent variables: NC - 1
    let r = initRelation(@[VariableIndex(0), VariableIndex(1)])
    check r.degreesOfFreedom(varList) == 5  # 3*2 - 1

  test "df for all variables":
    let r = initRelation(@[VariableIndex(0), VariableIndex(1), VariableIndex(2)])
    check r.degreesOfFreedom(varList) == 23  # 3*2*4 - 1

  test "df for empty relation":
    let r = initRelation(@[])
    check r.degreesOfFreedom(varList) == 0

suite "Relation mask":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(4)))
    discard varList.add(initVariable("B", "B", Cardinality(4)))
    discard varList.add(initVariable("C", "C", Cardinality(4)))

  test "mask has zeros for included variables":
    let r = initRelation(@[VariableIndex(0), VariableIndex(2)])
    let mask = r.buildMask(varList)

    let vA = varList[VariableIndex(0)]
    let vB = varList[VariableIndex(1)]
    let vC = varList[VariableIndex(2)]

    # A and C should have 0s in mask
    check (mask[0] and vA.mask) == KeySegment(0)
    check (mask[0] and vC.mask) == KeySegment(0)
    # B should have 1s (DontCare)
    check (mask[0] and vB.mask) == vB.mask

suite "Relation set operations":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(4)))
    discard varList.add(initVariable("D", "D", Cardinality(2)))

  test "union of relations":
    let r1 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let r2 = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let u = r1.union(r2)
    check u.variableCount == 3
    check u.hasVariable(VariableIndex(0))
    check u.hasVariable(VariableIndex(1))
    check u.hasVariable(VariableIndex(2))

  test "intersection of relations":
    let r1 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let r2 = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let i = r1.intersection(r2)
    check i.variableCount == 1
    check i.hasVariable(VariableIndex(1))

  test "intersection of disjoint relations":
    let r1 = initRelation(@[VariableIndex(0)])
    let r2 = initRelation(@[VariableIndex(2)])
    let i = r1.intersection(r2)
    check i.variableCount == 0

  test "difference of relations":
    let r1 = initRelation(@[VariableIndex(0), VariableIndex(1), VariableIndex(2)])
    let r2 = initRelation(@[VariableIndex(1)])
    let d = r1.difference(r2)
    check d.variableCount == 2
    check d.hasVariable(VariableIndex(0))
    check d.hasVariable(VariableIndex(2))
    check not d.hasVariable(VariableIndex(1))

suite "Relation ordering":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(4)))

  test "lexicographic comparison":
    let r1 = initRelation(@[VariableIndex(0)])
    let r2 = initRelation(@[VariableIndex(1)])
    check r1 < r2

  test "longer relation is greater when prefix matches":
    let r1 = initRelation(@[VariableIndex(0)])
    let r2 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    check r1 < r2

  test "can sort relations":
    var relations = @[
      initRelation(@[VariableIndex(2)]),
      initRelation(@[VariableIndex(0)]),
      initRelation(@[VariableIndex(1)])
    ]
    relations.sort()
    check relations[0].printName(varList) == "A"
    check relations[1].printName(varList) == "B"
    check relations[2].printName(varList) == "C"

suite "Relation with dependent variable":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("Z", "Z", Cardinality(2), isDependent = true))

  test "detect if contains dependent":
    let r1 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let r2 = initRelation(@[VariableIndex(0), VariableIndex(2)])
    check not r1.containsDependent(varList)
    check r2.containsDependent(varList)

  test "independent only relation":
    let r1 = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let r2 = initRelation(@[VariableIndex(2)])
    check r1.isIndependentOnly(varList)
    check not r2.isIndependentOnly(varList)


suite "Relation edge cases":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(4)))

  test "should handle empty relation":
    let r = initRelation(@[])
    check r.variableCount == 0
    check r.printName(varList) == ""

  test "should handle empty relation set operations":
    let empty = initRelation(@[])
    let r = initRelation(@[VariableIndex(0)])

    # Union with empty
    let u = empty.union(r)
    check u.variableCount == 1
    check u.hasVariable(VariableIndex(0))

    # Intersection with empty
    let i = empty.intersection(r)
    check i.variableCount == 0

    # Difference with empty
    let d = r.difference(empty)
    check d.variableCount == 1

  test "should handle self-intersection":
    let r = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let i = r.intersection(r)
    check i.variableCount == r.variableCount
    check i.hasVariable(VariableIndex(0))
    check i.hasVariable(VariableIndex(1))

  test "should handle self-union":
    let r = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let u = r.union(r)
    check u.variableCount == r.variableCount

  test "should handle self-difference":
    let r = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let d = r.difference(r)
    check d.variableCount == 0

  test "should handle single variable relation":
    let r = initRelation(@[VariableIndex(1)])
    check r.variableCount == 1
    check r.printName(varList) == "B"
    check r.hasVariable(VariableIndex(1))
    check not r.hasVariable(VariableIndex(0))

  test "should handle full relation (all variables)":
    let r = initRelation(@[VariableIndex(0), VariableIndex(1), VariableIndex(2)])
    check r.variableCount == 3
    check r.printName(varList) == "ABC"

  test "should handle duplicate variables in constructor":
    # Adding same variable twice - currently no dedupe, just sorts
    let r = initRelation(@[VariableIndex(0), VariableIndex(0), VariableIndex(1)])
    # Note: newRelation doesn't dedupe, it just sorts
    check r.variableCount == 3  # Contains duplicates
    check r.hasVariable(VariableIndex(0))
    check r.hasVariable(VariableIndex(1))

  test "should sort variables regardless of input order":
    let r1 = initRelation(@[VariableIndex(2), VariableIndex(0), VariableIndex(1)])
    let r2 = initRelation(@[VariableIndex(0), VariableIndex(1), VariableIndex(2)])
    check r1 == r2
    check r1.printName(varList) == "ABC"

  test "should handle relation equality with empty relations":
    let e1 = initRelation(@[])
    let e2 = initRelation(@[])
    check e1 == e2

  test "should handle relation subset with empty":
    let empty = initRelation(@[])
    let r = initRelation(@[VariableIndex(0)])

    # Empty is subset of everything
    check empty.isSubsetOf(r)
    check empty.isSubsetOf(empty)

    # Non-empty is not subset of empty
    check not r.isSubsetOf(empty)

  test "should handle containsVariable with empty relation":
    let empty = initRelation(@[])
    check not empty.containsVariable(VariableIndex(0))
    check not empty.containsVariable(VariableIndex(1))
    check not empty.containsVariable(VariableIndex(2))

