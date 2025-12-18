## Full search algorithm for OCCAM
## Explores entire model space including models with loops

{.push raises: [].}

import std/[algorithm, options]
import ../core/types
import ../core/variable
import ../core/relation
import ../core/model
import ../manager/vb
import base

type
  FullSearch* = object
    ## Full search configuration (includes loop models)
    config: SearchConfig


proc initFullSearch*(mgr: var VBManager; width: int = 3; maxLevels: int = 7): FullSearch =
  ## Initialize full search with given width and max levels
  result.config = initSearchConfig(mgr, width, maxLevels)


proc width*(search: FullSearch): int {.inline.} = search.config.width
proc maxLevels*(search: FullSearch): int {.inline.} = search.config.maxLevels


proc generateNeighborsUp(search: FullSearch; model: Model): seq[Model] =
  ## Generate parent models (upward search) - includes loop models
  ## For neutral systems: add new pairwise relations or merge existing ones
  ## For directed systems: add IVs to predictive relations
  result = @[]
  let mgr = search.config.mgr[]
  let varList = mgr.varList

  if varList.isDirected:
    # Directed up: add one IV to predictive relations
    # Find all predictive relations (contain DV)
    var predRelIndices: seq[int]
    let indOnlyRelIdx = findIndependentOnlyRelation(model, varList)

    for i in 0..<model.relationCount:
      let rel = model.relations[i]
      if rel.containsDependent(varList):
        predRelIndices.add(i)

    if predRelIndices.len == 0:
      return  # Malformed model

    # For each IV not in any predictive relation, try adding to each
    for varIdx in 0..<varList.len:
      let vIdx = VariableIndex(varIdx)
      if varList[vIdx].isDependent:
        continue

      for predRelIdx in predRelIndices:
        let predRel = model.relations[predRelIdx]
        if predRel.containsVariable(vIdx):
          continue  # Already in this relation

        # Add this IV to this predictive relation
        let newPredRel = addVariableToRelation(predRel, vIdx)

        var newRels: seq[Relation]
        for i in 0..<model.relationCount:
          if i == predRelIdx:
            newRels.add(newPredRel)
          elif indOnlyRelIdx.isSome and i == indOnlyRelIdx.get:
            # Remove this IV from the IV-only relation if present
            let newIvRel = removeVariableFromRelation(model.relations[i], vIdx)
            if newIvRel.variableCount > 0:
              newRels.add(newIvRel)
          else:
            newRels.add(model.relations[i])

        let simplified = simplifyRelations(newRels)
        let newModel = initModel(simplified)
        # No loop check - full search includes loops
        discard result.addIfUnique(newModel, varList)

  else:
    # Neutral up: two strategies
    # 1. Merge relations (same as loopless)
    # 2. Add new pairwise relation (creates loops)

    let varCount = varList.len

    # Strategy 1: Merge relations (like loopless)
    for i in 0..<varCount:
      for j in (i+1)..<varCount:
        let vi = VariableIndex(i)
        let vj = VariableIndex(j)

        let (relWithVi, relWithVj, bothInSame) = findRelationPair(model, vi, vj)

        # Skip if already in same relation or not found
        if bothInSame or relWithVi.isNone or relWithVj.isNone:
          continue

        # Merge the two relations
        let mergedRel = mergeRelations(model.relations[relWithVi.get], model.relations[relWithVj.get])

        # Build new model
        var newRels: seq[Relation]
        for relIdx in 0..<model.relationCount:
          if relIdx != relWithVi.get and relIdx != relWithVj.get:
            newRels.add(model.relations[relIdx])
        newRels.add(mergedRel)

        let simplified = simplifyRelations(newRels)
        let newModel = initModel(simplified)
        discard result.addIfUnique(newModel, varList)

    # Strategy 2: Add a new pairwise relation (can create loops)
    # For each pair of variables, if they're not already together in any relation,
    # add a new relation containing just that pair
    for i in 0..<varCount:
      for j in (i+1)..<varCount:
        let vi = VariableIndex(i)
        let vj = VariableIndex(j)

        # Check if this pair is already in any relation
        var pairExists = false
        for rel in model.relations:
          if rel.containsVariable(vi) and rel.containsVariable(vj):
            pairExists = true
            break

        if pairExists:
          continue

        # Add new pairwise relation
        let pairRel = initRelation(@[vi, vj])

        var newRels: seq[Relation]
        for rel in model.relations:
          newRels.add(rel)
        newRels.add(pairRel)

        let simplified = simplifyRelations(newRels)
        let newModel = initModel(simplified)
        discard result.addIfUnique(newModel, varList)


proc generateNeighborsDown(search: FullSearch; model: Model): seq[Model] =
  ## Generate child models (downward search) - includes loop models
  result = @[]
  let mgr = search.config.mgr[]
  let varList = mgr.varList

  if varList.isDirected:
    # Directed down: for each predictive relation, try removing each IV
    for relIdx in 0..<model.relationCount:
      let rel = model.relations[relIdx]
      if not rel.containsDependent(varList) or rel.isDependentOnly(varList):
        continue

      # Get IVs in this predictive relation
      let ivs = getIVsInRelation(rel, varList)

      if ivs.len == 0:
        continue

      # For each IV, create a child by removing it
      for ivToRemove in ivs:
        let newRel = removeVariableFromRelation(rel, ivToRemove)

        if newRel.variableCount == 0:
          continue

        var newRels: seq[Relation]
        for i in 0..<model.relationCount:
          if i == relIdx:
            newRels.add(newRel)
          else:
            newRels.add(model.relations[i])

        # Check if removed IV needs to be added to IV-only relation
        # For simplicity, we'll let model canonicalization handle this

        let simplified = simplifyRelations(newRels)
        let newModel = initModel(simplified)
        discard result.addIfUnique(newModel, varList)

  else:
    # Neutral down: split relations by removing variable pairs
    let varCount = varList.len

    for i in 0..<varCount:
      for j in (i+1)..<varCount:
        let vi = VariableIndex(i)
        let vj = VariableIndex(j)

        # Find relations containing this pair
        for relIdx in 0..<model.relationCount:
          let rel = model.relations[relIdx]
          if not (rel.containsVariable(vi) and rel.containsVariable(vj)):
            continue

          # Skip if relation only has these two variables
          if rel.variableCount <= 2:
            continue

          # Create two child relations
          let childRel1 = removeVariableFromRelation(rel, vi)
          let childRel2 = removeVariableFromRelation(rel, vj)

          # Build new model
          var newRels = buildModelExcludingRelation(model, relIdx)
          newRels.add(childRel1)
          newRels.add(childRel2)

          let simplified = simplifyRelations(newRels)
          let newModel = initModel(simplified)
          # No loop check - full search includes loops
          discard result.addIfUnique(newModel, varList)


proc generateNeighbors*(search: FullSearch; model: Model): seq[Model] =
  ## Generate neighbor models in the search direction
  let dir = search.config.direction
  if dir == Direction.Ascending:
    search.generateNeighborsUp(model)
  else:
    search.generateNeighborsDown(model)


# Re-export hasLoops from model module
export hasLoops
