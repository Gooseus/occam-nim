## Cache types for OCCAM
##
## Provides caching mechanisms for relations and models to avoid
## redundant computations during analysis.

{.push raises: [].}

import std/[tables, algorithm, options]
import ../core/types
import ../core/variable
import ../core/relation
import ../core/model

type
  RelationCache* = object
    ## Cache for relation objects indexed by their variable set
    cache: Table[string, Relation]

  ModelCache* = object
    ## Cache for model objects indexed by their canonical name
    cache: Table[string, Model]


# ============ Relation Cache ============

proc initRelationCache*(): RelationCache =
  ## Initialize an empty relation cache
  result.cache = initTable[string, Relation]()


proc cacheKey*(varIndices: seq[VariableIndex]): string =
  ## Create a cache key from sorted variable indices
  var sorted = varIndices
  sorted.sort(cmp)
  result = ""
  for i, idx in sorted:
    if i > 0: result.add(",")
    result.add($idx.toInt)


proc get*(rc: RelationCache; varIndices: seq[VariableIndex]): Option[Relation] =
  ## Get relation from cache, returns Some(relation) if found, none otherwise
  let key = cacheKey(varIndices)
  if key in rc.cache:
    try:
      some(rc.cache[key])
    except KeyError:
      none(Relation)
  else:
    none(Relation)


proc put*(rc: var RelationCache; rel: Relation): Relation =
  ## Put relation in cache, return (possibly existing) cached version
  let key = cacheKey(rel.varIndices)
  if key in rc.cache:
    try:
      rc.cache[key]
    except KeyError:
      rc.cache[key] = rel
      rel
  else:
    rc.cache[key] = rel
    rel


proc contains*(rc: RelationCache; varIndices: seq[VariableIndex]): bool =
  ## Check if relation is in cache
  cacheKey(varIndices) in rc.cache


proc len*(rc: RelationCache): int =
  ## Number of relations in cache
  rc.cache.len


proc clear*(rc: var RelationCache) =
  ## Clear all cached relations
  rc.cache.clear()


# ============ Model Cache ============

proc initModelCache*(): ModelCache =
  ## Initialize an empty model cache
  result.cache = initTable[string, Model]()


proc get*(mc: ModelCache; name: string): Option[Model] =
  ## Get model from cache by name, returns Some(model) if found, none otherwise
  if name in mc.cache:
    try:
      some(mc.cache[name])
    except KeyError:
      none(Model)
  else:
    none(Model)


proc put*(mc: var ModelCache; model: Model; varList: VariableList): Model =
  ## Put model in cache, return (possibly existing) cached version
  let name = model.printName(varList)
  if name in mc.cache:
    try:
      mc.cache[name]
    except KeyError:
      mc.cache[name] = model
      model
  else:
    mc.cache[name] = model
    model


proc contains*(mc: ModelCache; name: string): bool =
  ## Check if model is in cache by name
  name in mc.cache


proc len*(mc: ModelCache): int =
  ## Number of models in cache
  mc.cache.len


proc clear*(mc: var ModelCache) =
  ## Clear all cached models
  mc.cache.clear()


# Export types and basic functions
export RelationCache, ModelCache
export initRelationCache, initModelCache
