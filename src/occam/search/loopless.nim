## Loopless search algorithm for OCCAM
## Explores model space while avoiding models with loops

{.push raises: [].}

import std/[algorithm, options]
import ../core/types
import ../core/variable
import ../core/relation
import ../core/model
import ../manager/vb
import base

type
  LooplessSearch* = object
    ## Loopless search configuration
    config: SearchConfig


proc initLooplessSearch*(mgr: var VBManager; width: int = 3; maxLevels: int = 7): LooplessSearch =
  ## Initialize loopless search with given width and max levels
  result.config = initSearchConfig(mgr, width, maxLevels)


proc width*(search: LooplessSearch): int {.inline.} = search.config.width
proc maxLevels*(search: LooplessSearch): int {.inline.} = search.config.maxLevels


proc generateNeighborsUp(search: LooplessSearch; model: Model): seq[Model] =
  ## Generate loopless parent models (upward search)
  ## For neutral systems: find variable pairs in exactly one relation
  ## For directed systems: add IVs to predictive relations
  result = @[]
  let mgr = search.config.mgr[]
  let varList = mgr.varList

  if varList.isDirected:
    # Directed loopless up: add one IV to the DV relation
    # Use findDVRelation since we might start from DV-only (bottom model)
    let dvRelIdx = findDVRelation(model, varList)
    let indOnlyRelIdx = findIndependentOnlyRelation(model, varList)

    if dvRelIdx.isNone:
      return  # Malformed model

    let dvRel = model.relations[dvRelIdx.get]

    # Find IVs not in the DV relation
    for varIdx in 0..<varList.len:
      let vIdx = VariableIndex(varIdx)
      if varList[vIdx].isDependent:
        continue

      if not dvRel.containsVariable(vIdx):
        # Add this IV to the DV relation
        let newDvRel = addVariableToRelation(dvRel, vIdx)

        var newRels: seq[Relation]
        for i in 0..<model.relationCount:
          if i == dvRelIdx.get:
            newRels.add(newDvRel)
          elif indOnlyRelIdx.isSome and i == indOnlyRelIdx.get:
            # Remove this IV from the IV-only relation
            let ivOnlyRel = removeVariableFromRelation(model.relations[i], vIdx)
            if ivOnlyRel.variableCount > 0:
              newRels.add(ivOnlyRel)
          else:
            newRels.add(model.relations[i])

        let newModel = initModel(newRels)
        if not hasLoops(newModel, varList):
          discard result.addIfUnique(newModel, varList)

  else:
    # Neutral loopless up: find pairs in different relations and merge them
    let varCount = varList.len

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

        # Build new model: keep relations not being merged, add merged relation
        var newRels: seq[Relation]
        for relIdx in 0..<model.relationCount:
          if relIdx != relWithVi.get and relIdx != relWithVj.get:
            newRels.add(model.relations[relIdx])
        newRels.add(mergedRel)

        let newModel = initModel(newRels)
        if not hasLoops(newModel, varList):
          discard result.addIfUnique(newModel, varList)


proc generateNeighborsDown(search: LooplessSearch; model: Model): seq[Model] =
  ## Generate loopless child models (downward search)
  ## Split relations by removing variable pairs
  result = @[]
  let mgr = search.config.mgr[]
  let varList = mgr.varList

  if varList.isDirected:
    # Directed loopless down: remove one IV from predictive relation
    let predRelIdx = findPredictiveRelation(model, varList)

    if predRelIdx.isNone:
      return  # Can't go down further (at bottom)

    let predRel = model.relations[predRelIdx.get]
    let ivs = getIVsInRelation(predRel, varList)

    if ivs.len == 0:
      return  # No IVs to remove

    # For each IV, create a child by removing it
    for ivToRemove in ivs:
      let newPredRel = removeVariableFromRelation(predRel, ivToRemove)

      if newPredRel.variableCount == 0:
        continue

      let newRels = buildModelReplacingRelation(model, predRelIdx.get, newPredRel)
      let newModel = initModel(newRels)

      if not hasLoops(newModel, varList):
        discard result.addIfUnique(newModel, varList)

  else:
    # Neutral loopless down (Krippendorf's algorithm)
    # Find pairs (v', v") that appear together in exactly one relation
    # Replace K with (K-v'):(K-v")
    let varCount = varList.len

    for i in 0..<varCount:
      for j in (i+1)..<varCount:
        let vi = VariableIndex(i)
        let vj = VariableIndex(j)

        # Find the unique relation containing this pair
        var containIdx = -1
        var containCount = 0

        for relIdx in 0..<model.relationCount:
          let rel = model.relations[relIdx]
          if rel.containsVariable(vi) and rel.containsVariable(vj):
            containCount += 1
            containIdx = relIdx

        # Pair must be in exactly one relation
        if containCount != 1:
          continue

        let rel = model.relations[containIdx]

        # Skip if relation only has these two variables
        if rel.variableCount <= 2:
          continue

        # Create two child relations: (K-vi) and (K-vj)
        let childRel1 = removeVariableFromRelation(rel, vi)
        let childRel2 = removeVariableFromRelation(rel, vj)

        # Build new model
        var newRels = buildModelExcludingRelation(model, containIdx)
        newRels.add(childRel1)
        newRels.add(childRel2)

        let newModel = initModel(newRels)
        if not hasLoops(newModel, varList):
          discard result.addIfUnique(newModel, varList)


proc generateNeighbors*(search: LooplessSearch; model: Model): seq[Model] =
  ## Generate neighbor models in the search direction
  let dir = search.config.direction
  if dir == Direction.Ascending:
    search.generateNeighborsUp(model)
  else:
    search.generateNeighborsDown(model)


# Re-export hasLoops from model module
export hasLoops
