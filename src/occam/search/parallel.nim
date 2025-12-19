## Parallel Search Module
##
## Provides parallel exploration of model search space.
## Parallelizes at the LEVEL granularity - each thread processes
## one seed model and all its neighbors, amortizing thread overhead.
##
## Key insight: Individual model evaluation is fast (~0.1-3ms),
## but processing all neighbors of a seed model takes ~5-150ms,
## making thread overhead worthwhile.
##
## Usage:
##   let results = parallelSearchLevel(seeds, varList, inputTable,
##                                     SearchLoopless, SearchAIC, width)

{.push raises: [].}

import std/[cpuinfo, algorithm, tables, monotimes, times]
import ../core/types
import ../core/variable
import ../core/table as coretable
import ../core/relation
import ../core/model
import ../core/errors
import ../core/progress
import ../core/timing
import ../core/profile
import ../manager/vb
import ../manager/cache
import loopless
import full
import disjoint

type
  SearchStatistic* = enum
    ## Statistic to optimize during search
    SearchDDF   # Maximize degrees of freedom (ascending search)
    SearchAIC   # Minimize AIC
    SearchBIC   # Minimize BIC

  SearchFilter* = enum
    ## Type of search (determines neighbor generation)
    SearchLoopless
    SearchFull
    SearchDisjoint

  # Keep for backwards compatibility but prefer SearchFilter
  NeighborGenerator* = proc(model: Model): seq[Model] {.closure.}

  SearchCandidate* = object
    ## A candidate model with its computed statistic
    model*: Model
    name*: string       # Cached name for deduplication
    statistic*: float64

  LevelResult* = object
    ## Results from processing one level
    candidates*: seq[SearchCandidate]
    modelsEvaluated*: int
    looplessCount*: int          ## Models without loops (fast BP)
    loopCount*: int              ## Models with loops (slow IPF)

  SearchTimingResult* = object
    ## Timing results from a search operation
    totalTimeNs*: int64         ## Total wall-clock time
    levelTimesNs*: seq[int64]   ## Time per level
    modelsPerLevel*: seq[int]   ## Models evaluated per level
    totalModelsEvaluated*: int  ## Total models evaluated
    avgModelTimeNs*: float64    ## Average time per model
    cacheHitRate*: float64      ## Combined cache hit rate

  LevelStats* = object
    ## Statistics for one search level
    modelsEvaluated*: int
    looplessCount*: int
    loopCount*: int


proc computeStatistic(mgr: var VBManager; model: Model; stat: SearchStatistic): float64 {.raises: [JunctionTreeError, ConvergenceError, ComputationError].} =
  ## Compute the specified statistic for a model
  case stat
  of SearchDDF: float64(mgr.computeDDF(model))
  of SearchAIC: mgr.computeAIC(model)
  of SearchBIC: mgr.computeBIC(model)


proc generateNeighborsFor(
    mgr: var VBManager;
    model: Model;
    filter: SearchFilter;
    width: int
): seq[Model] =
  ## Generate neighbors based on filter type
  ## Creates thread-local search object to avoid closure issues
  case filter
  of SearchLoopless:
    let search = initLooplessSearch(mgr, width, 10)
    search.generateNeighbors(model)
  of SearchFull:
    let search = initFullSearch(mgr, width, 10)
    search.generateNeighbors(model)
  of SearchDisjoint:
    let search = initDisjointSearch(mgr, width, 10)
    search.generateNeighbors(model)


const MaxRelationSizeSeq = 15
  ## Maximum relation size for sequential evaluation (same as parallel)

proc isModelTooComplexSeq(model: Model): bool =
  ## Check if model has relations that are too large for practical evaluation
  for rel in model.relations:
    if rel.variableCount > MaxRelationSizeSeq:
      return true
  false

proc processOneSeedWithFilter(
    varList: VariableList;
    inputTable: coretable.ContingencyTable;
    seed: Model;
    filter: SearchFilter;
    stat: SearchStatistic;
    width: int;
    direction: Direction = Direction.Ascending
): LevelResult {.raises: [ValidationError, JunctionTreeError, ConvergenceError, ComputationError].} =
  ## Process one seed model using a search filter (thread-safe)
  ## Each call creates its own VBManager and search object

  # Create thread-local VBManager
  var mgr = newVBManager(varList, inputTable)
  mgr.setSearchDirection(direction)

  # Generate neighbors using thread-local search
  let neighbors = mgr.generateNeighborsFor(seed, filter, width)

  result.candidates = newSeq[SearchCandidate](neighbors.len)
  result.modelsEvaluated = neighbors.len
  result.looplessCount = 0
  result.loopCount = 0

  for i, neighbor in neighbors:
    # Check for loops BEFORE evaluation to track counts
    let hasLoop = neighbor.hasLoops(varList)

    # Skip overly complex loop models
    if neighbor.isModelTooComplexSeq() and hasLoop:
      result.candidates[i] = SearchCandidate(
        model: neighbor,
        name: "",  # Empty name marks as filtered
        statistic: Inf
      )
      result.loopCount += 1  # Still count as loop model (skipped)
      continue

    # Track loop vs loopless
    if hasLoop:
      result.loopCount += 1
    else:
      result.looplessCount += 1

    let name = neighbor.printName(varList)
    let statValue = mgr.computeStatistic(neighbor, stat)
    result.candidates[i] = SearchCandidate(
      model: neighbor,
      name: name,
      statistic: statValue
    )


# Legacy: closure-based version (not thread-safe)
proc processOneSeed*(
    varList: VariableList;
    inputTable: coretable.ContingencyTable;
    seed: Model;
    neighborGen: NeighborGenerator;
    stat: SearchStatistic
): LevelResult {.raises: [ValidationError, JunctionTreeError, ConvergenceError, ComputationError, Exception].} =
  ## Process one seed model: generate all neighbors and evaluate them
  ## WARNING: Not thread-safe due to closure capture

  # Create thread-local VBManager
  var mgr = newVBManager(varList, inputTable)

  # Generate all neighbors
  let neighbors = neighborGen(seed)

  result.candidates = newSeq[SearchCandidate](neighbors.len)
  result.modelsEvaluated = neighbors.len

  for i, neighbor in neighbors:
    let name = neighbor.printName(varList)
    let statValue = mgr.computeStatistic(neighbor, stat)
    result.candidates[i] = SearchCandidate(
      model: neighbor,
      name: name,
      statistic: statValue
    )


proc mergeCandidates(results: seq[LevelResult]): seq[SearchCandidate] =
  ## Merge candidates from all threads, deduplicating by name
  var seen = initTable[string, int]()  # name -> index in result
  result = @[]

  for levelResult in results:
    for candidate in levelResult.candidates:
      if candidate.name notin seen:
        seen[candidate.name] = result.len
        result.add(candidate)


proc sortCandidates(candidates: var seq[SearchCandidate]; stat: SearchStatistic) =
  ## Sort candidates by statistic (ascending for AIC/BIC, descending for DDF)
  if stat == SearchDDF:
    candidates.sort(proc(a, b: SearchCandidate): int = cmp(b.statistic, a.statistic))
  else:
    candidates.sort(proc(a, b: SearchCandidate): int = cmp(a.statistic, b.statistic))


proc selectBest(candidates: seq[SearchCandidate]; width: int): seq[SearchCandidate] =
  ## Select the top 'width' candidates
  if candidates.len <= width:
    candidates
  else:
    candidates[0..<width]


# ============ Sequential Implementation (baseline) ============

proc searchLevelSequential*(
    varList: VariableList;
    inputTable: coretable.ContingencyTable;
    seeds: seq[Model];
    filter: SearchFilter;
    stat: SearchStatistic;
    width: int;
    direction: Direction = Direction.Ascending
): (seq[Model], LevelStats) {.raises: [ValidationError, JunctionTreeError, ConvergenceError, ComputationError].} =
  ## Process one search level sequentially
  ## Returns (best models for next level, stats including loop counts for ALL evaluated)

  if seeds.len == 0:
    return (@[], LevelStats())

  var allResults: seq[LevelResult]

  for seed in seeds:
    allResults.add(processOneSeedWithFilter(varList, inputTable, seed, filter, stat, width, direction))

  var candidates = mergeCandidates(allResults)
  sortCandidates(candidates, stat)
  let best = selectBest(candidates, width)

  # Aggregate stats from all results
  var stats = LevelStats()
  for r in allResults:
    stats.modelsEvaluated += r.modelsEvaluated
    stats.looplessCount += r.looplessCount
    stats.loopCount += r.loopCount

  var models: seq[Model]
  for c in best:
    models.add(c.model)

  (models, stats)


# Legacy closure-based version (not thread-safe)
proc searchLevelSequentialLegacy*(
    varList: VariableList;
    inputTable: coretable.ContingencyTable;
    seeds: seq[Model];
    neighborGen: NeighborGenerator;
    stat: SearchStatistic;
    width: int
): (seq[Model], int) {.raises: [ValidationError, JunctionTreeError, ConvergenceError, ComputationError, Exception].} =
  ## Process one search level sequentially using closure (legacy)
  ## WARNING: Not thread-safe

  if seeds.len == 0:
    return (@[], 0)

  var allResults: seq[LevelResult]

  for seed in seeds:
    allResults.add(processOneSeed(varList, inputTable, seed, neighborGen, stat))

  var candidates = mergeCandidates(allResults)
  sortCandidates(candidates, stat)
  let best = selectBest(candidates, width)

  var totalEvaluated = 0
  for r in allResults:
    totalEvaluated += r.modelsEvaluated

  var models: seq[Model]
  for c in best:
    models.add(c.model)

  (models, totalEvaluated)


# ============ Parallel Implementation (malebolgia) ============

when compileOption("threads"):
  import malebolgia

  # Global storage for parallel results (avoids arrow syntax issues in older malebolgia)
  var gParallelResults: seq[LevelResult]

  # Global storage for neighbor-level parallelization
  var gNeighborCandidates: seq[SearchCandidate]

  const MaxRelationSizeForFull = 15
    ## Maximum relation size for full search evaluation
    ## Models with relations larger than this are skipped (too expensive for IPF)

  proc isModelTooComplex(model: Model; varList: VariableList): bool =
    ## Check if model has relations that are too large for practical evaluation
    ## Returns true if any relation has more than MaxRelationSizeForFull variables
    for rel in model.relations:
      if rel.variableCount > MaxRelationSizeForFull:
        return true
    false

  proc evaluateNeighborWorkerInto(
      idx: int;
      varList: VariableList;
      inputTable: coretable.ContingencyTable;
      neighbor: Model;
      stat: SearchStatistic;
      direction: Direction
  ) {.gcsafe, raises: [].} =
    ## Thread-safe worker that evaluates a single neighbor model
    ## Each call creates its own VBManager for thread safety
    {.cast(gcsafe).}:
      try:
        # Skip overly complex models (would take too long with IPF)
        if neighbor.isModelTooComplex(varList) and neighbor.hasLoops(varList):
          gNeighborCandidates[idx] = SearchCandidate(
            model: neighbor,
            name: "",  # Empty name marks as filtered
            statistic: Inf
          )
          return

        var mgr = newVBManager(varList, inputTable)
        mgr.setSearchDirection(direction)
        let name = neighbor.printName(varList)
        let statValue = mgr.computeStatistic(neighbor, stat)
        gNeighborCandidates[idx] = SearchCandidate(
          model: neighbor,
          name: name,
          statistic: statValue
        )
      except ValidationError, JunctionTreeError, ConvergenceError, ComputationError:
        # On error, mark with empty name (will be filtered)
        gNeighborCandidates[idx] = SearchCandidate(
          model: neighbor,
          name: "",
          statistic: Inf  # Will sort to bottom
        )


  proc evaluateNeighborsParallel(
      varList: VariableList;
      inputTable: coretable.ContingencyTable;
      neighbors: seq[Model];
      stat: SearchStatistic;
      direction: Direction
  ): seq[SearchCandidate] {.raises: [ValueError].} =
    ## Evaluate multiple neighbor models in parallel
    ## Returns evaluated candidates (some may have errors marked with empty name)
    if neighbors.len == 0:
      return @[]

    # Allocate result storage
    gNeighborCandidates = newSeq[SearchCandidate](neighbors.len)

    # Evaluate neighbors in parallel
    var m = createMaster()
    m.awaitAll:
      for i, neighbor in neighbors:
        m.spawn evaluateNeighborWorkerInto(i, varList, inputTable, neighbor, stat, direction)

    # Filter out error entries (empty name)
    result = @[]
    for candidate in gNeighborCandidates:
      if candidate.name.len > 0:
        result.add(candidate)


  proc processOneSeedWithFilterParallel(
      varList: VariableList;
      inputTable: coretable.ContingencyTable;
      seed: Model;
      filter: SearchFilter;
      stat: SearchStatistic;
      width: int;
      direction: Direction
  ): LevelResult {.raises: [ValidationError, JunctionTreeError, ConvergenceError, ComputationError, ValueError].} =
    ## Process one seed model with parallel neighbor evaluation
    ## Use this when there's a single seed with many neighbors (Level 1 scenario)

    # Create manager just for neighbor generation
    var mgr = newVBManager(varList, inputTable)
    mgr.setSearchDirection(direction)

    # Generate neighbors
    let neighbors = mgr.generateNeighborsFor(seed, filter, width)

    if neighbors.len == 0:
      return LevelResult(candidates: @[], modelsEvaluated: 0, looplessCount: 0, loopCount: 0)

    # Count loops before parallel evaluation
    for neighbor in neighbors:
      if neighbor.hasLoops(varList):
        result.loopCount += 1
      else:
        result.looplessCount += 1

    # Evaluate neighbors in parallel
    result.candidates = evaluateNeighborsParallel(varList, inputTable, neighbors, stat, direction)
    result.modelsEvaluated = neighbors.len


  proc processOneSeedWorkerInto(
      idx: int;
      varList: VariableList;
      inputTable: coretable.ContingencyTable;
      seed: Model;
      filter: SearchFilter;
      stat: SearchStatistic;
      width: int;
      direction: Direction
  ) {.gcsafe, raises: [].} =
    ## Thread-safe worker that stores result in global array
    ## Exceptions are caught internally since spawn requires raises: []
    {.cast(gcsafe).}:
      try:
        gParallelResults[idx] = processOneSeedWithFilter(varList, inputTable, seed, filter, stat, width, direction)
      except ValidationError, JunctionTreeError, ConvergenceError, ComputationError:
        # On error, leave result empty (will be filtered out during merge)
        gParallelResults[idx] = LevelResult(candidates: @[], modelsEvaluated: 0)


  proc searchLevelParallel*(
      varList: VariableList;
      inputTable: coretable.ContingencyTable;
      seeds: seq[Model];
      filter: SearchFilter;
      stat: SearchStatistic;
      width: int;
      direction: Direction = Direction.Ascending
  ): (seq[Model], LevelStats) {.raises: [ValidationError, JunctionTreeError, ConvergenceError, ComputationError, ValueError].} =
    ## Process one search level in parallel using malebolgia
    ## Each seed model is processed by a separate thread
    ## Returns (selected models, stats including loop counts for ALL evaluated models)
    ##
    ## This provides ~4-5x speedup on workloads with multiple seeds.

    if seeds.len == 0:
      return (@[], LevelStats())

    let numCores = countProcessors()

    # For single seed, use neighbor-level parallelization instead of seed-level
    # This is critical for Level 1 performance where we have 1 seed but many neighbors
    if seeds.len == 1 and numCores >= 2:
      var levelResult = processOneSeedWithFilterParallel(
        varList, inputTable, seeds[0], filter, stat, width, direction
      )
      sortCandidates(levelResult.candidates, stat)
      let best = selectBest(levelResult.candidates, width)
      var models: seq[Model]
      for c in best:
        models.add(c.model)
      let stats = LevelStats(
        modelsEvaluated: levelResult.modelsEvaluated,
        looplessCount: levelResult.looplessCount,
        loopCount: levelResult.loopCount
      )
      return (models, stats)

    # Fallback to sequential if no parallelization available
    if numCores < 2:
      return searchLevelSequential(varList, inputTable, seeds, filter, stat, width, direction)

    # Allocate result storage
    gParallelResults = newSeq[LevelResult](seeds.len)

    # Process seeds in parallel using malebolgia
    var m = createMaster()
    m.awaitAll:
      for i, seed in seeds:
        m.spawn processOneSeedWorkerInto(i, varList, inputTable, seed, filter, stat, width, direction)

    # Merge, sort, select from results
    var candidates = mergeCandidates(gParallelResults)
    sortCandidates(candidates, stat)
    let best = selectBest(candidates, width)

    # Aggregate stats from all parallel results
    var stats = LevelStats()
    for r in gParallelResults:
      stats.modelsEvaluated += r.modelsEvaluated
      stats.looplessCount += r.looplessCount
      stats.loopCount += r.loopCount

    var models: seq[Model]
    for c in best:
      models.add(c.model)

    (models, stats)


else:
  # Fallback when threads not enabled
  proc searchLevelParallel*(
      varList: VariableList;
      inputTable: coretable.ContingencyTable;
      seeds: seq[Model];
      filter: SearchFilter;
      stat: SearchStatistic;
      width: int;
      direction: Direction = Direction.Ascending
  ): (seq[Model], LevelStats) {.raises: [ValidationError, JunctionTreeError, ConvergenceError, ComputationError, ValueError].} =
    searchLevelSequential(varList, inputTable, seeds, filter, stat, width, direction)


# ============ Full Search with Multiple Levels ============

proc parallelSearch*(
    varList: VariableList;
    inputTable: coretable.ContingencyTable;
    startModel: Model;
    filter: SearchFilter;
    stat: SearchStatistic;
    width: int;
    maxLevels: int;
    useParallel = true;
    progress: ProgressConfig = initProgressConfig();
    direction: Direction = Direction.Ascending
): seq[SearchCandidate] {.raises: [ValidationError, JunctionTreeError, ConvergenceError, ComputationError, ValueError, Exception].} =
  ## Perform full parallel search from a starting model
  ## Returns all unique models found, sorted by statistic
  ##
  ## Parameters:
  ##   direction - Search direction (Ascending = up from bottom, Descending = down from top)
  ##   progress - Optional progress reporting config. When enabled,
  ##              emits events at search start, after each level, and on completion.

  # Determine statistic name for progress reporting
  let statName = case stat
    of SearchDDF: "DDF"
    of SearchAIC: "AIC"
    of SearchBIC: "BIC"

  # Emit search started event
  progress.emit(makeSearchStartEvent(maxLevels, statName))

  var currentLevel = @[startModel]
  var allCandidates: seq[SearchCandidate]
  var seen = initTable[string, bool]()
  var totalModelsEvaluated = 0

  # Add starting model
  var mgr = initVBManager(varList, inputTable)
  let startName = startModel.printName(varList)
  let startStat = mgr.computeStatistic(startModel, stat)
  allCandidates.add(SearchCandidate(
    model: startModel,
    name: startName,
    statistic: startStat
  ))
  seen[startName] = true
  totalModelsEvaluated += 1

  for level in 1..maxLevels:
    if currentLevel.len == 0:
      break

    let (nextModels, levelStats) = if useParallel:
      searchLevelParallel(varList, inputTable, currentLevel, filter, stat, width, direction)
    else:
      searchLevelSequential(varList, inputTable, currentLevel, filter, stat, width, direction)

    totalModelsEvaluated += levelStats.modelsEvaluated

    # Add new unique models to allCandidates
    for model in nextModels:
      let name = model.printName(varList)
      if name notin seen:
        seen[name] = true
        let statValue = mgr.computeStatistic(model, stat)
        allCandidates.add(SearchCandidate(
          model: model,
          name: name,
          statistic: statValue
        ))

    currentLevel = nextModels

    # Use loop counts from ALL evaluated models (not just selected)
    # This is critical for understanding why BIC is slow!

    # Emit level progress event with loop breakdown
    sortCandidates(allCandidates, stat)
    let bestName = if allCandidates.len > 0: allCandidates[0].name else: ""
    let bestStat = if allCandidates.len > 0: allCandidates[0].statistic else: 0.0
    progress.emit(makeLevelEventWithLoops(
      level, maxLevels, totalModelsEvaluated,
      levelStats.looplessCount, levelStats.loopCount,
      bestName, bestStat, statName
    ))

  sortCandidates(allCandidates, stat)

  # Emit search complete event
  let finalBestName = if allCandidates.len > 0: allCandidates[0].name else: ""
  let finalBestStat = if allCandidates.len > 0: allCandidates[0].statistic else: 0.0
  progress.emit(makeCompleteEvent(totalModelsEvaluated, finalBestName, finalBestStat, statName))

  allCandidates


proc parallelSearchTimed*(
    varList: VariableList;
    inputTable: coretable.ContingencyTable;
    startModel: Model;
    filter: SearchFilter;
    stat: SearchStatistic;
    width: int;
    maxLevels: int;
    useParallel = true;
    progress: ProgressConfig = initProgressConfig();
    direction: Direction = Direction.Ascending
): (seq[SearchCandidate], SearchTimingResult) {.raises: [ValidationError, JunctionTreeError, ConvergenceError, ComputationError, ValueError, Exception].} =
  ## Perform full parallel search with detailed timing information
  ## Returns (candidates, timing) tuple
  ##
  ## This variant provides:
  ## - Wall-clock timing using getMonoTime()
  ## - Runtime estimation with ETA in progress events
  ## - Per-level timing breakdown
  ## - Cache hit rate tracking

  let searchStart = getMonoTime()

  # Initialize timing result
  var timing = SearchTimingResult(
    levelTimesNs: newSeqOfCap[int64](maxLevels),
    modelsPerLevel: newSeqOfCap[int](maxLevels)
  )

  # Initialize runtime estimator for ETA
  var estimator = initRuntimeEstimator(maxLevels)
  estimator.start()

  # Determine statistic name for progress reporting
  let statName = case stat
    of SearchDDF: "DDF"
    of SearchAIC: "AIC"
    of SearchBIC: "BIC"

  # Emit search started event
  progress.emit(makeSearchStartEvent(maxLevels, statName))

  var currentLevel = @[startModel]
  var allCandidates: seq[SearchCandidate]
  var seen = initTable[string, bool]()
  var totalModelsEvaluated = 0

  # Add starting model
  var mgr = initVBManager(varList, inputTable)
  mgr.resetCacheStats()

  let startName = startModel.printName(varList)
  let startStat = mgr.computeStatistic(startModel, stat)
  allCandidates.add(SearchCandidate(
    model: startModel,
    name: startName,
    statistic: startStat
  ))
  seen[startName] = true
  totalModelsEvaluated += 1

  for level in 1..maxLevels:
    if currentLevel.len == 0:
      break

    let levelStart = getMonoTime()

    let (nextModels, levelStats) = if useParallel:
      searchLevelParallel(varList, inputTable, currentLevel, filter, stat, width, direction)
    else:
      searchLevelSequential(varList, inputTable, currentLevel, filter, stat, width, direction)

    let levelTimeNs = (getMonoTime() - levelStart).inNanoseconds
    timing.levelTimesNs.add(levelTimeNs)
    timing.modelsPerLevel.add(levelStats.modelsEvaluated)

    totalModelsEvaluated += levelStats.modelsEvaluated

    # Update estimator
    estimator.recordUnit(levelTimeNs)

    # Add new unique models to allCandidates
    for model in nextModels:
      let name = model.printName(varList)
      if name notin seen:
        seen[name] = true
        let statValue = mgr.computeStatistic(model, stat)
        allCandidates.add(SearchCandidate(
          model: model,
          name: name,
          statistic: statValue
        ))

    currentLevel = nextModels

    # Use loop counts from ALL evaluated models (not just selected)
    # This shows why BIC is slow - it evaluates more loop models!

    # Emit level progress event with timing and loop breakdown
    sortCandidates(allCandidates, stat)
    let bestName = if allCandidates.len > 0: allCandidates[0].name else: ""
    let bestStat = if allCandidates.len > 0: allCandidates[0].statistic else: 0.0
    let elapsedNs = (getMonoTime() - searchStart).inNanoseconds
    let avgModelTime = if totalModelsEvaluated > 0:
      float64(elapsedNs) / float64(totalModelsEvaluated)
    else:
      0.0

    progress.emit(makeLevelEventWithTiming(
      level, maxLevels, totalModelsEvaluated,
      bestName, bestStat, statName,
      elapsedNs, estimator.estimateRemainingNs(),
      levelTimeNs, avgModelTime,
      mgr.getCacheHitRate(),
      levelStats.looplessCount, levelStats.loopCount
    ))

  sortCandidates(allCandidates, stat)

  # Finalize timing
  timing.totalTimeNs = (getMonoTime() - searchStart).inNanoseconds
  timing.totalModelsEvaluated = totalModelsEvaluated
  timing.avgModelTimeNs = if totalModelsEvaluated > 0:
    float64(timing.totalTimeNs) / float64(totalModelsEvaluated)
  else:
    0.0
  timing.cacheHitRate = mgr.getCacheHitRate()

  # Emit search complete event with timing
  let finalBestName = if allCandidates.len > 0: allCandidates[0].name else: ""
  let finalBestStat = if allCandidates.len > 0: allCandidates[0].statistic else: 0.0
  progress.emit(makeCompleteEventWithTiming(
    totalModelsEvaluated, finalBestName, finalBestStat, statName,
    timing.totalTimeNs, timing.avgModelTimeNs, timing.cacheHitRate
  ))

  (allCandidates, timing)


# ============================================================================
# ResourceProfile conversion
# ============================================================================

proc toResourceProfile*(timing: SearchTimingResult; cacheStats: CacheStats): ResourceProfile =
  ## Convert SearchTimingResult to ResourceProfile for unified profiling output
  result.totalTimeNs = timing.totalTimeNs
  result.modelsEvaluated = timing.totalModelsEvaluated
  result.cacheStats = ProfileCacheStats(
    hits: cacheStats.hits,
    misses: cacheStats.misses,
    entries: cacheStats.entries
  )

  # Convert level times to level profiles
  for i, timeNs in timing.levelTimesNs:
    result.levelProfiles.add(LevelProfile(
      level: i + 1,
      timeNs: timeNs,
      modelsEvaluated: if i < timing.modelsPerLevel.len: timing.modelsPerLevel[i] else: 0
    ))

  # Add projection stats if profiling is enabled
  when defined(profileProjections):
    let (projCount, projTimeNs) = getProjectionStats()
    result.projectionCount = projCount
    result.projectionTimeNs = projTimeNs


proc parallelSearchProfiled*(
    varList: VariableList;
    inputTable: coretable.ContingencyTable;
    startModel: Model;
    filter: SearchFilter;
    stat: SearchStatistic;
    width: int;
    maxLevels: int;
    useParallel = true;
    progress: ProgressConfig = initProgressConfig();
    direction: Direction = Direction.Ascending;
    profileConfig: ProfileConfig = initProfileConfig(pgSummary)
): (seq[SearchCandidate], ResourceProfile) {.raises: [ValidationError, JunctionTreeError, ConvergenceError, ComputationError, ValueError, Exception].} =
  ## Perform parallel search with full resource profiling
  ## Returns (candidates, profile) tuple
  ##
  ## This variant provides:
  ## - All timing from parallelSearchTimed
  ## - Memory tracking (peak RSS on posix)
  ## - Per-level breakdown
  ## - Projection statistics (when compiled with -d:profileProjections)

  # Reset projection stats if profiling
  when defined(profileProjections):
    resetProjectionStats()

  # Capture starting memory
  let startMemory = if profileConfig.trackMemory: getCurrentMemoryBytes() else: 0'i64

  # Run the timed search
  let (candidates, timing) = parallelSearchTimed(
    varList, inputTable, startModel, filter, stat, width, maxLevels,
    useParallel, progress, direction
  )

  # Get cache stats for the profile
  var mgr = initVBManager(varList, inputTable)
  let cacheStats = mgr.getCombinedCacheStats()

  # Convert to ResourceProfile
  var profile = timing.toResourceProfile(cacheStats)

  # Add memory tracking
  if profileConfig.trackMemory:
    profile.startMemoryBytes = startMemory
    profile.peakMemoryBytes = getPeakMemoryBytes()

  (candidates, profile)


# Exports
export SearchStatistic, SearchFilter, NeighborGenerator, SearchCandidate, LevelResult, SearchTimingResult
export processOneSeed, processOneSeedWithFilter, mergeCandidates, sortCandidates, selectBest
export searchLevelSequential, searchLevelSequentialLegacy, searchLevelParallel, parallelSearch, parallelSearchTimed
export parallelSearchProfiled, toResourceProfile
export progress, timing, profile
