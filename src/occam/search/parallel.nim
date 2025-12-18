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

import std/[cpuinfo, algorithm, tables]
import ../core/types
import ../core/variable
import ../core/table as coretable
import ../core/relation
import ../core/model
import ../core/errors
import ../core/progress
import ../manager/vb
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


proc processOneSeedWithFilter(
    varList: VariableList;
    inputTable: coretable.ContingencyTable;
    seed: Model;
    filter: SearchFilter;
    stat: SearchStatistic;
    width: int
): LevelResult {.raises: [ValidationError, JunctionTreeError, ConvergenceError, ComputationError].} =
  ## Process one seed model using a search filter (thread-safe)
  ## Each call creates its own VBManager and search object

  # Create thread-local VBManager
  var mgr = newVBManager(varList, inputTable)

  # Generate neighbors using thread-local search
  let neighbors = mgr.generateNeighborsFor(seed, filter, width)

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
    width: int
): (seq[Model], int) {.raises: [ValidationError, JunctionTreeError, ConvergenceError, ComputationError].} =
  ## Process one search level sequentially
  ## Returns (best models for next level, total models evaluated)

  if seeds.len == 0:
    return (@[], 0)

  var allResults: seq[LevelResult]

  for seed in seeds:
    allResults.add(processOneSeedWithFilter(varList, inputTable, seed, filter, stat, width))

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

  proc processOneSeedWorkerInto(
      idx: int;
      varList: VariableList;
      inputTable: coretable.ContingencyTable;
      seed: Model;
      filter: SearchFilter;
      stat: SearchStatistic;
      width: int
  ) {.gcsafe, raises: [].} =
    ## Thread-safe worker that stores result in global array
    ## Exceptions are caught internally since spawn requires raises: []
    {.cast(gcsafe).}:
      try:
        gParallelResults[idx] = processOneSeedWithFilter(varList, inputTable, seed, filter, stat, width)
      except ValidationError, JunctionTreeError, ConvergenceError, ComputationError:
        # On error, leave result empty (will be filtered out during merge)
        gParallelResults[idx] = LevelResult(candidates: @[], modelsEvaluated: 0)


  proc searchLevelParallel*(
      varList: VariableList;
      inputTable: coretable.ContingencyTable;
      seeds: seq[Model];
      filter: SearchFilter;
      stat: SearchStatistic;
      width: int
  ): (seq[Model], int) {.raises: [ValidationError, JunctionTreeError, ConvergenceError, ComputationError, ValueError].} =
    ## Process one search level in parallel using malebolgia
    ## Each seed model is processed by a separate thread
    ##
    ## This provides ~4-5x speedup on workloads with multiple seeds.

    if seeds.len == 0:
      return (@[], 0)

    # For single seed, sequential is faster (no parallelization benefit)
    let numCores = countProcessors()
    if seeds.len < 2 or numCores < 2:
      return searchLevelSequential(varList, inputTable, seeds, filter, stat, width)

    # Allocate result storage
    gParallelResults = newSeq[LevelResult](seeds.len)

    # Process seeds in parallel using malebolgia
    var m = createMaster()
    m.awaitAll:
      for i, seed in seeds:
        m.spawn processOneSeedWorkerInto(i, varList, inputTable, seed, filter, stat, width)

    # Merge, sort, select from results
    var candidates = mergeCandidates(gParallelResults)
    sortCandidates(candidates, stat)
    let best = selectBest(candidates, width)

    var totalEvaluated = 0
    for r in gParallelResults:
      totalEvaluated += r.modelsEvaluated

    var models: seq[Model]
    for c in best:
      models.add(c.model)

    (models, totalEvaluated)


else:
  # Fallback when threads not enabled
  proc searchLevelParallel*(
      varList: VariableList;
      inputTable: coretable.ContingencyTable;
      seeds: seq[Model];
      filter: SearchFilter;
      stat: SearchStatistic;
      width: int
  ): (seq[Model], int) {.raises: [ValidationError, JunctionTreeError, ConvergenceError, ComputationError, ValueError].} =
    searchLevelSequential(varList, inputTable, seeds, filter, stat, width)


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
    progress: ProgressConfig = initProgressConfig()
): seq[SearchCandidate] {.raises: [ValidationError, JunctionTreeError, ConvergenceError, ComputationError, ValueError, Exception].} =
  ## Perform full parallel search from a starting model
  ## Returns all unique models found, sorted by statistic
  ##
  ## Parameters:
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

    let (nextModels, levelEvaluated) = if useParallel:
      searchLevelParallel(varList, inputTable, currentLevel, filter, stat, width)
    else:
      searchLevelSequential(varList, inputTable, currentLevel, filter, stat, width)

    totalModelsEvaluated += levelEvaluated

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

    # Emit level progress event
    sortCandidates(allCandidates, stat)
    let bestName = if allCandidates.len > 0: allCandidates[0].name else: ""
    let bestStat = if allCandidates.len > 0: allCandidates[0].statistic else: 0.0
    progress.emit(makeLevelEvent(level, maxLevels, totalModelsEvaluated, bestName, bestStat, statName))

  sortCandidates(allCandidates, stat)

  # Emit search complete event
  let finalBestName = if allCandidates.len > 0: allCandidates[0].name else: ""
  let finalBestStat = if allCandidates.len > 0: allCandidates[0].statistic else: 0.0
  progress.emit(makeCompleteEvent(totalModelsEvaluated, finalBestName, finalBestStat, statName))

  allCandidates


# Exports
export SearchStatistic, SearchFilter, NeighborGenerator, SearchCandidate, LevelResult
export processOneSeed, processOneSeedWithFilter, mergeCandidates, sortCandidates, selectBest
export searchLevelSequential, searchLevelSequentialLegacy, searchLevelParallel, parallelSearch
export progress
