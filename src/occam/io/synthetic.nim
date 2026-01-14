## Synthetic data generator for OCCAM testing
## Generates data from known graphical model structures

{.push raises: [].}

import std/[random, math, sequtils, strutils, options]
import std/tables as stdtables
import ../core/types
import ../core/variable
import ../core/key
import ../core/table as coretable
import ../core/relation
import ../core/model
import ../core/iterators

type
  ConditionalTable* = object
    ## P(child | parents) stored as nested table
    ## Key: parent state tuple, Value: distribution over child states
    probs: stdtables.Table[seq[int], seq[float64]]
    childCard: int

  GraphicalModel* = object
    ## Defines dependency structure for data generation
    ## Each variable has optional parents and a conditional distribution
    varList*: VariableList
    conditionals: seq[ConditionalTable]  # P(V_i | parents(V_i))
    parents: seq[seq[VariableIndex]]     # Parent indices for each variable


proc initConditionalTable*(childCard: int): ConditionalTable =
  result.probs = stdtables.initTable[seq[int], seq[float64]]()
  result.childCard = childCard


proc setProb*(ct: var ConditionalTable; parentStates: seq[int]; childDist: seq[float64]) =
  ## Set P(child | parent states) distribution
  assert childDist.len == ct.childCard
  ct.probs[parentStates] = childDist


proc getProb*(ct: ConditionalTable; parentStates: seq[int]): seq[float64] =
  ## Get distribution over child given parent states
  if parentStates in ct.probs:
    try:
      ct.probs[parentStates]
    except KeyError:
      # Uniform if lookup fails
      newSeqWith(ct.childCard, 1.0 / float64(ct.childCard))
  else:
    # Uniform if not specified
    newSeqWith(ct.childCard, 1.0 / float64(ct.childCard))


proc sample*(ct: ConditionalTable; parentStates: seq[int]): int =
  ## Sample from P(child | parent states)
  let dist = ct.getProb(parentStates)
  let r = rand(1.0)
  var cumulative = 0.0
  for i, p in dist:
    cumulative += p
    if r <= cumulative:
      return i
  return dist.len - 1


proc initGraphicalModel*(varList: VariableList): GraphicalModel =
  result.varList = varList
  result.conditionals = newSeq[ConditionalTable](varList.len)
  result.parents = newSeq[seq[VariableIndex]](varList.len)

  # Initialize each variable with no parents (uniform marginal)
  for i in 0..<varList.len:
    result.conditionals[i] = initConditionalTable(varList[VariableIndex(i)].cardinality.toInt)
    result.parents[i] = @[]


proc setParents*(gm: var GraphicalModel; child: VariableIndex; parentIndices: seq[VariableIndex]) =
  ## Set parent variables for a child variable
  gm.parents[child.toInt] = parentIndices


proc setConditional*(gm: var GraphicalModel; child: VariableIndex;
                     parentStates: seq[int]; childDist: seq[float64]) =
  ## Set P(child | parent states)
  gm.conditionals[child.toInt].setProb(parentStates, childDist)


proc sampleOne*(gm: GraphicalModel): seq[int] =
  ## Generate one sample from the graphical model
  ## Variables must be in topological order (parents before children)
  result = newSeq[int](gm.varList.len)

  for i in 0..<gm.varList.len:
    let parentIndices = gm.parents[i]
    var parentStates: seq[int]
    for pIdx in parentIndices:
      parentStates.add(result[pIdx.toInt])
    result[i] = gm.conditionals[i].sample(parentStates)


proc generateSamples*(gm: GraphicalModel; n: int): seq[seq[int]] =
  ## Generate n samples from the model
  result = newSeq[seq[int]](n)
  for i in 0..<n:
    result[i] = gm.sampleOne()


proc samplesToTable*(gm: GraphicalModel; samples: seq[seq[int]]): coretable.ContingencyTable =
  ## Convert samples to a count table
  var counts = stdtables.initTable[seq[int], float64]()

  for sample in samples:
    if sample in counts:
      try:
        counts[sample] += 1.0
      except KeyError:
        counts[sample] = 1.0
    else:
      counts[sample] = 1.0

  result = coretable.initTable(gm.varList.keySize, counts.len)

  for state, count in counts:
    var k = initKey(gm.varList.keySize)
    for i, val in state:
      k.setValue(gm.varList, VariableIndex(i), val)
    result.add(k, count)

  result.sort()


# ============ Convenience functions for common structures ============

proc createIndependentModel*(varList: VariableList): GraphicalModel =
  ## Create a model where all variables are independent
  ## Each variable has uniform distribution
  result = initGraphicalModel(varList)
  # Default initialization already gives uniform marginals with no parents


proc createChainModel*(varList: VariableList; transitionStrength: float64 = 0.8): GraphicalModel =
  ## Create a Markov chain: V0 → V1 → V2 → ... → Vn
  ## True OCCAM model: V0V1:V1V2:V2V3:...
  ## transitionStrength controls how strongly each variable depends on its parent
  ## 1.0 = deterministic, 0.5 = uniform (no dependence)
  result = initGraphicalModel(varList)

  # First variable has uniform distribution (no parents)
  let card0 = varList[VariableIndex(0)].cardinality.toInt
  result.setConditional(VariableIndex(0), @[], newSeqWith(card0, 1.0 / float64(card0)))

  # Each subsequent variable depends on the previous one
  for i in 1..<varList.len:
    result.setParents(VariableIndex(i), @[VariableIndex(i-1)])

    let parentCard = varList[VariableIndex(i-1)].cardinality.toInt
    let childCard = varList[VariableIndex(i)].cardinality.toInt

    # For each parent state, create a distribution that favors same value
    for p in 0..<parentCard:
      var dist = newSeq[float64](childCard)
      for c in 0..<childCard:
        if c == p mod childCard:
          dist[c] = transitionStrength
        else:
          dist[c] = (1.0 - transitionStrength) / float64(childCard - 1)
      result.setConditional(VariableIndex(i), @[p], dist)


proc createStarModel*(varList: VariableList; centerIdx: VariableIndex;
                      dependenceStrength: float64 = 0.8): GraphicalModel =
  ## Create a star model where one variable is the center and all others depend on it
  ## True OCCAM model: CV0:CV1:CV2:... (where C is center)
  result = initGraphicalModel(varList)

  # Center variable has uniform distribution
  let centerCard = varList[centerIdx].cardinality.toInt
  result.setConditional(centerIdx, @[], newSeqWith(centerCard, 1.0 / float64(centerCard)))

  # All other variables depend on center
  for i in 0..<varList.len:
    if VariableIndex(i) != centerIdx:
      result.setParents(VariableIndex(i), @[centerIdx])

      let childCard = varList[VariableIndex(i)].cardinality.toInt

      for p in 0..<centerCard:
        var dist = newSeq[float64](childCard)
        for c in 0..<childCard:
          if c == p mod childCard:
            dist[c] = dependenceStrength
          else:
            dist[c] = (1.0 - dependenceStrength) / float64(childCard - 1)
        result.setConditional(VariableIndex(i), @[p], dist)


proc createFullyConnectedModel*(varList: VariableList;
                                interactionStrength: float64 = 0.7): GraphicalModel =
  ## Create a model where each variable depends on all previous variables
  ## True OCCAM model: V0V1V2...Vn (saturated)
  result = initGraphicalModel(varList)

  # First variable is uniform
  let card0 = varList[VariableIndex(0)].cardinality.toInt
  result.setConditional(VariableIndex(0), @[], newSeqWith(card0, 1.0 / float64(card0)))

  # Each variable depends on all previous
  for i in 1..<varList.len:
    var parentIndices: seq[VariableIndex]
    for j in 0..<i:
      parentIndices.add(VariableIndex(j))
    result.setParents(VariableIndex(i), parentIndices)

    # Generate conditional distributions for all parent combinations
    # This is exponential but fine for small examples
    let childCard = varList[VariableIndex(i)].cardinality.toInt

    proc generateParentStates(idx: int; current: seq[int];
                              gm: var GraphicalModel; childIdx: int;
                              childCard: int; strength: float64) =
      if idx >= parentIndices.len:
        # Generate distribution based on sum of parent values
        let parentSum = current.foldl(a + b, 0)
        var dist = newSeq[float64](childCard)
        for c in 0..<childCard:
          if c == parentSum mod childCard:
            dist[c] = strength
          else:
            dist[c] = (1.0 - strength) / float64(childCard - 1)
        gm.setConditional(VariableIndex(childIdx), current, dist)
      else:
        let pCard = varList[parentIndices[idx]].cardinality.toInt
        for v in 0..<pCard:
          var next = current
          next.add(v)
          generateParentStates(idx + 1, next, gm, childIdx, childCard, strength)

    generateParentStates(0, @[], result, i, childCard, interactionStrength)


proc expectedModel*(structure: string): string =
  ## Document what OCCAM model we expect to find for a given structure
  ## "chain" -> "AB:BC:CD:..."
  ## "star(B)" -> "AB:BC:BD:..."
  ## "independent" -> "A:B:C:..."
  ## "saturated" -> "ABC..."
  structure  # Just returns the input for now as documentation


# ============ Model from specification ============

proc parseVariableSpec*(spec: string): VariableList {.raises: [ValueError].} =
  ## Parse variable specification string like "A:2,B:2,C:2"
  ## Returns a VariableList with the specified variables and cardinalities
  result = initVariableList()
  let parts = spec.split(',')
  for part in parts:
    let trimmed = part.strip()
    if trimmed.len == 0:
      continue
    let colonIdx = trimmed.find(':')
    if colonIdx < 0:
      raise newException(ValueError, "Invalid variable spec: " & trimmed & " (expected format: A:2)")
    let abbrev = trimmed[0..<colonIdx].strip()
    let cardStr = trimmed[(colonIdx+1)..^1].strip()
    let card = parseInt(cardStr)
    discard result.add(initVariable(abbrev, abbrev, Cardinality(card)))


proc parseModelSpec*(varList: VariableList; modelSpec: string): seq[Relation] {.raises: [ValueError].} =
  ## Parse model specification like "AB:BC" or "A:B:C" into relations
  result = @[]
  let parts = modelSpec.split(':')
  for part in parts:
    let trimmed = part.strip()
    if trimmed.len == 0:
      continue
    var varIndices: seq[VariableIndex]
    for c in trimmed:
      let idxOpt = varList.findByAbbrev($c)
      if idxOpt.isSome:
        varIndices.add(idxOpt.get)
      else:
        raise newException(ValueError, "Unknown variable abbreviation: " & $c)
    if varIndices.len > 0:
      result.add(initRelation(varIndices))


proc createRandomMarginal(varList: VariableList; varIndices: seq[VariableIndex];
                          strength: float64): coretable.ContingencyTable =
  ## Create a random marginal distribution for a set of variables
  ## strength controls how non-uniform the distribution is (0.5=uniform, 1.0=deterministic)
  var stateCount = 1
  for vi in varIndices:
    stateCount *= varList[vi].cardinality.toInt

  result = coretable.initTable(varList.keySize, stateCount)

  # Generate random probabilities
  var probs = newSeq[float64](stateCount)
  for i in 0..<stateCount:
    probs[i] = rand(1.0)

  # Add some structure: make certain states more likely based on strength
  # Higher strength = more skewed distribution
  for i in 0..<stateCount:
    probs[i] = pow(probs[i], 1.0 / (1.0 - strength + 0.01))

  # Normalize
  let total = probs.foldl(a + b, 0.0)
  for i in 0..<stateCount:
    probs[i] /= total

  # Build the table by enumerating all states
  var stateIndices = newSeq[int](varIndices.len)
  for idx in 0..<stateCount:
    var keyPairs: seq[(VariableIndex, int)]
    for i, vi in varIndices:
      keyPairs.add((vi, stateIndices[i]))

    let key = varList.buildKey(keyPairs)
    result.add(key, probs[idx])

    # Increment stateIndices
    var carry = true
    for i in countdown(varIndices.len - 1, 0):
      if carry:
        stateIndices[i] += 1
        if stateIndices[i] >= varList[varIndices[i]].cardinality.toInt:
          stateIndices[i] = 0
        else:
          carry = false

  result.sort()


proc createDependentMarginal(varList: VariableList; varIndices: seq[VariableIndex];
                             strength: float64): coretable.ContingencyTable =
  ## Create a marginal where later variables depend on earlier ones
  ## Used for chain and star models
  ## Returns a table with keys matching what project() would return
  var stateCount = 1
  for vi in varIndices:
    stateCount *= varList[vi].cardinality.toInt

  # Create mask for the marginal projection
  let mask = varList.buildMask(varIndices)

  result = coretable.initTable(varList.keySize, stateCount)

  # Enumerate all states and compute conditional probabilities
  var stateIndices = newSeq[int](varIndices.len)
  var probs = newSeq[float64](stateCount)

  for idx in 0..<stateCount:
    # Probability is product of P(Vi | V1..Vi-1)
    # We simulate this by making P high when values match
    var p = 1.0

    if varIndices.len > 1:
      for i in 1..<varIndices.len:
        # P(Vi | Vi-1) - depends on previous value
        let prev = stateIndices[i-1]
        let curr = stateIndices[i]
        let card = varList[varIndices[i]].cardinality.toInt

        if curr == prev mod card:
          p *= strength
        else:
          p *= (1.0 - strength) / float64(card - 1)

    probs[idx] = p

    # Increment stateIndices
    var carry = true
    for i in countdown(varIndices.len - 1, 0):
      if carry:
        stateIndices[i] += 1
        if stateIndices[i] >= varList[varIndices[i]].cardinality.toInt:
          stateIndices[i] = 0
        else:
          carry = false

  # Normalize
  let total = probs.foldl(a + b, 0.0)
  for i in 0..<stateCount:
    probs[i] /= total

  # Build the table with masked keys (like what project() returns)
  stateIndices = newSeq[int](varIndices.len)
  for idx in 0..<stateCount:
    # Build full key first, then apply mask
    var keyPairs: seq[(VariableIndex, int)]
    for i, vi in varIndices:
      keyPairs.add((vi, stateIndices[i]))

    let fullKey = varList.buildKey(keyPairs)
    let maskedKey = fullKey.applyMask(mask)
    result.add(maskedKey, probs[idx])

    # Increment stateIndices
    var carry = true
    for i in countdown(varIndices.len - 1, 0):
      if carry:
        stateIndices[i] += 1
        if stateIndices[i] >= varList[varIndices[i]].cardinality.toInt:
          stateIndices[i] = 0
        else:
          carry = false

  result.sort()


proc computeFullStateSpace(varList: VariableList): coretable.ContingencyTable =
  ## Create a uniform distribution over the full state space
  var stateCount = 1
  for i in 0..<varList.len:
    stateCount *= varList[VariableIndex(i)].cardinality.toInt

  result = coretable.initTable(varList.keySize, stateCount)
  let prob = 1.0 / float64(stateCount)

  var stateIndices = newSeq[int](varList.len)
  for idx in 0..<stateCount:
    var keyPairs: seq[(VariableIndex, int)]
    for i in 0..<varList.len:
      keyPairs.add((VariableIndex(i), stateIndices[i]))

    let key = varList.buildKey(keyPairs)
    result.add(key, prob)

    # Increment stateIndices
    var carry = true
    for i in countdown(varList.len - 1, 0):
      if carry:
        stateIndices[i] += 1
        if stateIndices[i] >= varList[VariableIndex(i)].cardinality.toInt:
          stateIndices[i] = 0
        else:
          carry = false

  result.sort()


proc sampleFromTable*(varList: VariableList; probTable: coretable.ContingencyTable): seq[int] =
  ## Sample one state from a probability table
  result = newSeq[int](varList.len)
  let r = rand(1.0)
  var cumulative = 0.0

  for tup in probTable:
    cumulative += tup.value
    if r <= cumulative:
      for i in 0..<varList.len:
        result[i] = tup.key.getValue(varList, VariableIndex(i))
      return

  # Fallback to last state
  if probTable.len > 0:
    let lastTup = probTable[probTable.len - 1]
    for i in 0..<varList.len:
      result[i] = lastTup.key.getValue(varList, VariableIndex(i))


type
  TableBasedModel* = object
    ## A model that samples directly from a probability table
    varList*: VariableList
    probTable*: coretable.ContingencyTable


proc initTableBasedModel*(varList: VariableList; probTable: coretable.ContingencyTable): TableBasedModel =
  result.varList = varList
  result.probTable = probTable


proc sampleOne*(tbm: TableBasedModel): seq[int] =
  sampleFromTable(tbm.varList, tbm.probTable)


proc generateSamples*(tbm: TableBasedModel; n: int): seq[seq[int]] =
  result = newSeq[seq[int]](n)
  for i in 0..<n:
    result[i] = tbm.sampleOne()


proc samplesToTable*(tbm: TableBasedModel; samples: seq[seq[int]]): coretable.ContingencyTable =
  ## Convert samples to a count table
  var counts = stdtables.initTable[seq[int], float64]()

  for sample in samples:
    if sample in counts:
      try:
        counts[sample] += 1.0
      except KeyError:
        counts[sample] = 1.0
    else:
      counts[sample] = 1.0

  result = coretable.initTable(tbm.varList.keySize, counts.len)

  for state, count in counts:
    var k = initKey(tbm.varList.keySize)
    for i, val in state:
      k.setValue(tbm.varList, VariableIndex(i), val)
    result.add(k, count)

  result.sort()


proc createModelFromSpec*(varList: VariableList; modelSpec: string;
                          strength: float64 = 0.8): (GraphicalModel, bool) {.raises: [ValueError].} =
  ## Create a graphical model from a model specification string
  ## Returns the model and whether it has loops
  ##
  ## For loopless models, creates a DAG with appropriate conditionals.
  ## For loop models, uses IPF to create a maximum entropy distribution
  ## that satisfies the marginal constraints, then samples from it.
  ##
  ## Examples:
  ##   "A:B:C" -> independence model
  ##   "AB:BC" -> chain A-B-C
  ##   "AB:AC:AD" -> star with A as center
  ##   "ABC" -> saturated
  ##   "AB:BC:AC" -> triangle (loop)

  let relations = parseModelSpec(varList, modelSpec)
  let model = initModel(relations)
  let loopFlag = hasLoops(model, varList)

  if loopFlag:
    # Loop model: use IPF approach
    # For a loop model like AB:BC:AC (triangle), we create a joint distribution
    # that has the desired pairwise dependencies
    #
    # Strategy:
    # 1. Create target marginals for each relation with the desired dependence
    # 2. Use IPF to find the maximum entropy distribution matching all marginals

    # Create target marginals with dependence structure
    var targetMarginals: seq[coretable.ContingencyTable]
    for rel in relations:
      let marginal = createDependentMarginal(varList, rel.varIndices, strength)
      targetMarginals.add(marginal)

    # Start with a random initial distribution that has some structure
    var fitTable = computeFullStateSpace(varList)

    # IPF iterations to match all marginals
    for iter in 0..<200:
      for i, rel in relations:
        # Scale fitTable so its projection onto rel matches targetMarginals[i]
        let targetMarg = targetMarginals[i]
        let currentMarg = fitTable.project(varList, rel.varIndices)
        let mask = varList.buildMask(rel.varIndices)

        # Build scaling factors - map from projected key to scale
        # Use string representation for reliable hashing
        var scaleFactors = stdtables.initTable[string, float64]()
        for ti in 0..<targetMarg.len:
          let targetTup = targetMarg[ti]
          let targetKey = targetTup.key
          var keyStr = ""
          for j in 0..<targetKey.len:
            keyStr.add($targetKey[j].toUint32)
            keyStr.add(",")

          # Find matching entry in current marginal
          let idx = currentMarg.find(targetKey)
          var currentVal = 1e-10
          if idx.isSome:
            currentVal = max(currentMarg[idx.get].value, 1e-10)
          scaleFactors[keyStr] = targetTup.value / currentVal

        # Apply scaling to each cell in the joint
        var newTable = coretable.initTable(varList.keySize, fitTable.len)
        for tup in fitTable:
          let projKey = tup.key.applyMask(mask)
          var keyStr = ""
          for j in 0..<projKey.len:
            keyStr.add($projKey[j].toUint32)
            keyStr.add(",")

          var scale = 1.0
          if keyStr in scaleFactors:
            try:
              scale = scaleFactors[keyStr]
            except KeyError:
              discard
          newTable.add(tup.key, tup.value * scale)

        newTable.sort()
        newTable.normalize()
        fitTable = newTable

    # Now convert the fitted table to a GraphicalModel by computing conditionals
    var gm = initGraphicalModel(varList)

    # For a loop model with IPF, we need to compute full conditionals
    # P(V_i | V_1, ..., V_{i-1}) from the joint distribution
    # This creates a saturated graphical model that generates the same distribution

    for i in 0..<varList.len:
      if i == 0:
        # First variable: use marginal from fitted table
        let marginal = fitTable.project(varList, @[VariableIndex(0)])
        let card = varList[VariableIndex(0)].cardinality.toInt
        var dist = newSeq[float64](card)
        for tup in marginal:
          let v = tup.key.getValue(varList, VariableIndex(0))
          dist[v] = tup.value
        # Normalize
        let total = dist.foldl(a + b, 0.0)
        if total > 1e-10:
          for j in 0..<card:
            dist[j] /= total
        else:
          for j in 0..<card:
            dist[j] = 1.0 / float64(card)
        gm.setConditional(VariableIndex(0), @[], dist)
      else:
        var parents: seq[VariableIndex]
        for j in 0..<i:
          parents.add(VariableIndex(j))
        gm.setParents(VariableIndex(i), parents)

        # Compute P(V_i | parents) from joint
        let childCard = varList[VariableIndex(i)].cardinality.toInt
        var parentCards: seq[int]
        for p in parents:
          parentCards.add(varList[p].cardinality.toInt)

        # Get variables after current one (to sum over)
        var futureVars: seq[VariableIndex]
        var futureCards: seq[int]
        for j in (i+1)..<varList.len:
          futureVars.add(VariableIndex(j))
          futureCards.add(varList[VariableIndex(j)].cardinality.toInt)

        # Enumerate all parent states using iterator
        for parentIndices in stateEnumerationReverse(parentCards):
          var condDist = newSeq[float64](childCard)
          var parentProb = 0.0

          # Sum over all values of V_i and future variables
          for c in 0..<childCard:
            # Need to sum over all future variable combinations
            if futureVars.len == 0:
              # No future variables - direct lookup
              var keyPairs: seq[(VariableIndex, int)]
              for k, p in parents:
                keyPairs.add((p, parentIndices[k]))
              keyPairs.add((VariableIndex(i), c))
              let fullKey = varList.buildKey(keyPairs)
              let idx = fitTable.find(fullKey)
              if idx.isSome:
                condDist[c] += fitTable[idx.get].value
                parentProb += fitTable[idx.get].value
            else:
              # Sum over all future variable combinations using iterator
              for futureIndices in stateEnumerationReverse(futureCards):
                var keyPairs: seq[(VariableIndex, int)]
                for k, p in parents:
                  keyPairs.add((p, parentIndices[k]))
                keyPairs.add((VariableIndex(i), c))
                for k, fv in futureVars:
                  keyPairs.add((fv, futureIndices[k]))
                let fullKey = varList.buildKey(keyPairs)
                let idx = fitTable.find(fullKey)
                if idx.isSome:
                  condDist[c] += fitTable[idx.get].value
                  parentProb += fitTable[idx.get].value

          # Normalize to get conditional
          if parentProb > 1e-10:
            for c in 0..<childCard:
              condDist[c] /= parentProb
          else:
            for c in 0..<childCard:
              condDist[c] = 1.0 / float64(childCard)

          gm.setConditional(VariableIndex(i), parentIndices, condDist)

    result = (gm, true)

  else:
    # Loopless model: create DAG structure
    # We need to find a topological ordering of variables based on the model structure

    var gm = initGraphicalModel(varList)

    # For a loopless model, we can use the relations to define dependencies
    # A relation like AB means A and B are dependent
    # We'll assign directions based on alphabetical/index order

    # Check if this is an independence model (all single-var relations)
    var isIndep = true
    for rel in relations:
      if rel.variableCount > 1:
        isIndep = false
        break

    if isIndep:
      # Independence model: all uniform marginals
      for i in 0..<varList.len:
        let card = varList[VariableIndex(i)].cardinality.toInt
        gm.setConditional(VariableIndex(i), @[], newSeqWith(card, 1.0/float64(card)))
      result = (gm, false)
      return

    # Check if saturated (one relation with all vars)
    if relations.len == 1 and relations[0].variableCount == varList.len:
      # Saturated: each var depends on all previous
      result = (createFullyConnectedModel(varList, strength), false)
      return

    # General loopless model: build DAG based on relations
    # Use a simple heuristic: for each relation, variables depend on the first one

    var hasParent = newSeq[bool](varList.len)
    var parents = newSeq[seq[VariableIndex]](varList.len)

    for rel in relations:
      let vars = rel.varIndices
      if vars.len > 1:
        # First variable in relation is "root" of this clique
        let root = vars[0]
        for i in 1..<vars.len:
          let child = vars[i]
          if not hasParent[child.toInt]:
            parents[child.toInt].add(root)
            hasParent[child.toInt] = true

    # Set up the graphical model
    for i in 0..<varList.len:
      let vi = VariableIndex(i)
      let card = varList[vi].cardinality.toInt

      if parents[i].len == 0:
        # No parents: uniform marginal
        gm.setConditional(vi, @[], newSeqWith(card, 1.0/float64(card)))
      else:
        gm.setParents(vi, parents[i])

        # Create conditional P(Vi | parents)
        var parentCards: seq[int]
        for p in parents[i]:
          parentCards.add(varList[p].cardinality.toInt)

        # Enumerate parent states using iterator
        for parentIndices in stateEnumerationReverse(parentCards):
          # P(Vi | parents) - make it favor matching values
          var dist = newSeq[float64](card)
          let parentSum = parentIndices.foldl(a + b, 0)

          for c in 0..<card:
            if c == parentSum mod card:
              dist[c] = strength
            else:
              dist[c] = (1.0 - strength) / float64(card - 1)

          gm.setConditional(vi, parentIndices, dist)

    result = (gm, false)

