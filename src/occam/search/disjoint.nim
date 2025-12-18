## Disjoint search algorithm for OCCAM
## Explores model space where relations don't share variables

{.push raises: [].}

import std/[algorithm, options]
import ../core/types
import ../core/variable
import ../core/relation
import ../core/model
import ../manager/vb
import base

type
  DisjointSearch* = object
    ## Disjoint search configuration (non-overlapping relations only)
    config: SearchConfig


proc isDisjointModel*(model: Model; varList: VariableList): bool =
  ## Check if model is disjoint (no relations share variables)
  ## A disjoint model partitions variables into non-overlapping subsets
  for i in 0..<model.relationCount:
    for j in (i+1)..<model.relationCount:
      if model.relations[i].overlaps(model.relations[j]):
        return false
  return true


proc initDisjointSearch*(mgr: var VBManager; width: int = 3; maxLevels: int = 7): DisjointSearch =
  ## Initialize disjoint search with given width and max levels
  result.config = initSearchConfig(mgr, width, maxLevels)


proc width*(search: DisjointSearch): int {.inline.} = search.config.width
proc maxLevels*(search: DisjointSearch): int {.inline.} = search.config.maxLevels


proc generateNeighborsUp(search: DisjointSearch; model: Model): seq[Model] =
  ## Generate disjoint parent models (upward search)
  ## For disjoint search, we merge two relations into one (which stays disjoint
  ## since each variable appears in exactly one relation in a disjoint model)
  result = @[]
  let mgr = search.config.mgr[]
  let varList = mgr.varList

  if varList.isDirected:
    # Directed disjoint up: add one IV to the predictive relation
    # This maintains disjointness since each IV appears in exactly one relation
    let dvRelIdx = findDVRelation(model, varList)
    let indOnlyRelIdx = findIndependentOnlyRelation(model, varList)

    if dvRelIdx.isNone:
      return  # Malformed model

    let dvRel = model.relations[dvRelIdx.get]

    # Find IVs not in the DV relation (in separate IV-only relations)
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
            let newIvRel = removeVariableFromRelation(model.relations[i], vIdx)
            if newIvRel.variableCount > 0:
              newRels.add(newIvRel)
          else:
            # Remove single-IV relations for the variable being added
            let rel = model.relations[i]
            if rel.variableCount == 1 and rel.containsVariable(vIdx):
              continue  # Skip this relation
            newRels.add(rel)

        let newModel = initModel(newRels)
        if isDisjointModel(newModel, varList):
          discard result.addIfUnique(newModel, varList)

  else:
    # Neutral disjoint up: merge two single-variable (or small) relations
    # For disjoint models, each variable appears in exactly one relation
    # So we merge two relations completely to form one larger relation
    for i in 0..<model.relationCount:
      for j in (i+1)..<model.relationCount:
        let relI = model.relations[i]
        let relJ = model.relations[j]

        # Merge relations i and j
        let mergedRel = mergeRelations(relI, relJ)

        # Build new model: keep other relations, add merged relation
        var newRels: seq[Relation]
        for k in 0..<model.relationCount:
          if k != i and k != j:
            newRels.add(model.relations[k])
        newRels.add(mergedRel)

        let newModel = initModel(newRels)
        # Disjoint model check (should always pass when merging disjoint relations)
        if isDisjointModel(newModel, varList):
          discard result.addIfUnique(newModel, varList)


proc generateNeighborsDown(search: DisjointSearch; model: Model): seq[Model] =
  ## Generate disjoint child models (downward search)
  ## For disjoint search, we split one relation into two (maintaining disjointness)
  result = @[]
  let mgr = search.config.mgr[]
  let varList = mgr.varList

  if varList.isDirected:
    # Directed disjoint down: remove one IV from predictive relation
    let predRelIdx = findPredictiveRelation(model, varList)

    if predRelIdx.isNone:
      return  # Can't go down further (at bottom)

    let predRel = model.relations[predRelIdx.get]

    # Get IVs in the predictive relation
    let ivs = getIVsInRelation(predRel, varList)

    if ivs.len == 0:
      return  # No IVs to remove

    # For each IV, create a child by removing it
    for ivToRemove in ivs:
      let newPredRel = removeVariableFromRelation(predRel, ivToRemove)

      if newPredRel.variableCount == 0:
        continue

      var newRels = buildModelReplacingRelation(model, predRelIdx.get, newPredRel)

      # Add the removed IV as its own relation (maintains disjointness)
      newRels.add(initRelation(@[ivToRemove]))

      let newModel = initModel(newRels)
      if isDisjointModel(newModel, varList):
        discard result.addIfUnique(newModel, varList)

  else:
    # Neutral disjoint down: split one relation into two separate relations
    # Each variable goes to exactly one of the two resulting relations
    for relIdx in 0..<model.relationCount:
      let rel = model.relations[relIdx]

      # Can only split relations with 2+ variables
      if rel.variableCount < 2:
        continue

      # For each way to split the variables into two non-empty groups
      # Simple approach: remove one variable at a time
      for v in rel.varIndices:
        # Split: v by itself, rest of vars together
        let singleRel = initRelation(@[v])
        let restRel = removeVariableFromRelation(rel, v)

        if restRel.variableCount == 0:
          continue

        # Build new model
        var newRels = buildModelExcludingRelation(model, relIdx)
        newRels.add(singleRel)  # Single variable relation
        newRels.add(restRel)    # Rest of variables

        let newModel = initModel(newRels)
        if isDisjointModel(newModel, varList):
          discard result.addIfUnique(newModel, varList)


proc generateNeighbors*(search: DisjointSearch; model: Model): seq[Model] =
  ## Generate neighbor models in the search direction
  let dir = search.config.direction
  if dir == Direction.Ascending:
    search.generateNeighborsUp(model)
  else:
    search.generateNeighborsDown(model)


# Re-export isDisjointModel for external use
export isDisjointModel
