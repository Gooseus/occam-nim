## Model type for OCCAM
## Represents a hypothesis as a collection of relations

{.push raises: [].}

import std/[algorithm, options, hashes, sets]
import types
import variable
import relation
import graph

type
  Model* = object
    ## A model is a collection of relations
    ## Relations are always stored in sorted order
    relations*: seq[Relation]
    ## LIFETIME: progenitorModel is a raw pointer to avoid circular ref issues
    ## and copying large objects. The progenitor model MUST outlive this model.
    ## This is used for debugging/tracing search paths only.
    ## Currently unused in production code - only tested.
    progenitorModel: Option[ptr Model]
    modelId: int


func initModel*(relations: openArray[Relation] = []): Model =
  ## Create a new model with the given relations
  ## Relations will be sorted automatically
  result.relations = @relations
  result.relations.sort()
  result.progenitorModel = none(ptr Model)
  result.modelId = 0


func relationCount*(m: Model): int {.inline.} =
  ## Number of relations in the model
  m.relations.len


func `[]`*(m: Model; idx: int): Relation {.inline.} =
  ## Access relation by index
  m.relations[idx]


func printName*(m: Model; varList: VariableList): string =
  ## Get printable name from relation names, separated by colons
  if m.relations.len == 0:
    return ""
  result = m.relations[0].printName(varList)
  for i in 1..<m.relations.len:
    result.add(":")
    result.add(m.relations[i].printName(varList))


func containsRelation*(m: Model; r: Relation): bool =
  ## Check if any relation in the model contains (is superset of) the given relation
  for rel in m.relations:
    if r.isSubsetOf(rel):
      return true
  false


func containsModel*(m: Model; child: Model): bool =
  ## Check if this model is a parent (or ancestor) of the child
  ## in the model lattice. A parent is "above" the child (more constrained).
  ## This is true if every relation in the parent is a subset of some relation in the child.
  for parentRel in m.relations:
    var found = false
    for childRel in child.relations:
      if parentRel.isSubsetOf(childRel):
        found = true
        break
    if not found:
      return false
  true


func `==`*(a, b: Model): bool =
  ## Check if two models have the same relations
  a.relations == b.relations


func cmp*(a, b: Model): int =
  ## Lexicographic comparison of models
  let minLen = min(a.relations.len, b.relations.len)
  for i in 0..<minLen:
    let c = cmp(a.relations[i], b.relations[i])
    if c != 0: return c
  cmp(a.relations.len, b.relations.len)


func `<`*(a, b: Model): bool =
  ## Less than comparison for sorting
  cmp(a, b) < 0


func hash*(m: Model): Hash =
  ## Hash function for use in tables
  var h: Hash = 0
  for rel in m.relations:
    h = h !& hash(rel)
  !$h


func allVariables*(m: Model): seq[VariableIndex] =
  ## Get all unique variables across all relations
  var varSet: HashSet[int]
  for rel in m.relations:
    for idx in rel:
      varSet.incl(idx.toInt)
  for v in varSet:
    result.add(VariableIndex(v))
  result.sort(cmp)


func containsDependent*(m: Model; varList: VariableList): bool =
  ## Check if any relation in the model contains the dependent variable
  for rel in m.relations:
    if rel.containsDependent(varList):
      return true
  false


func progenitor*(m: Model): Option[ptr Model] {.inline.} =
  ## Get the progenitor (parent in search) of this model
  m.progenitorModel


proc setProgenitor*(m: var Model; parent: var Model) =
  ## Set the progenitor (parent in search) of this model
  m.progenitorModel = some(addr parent)


func id*(m: Model): int {.inline.} =
  ## Get the model's ID
  m.modelId


proc `id=`*(m: var Model; value: int) {.inline.} =
  ## Set the model's ID
  m.modelId = value


func createIndependenceModel*(varList: VariableList): Model =
  ## Create the independence model (all single-variable relations)
  var relations: seq[Relation]
  for idx, v in varList.pairs:
    relations.add(initRelation(@[idx]))
  initModel(relations)


func createSaturatedModel*(varList: VariableList): Model =
  ## Create the saturated model (one relation with all variables)
  var allIndices: seq[VariableIndex]
  for idx, v in varList.pairs:
    allIndices.add(idx)
  initModel(@[initRelation(allIndices)])


func isIndependenceModel*(m: Model; varList: VariableList): bool =
  ## Check if this is the independence model (all single-variable relations)
  if m.relations.len != varList.len:
    return false
  for rel in m.relations:
    if rel.variableCount != 1:
      return false
  true


func isSaturatedModel*(m: Model; varList: VariableList): bool =
  ## Check if this is the saturated model (one relation with all variables)
  if m.relations.len != 1:
    return false
  m.relations[0].variableCount == varList.len


iterator items*(m: Model): Relation =
  ## Iterate over relations
  for rel in m.relations:
    yield rel


iterator pairs*(m: Model): (int, Relation) =
  ## Iterate with indices
  for i, rel in m.relations:
    yield (i, rel)


func createIndependenceModel*(indices: seq[VariableIndex]): Model =
  ## Create an independence model from a list of variable indices
  ## Each variable becomes a single-variable relation
  var relations: seq[Relation]
  for idx in indices:
    relations.add(initRelation(@[idx]))
  initModel(relations)


func hasLoops*(m: Model; varList: VariableList): bool =
  ## Check if the model has loops using graph algorithms
  ##
  ## A model (hypergraph) is alpha-acyclic (decomposable) if and only if:
  ## 1. No relation is a subset of another (no redundancy)
  ## 2. The primal graph is chordal
  ## 3. Every maximal clique of the primal graph is contained in some relation
  ##
  ## This is equivalent to the model having a junction tree representation.
  ##
  ## Uses O(n² + v²) graph algorithms instead of the brute-force O(n × 2^n)
  ## approach of trying all RIP orderings.
  ##
  ## Reference: Beeri et al. (1983), Tarjan & Yannakakis (1984), Krippendorff (1986)
  hasLoopsViaGraph(m.relations)


func isDecomposable*(m: Model; varList: VariableList): bool =
  ## Check if the model is decomposable (has no loops)
  ##
  ## A decomposable model can be represented as a junction tree and
  ## fitted exactly using belief propagation. Non-decomposable models
  ## require iterative algorithms like IPF.
  ##
  ## This is the inverse of `hasLoops`.
  not hasLoopsViaGraph(m.relations)

