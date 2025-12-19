## Resource & Performance Profiling for OCCAM-Nim
##
## Provides optional, granular profiling of Search and Fit operations.
## Designed for zero overhead when disabled.
##
## Usage:
##   let config = initProfileConfig(pgOperations)
##   var profiler = initProfileAccumulator(config)
##   profiler.start()
##   # ... operations ...
##   let profile = profiler.toResourceProfile()
##   echo profile.toJson().pretty()

import std/[tables, json, monotimes, times, strformat]

# Platform-specific memory tracking
when defined(posix):
  proc c_getrusage(who: cint; usage: pointer): cint {.importc: "getrusage", header: "<sys/resource.h>".}

  type
    CRusage {.importc: "struct rusage", header: "<sys/resource.h>".} = object
      ru_maxrss: clong  # Maximum resident set size

type
  ProfileGranularity* = enum
    ## Level of detail for profiling
    pgNone        ## Disabled - zero overhead
    pgSummary     ## Total time + cache stats only
    pgOperations  ## Time per operation type (fit, projection, etc.)
    pgDetailed    ## Per-call timing with min/max/avg

  ProfileConfig* = object
    ## Configuration for profiling behavior
    enabled*: bool
    granularity*: ProfileGranularity
    trackMemory*: bool  ## Track peak memory (posix only)

  ProfileCacheStats* = object
    ## Cache statistics for profiling (standalone, no external deps)
    hits*: int
    misses*: int
    entries*: int

  OperationProfile* = object
    ## Profile for a single operation type
    name*: string
    totalTimeNs*: int64
    callCount*: int
    minTimeNs*: int64
    maxTimeNs*: int64
    # Computed on finalization
    avgTimeNs*: int64
    # For IPF specifically
    totalIterations*: int
    # For cache operations
    hits*: int
    misses*: int

  LevelProfile* = object
    ## Profile for a single search level
    level*: int
    timeNs*: int64
    modelsEvaluated*: int
    # Breakdown by fit type
    fitLooplessCount*: int
    fitLooplessTimeNs*: int64
    fitIPFCount*: int
    fitIPFTimeNs*: int64
    fitSaturatedCount*: int
    fitIndependenceCount*: int

  ResourceProfile* = object
    ## Complete resource profile for an operation
    totalTimeNs*: int64
    operations*: Table[string, OperationProfile]
    cacheStats*: ProfileCacheStats
    modelsEvaluated*: int
    # Memory (optional, posix only)
    peakMemoryBytes*: int64
    startMemoryBytes*: int64
    # Hierarchical breakdown for search
    levelProfiles*: seq[LevelProfile]
    # Projection stats (when compiled with -d:profileProjections)
    projectionCount*: int
    projectionTimeNs*: int64

  ProfileAccumulator* = ref object
    ## Accumulator for collecting profiling metrics during execution.
    ## Use `ref object` so it can be nil when profiling is disabled.
    config*: ProfileConfig
    startTime: MonoTime
    startMemory: int64
    operations: Table[string, OperationProfile]
    currentLevel: int
    levelProfiles: seq[LevelProfile]
    modelsEvaluated: int


# ============================================================================
# ProfileCacheStats utilities
# ============================================================================

proc initProfileCacheStats*(): ProfileCacheStats =
  ProfileCacheStats(hits: 0, misses: 0, entries: 0)

proc hitRate*(stats: ProfileCacheStats): float64 =
  ## Calculate hit rate as a percentage (0.0 to 1.0)
  let total = stats.hits + stats.misses
  if total == 0: 0.0
  else: float64(stats.hits) / float64(total)


# ============================================================================
# Memory Tracking (Platform-specific)
# ============================================================================

when defined(posix):
  const RUSAGE_SELF = 0.cint

  proc getPeakMemoryBytes*(): int64 =
    ## Get peak RSS in bytes (macOS/Linux only)
    var usage: CRusage
    if c_getrusage(RUSAGE_SELF, addr usage) == 0:
      when defined(macosx):
        result = int64(usage.ru_maxrss)  # bytes on macOS
      else:
        result = int64(usage.ru_maxrss) * 1024  # KB on Linux, convert to bytes
    else:
      result = 0

  proc getCurrentMemoryBytes*(): int64 =
    ## Get current RSS in bytes (approximate via peak for simplicity)
    getPeakMemoryBytes()

else:
  proc getPeakMemoryBytes*(): int64 = 0
  proc getCurrentMemoryBytes*(): int64 = 0


# ============================================================================
# ProfileConfig
# ============================================================================

proc initProfileConfig*(
    granularity = pgNone;
    trackMemory = false
): ProfileConfig =
  ## Initialize a profile configuration.
  ## Default is pgNone (disabled) for zero overhead.
  result.granularity = granularity
  result.enabled = granularity != pgNone
  result.trackMemory = trackMemory and (granularity != pgNone)


proc disabled*(): ProfileConfig {.inline.} =
  ## Convenience for disabled profiling
  initProfileConfig(pgNone)


proc summary*(): ProfileConfig {.inline.} =
  ## Convenience for summary profiling
  initProfileConfig(pgSummary, trackMemory = true)


proc operations*(): ProfileConfig {.inline.} =
  ## Convenience for operation-level profiling
  initProfileConfig(pgOperations, trackMemory = true)


proc detailed*(): ProfileConfig {.inline.} =
  ## Convenience for detailed profiling
  initProfileConfig(pgDetailed, trackMemory = true)


# ============================================================================
# ProfileAccumulator
# ============================================================================

proc initProfileAccumulator*(config: ProfileConfig): ProfileAccumulator =
  ## Create a new profile accumulator.
  ## Returns nil if profiling is disabled.
  if not config.enabled:
    return nil

  new(result)
  result.config = config
  result.operations = initTable[string, OperationProfile]()
  result.levelProfiles = @[]
  result.currentLevel = 0
  result.modelsEvaluated = 0


proc start*(acc: ProfileAccumulator) =
  ## Start the profiling timer
  if acc == nil:
    return
  acc.startTime = getMonoTime()
  if acc.config.trackMemory:
    acc.startMemory = getCurrentMemoryBytes()


proc recordOp*(acc: ProfileAccumulator; name: string; elapsedNs: int64;
               iterations = 0; hits = 0; misses = 0) =
  ## Record a single operation
  if acc == nil or not acc.config.enabled:
    return

  if acc.config.granularity < pgOperations:
    return  # Don't track individual operations in summary mode

  if name notin acc.operations:
    acc.operations[name] = OperationProfile(
      name: name,
      minTimeNs: int64.high,
      maxTimeNs: 0
    )

  var op = addr acc.operations[name]
  op.totalTimeNs += elapsedNs
  op.callCount += 1
  op.totalIterations += iterations
  op.hits += hits
  op.misses += misses

  if acc.config.granularity >= pgDetailed:
    if elapsedNs < op.minTimeNs:
      op.minTimeNs = elapsedNs
    if elapsedNs > op.maxTimeNs:
      op.maxTimeNs = elapsedNs


proc startLevel*(acc: ProfileAccumulator; level: int) =
  ## Start timing a search level
  if acc == nil:
    return
  acc.currentLevel = level
  # Ensure we have enough level profiles
  while acc.levelProfiles.len < level:
    acc.levelProfiles.add(LevelProfile(level: acc.levelProfiles.len + 1))


proc endLevel*(acc: ProfileAccumulator; level: int; timeNs: int64; modelsEvaluated: int) =
  ## End timing a search level
  if acc == nil:
    return
  if level > 0 and level <= acc.levelProfiles.len:
    acc.levelProfiles[level - 1].timeNs = timeNs
    acc.levelProfiles[level - 1].modelsEvaluated = modelsEvaluated


proc recordModel*(acc: ProfileAccumulator) =
  ## Record that a model was evaluated
  if acc == nil:
    return
  acc.modelsEvaluated += 1


proc recordFit*(acc: ProfileAccumulator; fitType: string; timeNs: int64) =
  ## Record a fit operation with its type
  if acc == nil:
    return

  # Record in operations table
  acc.recordOp(fitType, timeNs)

  # Also record in current level breakdown
  if acc.currentLevel > 0 and acc.currentLevel <= acc.levelProfiles.len:
    var lp = addr acc.levelProfiles[acc.currentLevel - 1]
    case fitType
    of "fit_loopless":
      lp.fitLooplessCount += 1
      lp.fitLooplessTimeNs += timeNs
    of "fit_ipf":
      lp.fitIPFCount += 1
      lp.fitIPFTimeNs += timeNs
    of "fit_saturated":
      lp.fitSaturatedCount += 1
    of "fit_independence":
      lp.fitIndependenceCount += 1
    else:
      discard


proc toResourceProfile*(acc: ProfileAccumulator; cacheStats = initProfileCacheStats()): ResourceProfile =
  ## Finalize the accumulator into a ResourceProfile
  if acc == nil:
    return ResourceProfile()

  result.totalTimeNs = inNanoseconds(getMonoTime() - acc.startTime)
  result.modelsEvaluated = acc.modelsEvaluated
  result.cacheStats = cacheStats
  result.levelProfiles = acc.levelProfiles

  # Copy and finalize operations
  result.operations = initTable[string, OperationProfile]()
  for name, op in acc.operations:
    var finalOp = op
    if finalOp.callCount > 0:
      finalOp.avgTimeNs = finalOp.totalTimeNs div finalOp.callCount
    if finalOp.minTimeNs == int64.high:
      finalOp.minTimeNs = 0
    result.operations[name] = finalOp

  # Memory tracking
  if acc.config.trackMemory:
    result.peakMemoryBytes = getPeakMemoryBytes()
    result.startMemoryBytes = acc.startMemory


# ============================================================================
# Zero-overhead profiling template
# ============================================================================

template profileOp*(acc: ProfileAccumulator; name: string; body: untyped) =
  ## Profile a code block with zero overhead when acc is nil.
  ## Usage:
  ##   profileOp(acc, "computeAIC"):
  ##     result = actualComputation()
  if acc != nil and acc.config.enabled:
    let profStart = getMonoTime()
    body
    acc.recordOp(name, inNanoseconds(getMonoTime() - profStart))
  else:
    body


template profileFit*(acc: ProfileAccumulator; fitType: string; body: untyped) =
  ## Profile a fit operation, recording both timing and fit type.
  if acc != nil and acc.config.enabled:
    let profStart = getMonoTime()
    body
    acc.recordFit(fitType, inNanoseconds(getMonoTime() - profStart))
  else:
    body


# ============================================================================
# JSON Export
# ============================================================================

proc formatBytes*(bytes: int64): string =
  ## Format bytes as human-readable string
  if bytes < 1024:
    return fmt"{bytes} B"
  elif bytes < 1024 * 1024:
    return fmt"{bytes.float / 1024.0:.1f} KB"
  elif bytes < 1024 * 1024 * 1024:
    return fmt"{bytes.float / (1024.0 * 1024.0):.1f} MB"
  else:
    return fmt"{bytes.float / (1024.0 * 1024.0 * 1024.0):.2f} GB"


proc toJson*(op: OperationProfile): JsonNode =
  ## Convert operation profile to JSON
  result = %*{
    "totalMs": op.totalTimeNs.float / 1_000_000.0,
    "count": op.callCount,
    "avgMs": op.avgTimeNs.float / 1_000_000.0
  }
  if op.minTimeNs > 0:
    result["minMs"] = %(op.minTimeNs.float / 1_000_000.0)
    result["maxMs"] = %(op.maxTimeNs.float / 1_000_000.0)
  if op.totalIterations > 0:
    result["totalIterations"] = %op.totalIterations
  if op.hits > 0 or op.misses > 0:
    result["hits"] = %op.hits
    result["misses"] = %op.misses
    let total = op.hits + op.misses
    if total > 0:
      result["hitRate"] = %(op.hits.float / total.float)


proc toJson*(lp: LevelProfile): JsonNode =
  ## Convert level profile to JSON
  result = %*{
    "level": lp.level,
    "timeMs": lp.timeNs.float / 1_000_000.0,
    "modelsEvaluated": lp.modelsEvaluated
  }
  if lp.fitLooplessCount > 0:
    result["fitLoopless"] = %*{
      "count": lp.fitLooplessCount,
      "timeMs": lp.fitLooplessTimeNs.float / 1_000_000.0
    }
  if lp.fitIPFCount > 0:
    result["fitIPF"] = %*{
      "count": lp.fitIPFCount,
      "timeMs": lp.fitIPFTimeNs.float / 1_000_000.0
    }
  if lp.fitSaturatedCount > 0:
    result["fitSaturatedCount"] = %lp.fitSaturatedCount
  if lp.fitIndependenceCount > 0:
    result["fitIndependenceCount"] = %lp.fitIndependenceCount


proc toJson*(profile: ResourceProfile): JsonNode =
  ## Convert resource profile to JSON
  result = %*{
    "totalTimeMs": profile.totalTimeNs.float / 1_000_000.0,
    "modelsEvaluated": profile.modelsEvaluated,
    "cacheHitRate": profile.cacheStats.hitRate
  }

  # Cache stats
  result["cache"] = %*{
    "hits": profile.cacheStats.hits,
    "misses": profile.cacheStats.misses,
    "entries": profile.cacheStats.entries,
    "hitRate": profile.cacheStats.hitRate
  }

  # Memory (if tracked)
  if profile.peakMemoryBytes > 0:
    result["memory"] = %*{
      "peakBytes": profile.peakMemoryBytes,
      "peakFormatted": formatBytes(profile.peakMemoryBytes),
      "startBytes": profile.startMemoryBytes
    }

  # Operations breakdown
  if profile.operations.len > 0:
    var opsJson = newJObject()
    for name, op in profile.operations:
      opsJson[name] = op.toJson()
    result["operations"] = opsJson

  # Level profiles
  if profile.levelProfiles.len > 0:
    var levelsJson = newJArray()
    for lp in profile.levelProfiles:
      levelsJson.add(lp.toJson())
    result["levels"] = levelsJson

  # Projection stats (when available)
  if profile.projectionCount > 0:
    result["projections"] = %*{
      "count": profile.projectionCount,
      "totalMs": profile.projectionTimeNs.float / 1_000_000.0,
      "avgUs": (profile.projectionTimeNs.float / profile.projectionCount.float) / 1000.0
    }


proc `$`*(profile: ResourceProfile): string =
  ## String representation for logging
  let hitRatePct = profile.cacheStats.hitRate * 100.0
  result = fmt"ResourceProfile(totalTime={profile.totalTimeNs.float / 1_000_000.0:.1f}ms, " &
           fmt"models={profile.modelsEvaluated}, cacheHitRate={hitRatePct:.1f}%)"


# ============================================================================
# Projection tracking (compile-time flag: -d:profileProjections)
# ============================================================================

when defined(profileProjections):
  var gProjectionCount* {.threadvar.}: int
  var gProjectionTimeNs* {.threadvar.}: int64

  proc resetProjectionStats*() =
    gProjectionCount = 0
    gProjectionTimeNs = 0

  proc getProjectionStats*(): (int, int64) =
    (gProjectionCount, gProjectionTimeNs)

  proc addProjectionStat*(timeNs: int64) =
    gProjectionCount += 1
    gProjectionTimeNs += timeNs

else:
  proc resetProjectionStats*() = discard
  proc getProjectionStats*(): (int, int64) = (0, 0'i64)
  proc addProjectionStat*(timeNs: int64) = discard


# ============================================================================
# Exports
# ============================================================================

export ProfileGranularity, ProfileConfig, ProfileCacheStats
export OperationProfile, LevelProfile, ResourceProfile, ProfileAccumulator
export initProfileConfig, disabled, summary, operations, detailed
export initProfileCacheStats, hitRate
export initProfileAccumulator, start, recordOp, startLevel, endLevel
export recordModel, recordFit, toResourceProfile
export profileOp, profileFit
export toJson, formatBytes
export getPeakMemoryBytes, getCurrentMemoryBytes
export resetProjectionStats, getProjectionStats, addProjectionStat
