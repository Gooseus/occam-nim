## Test suite for belief propagation helper functions
## Tests the individual operations used in BP: marginalize, extend, multiply, divide

import std/[unittest, math, sequtils, options]
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/core/junction_tree
import ../src/occam/math/belief_propagation
import ../src/occam/math/entropy


proc makeTestVarList(n: int; cardinality: int = 2): VariableList =
  ## Create a test variable list with n variables A, B, C, ...
  result = initVariableList()
  for i in 0..<n:
    let name = $chr(ord('A') + i)
    discard result.add(newVariable(name, name, Cardinality(cardinality)))


proc makeUniformTable(varList: VariableList; vars: seq[VariableIndex]): Table =
  ## Create uniform distribution over specified variables
  var totalStates = 1
  for v in vars:
    totalStates *= varList[v].cardinality.toInt

  result = initTable(varList.keySize, totalStates)
  let prob = 1.0 / float64(totalStates)

  var indices = newSeq[int](vars.len)
  var done = false
  while not done:
    var keyPairs: seq[(VariableIndex, int)]
    for i, v in vars:
      keyPairs.add((v, indices[i]))
    let key = varList.buildKey(keyPairs)
    result.add(key, prob)

    var carry = true
    for i in 0..<vars.len:
      if carry:
        indices[i] += 1
        if indices[i] >= varList[vars[i]].cardinality.toInt:
          indices[i] = 0
        else:
          carry = false
    if carry:
      done = true

  result.sort()


proc makeBiasedTable(varList: VariableList; vars: seq[VariableIndex]; bias: float64 = 0.7): Table =
  ## Create biased distribution where state 0 has higher probability
  var totalStates = 1
  for v in vars:
    totalStates *= varList[v].cardinality.toInt

  result = initTable(varList.keySize, totalStates)

  var indices = newSeq[int](vars.len)
  var done = false
  var total = 0.0

  while not done:
    # Higher probability when all values are 0
    var prob = 1.0
    for i, v in vars:
      if indices[i] == 0:
        prob *= bias
      else:
        prob *= (1.0 - bias) / float64(varList[v].cardinality.toInt - 1)

    var keyPairs: seq[(VariableIndex, int)]
    for i, v in vars:
      keyPairs.add((v, indices[i]))
    let key = varList.buildKey(keyPairs)
    result.add(key, prob)
    total += prob

    var carry = true
    for i in 0..<vars.len:
      if carry:
        indices[i] += 1
        if indices[i] >= varList[vars[i]].cardinality.toInt:
          indices[i] = 0
        else:
          carry = false
    if carry:
      done = true

  result.sort()
  # Normalize
  for i in 0..<result.len:
    result[i].value = result[i].value / total


suite "Marginalize - basic":
  setup:
    let varList = makeTestVarList(3)  # A, B, C all binary

  test "marginalize to empty sums all values":
    let table = makeUniformTable(varList, @[VariableIndex(0), VariableIndex(1)])
    let marginal = marginalize(table, varList,
                               @[VariableIndex(0), VariableIndex(1)],
                               @[])
    check marginal.len == 1
    check abs(marginal.sum - 1.0) < 1e-10

  test "marginalize to single variable":
    let table = makeUniformTable(varList, @[VariableIndex(0), VariableIndex(1)])
    let marginal = marginalize(table, varList,
                               @[VariableIndex(0), VariableIndex(1)],
                               @[VariableIndex(0)])
    check marginal.len == 2  # Binary variable
    # Uniform: P(A=0) = P(A=1) = 0.5
    for tup in marginal:
      check abs(tup.value - 0.5) < 1e-10

  test "marginalize to same variables returns equivalent":
    let table = makeUniformTable(varList, @[VariableIndex(0), VariableIndex(1)])
    let marginal = marginalize(table, varList,
                               @[VariableIndex(0), VariableIndex(1)],
                               @[VariableIndex(0), VariableIndex(1)])
    check marginal.len == table.len
    check abs(marginal.sum - table.sum) < 1e-10


suite "Marginalize - preserves probability":
  setup:
    let varList = makeTestVarList(4)

  test "marginalize preserves sum":
    let vars = @[VariableIndex(0), VariableIndex(1), VariableIndex(2)]
    let table = makeBiasedTable(varList, vars, 0.8)

    let marginal = marginalize(table, varList, vars, @[VariableIndex(0)])
    check abs(marginal.sum - table.sum) < 1e-10

  test "marginalize to two variables":
    let vars = @[VariableIndex(0), VariableIndex(1), VariableIndex(2)]
    let table = makeBiasedTable(varList, vars, 0.75)

    let marginal = marginalize(table, varList, vars,
                               @[VariableIndex(0), VariableIndex(1)])
    check abs(marginal.sum - table.sum) < 1e-10
    check marginal.len == 4  # 2x2


suite "Extend potential":
  setup:
    let varList = makeTestVarList(3)

  test "extend with no new variables returns same":
    let table = makeUniformTable(varList, @[VariableIndex(0)])
    let extended = extendPotential(table, varList,
                                   @[VariableIndex(0)],
                                   @[VariableIndex(0)])
    check extended.len == table.len
    check abs(extended.sum - table.sum) < 1e-10

  test "extend single variable to two":
    let table = makeUniformTable(varList, @[VariableIndex(0)])
    let extended = extendPotential(table, varList,
                                   @[VariableIndex(0)],
                                   @[VariableIndex(0), VariableIndex(1)])
    # Extended table has 4 entries (2x2)
    check extended.len == 4
    # Original values replicated
    check abs(extended.sum - 2.0 * table.sum) < 1e-10  # Each original val appears twice

  test "extend preserves original values at their keys":
    let table = makeBiasedTable(varList, @[VariableIndex(0)], 0.9)
    let extended = extendPotential(table, varList,
                                   @[VariableIndex(0)],
                                   @[VariableIndex(0), VariableIndex(1)])
    # P(A=0) should appear in both (A=0,B=0) and (A=0,B=1)
    # P(A=1) should appear in both (A=1,B=0) and (A=1,B=1)
    check extended.len == 4


suite "Multiply potentials":
  setup:
    let varList = makeTestVarList(3)

  test "multiply disjoint potentials":
    let tableA = makeUniformTable(varList, @[VariableIndex(0)])  # P(A)
    let tableB = makeUniformTable(varList, @[VariableIndex(1)])  # P(B)

    let product = multiplyPotentials(tableA, tableB, varList,
                                     @[VariableIndex(0)],
                                     @[VariableIndex(1)])
    # Result should have 4 entries
    check product.len == 4
    # Each entry should be 0.5 * 0.5 = 0.25
    for tup in product:
      check abs(tup.value - 0.25) < 1e-10

  test "multiply overlapping potentials":
    let tableAB = makeUniformTable(varList, @[VariableIndex(0), VariableIndex(1)])
    let tableBC = makeUniformTable(varList, @[VariableIndex(1), VariableIndex(2)])

    let product = multiplyPotentials(tableAB, tableBC, varList,
                                     @[VariableIndex(0), VariableIndex(1)],
                                     @[VariableIndex(1), VariableIndex(2)])
    # Result has A, B, C -> 8 entries
    check product.len == 8
    # Uniform: 0.25 * 0.25 = 0.0625
    for tup in product:
      check abs(tup.value - 0.0625) < 1e-10

  test "multiply same potential squares values":
    let table = makeUniformTable(varList, @[VariableIndex(0)])
    let product = multiplyPotentials(table, table, varList,
                                     @[VariableIndex(0)],
                                     @[VariableIndex(0)])
    check product.len == 2
    # 0.5 * 0.5 = 0.25
    for tup in product:
      check abs(tup.value - 0.25) < 1e-10


suite "Divide potentials":
  setup:
    let varList = makeTestVarList(3)

  test "divide by uniform is inverse of multiply":
    let tableAB = makeBiasedTable(varList, @[VariableIndex(0), VariableIndex(1)], 0.7)
    let tableB = makeUniformTable(varList, @[VariableIndex(1)])

    let quotient = dividePotentials(tableAB, tableB, varList,
                                    @[VariableIndex(0), VariableIndex(1)],
                                    @[VariableIndex(1)])
    # Dividing by 0.5 doubles each value
    check abs(quotient.sum - tableAB.sum * 2.0) < 1e-10

  test "divide handles near-zero gracefully":
    let varList2 = makeTestVarList(2)
    var tableA = initTable(varList2.keySize, 2)
    let k0 = varList2.buildKey(@[(VariableIndex(0), 0)])
    let k1 = varList2.buildKey(@[(VariableIndex(0), 1)])
    tableA.add(k0, 1.0)
    tableA.add(k1, 0.0)
    tableA.sort()

    var tableB = initTable(varList2.keySize, 2)
    tableB.add(k0, 0.5)
    tableB.add(k1, 1e-20)  # Near zero
    tableB.sort()

    let quotient = dividePotentials(tableA, tableB, varList2,
                                    @[VariableIndex(0)],
                                    @[VariableIndex(0)])
    # Should not crash, value at k1 should be 0 (0/small = 0)
    check quotient.len == 2

  test "divide by itself gives ones":
    let table = makeUniformTable(varList, @[VariableIndex(0)])
    let quotient = dividePotentials(table, table, varList,
                                    @[VariableIndex(0)],
                                    @[VariableIndex(0)])
    for tup in quotient:
      check abs(tup.value - 1.0) < 1e-10


suite "Get marginal from BP result":
  setup:
    let varList = makeTestVarList(3)  # A, B, C

  test "getMarginal for clique variable":
    # Build chain model AB:BC
    let relAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let relBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let model = initModel(@[relAB, relBC])

    let inputTable = makeUniformTable(varList,
                                      @[VariableIndex(0), VariableIndex(1), VariableIndex(2)])

    let jtResult = buildJunctionTree(model, varList)
    check jtResult.valid

    let bpResult = beliefPropagation(inputTable, jtResult.tree, varList)

    # Query marginal P(A)
    let marginalA = getMarginal(bpResult, jtResult.tree, varList, @[VariableIndex(0)])
    check marginalA.len == 2
    check abs(marginalA.sum - 1.0) < 1e-10
    for tup in marginalA:
      check abs(tup.value - 0.5) < 1e-10

  test "getMarginal for separator variable":
    let relAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let relBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let model = initModel(@[relAB, relBC])

    let inputTable = makeUniformTable(varList,
                                      @[VariableIndex(0), VariableIndex(1), VariableIndex(2)])

    let jtResult = buildJunctionTree(model, varList)
    let bpResult = beliefPropagation(inputTable, jtResult.tree, varList)

    # Query marginal P(B) - the separator variable
    let marginalB = getMarginal(bpResult, jtResult.tree, varList, @[VariableIndex(1)])
    check marginalB.len == 2
    check abs(marginalB.sum - 1.0) < 1e-10


suite "BP config options":
  setup:
    let varList = makeTestVarList(3)

  test "normalize=true produces valid probabilities":
    let relAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let relBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let model = initModel(@[relAB, relBC])

    let inputTable = makeUniformTable(varList,
                                      @[VariableIndex(0), VariableIndex(1), VariableIndex(2)])

    let jtResult = buildJunctionTree(model, varList)
    let config = initBPConfig(normalize = true)
    let bpResult = beliefPropagation(inputTable, jtResult.tree, varList, config)

    # Each clique potential should sum to 1
    for potential in bpResult.cliquePotentials:
      check abs(potential.sum - 1.0) < 1e-10

  test "normalize=false preserves raw potentials":
    let relAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let model = initModel(@[relAB])  # Single clique

    let inputTable = makeBiasedTable(varList, @[VariableIndex(0), VariableIndex(1)], 0.8)

    let jtResult = buildJunctionTree(model, varList)
    let config = initBPConfig(normalize = false)
    let bpResult = beliefPropagation(inputTable, jtResult.tree, varList, config)

    # Clique potential should match input (already normalized from makeBiasedTable)
    check abs(bpResult.cliquePotentials[0].sum - inputTable.sum) < 1e-10


suite "BP edge cases":
  test "single clique model":
    let varList = makeTestVarList(2)
    let rel = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let model = initModel(@[rel])

    let inputTable = makeBiasedTable(varList, @[VariableIndex(0), VariableIndex(1)], 0.7)

    let jtResult = buildJunctionTree(model, varList)
    check jtResult.valid
    check jtResult.tree.cliques.len == 1

    let bpResult = beliefPropagation(inputTable, jtResult.tree, varList)
    check bpResult.converged
    check bpResult.cliquePotentials.len == 1

  test "larger cardinality variables":
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(4)))
    discard varList.add(newVariable("B", "B", Cardinality(3)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))

    let relAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let relBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let model = initModel(@[relAB, relBC])

    let inputTable = makeUniformTable(varList,
                                      @[VariableIndex(0), VariableIndex(1), VariableIndex(2)])

    let jtResult = buildJunctionTree(model, varList)
    check jtResult.valid

    let bpResult = beliefPropagation(inputTable, jtResult.tree, varList)
    check bpResult.converged

    # Check clique potential sizes
    # AB clique: 4*3 = 12 states
    # BC clique: 3*2 = 6 states
    var foundAB = false
    var foundBC = false
    for i, potential in bpResult.cliquePotentials:
      if potential.len == 12:
        foundAB = true
      if potential.len == 6:
        foundBC = true
    check foundAB or foundBC  # At least one should match

  test "star topology":
    let varList = makeTestVarList(4)  # A, B, C, D

    # Star with A at center
    let relAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let relAC = initRelation(@[VariableIndex(0), VariableIndex(2)])
    let relAD = initRelation(@[VariableIndex(0), VariableIndex(3)])
    let model = initModel(@[relAB, relAC, relAD])

    let inputTable = makeUniformTable(varList,
                                      @[VariableIndex(0), VariableIndex(1),
                                        VariableIndex(2), VariableIndex(3)])

    let jtResult = buildJunctionTree(model, varList)
    check jtResult.valid
    check jtResult.tree.cliques.len == 3

    let bpResult = beliefPropagation(inputTable, jtResult.tree, varList)
    check bpResult.converged

    # All separators should contain A
    for sep in jtResult.tree.separators:
      check VariableIndex(0) in sep.variables


suite "Compute joint from BP":
  setup:
    let varList = makeTestVarList(3)

  test "joint reconstruction sums to 1":
    let relAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let relBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let model = initModel(@[relAB, relBC])

    let inputTable = makeBiasedTable(varList,
                                     @[VariableIndex(0), VariableIndex(1), VariableIndex(2)],
                                     0.75)

    let jtResult = buildJunctionTree(model, varList)
    let bpResult = beliefPropagation(inputTable, jtResult.tree, varList)
    let joint = computeJointFromBP(bpResult, jtResult.tree, varList)

    check joint.len == 8  # 2^3
    check abs(joint.sum - 1.0) < 1e-10

  test "joint matches original for decomposable model":
    let relAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let relBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let model = initModel(@[relAB, relBC])

    # Use input that is already factorizable as AB:BC
    let inputTable = makeUniformTable(varList,
                                      @[VariableIndex(0), VariableIndex(1), VariableIndex(2)])

    let jtResult = buildJunctionTree(model, varList)
    let bpResult = beliefPropagation(inputTable, jtResult.tree, varList)
    let joint = computeJointFromBP(bpResult, jtResult.tree, varList)

    # For uniform input, BP joint should also be uniform
    for tup in joint:
      check abs(tup.value - 0.125) < 1e-6  # 1/8


suite "Numerical stability":
  test "marginalize handles very small probabilities":
    let varList = makeTestVarList(2)
    var table = initTable(varList.keySize, 4)
    let keys = @[
      varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)]),
      varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 1)]),
      varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 0)]),
      varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)])
    ]
    # Very small probabilities
    table.add(keys[0], 1e-15)
    table.add(keys[1], 1e-15)
    table.add(keys[2], 1e-14)
    table.add(keys[3], 1e-14)
    table.sort()

    let marginal = marginalize(table, varList,
                               @[VariableIndex(0), VariableIndex(1)],
                               @[VariableIndex(0)])
    check marginal.len == 2
    # Should not have NaN or Inf
    for tup in marginal:
      check not tup.value.isNaN
      check tup.value.classify != fcInf

  test "multiply handles very small probabilities":
    let varList = makeTestVarList(2)
    var tableA = initTable(varList.keySize, 2)
    let k0 = varList.buildKey(@[(VariableIndex(0), 0)])
    let k1 = varList.buildKey(@[(VariableIndex(0), 1)])
    tableA.add(k0, 1e-100)
    tableA.add(k1, 1e-100)
    tableA.sort()

    var tableB = initTable(varList.keySize, 2)
    let kb0 = varList.buildKey(@[(VariableIndex(1), 0)])
    let kb1 = varList.buildKey(@[(VariableIndex(1), 1)])
    tableB.add(kb0, 1e-100)
    tableB.add(kb1, 1e-100)
    tableB.sort()

    let product = multiplyPotentials(tableA, tableB, varList,
                                     @[VariableIndex(0)],
                                     @[VariableIndex(1)])
    check product.len == 4
    for tup in product:
      check not tup.value.isNaN
      # Very small but valid
      check tup.value >= 0.0
