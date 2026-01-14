## Test suite for chain search algorithm
## Tests chain model detection and chain generation

import std/[tables, algorithm, sequtils]
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/manager/vb
import ../src/occam/search/chain


suite "Chain model detection":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))
    discard varList.add(initVariable("D", "D", Cardinality(2)))

  test "model AB:BC is a chain":
    # Linear chain: A-B-C
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let m = initModel(@[rAB, rBC])
    check isChainModel(m)

  test "model AB:BC:CD is a chain":
    # Linear chain: A-B-C-D
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let rCD = initRelation(@[VariableIndex(2), VariableIndex(3)])
    let m = initModel(@[rAB, rBC, rCD])
    check isChainModel(m)

  test "model AC:CB:BD is a chain":
    # Linear chain: A-C-B-D
    let rAC = initRelation(@[VariableIndex(0), VariableIndex(2)])
    let rCB = initRelation(@[VariableIndex(2), VariableIndex(1)])
    let rBD = initRelation(@[VariableIndex(1), VariableIndex(3)])
    let m = initModel(@[rAC, rCB, rBD])
    check isChainModel(m)

  test "model AB:CD is NOT a chain (disconnected)":
    # Two separate components, not connected
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rCD = initRelation(@[VariableIndex(2), VariableIndex(3)])
    let m = initModel(@[rAB, rCD])
    check not isChainModel(m)

  test "model AB:BC:AC is NOT a chain (has cycle)":
    # Triangle - forms a cycle
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let rAC = initRelation(@[VariableIndex(0), VariableIndex(2)])
    let m = initModel(@[rAB, rBC, rAC])
    check not isChainModel(m)

  test "model ABC is NOT a chain (not binary)":
    # Single 3-variable relation
    let rABC = initRelation(@[VariableIndex(0), VariableIndex(1), VariableIndex(2)])
    let m = initModel(@[rABC])
    check not isChainModel(m)

  test "model AB:AC IS a chain (path B-A-C)":
    # AB:AC forms path B-A-C, which is a valid chain
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rAC = initRelation(@[VariableIndex(0), VariableIndex(2)])
    let m = initModel(@[rAB, rAC])
    check isChainModel(m)

  test "model AB:AC:AD is NOT a chain (true star pattern)":
    # True star with A at center - A has 3 neighbors
    var varList5 = initVariableList()
    discard varList5.add(initVariable("A", "A", Cardinality(2)))
    discard varList5.add(initVariable("B", "B", Cardinality(2)))
    discard varList5.add(initVariable("C", "C", Cardinality(2)))
    discard varList5.add(initVariable("D", "D", Cardinality(2)))

    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rAC = initRelation(@[VariableIndex(0), VariableIndex(2)])
    let rAD = initRelation(@[VariableIndex(0), VariableIndex(3)])
    let m = initModel(@[rAB, rAC, rAD])
    check not isChainModel(m)

  test "single binary relation is a chain":
    # AB by itself is technically a valid chain
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let m = initModel(@[rAB])
    check isChainModel(m)


suite "Chain generation":
  setup:
    var varList3 = initVariableList()
    discard varList3.add(initVariable("A", "A", Cardinality(2)))
    discard varList3.add(initVariable("B", "B", Cardinality(2)))
    discard varList3.add(initVariable("C", "C", Cardinality(2)))

    var varList4 = initVariableList()
    discard varList4.add(initVariable("A", "A", Cardinality(2)))
    discard varList4.add(initVariable("B", "B", Cardinality(2)))
    discard varList4.add(initVariable("C", "C", Cardinality(2)))
    discard varList4.add(initVariable("D", "D", Cardinality(2)))

  test "generate all chains for 3 variables":
    let chains = generateAllChains(varList3)

    # For 3 variables, there are 3!/2 = 3 unique chains
    # A-B-C, A-C-B, B-A-C (but A-B-C == C-B-A, etc.)
    check chains.len == 3

    for chain in chains:
      check isChainModel(chain)

  test "generate all chains for 4 variables":
    let chains = generateAllChains(varList4)

    # For 4 variables, there are 4!/2 = 12 unique chains
    check chains.len == 12

    for chain in chains:
      check isChainModel(chain)

  test "all generated chains are unique":
    let chains = generateAllChains(varList4)

    var names: seq[string]
    for chain in chains:
      let name = chain.printName(varList4)
      check name notin names
      names.add(name)

  test "generated chains are always loopless":
    let chains = generateAllChains(varList4)

    for chain in chains:
      check not hasLoops(chain, varList4)


suite "Chain search with statistics":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

    # Create data with chain structure A-B-C
    var inputTable = initContingencyTable(varList.keySize, 8)
    for a in 0..<2:
      for b in 0..<2:
        for c in 0..<2:
          var k = initKey(varList.keySize)
          k.setValue(varList, VariableIndex(0), a)
          k.setValue(varList, VariableIndex(1), b)
          k.setValue(varList, VariableIndex(2), c)
          # Create pattern where A-B and B-C are related but A-C are independent given B
          let count = if a == b and b == c: 40.0 elif a == b or b == c: 15.0 else: 5.0
          inputTable.add(k, count)
    inputTable.sort()

  test "can compute statistics for all chains":
    var mgr = initVBManager(varList, inputTable)
    let chains = generateAllChains(varList)

    for chain in chains:
      let df = mgr.computeDF(chain)
      let h = mgr.computeH(chain)
      check df > 0
      check h > 0.0

  test "all chains have same DF":
    var mgr = initVBManager(varList, inputTable)
    let chains = generateAllChains(varList)

    # All chain models of same length have same DF
    let firstDf = mgr.computeDF(chains[0])
    for chain in chains:
      check mgr.computeDF(chain) == firstDf


suite "Chain search edge cases":
  test "single variable - no chains":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))

    let chains = generateAllChains(varList)
    check chains.len == 0

  test "two variables - one chain":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))

    let chains = generateAllChains(varList)
    check chains.len == 1
    check isChainModel(chains[0])

  test "five variables - 60 chains":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))
    discard varList.add(initVariable("D", "D", Cardinality(2)))
    discard varList.add(initVariable("E", "E", Cardinality(2)))

    let chains = generateAllChains(varList)
    # 5!/2 = 60 unique chains
    check chains.len == 60
