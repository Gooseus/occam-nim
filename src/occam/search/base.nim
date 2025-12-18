## Search Base Module
##
## Common utilities and base types shared across search algorithms:
## - SearchConfig base type
## - Duplicate model detection
## - Relation simplification
## - Relation merging utilities

{.push raises: [].}

import std/[algorithm, options]
import ../core/types
import ../core/variable
import ../core/relation
import ../core/model
import ../manager/vb

type
  SearchConfig* = object
    ## Base configuration for all search algorithms.
    ##
    ## LIFETIME: mgr is a raw pointer to avoid copying the large VBManager
    ## object on every search call. The caller MUST ensure the manager
    ## outlives the search config. This is safe because:
    ## - SearchConfig is created, used for search, and discarded immediately
    ## - VBManager is always on the caller's stack/heap during search
    mgr*: ptr VBManager
    width*: int
    maxLevels*: int


proc initSearchConfig*(mgr: var VBManager; width: int = 3; maxLevels: int = 7): SearchConfig =
  ## Initialize base search configuration
  result.mgr = addr mgr
  result.width = width
  result.maxLevels = maxLevels


proc varList*(config: SearchConfig): VariableList {.inline.} =
  ## Get the variable list from search config
  config.mgr[].varList


proc direction*(config: SearchConfig): Direction {.inline.} =
  ## Get the search direction from config
  config.mgr[].searchDirection


proc addIfUnique*(models: var seq[Model]; newModel: Model; varList: VariableList): bool =
  ## Add model to list if not already present (by name)
  ## Returns true if added, false if duplicate
  let newName = newModel.printName(varList)
  for existing in models:
    if existing.printName(varList) == newName:
      return false
  models.add(newModel)
  true


func simplifyRelations*(relations: seq[Relation]): seq[Relation] =
  ## Remove redundant relations (those that are proper subsets of others)
  ## A relation R1 is redundant if R1 ⊂ R2 for some R2 in the set
  result = @[]
  for i, relI in relations:
    var isRedundant = false
    for j, relJ in relations:
      if i != j and relI.isSubsetOf(relJ) and not relJ.isSubsetOf(relI):
        # relI is a proper subset of relJ, so relI is redundant
        isRedundant = true
        break
    if not isRedundant:
      result.add(relI)


func mergeRelations*(relA, relB: Relation): Relation =
  ## Merge two relations by combining their variables
  var mergedVars: seq[VariableIndex]

  for v in relA.varIndices:
    mergedVars.add(v)
  for v in relB.varIndices:
    if v notin mergedVars:
      mergedVars.add(v)

  mergedVars.sort(cmp)
  initRelation(mergedVars)


func removeVariableFromRelation*(rel: Relation; varToRemove: VariableIndex): Relation =
  ## Create new relation with specified variable removed
  var newVars: seq[VariableIndex]
  for v in rel.varIndices:
    if v != varToRemove:
      newVars.add(v)
  initRelation(newVars)


func addVariableToRelation*(rel: Relation; varToAdd: VariableIndex): Relation =
  ## Create new relation with specified variable added
  var newVars = rel.varIndices
  if varToAdd notin newVars:
    newVars.add(varToAdd)
  newVars.sort(cmp)
  initRelation(newVars)


func findRelationWithVariable*(model: Model; varIdx: VariableIndex): Option[int] =
  ## Find index of first relation containing the given variable
  ## Returns none if not found
  for i in 0..<model.relationCount:
    if model.relations[i].containsVariable(varIdx):
      return some(i)
  none(int)


func findRelationPair*(model: Model; vi, vj: VariableIndex):
    tuple[relWithVi, relWithVj: Option[int]; bothInSame: bool] =
  ## Find relations containing vi and vj
  ## Returns indices of relations and whether they're in the same relation
  result.relWithVi = none(int)
  result.relWithVj = none(int)
  result.bothInSame = false

  for relIdx in 0..<model.relationCount:
    let rel = model.relations[relIdx]
    let hasVi = rel.containsVariable(vi)
    let hasVj = rel.containsVariable(vj)

    if hasVi and hasVj:
      result.bothInSame = true
      return

    if hasVi:
      result.relWithVi = some(relIdx)
    if hasVj:
      result.relWithVj = some(relIdx)


func findPredictiveRelation*(model: Model; varList: VariableList): Option[int] =
  ## Find index of the predictive relation (contains DV and at least one IV)
  ## Returns none if not found
  for i in 0..<model.relationCount:
    let rel = model.relations[i]
    if rel.containsDependent(varList) and not rel.isDependentOnly(varList):
      return some(i)
  none(int)


func findDVRelation*(model: Model; varList: VariableList): Option[int] =
  ## Find index of any relation containing the DV (including DV-only)
  ## Returns none if not found
  for i in 0..<model.relationCount:
    let rel = model.relations[i]
    if rel.containsDependent(varList):
      return some(i)
  none(int)


func findIndependentOnlyRelation*(model: Model; varList: VariableList): Option[int] =
  ## Find index of the IV-only relation (directed systems)
  ## Returns none if not found
  for i in 0..<model.relationCount:
    let rel = model.relations[i]
    if rel.isIndependentOnly(varList):
      return some(i)
  none(int)


func getIVsInRelation*(rel: Relation; varList: VariableList): seq[VariableIndex] =
  ## Get all independent variable indices in a relation
  result = @[]
  for v in rel.varIndices:
    if not varList[v].isDependent:
      result.add(v)


func buildModelExcludingRelation*(model: Model; excludeIdx: int): seq[Relation] =
  ## Build relation list excluding one relation
  result = @[]
  for i in 0..<model.relationCount:
    if i != excludeIdx:
      result.add(model.relations[i])


func buildModelReplacingRelation*(model: Model; replaceIdx: int; newRel: Relation): seq[Relation] =
  ## Build relation list with one relation replaced
  result = @[]
  for i in 0..<model.relationCount:
    if i == replaceIdx:
      result.add(newRel)
    else:
      result.add(model.relations[i])


# Re-export commonly used items for convenience
export Direction, Model, Relation, VariableIndex, VariableList
export initModel, initRelation, hasLoops, printName
