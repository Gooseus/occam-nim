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
  CacheStats* = object
    ## Statistics for cache performance tracking
    hits*: int       ## Number of cache hits
    misses*: int     ## Number of cache misses
    entries*: int    ## Current number of entries

  RelationCache* = object
    ## Cache for relation objects indexed by their variable set
    cache: Table[string, Relation]
    stats*: CacheStats

  ModelCache* = object
    ## Cache for model objects indexed by their canonical name
    cache: Table[string, Model]
    stats*: CacheStats


# ============ CacheStats Utilities ============

proc initCacheStats*(): CacheStats =
  ## Initialize empty cache statistics
  CacheStats(hits: 0, misses: 0, entries: 0)


proc hitRate*(stats: CacheStats): float64 =
  ## Calculate hit rate as a percentage (0.0 to 1.0)
  let total = stats.hits + stats.misses
  if total == 0:
    0.0
  else:
    float64(stats.hits) / float64(total)


proc reset*(stats: var CacheStats) =
  ## Reset statistics counters (but not entries count)
  stats.hits = 0
  stats.misses = 0


# ============ Relation Cache ============

proc initRelationCache*(): RelationCache =
  ## Initialize an empty relation cache
  result.cache = initTable[string, Relation]()
  result.stats = initCacheStats()


proc cacheKey*(varIndices: seq[VariableIndex]): string =
  ## Create a cache key from sorted variable indices
  var sorted = varIndices
  sorted.sort(cmp)
  result = ""
  for i, idx in sorted:
    if i > 0: result.add(",")
    result.add($idx.toInt)


proc get*(rc: var RelationCache; varIndices: seq[VariableIndex]): Option[Relation] =
  ## Get relation from cache, returns Some(relation) if found, none otherwise
  ## Updates cache statistics (hits/misses)
  let key = cacheKey(varIndices)
  if key in rc.cache:
    rc.stats.hits += 1
    try:
      some(rc.cache[key])
    except KeyError:
      none(Relation)
  else:
    rc.stats.misses += 1
    none(Relation)


proc put*(rc: var RelationCache; rel: Relation): Relation =
  ## Put relation in cache, return (possibly existing) cached version
  ## Updates entries count when adding new entries
  let key = cacheKey(rel.varIndices)
  if key in rc.cache:
    try:
      rc.cache[key]
    except KeyError:
      rc.cache[key] = rel
      rc.stats.entries += 1
      rel
  else:
    rc.cache[key] = rel
    rc.stats.entries += 1
    rel


proc contains*(rc: RelationCache; varIndices: seq[VariableIndex]): bool =
  ## Check if relation is in cache
  cacheKey(varIndices) in rc.cache


proc len*(rc: RelationCache): int =
  ## Number of relations in cache
  rc.cache.len


proc clear*(rc: var RelationCache) =
  ## Clear all cached relations and reset statistics
  rc.cache.clear()
  rc.stats = initCacheStats()


proc resetStats*(rc: var RelationCache) =
  ## Reset statistics counters without clearing cache
  rc.stats.hits = 0
  rc.stats.misses = 0
  rc.stats.entries = rc.cache.len


# ============ Model Cache ============

proc initModelCache*(): ModelCache =
  ## Initialize an empty model cache
  result.cache = initTable[string, Model]()
  result.stats = initCacheStats()


proc get*(mc: var ModelCache; name: string): Option[Model] =
  ## Get model from cache by name, returns Some(model) if found, none otherwise
  ## Updates cache statistics (hits/misses)
  if name in mc.cache:
    mc.stats.hits += 1
    try:
      some(mc.cache[name])
    except KeyError:
      none(Model)
  else:
    mc.stats.misses += 1
    none(Model)


proc put*(mc: var ModelCache; model: Model; varList: VariableList): Model =
  ## Put model in cache, return (possibly existing) cached version
  ## Updates entries count when adding new entries
  let name = model.printName(varList)
  if name in mc.cache:
    try:
      mc.cache[name]
    except KeyError:
      mc.cache[name] = model
      mc.stats.entries += 1
      model
  else:
    mc.cache[name] = model
    mc.stats.entries += 1
    model


proc contains*(mc: ModelCache; name: string): bool =
  ## Check if model is in cache by name
  name in mc.cache


proc len*(mc: ModelCache): int =
  ## Number of models in cache
  mc.cache.len


proc clear*(mc: var ModelCache) =
  ## Clear all cached models and reset statistics
  mc.cache.clear()
  mc.stats = initCacheStats()


proc resetStats*(mc: var ModelCache) =
  ## Reset statistics counters without clearing cache
  mc.stats.hits = 0
  mc.stats.misses = 0
  mc.stats.entries = mc.cache.len


# Export types and basic functions
export CacheStats, RelationCache, ModelCache
export initCacheStats, hitRate, reset
export initRelationCache, initModelCache, resetStats
