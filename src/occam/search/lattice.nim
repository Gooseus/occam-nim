## Lattice enumeration for OCCAM
## Generates all models in the model lattice

{.push raises: [].}

import std/[algorithm, sets, tables, hashes, options, deques]
import ../core/types
import ../core/variable
import ../core/relation
import ../core/model

type
  LatticeModel* = object
    ## A model in the lattice with metadata
    model*: Model
    hasLoops*: bool
    level*: int  # Distance from independence model

proc hashModel(m: Model): Hash =
  ## Hash a model by its relation structure
  var h: Hash = 0
  for rel in m.relations:
    var relHash: Hash = 0
    for v in rel.varIndices:
      relHash = relHash !& hash(v.toInt)
    h = h !& relHash
  !$h


proc generateParents*(m: Model; varList: VariableList): seq[Model] =
  ## Generate all immediate parent models (one step up the lattice)
  ## Parents are formed by merging pairs of relations that share variables,
  ## or by adding a variable pair to create a new connection
  result = @[]

  let varCount = varList.len

  # For each pair of variables not currently in the same relation,
  # create a new model by merging their relations
  for i in 0..<varCount:
    for j in (i+1)..<varCount:
      let vi = VariableIndex(i)
      let vj = VariableIndex(j)

      # Find which relations contain vi and vj
      var relWithVi = -1
      var relWithVj = -1
      var bothInSame = false

      for relIdx in 0..<m.relationCount:
        let rel = m.relations[relIdx]
        let hasVi = rel.containsVariable(vi)
        let hasVj = rel.containsVariable(vj)

        if hasVi and hasVj:
          bothInSame = true
          break
        if hasVi:
          relWithVi = relIdx
        if hasVj:
          relWithVj = relIdx

      # Skip if already in same relation
      if bothInSame or relWithVi < 0 or relWithVj < 0:
        continue

      # Skip if same relation (shouldn't happen but safety check)
      if relWithVi == relWithVj:
        continue

      # Merge the two relations
      let relA = m.relations[relWithVi]
      let relB = m.relations[relWithVj]
      var mergedVars: seq[VariableIndex]

      for v in relA.varIndices:
        mergedVars.add(v)
      for v in relB.varIndices:
        if v notin mergedVars:
          mergedVars.add(v)

      mergedVars.sort(cmp)
      let mergedRel = initRelation(mergedVars)

      # Build new model
      var newRels: seq[Relation]
      for relIdx in 0..<m.relationCount:
        if relIdx != relWithVi and relIdx != relWithVj:
          newRels.add(m.relations[relIdx])
      newRels.add(mergedRel)

      let newModel = initModel(newRels)

      # Check for duplicates
      var isDup = false
      for existing in result:
        if existing == newModel:
          isDup = true
          break
      if not isDup:
        result.add(newModel)


proc generateChildren*(m: Model; varList: VariableList): seq[Model] =
  ## Generate all immediate child models (one step down the lattice)
  ## Children are formed by splitting relations
  result = @[]

  let varCount = varList.len

  # For each relation with more than one variable,
  # try splitting by removing one variable
  for relIdx in 0..<m.relationCount:
    let rel = m.relations[relIdx]

    if rel.variableCount <= 1:
      continue  # Can't split a singleton

    # For each pair of variables in this relation, try splitting
    for i in 0..<rel.variableCount:
      for j in (i+1)..<rel.variableCount:
        let vi = rel.varIndices[i]
        let vj = rel.varIndices[j]

        # Create two child relations: rel - vi and rel - vj
        var child1Vars: seq[VariableIndex]
        var child2Vars: seq[VariableIndex]

        for v in rel.varIndices:
          if v != vi:
            child1Vars.add(v)
          if v != vj:
            child2Vars.add(v)

        # Build new model
        var newRels: seq[Relation]
        for idx in 0..<m.relationCount:
          if idx != relIdx:
            newRels.add(m.relations[idx])

        newRels.add(initRelation(child1Vars))
        newRels.add(initRelation(child2Vars))

        let newModel = initModel(newRels)

        # Check for duplicates
        var isDup = false
        for existing in result:
          if existing == newModel:
            isDup = true
            break
        if not isDup:
          result.add(newModel)


proc enumerateLattice*(varList: VariableList; looplessOnly = false; maxModels = 10000): seq[LatticeModel] =
  ## Enumerate all models in the lattice
  ## Uses BFS from independence model upward
  ##
  ## Arguments:
  ##   varList: Variable list defining the system
  ##   looplessOnly: If true, only include loopless (decomposable) models
  ##   maxModels: Maximum number of models to generate
  result = @[]

  # Start with independence model
  let indepModel = createIndependenceModel(varList)

  # Track visited models by their print name
  var visited = initHashSet[string]()
  var queue = initDeque[(Model, int)]()  # (model, level)

  # Add independence model
  let indepName = indepModel.printName(varList)
  visited.incl(indepName)
  queue.addLast((indepModel, 0))
  result.add(LatticeModel(
    model: indepModel,
    hasLoops: false,
    level: 0
  ))

  # BFS upward through the lattice
  while queue.len > 0 and result.len < maxModels:
    let (currentModel, currentLevel) = queue.popFirst()

    # Generate parents
    let parents = generateParents(currentModel, varList)

    for parent in parents:
      let parentName = parent.printName(varList)

      if parentName notin visited:
        visited.incl(parentName)

        let loops = hasLoops(parent, varList)

        if looplessOnly and loops:
          continue

        queue.addLast((parent, currentLevel + 1))
        result.add(LatticeModel(
          model: parent,
          hasLoops: loops,
          level: currentLevel + 1
        ))

  # Sort by level then by name
  result.sort(proc(a, b: LatticeModel): int =
    let levelCmp = cmp(a.level, b.level)
    if levelCmp != 0:
      return levelCmp
    # For same level, sort by relation count then name
    let relCmp = cmp(a.model.relationCount, b.model.relationCount)
    if relCmp != 0:
      return -relCmp  # More relations = lower in lattice within same level
    0
  )


proc enumerateDirectedLattice*(varList: VariableList; looplessOnly = false; maxModels = 10000): seq[LatticeModel] =
  ## Enumerate models in a directed system lattice
  ## For directed systems, models have structure: IVs:DVprediction
  result = @[]

  if not varList.isDirected:
    return enumerateLattice(varList, looplessOnly, maxModels)

  # Get dependent variable index
  let dvIdx = varList.dependentIndex
  if dvIdx.isNone:
    return enumerateLattice(varList, looplessOnly, maxModels)

  let dv = dvIdx.get

  # Collect IV indices
  var ivs: seq[VariableIndex]
  for idx in 0..<varList.len:
    let vIdx = VariableIndex(idx)
    if not varList[vIdx].isDependent:
      ivs.add(vIdx)

  # Bottom model: all IVs together, DV separate
  var bottomRels: seq[Relation]
  if ivs.len > 0:
    bottomRels.add(initRelation(ivs))
  bottomRels.add(initRelation(@[dv]))
  let bottomModel = initModel(bottomRels)

  var visited = initHashSet[string]()
  var queue = initDeque[(Model, int)]()

  let bottomName = bottomModel.printName(varList)
  visited.incl(bottomName)
  queue.addLast((bottomModel, 0))
  result.add(LatticeModel(
    model: bottomModel,
    hasLoops: false,
    level: 0
  ))

  # BFS: add IVs to the predictive relation
  while queue.len > 0 and result.len < maxModels:
    let (currentModel, currentLevel) = queue.popFirst()

    # Find the predictive relation (contains DV)
    var predRelIdx = -1
    var ivOnlyRelIdx = -1

    for i in 0..<currentModel.relationCount:
      let rel = currentModel.relations[i]
      if rel.containsVariable(dv):
        predRelIdx = i
      elif rel.variableCount > 0:
        # Check if this is IV-only
        var allIV = true
        for v in rel.varIndices:
          if varList[v].isDependent:
            allIV = false
            break
        if allIV:
          ivOnlyRelIdx = i

    if predRelIdx < 0:
      continue

    let predRel = currentModel.relations[predRelIdx]

    # Find IVs not yet in predictive relation
    for iv in ivs:
      if not predRel.containsVariable(iv):
        # Add this IV to the predictive relation
        var newPredVars = predRel.varIndices
        newPredVars.add(iv)
        newPredVars.sort(cmp)

        var newRels: seq[Relation]
        for i in 0..<currentModel.relationCount:
          if i == predRelIdx:
            newRels.add(initRelation(newPredVars))
          elif i == ivOnlyRelIdx:
            # Remove this IV from IV-only relation
            var newIvVars: seq[VariableIndex]
            for v in currentModel.relations[i].varIndices:
              if v != iv:
                newIvVars.add(v)
            if newIvVars.len > 0:
              newRels.add(initRelation(newIvVars))
          else:
            newRels.add(currentModel.relations[i])

        let newModel = initModel(newRels)
        let newName = newModel.printName(varList)

        if newName notin visited:
          visited.incl(newName)

          let loops = hasLoops(newModel, varList)

          if looplessOnly and loops:
            continue

          queue.addLast((newModel, currentLevel + 1))
          result.add(LatticeModel(
            model: newModel,
            hasLoops: loops,
            level: currentLevel + 1
          ))

  result.sort(proc(a, b: LatticeModel): int =
    cmp(a.level, b.level)
  )
