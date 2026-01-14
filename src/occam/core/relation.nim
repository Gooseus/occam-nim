## Relation type for OCCAM
## Represents a subset of variables in the model space

{.push raises: [].}

import std/[algorithm, hashes, options]
import types
import variable
import key
import table

type
  Relation* = object
    ## A relation is a subset of variables
    ## Variables are always stored in sorted order
    varIndices*: seq[VariableIndex]
    projectionTable: Option[ContingencyTable]


func variableCount*(r: Relation): int {.inline.} =
  ## Number of variables in the relation
  r.varIndices.len


func variables*(r: Relation): seq[VariableIndex] {.inline.} =
  ## Get the sorted list of variable indices
  r.varIndices


func hasVariable*(r: Relation; idx: VariableIndex): bool =
  ## Check if relation contains a specific variable
  for v in r.varIndices:
    if v == idx:
      return true
  false


func printName*(r: Relation; varList: VariableList): string =
  ## Get printable name from variable abbreviations
  result = ""
  for idx in r.varIndices:
    result.add(varList[idx].abbrev)


func nc*(r: Relation; varList: VariableList): int64 =
  ## Compute NC (cartesian product size) for this relation
  if r.varIndices.len == 0:
    return 1
  result = 1
  for idx in r.varIndices:
    result *= varList[idx].cardinality.toInt


func degreesOfFreedom*(r: Relation; varList: VariableList): int64 =
  ## Compute degrees of freedom for this relation
  ## DF = NC - 1 for a single relation
  if r.varIndices.len == 0:
    return 0
  r.nc(varList) - 1


func `==`*(a, b: Relation): bool =
  ## Check if two relations have the same variables
  a.varIndices == b.varIndices


func cmp*(a, b: Relation): int =
  ## Lexicographic comparison of relations
  let minLen = min(a.varIndices.len, b.varIndices.len)
  for i in 0..<minLen:
    let c = cmp(a.varIndices[i], b.varIndices[i])
    if c != 0: return c
  cmp(a.varIndices.len, b.varIndices.len)


func `<`*(a, b: Relation): bool =
  ## Less than comparison for sorting
  cmp(a, b) < 0


func hash*(r: Relation): Hash =
  ## Hash function for use in tables
  var h: Hash = 0
  for idx in r.varIndices:
    h = h !& hash(idx.toInt)
  !$h


func isSubsetOf*(a, b: Relation): bool =
  ## Check if a is a subset of b (all variables in a are in b)
  for idx in a.varIndices:
    if not b.hasVariable(idx):
      return false
  true


func isProperSubsetOf*(a, b: Relation): bool =
  ## Check if a is a proper subset of b (subset and not equal)
  a.isSubsetOf(b) and a.varIndices.len < b.varIndices.len


func overlaps*(a, b: Relation): bool =
  ## Check if two relations share any variables
  for idx in a.varIndices:
    if b.hasVariable(idx):
      return true
  false


func union*(a, b: Relation): Relation =
  ## Return union of two relations
  var combined = a.varIndices
  for idx in b.varIndices:
    if not a.hasVariable(idx):
      combined.add(idx)
  combined.sort(cmp)
  result.varIndices = combined


func intersection*(a, b: Relation): Relation =
  ## Return intersection of two relations
  var common: seq[VariableIndex]
  for idx in a.varIndices:
    if b.hasVariable(idx):
      common.add(idx)
  result.varIndices = common


func difference*(a, b: Relation): Relation =
  ## Return a - b (variables in a but not in b)
  var diff: seq[VariableIndex]
  for idx in a.varIndices:
    if not b.hasVariable(idx):
      diff.add(idx)
  result.varIndices = diff


func buildMask*(r: Relation; varList: VariableList): Key =
  ## Create mask with 0s for included variables, 1s (DontCare) elsewhere
  varList.buildMask(r.varIndices)


func containsDependent*(r: Relation; varList: VariableList): bool =
  ## Check if relation contains the dependent variable
  for idx in r.varIndices:
    if varList[idx].isDependent:
      return true
  false


func isIndependentOnly*(r: Relation; varList: VariableList): bool =
  ## Check if relation contains only independent variables
  for idx in r.varIndices:
    if varList[idx].isDependent:
      return false
  true


iterator items*(r: Relation): VariableIndex =
  ## Iterate over variable indices
  for idx in r.varIndices:
    yield idx


func initRelation*(indices: openArray[VariableIndex]): Relation =
  ## Create a new relation with the given variable indices
  ## Indices will be sorted automatically
  result.varIndices = @indices
  result.varIndices.sort(cmp)
  result.projectionTable = none(ContingencyTable)


func containsVariable*(r: Relation; idx: VariableIndex): bool {.inline.} =
  ## Alias for hasVariable - check if relation contains a specific variable
  r.hasVariable(idx)


func isDependentOnly*(r: Relation; varList: VariableList): bool =
  ## Check if relation contains only dependent variables
  for idx in r.varIndices:
    if not varList[idx].isDependent:
      return false
  true


func hasProjection*(r: Relation): bool =
  ## Check if relation has a projection table computed
  r.projectionTable.isSome


func projection*(r: Relation): ContingencyTable =
  ## Get the projection table (assumes it exists)
  r.projectionTable.get


proc setProjection*(r: var Relation; proj: ContingencyTable) =
  ## Set the projection table for this relation
  r.projectionTable = some(proj)

