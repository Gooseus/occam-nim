## Tests for graph algorithms used in loop detection
##
## These tests verify that the graph-based loop detection produces
## identical results to the original RIP-based implementation.

import std/[strutils, options, sets]
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/core/graph


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


# Helper to get relations from a model spec
proc makeRelations(varList: VariableList; spec: string): seq[Relation] =
  for part in spec.split(':'):
    var indices: seq[VariableIndex]
    for c in part:
      let idx = varList.findByAbbrev($c)
      if idx.isSome:
        indices.add(idx.get)
    if indices.len > 0:
      result.add(initRelation(indices))


suite "Graph - basic operations":
  test "create empty graph":
    let g = initGraph(5)
    check g.nodeCount == 5
    check g.degree(0) == 0
    check g.degree(4) == 0

  test "add edges":
    var g = initGraph(4)
    g.addEdge(0, 1)
    g.addEdge(1, 2)
    g.addEdge(2, 3)
    check g.hasEdge(0, 1)
    check g.hasEdge(1, 0)  # Undirected
    check g.hasEdge(1, 2)
    check not g.hasEdge(0, 2)
    check g.degree(1) == 2

  test "self-loops are ignored":
    var g = initGraph(3)
    g.addEdge(0, 0)
    check g.degree(0) == 0


suite "Graph - Maximum Cardinality Search":
  test "MCS on empty graph":
    let g = initGraph(0)
    let ordering = maximumCardinalitySearch(g)
    check ordering.len == 0

  test "MCS on single node":
    let g = initGraph(1)
    let ordering = maximumCardinalitySearch(g)
    check ordering == @[0]

  test "MCS on path graph":
    # 0 -- 1 -- 2 -- 3
    var g = initGraph(4)
    g.addEdge(0, 1)
    g.addEdge(1, 2)
    g.addEdge(2, 3)
    let ordering = maximumCardinalitySearch(g)
    check ordering.len == 4
    # MCS should visit all nodes
    var visited: set[int16]
    for n in ordering:
      visited.incl(int16(n))
    check visited == {0'i16, 1, 2, 3}

  test "MCS on complete graph K4":
    # Complete graph is chordal
    var g = initGraph(4)
    for i in 0..<4:
      for j in (i+1)..<4:
        g.addEdge(i, j)
    let ordering = maximumCardinalitySearch(g)
    check ordering.len == 4


suite "Graph - Chordality testing":
  test "empty graph is chordal":
    let g = initGraph(0)
    check isChordal(g)

  test "single node is chordal":
    let g = initGraph(1)
    check isChordal(g)

  test "path is chordal":
    # 0 -- 1 -- 2 -- 3
    var g = initGraph(4)
    g.addEdge(0, 1)
    g.addEdge(1, 2)
    g.addEdge(2, 3)
    check isChordal(g)

  test "triangle is chordal":
    # 0 -- 1
    # |  / |
    # 2    (triangle 0-1-2)
    var g = initGraph(3)
    g.addEdge(0, 1)
    g.addEdge(1, 2)
    g.addEdge(0, 2)
    check isChordal(g)

  test "4-cycle (square) is NOT chordal":
    # 0 -- 1
    # |    |
    # 3 -- 2
    var g = initGraph(4)
    g.addEdge(0, 1)
    g.addEdge(1, 2)
    g.addEdge(2, 3)
    g.addEdge(3, 0)
    check not isChordal(g)

  test "4-cycle with chord is chordal":
    # 0 -- 1
    # | \  |
    # 3 -- 2
    var g = initGraph(4)
    g.addEdge(0, 1)
    g.addEdge(1, 2)
    g.addEdge(2, 3)
    g.addEdge(3, 0)
    g.addEdge(0, 2)  # chord
    check isChordal(g)

  test "complete graph K5 is chordal":
    var g = initGraph(5)
    for i in 0..<5:
      for j in (i+1)..<5:
        g.addEdge(i, j)
    check isChordal(g)


suite "Graph - Intersection graph construction":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))
    discard varList.add(initVariable("D", "D", Cardinality(2)))

  test "disconnected relations have no edges":
    let rels = makeRelations(varList, "AB:CD")
    let ig = buildIntersectionGraph(rels)
    check ig.graph.nodeCount == 2
    check ig.graph.degree(0) == 0
    check ig.graph.degree(1) == 0

  test "chain relations form path":
    let rels = makeRelations(varList, "AB:BC:CD")
    let ig = buildIntersectionGraph(rels)
    check ig.graph.nodeCount == 3
    check ig.graph.hasEdge(0, 1)  # AB-BC share B
    check ig.graph.hasEdge(1, 2)  # BC-CD share C
    check not ig.graph.hasEdge(0, 2)  # AB-CD don't share

  test "triangle relations form triangle":
    let rels = makeRelations(varList, "AB:BC:AC")
    let ig = buildIntersectionGraph(rels)
    check ig.graph.nodeCount == 3
    check ig.graph.hasEdge(0, 1)  # AB-BC share B
    check ig.graph.hasEdge(1, 2)  # BC-AC share C
    check ig.graph.hasEdge(0, 2)  # AB-AC share A


suite "Graph - Equivalence with hasLoops (basic cases)":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))
    discard varList.add(initVariable("D", "D", Cardinality(2)))

  test "single relation ABC":
    let m = makeModel(varList, "ABC")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult

  test "independence A:B:C":
    let m = makeModel(varList, "A:B:C")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult

  test "disconnected AB:CD":
    let m = makeModel(varList, "AB:CD")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult

  test "chain AB:BC":
    let m = makeModel(varList, "AB:BC")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult

  test "longer chain AB:BC:CD":
    let m = makeModel(varList, "AB:BC:CD")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult

  test "star AB:AC:AD":
    let m = makeModel(varList, "AB:AC:AD")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult

  test "triangle AB:BC:AC has loops":
    let m = makeModel(varList, "AB:BC:AC")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check graphResult  # Has loops

  test "square AB:BC:CD:AD has loops":
    let m = makeModel(varList, "AB:BC:CD:AD")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check graphResult  # Has loops


suite "Graph - Equivalence with hasLoops (larger models)":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))
    discard varList.add(initVariable("D", "D", Cardinality(2)))
    discard varList.add(initVariable("E", "E", Cardinality(2)))

  test "pentagon has loops":
    let m = makeModel(varList, "AB:BC:CD:DE:AE")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check graphResult

  test "chain of 5 is loopless":
    let m = makeModel(varList, "AB:BC:CD:DE")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult

  test "star from center B is loopless":
    let m = makeModel(varList, "AB:BC:BD:BE")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult

  test "two triangles sharing edge has loops":
    let m = makeModel(varList, "AB:AC:BC:BD:CD")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check graphResult


suite "Graph - Equivalence with hasLoops (3-variable relations)":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))
    discard varList.add(initVariable("D", "D", Cardinality(2)))
    discard varList.add(initVariable("E", "E", Cardinality(2)))

  test "ABC:BCD is loopless":
    let m = makeModel(varList, "ABC:BCD")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult

  test "ABC:ACD is loopless":
    let m = makeModel(varList, "ABC:ACD")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult

  test "ABC:ABD:ACD has loops":
    let m = makeModel(varList, "ABC:ABD:ACD")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check graphResult

  test "ABC:BCD:CDE is loopless":
    let m = makeModel(varList, "ABC:BCD:CDE")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult


suite "Graph - Equivalence with hasLoops (mixed sizes)":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))
    discard varList.add(initVariable("D", "D", Cardinality(2)))

  test "ABC:D is loopless":
    let m = makeModel(varList, "ABC:D")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult

  test "ABC:CD is loopless":
    let m = makeModel(varList, "ABC:CD")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult

  test "ABC:BD:CD has loops":
    let m = makeModel(varList, "ABC:BD:CD")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check graphResult

  test "AB:BCD is loopless":
    let m = makeModel(varList, "AB:BCD")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult


suite "Graph - Equivalence with hasLoops (disconnected)":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))
    discard varList.add(initVariable("D", "D", Cardinality(2)))
    discard varList.add(initVariable("E", "E", Cardinality(2)))
    discard varList.add(initVariable("F", "F", Cardinality(2)))

  test "AB:CD:EF is loopless":
    let m = makeModel(varList, "AB:CD:EF")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult

  test "AB:BC:DE:EF is loopless":
    let m = makeModel(varList, "AB:BC:DE:EF")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult

  test "AB:BC:AC:DE has loops":
    let m = makeModel(varList, "AB:BC:AC:DE")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check graphResult


suite "Graph - Equivalence with hasLoops (redundant relations)":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

  test "AB:ABC has redundant relation":
    let m = makeModel(varList, "AB:ABC")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check graphResult  # Redundant = loop


suite "Graph - Equivalence with hasLoops (edge cases)":
  test "empty model":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    let m = initModel(@[])
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult

  test "single variable A":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    let m = makeModel(varList, "A")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult


suite "Graph - Equivalence with hasLoops (directed systems)":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))
    discard varList.add(initVariable("Z", "Z", Cardinality(2), isDependent = true))

  test "ABC:Z is loopless":
    let m = makeModel(varList, "ABC:Z")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult

  test "BC:AZ is loopless":
    let m = makeModel(varList, "BC:AZ")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult

  test "C:ABZ is loopless":
    let m = makeModel(varList, "C:ABZ")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult

  test "ABCZ is loopless":
    let m = makeModel(varList, "ABCZ")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check not graphResult

  test "AB:AZ:BZ has loops":
    let m = makeModel(varList, "AB:AZ:BZ")
    let graphResult = hasLoopsViaGraph(m.relations)
    let origResult = hasLoops(m, varList)
    check graphResult == origResult
    check graphResult


suite "Graph - findRIPOrdering":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))
    discard varList.add(initVariable("D", "D", Cardinality(2)))

  test "loopless model has RIP ordering":
    let rels = makeRelations(varList, "AB:BC:CD")
    let ordering = findRIPOrdering(rels)
    check ordering.isSome
    check ordering.get.len == 3

  test "loop model has no RIP ordering":
    let rels = makeRelations(varList, "AB:BC:AC")
    let ordering = findRIPOrdering(rels)
    check ordering.isNone
