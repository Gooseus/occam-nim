## Comprehensive tests for loop detection in OCCAM models
##
## A model is "loopless" (decomposable) if it can be represented as a junction tree.
## The junction graph has relations as nodes, with edges between relations that share variables.
## A model has loops if the junction graph contains a cycle.
##
## Reference: Krippendorff (1986), Zwick (2004)

import std/[strutils, options]
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/relation
import ../src/occam/core/model


# Helper to create a model from a string like "AB:BC:AC"
proc makeModel(varList: VariableList; spec: string): Model =
  var relations: seq[Relation]
  for part in spec.split(':'):
    var indices: seq[VariableIndex]
    for c in part:
      let idx = varList.findByAbbrev($c)
      if idx.isSome:
        indices.add(idx.get)
    if indices.len > 0:
      relations.add(initRelation(indices))
  initModel(relations)


suite "Loop detection - basic cases":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    discard varList.add(newVariable("D", "D", Cardinality(2)))

  test "single relation ABC is loopless":
    let m = makeModel(varList, "ABC")
    check not hasLoops(m, varList)

  test "independence A:B:C is loopless":
    let m = makeModel(varList, "A:B:C")
    check not hasLoops(m, varList)

  test "two disconnected relations AB:CD is loopless":
    let m = makeModel(varList, "AB:CD")
    check not hasLoops(m, varList)

  test "chain AB:BC is loopless":
    let m = makeModel(varList, "AB:BC")
    check not hasLoops(m, varList)

  test "longer chain AB:BC:CD is loopless":
    let m = makeModel(varList, "AB:BC:CD")
    check not hasLoops(m, varList)

  test "star AB:AC:AD is loopless":
    let m = makeModel(varList, "AB:AC:AD")
    check not hasLoops(m, varList)

  test "triangle AB:BC:AC has loops":
    let m = makeModel(varList, "AB:BC:AC")
    check hasLoops(m, varList)

  test "square AB:BC:CD:AD has loops":
    let m = makeModel(varList, "AB:BC:CD:AD")
    check hasLoops(m, varList)


suite "Loop detection - larger models":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    discard varList.add(newVariable("D", "D", Cardinality(2)))
    discard varList.add(newVariable("E", "E", Cardinality(2)))

  test "pentagon AB:BC:CD:DE:AE has loops":
    let m = makeModel(varList, "AB:BC:CD:DE:AE")
    check hasLoops(m, varList)

  test "chain of 5 is loopless":
    let m = makeModel(varList, "AB:BC:CD:DE")
    check not hasLoops(m, varList)

  test "star from center B is loopless":
    let m = makeModel(varList, "AB:BC:BD:BE")
    check not hasLoops(m, varList)

  test "two triangles sharing edge has loops":
    # AB:BC:AC (triangle 1) and BC:CD:BD (triangle 2)
    # Together: AB:AC:BC:BD:CD - BC is shared
    let m = makeModel(varList, "AB:AC:BC:BD:CD")
    check hasLoops(m, varList)


suite "Loop detection - 3-variable relations":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    discard varList.add(newVariable("D", "D", Cardinality(2)))

  test "ABC:BCD is loopless (share BC)":
    let m = makeModel(varList, "ABC:BCD")
    check not hasLoops(m, varList)

  test "ABC:ACD is loopless (share AC)":
    let m = makeModel(varList, "ABC:ACD")
    check not hasLoops(m, varList)

  test "ABC:ABD:ACD has loops (triangle of 3-relations)":
    # Junction graph: ABC-ABD (share AB), ABD-ACD (share AD), ACD-ABC (share AC)
    # Forms a cycle
    let m = makeModel(varList, "ABC:ABD:ACD")
    check hasLoops(m, varList)

  test "ABC:BCD:CDE is loopless (chain)":
    var vl5 = initVariableList()
    discard vl5.add(newVariable("A", "A", Cardinality(2)))
    discard vl5.add(newVariable("B", "B", Cardinality(2)))
    discard vl5.add(newVariable("C", "C", Cardinality(2)))
    discard vl5.add(newVariable("D", "D", Cardinality(2)))
    discard vl5.add(newVariable("E", "E", Cardinality(2)))
    let m = makeModel(vl5, "ABC:BCD:CDE")
    check not hasLoops(m, vl5)


suite "Loop detection - mixed relation sizes":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    discard varList.add(newVariable("D", "D", Cardinality(2)))

  test "ABC:D is loopless (disconnected)":
    let m = makeModel(varList, "ABC:D")
    check not hasLoops(m, varList)

  test "ABC:CD is loopless (share C)":
    let m = makeModel(varList, "ABC:CD")
    check not hasLoops(m, varList)

  test "ABC:BD:CD has loops":
    # ABC-BD share B, ABC-CD share C, BD-CD share D
    # Triangle in junction graph
    let m = makeModel(varList, "ABC:BD:CD")
    check hasLoops(m, varList)

  test "AB:BCD is loopless (share B)":
    let m = makeModel(varList, "AB:BCD")
    check not hasLoops(m, varList)


suite "Loop detection - disconnected components":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    discard varList.add(newVariable("D", "D", Cardinality(2)))
    discard varList.add(newVariable("E", "E", Cardinality(2)))
    discard varList.add(newVariable("F", "F", Cardinality(2)))

  test "AB:CD:EF is loopless (3 disconnected)":
    let m = makeModel(varList, "AB:CD:EF")
    check not hasLoops(m, varList)

  test "AB:BC:DE:EF is loopless (two chains)":
    let m = makeModel(varList, "AB:BC:DE:EF")
    check not hasLoops(m, varList)

  test "AB:BC:AC:DE is loop (triangle + disconnected)":
    # Triangle in ABC, plus disconnected DE
    let m = makeModel(varList, "AB:BC:AC:DE")
    check hasLoops(m, varList)


suite "Loop detection - duplicate pairs":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))

  test "AB:ABC has duplicate pair (A,B) - is this a loop?":
    # The pair (A,B) appears in both AB and ABC
    # Junction graph: AB-ABC (share A,B) - just one edge, no cycle
    # But duplicate pairs violate the decomposability condition
    let m = makeModel(varList, "AB:ABC")
    # Note: In OCCAM, this would typically be simplified to just ABC
    # But if we have it, the duplicate pair should be flagged
    check hasLoops(m, varList)


suite "Loop detection - edge cases":
  test "empty model has no loops":
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    let m = initModel(@[])
    check not hasLoops(m, varList)

  test "single variable A has no loops":
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    let m = makeModel(varList, "A")
    check not hasLoops(m, varList)


suite "Loop detection - directed system models":
  # In directed systems, the bottom model has IVs together and DV separate
  # Moving up adds IVs to predict the DV

  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    discard varList.add(newVariable("Z", "Z", Cardinality(2), isDependent = true))

  test "ABC:Z is loopless (bottom model)":
    let m = makeModel(varList, "ABC:Z")
    check not hasLoops(m, varList)

  test "BC:AZ is loopless (A predicts Z)":
    let m = makeModel(varList, "BC:AZ")
    check not hasLoops(m, varList)

  test "C:ABZ is loopless (A,B predict Z)":
    let m = makeModel(varList, "C:ABZ")
    check not hasLoops(m, varList)

  test "ABCZ is loopless (saturated)":
    let m = makeModel(varList, "ABCZ")
    check not hasLoops(m, varList)

  test "AB:AZ:BZ has loops (both predict Z via different paths)":
    # This would violate SPC (single predictive component)
    let m = makeModel(varList, "AB:AZ:BZ")
    check hasLoops(m, varList)
