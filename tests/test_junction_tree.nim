## Tests for Junction Tree and Belief Propagation
##
## Verifies:
## 1. Junction tree construction from decomposable models
## 2. Belief propagation produces correct marginals
## 3. BP results match IPF results for decomposable models

import std/[unittest, math, sequtils, options]
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/core/junction_tree
import ../src/occam/math/belief_propagation
import ../src/occam/math/ipf
import ../src/occam/math/entropy


proc makeTestVarList(n: int): VariableList =
  ## Create a test variable list with n binary variables A, B, C, ...
  result = initVariableList()
  for i in 0..<n:
    let name = $chr(ord('A') + i)
    discard result.add(newVariable(name, name, Cardinality(2)))


proc makeUniformTable(varList: VariableList): Table =
  ## Create uniform distribution over all variables
  let n = varList.len
  var totalStates = 1
  for i in 0..<n:
    totalStates *= varList[VariableIndex(i)].cardinality.toInt

  result = initContingencyTable(varList.keySize, totalStates)
  let prob = 1.0 / float64(totalStates)

  var indices = newSeq[int](n)
  var done = false
  while not done:
    var keyPairs: seq[(VariableIndex, int)]
    for i in 0..<n:
      keyPairs.add((VariableIndex(i), indices[i]))
    let key = varList.buildKey(keyPairs)
    result.add(key, prob)

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


proc makeChainData(varList: VariableList; strength: float64 = 0.8): Table =
  ## Create data with chain dependency structure A-B-C-...
  ## Higher strength = stronger dependency between neighbors
  let n = varList.len
  var totalStates = 1
  for i in 0..<n:
    totalStates *= varList[VariableIndex(i)].cardinality.toInt

  result = initContingencyTable(varList.keySize, totalStates)

  var indices = newSeq[int](n)
  var done = false
  while not done:
    # Compute probability based on chain structure
    var prob = 1.0 / 2.0  # P(A)

    for i in 1..<n:
      # P(Xi | Xi-1): higher probability when values match
      if indices[i] == indices[i-1]:
        prob *= strength
      else:
        prob *= (1.0 - strength)

    var keyPairs: seq[(VariableIndex, int)]
    for i in 0..<n:
      keyPairs.add((VariableIndex(i), indices[i]))
    let key = varList.buildKey(keyPairs)
    result.add(key, prob)

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
  result.normalize()


suite "Junction Tree Construction":
  test "single clique is valid junction tree":
    let varList = makeTestVarList(3)  # A, B, C
    let rel = initRelation(@[VariableIndex(0), VariableIndex(1), VariableIndex(2)])
    let model = initModel(@[rel])

    let jtResult = buildJunctionTree(model, varList)

    check jtResult.valid
    check jtResult.tree.cliques.len == 1
    check jtResult.tree.separators.len == 0

  test "chain model AB:BC is valid junction tree":
    let varList = makeTestVarList(3)  # A, B, C
    let relAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let relBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let model = initModel(@[relAB, relBC])

    let jtResult = buildJunctionTree(model, varList)

    check jtResult.valid
    check jtResult.tree.cliques.len == 2
    check jtResult.tree.separators.len == 1
    # Separator should be B
    check jtResult.tree.separators[0].variables.len == 1
    check jtResult.tree.separators[0].variables[0] == VariableIndex(1)

  test "chain model AB:BC:CD is valid junction tree":
    let varList = makeTestVarList(4)  # A, B, C, D
    let relAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let relBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let relCD = initRelation(@[VariableIndex(2), VariableIndex(3)])
    let model = initModel(@[relAB, relBC, relCD])

    let jtResult = buildJunctionTree(model, varList)

    check jtResult.valid
    check jtResult.tree.cliques.len == 3
    check jtResult.tree.separators.len == 2

  test "star model AB:AC:AD is valid junction tree":
    let varList = makeTestVarList(4)  # A, B, C, D
    let relAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let relAC = initRelation(@[VariableIndex(0), VariableIndex(2)])
    let relAD = initRelation(@[VariableIndex(0), VariableIndex(3)])
    let model = initModel(@[relAB, relAC, relAD])

    let jtResult = buildJunctionTree(model, varList)

    check jtResult.valid
    check jtResult.tree.cliques.len == 3
    check jtResult.tree.separators.len == 2
    # All separators should contain A
    for sep in jtResult.tree.separators:
      check VariableIndex(0) in sep.variables

  test "tree traversal orders":
    let varList = makeTestVarList(4)
    let relAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let relBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let relCD = initRelation(@[VariableIndex(2), VariableIndex(3)])
    let model = initModel(@[relAB, relBC, relCD])

    let jtResult = buildJunctionTree(model, varList)
    check jtResult.valid

    let postOrd = jtResult.tree.postOrder()
    let preOrd = jtResult.tree.preOrder()

    # Both should contain all cliques
    check postOrd.len == 3
    check preOrd.len == 3

    # Root should be last in post-order, first in pre-order
    check postOrd[^1] == jtResult.tree.root
    check preOrd[0] == jtResult.tree.root


suite "Belief Propagation - Basic":
  test "BP on single clique equals input marginal":
    let varList = makeTestVarList(2)  # A, B
    let inputTable = makeChainData(varList, 0.8)

    let rel = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let model = initModel(@[rel])

    let jtResult = buildJunctionTree(model, varList)
    check jtResult.valid

    let bpResult = beliefPropagation(inputTable, jtResult.tree, varList)

    # Single clique should match input
    check bpResult.cliquePotentials.len == 1

    let bpMarginal = bpResult.cliquePotentials[0]
    for tup in inputTable:
      let idx = bpMarginal.find(tup.key)
      check idx.isSome
      check abs(bpMarginal[idx.get].value - tup.value) < 1e-10

  test "BP on chain preserves marginals":
    let varList = makeTestVarList(3)  # A, B, C
    let inputTable = makeChainData(varList, 0.7)

    let relAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let relBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let model = initModel(@[relAB, relBC])

    let jtResult = buildJunctionTree(model, varList)
    check jtResult.valid

    let bpResult = beliefPropagation(inputTable, jtResult.tree, varList)

    # Check that AB marginal is preserved
    let inputAB = inputTable.project(varList, @[VariableIndex(0), VariableIndex(1)])

    # Find clique containing AB
    for i, clique in jtResult.tree.cliques:
      if clique.containsVariable(VariableIndex(0)) and
         clique.containsVariable(VariableIndex(1)):
        let bpAB = bpResult.cliquePotentials[i]
        for tup in inputAB:
          let idx = bpAB.find(tup.key)
          check idx.isSome
          check abs(bpAB[idx.get].value - tup.value) < 1e-6


suite "BP vs IPF Equivalence":
  test "chain model AB:BC - BP equals IPF":
    let varList = makeTestVarList(3)
    let inputTable = makeChainData(varList, 0.75)

    let relAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let relBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let model = initModel(@[relAB, relBC])

    # Run IPF
    let ipfResult = ipf.ipf(inputTable, @[relAB, relBC], varList)
    check ipfResult.converged

    # Run BP
    let jtResult = buildJunctionTree(model, varList)
    check jtResult.valid
    let bpResult = beliefPropagation(inputTable, jtResult.tree, varList)

    # Compute joint from BP
    let bpJoint = computeJointFromBP(bpResult, jtResult.tree, varList)

    # Compare IPF and BP results
    for ipfTup in ipfResult.fitTable:
      let bpIdx = bpJoint.find(ipfTup.key)
      if ipfTup.value > 1e-10:
        check bpIdx.isSome
        let diff = abs(bpJoint[bpIdx.get].value - ipfTup.value)
        check diff < 1e-6

  test "star model AB:AC:AD - BP equals IPF":
    let varList = makeTestVarList(4)
    let inputTable = makeUniformTable(varList)

    let relAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let relAC = initRelation(@[VariableIndex(0), VariableIndex(2)])
    let relAD = initRelation(@[VariableIndex(0), VariableIndex(3)])
    let model = initModel(@[relAB, relAC, relAD])

    # Run IPF
    let ipfResult = ipf.ipf(inputTable, @[relAB, relAC, relAD], varList)
    check ipfResult.converged

    # Run BP
    let jtResult = buildJunctionTree(model, varList)
    check jtResult.valid
    let bpResult = beliefPropagation(inputTable, jtResult.tree, varList)
    let bpJoint = computeJointFromBP(bpResult, jtResult.tree, varList)

    # Compare entropies
    let ipfH = entropy(ipfResult.fitTable)
    let bpH = entropy(bpJoint)
    check abs(ipfH - bpH) < 1e-6

  test "longer chain AB:BC:CD:DE - BP equals IPF":
    let varList = makeTestVarList(5)
    let inputTable = makeChainData(varList, 0.65)

    let relAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let relBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let relCD = initRelation(@[VariableIndex(2), VariableIndex(3)])
    let relDE = initRelation(@[VariableIndex(3), VariableIndex(4)])
    let rels = @[relAB, relBC, relCD, relDE]
    let model = initModel(rels)

    # Run IPF
    let ipfResult = ipf.ipf(inputTable, rels, varList)
    check ipfResult.converged

    # Run BP
    let jtResult = buildJunctionTree(model, varList)
    check jtResult.valid
    let bpResult = beliefPropagation(inputTable, jtResult.tree, varList)
    let bpJoint = computeJointFromBP(bpResult, jtResult.tree, varList)

    # Compare entropies
    let ipfH = entropy(ipfResult.fitTable)
    let bpH = entropy(bpJoint)
    echo "IPF entropy: ", ipfH
    echo "BP entropy: ", bpH
    check abs(ipfH - bpH) < 1e-5


suite "Entropy from Junction Tree":
  test "entropy matches inclusion-exclusion formula":
    let varList = makeTestVarList(3)
    let inputTable = makeChainData(varList, 0.8)

    let relAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let relBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let model = initModel(@[relAB, relBC])

    # Build junction tree
    let jtResult = buildJunctionTree(model, varList)
    check jtResult.valid

    # Compute entropy using inclusion-exclusion: H = Σ H(cliques) - Σ H(separators)
    var sumCliqueH = 0.0
    for clique in jtResult.tree.cliques:
      let marginal = inputTable.project(varList, clique.varIndices)
      sumCliqueH += entropy(marginal)

    var sumSepH = 0.0
    for sep in jtResult.tree.separators:
      if sep.variables.len > 0:
        let marginal = inputTable.project(varList, sep.variables)
        sumSepH += entropy(marginal)

    let inclusionExclusionH = sumCliqueH - sumSepH

    # Compare with entropy of BP joint
    let bpResult = beliefPropagation(inputTable, jtResult.tree, varList)
    let bpJoint = computeJointFromBP(bpResult, jtResult.tree, varList)
    let bpH = entropy(bpJoint)

    echo "Inclusion-exclusion H: ", inclusionExclusionH
    echo "BP joint H: ", bpH

    check abs(inclusionExclusionH - bpH) < 1e-6
