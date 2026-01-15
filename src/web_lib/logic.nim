## Web API Business Logic
##
## These functions process requests and return responses.
## They are separated from HTTP handling for testability.

import std/[cpuinfo, math, strutils]
import ../occam
import ../occam/core/progress
import ./models

const VERSION = "0.1.0"


# =============================================================================
# Loop Probability Estimation
# =============================================================================
# Based on random graph theory:
# - Expected triangles in G(n,p): E[tri] = C(n,3) * p³
# - For ascending search at level L: p ≈ 2L / (n(n-1))
# - E[tri] at level L ≈ 4L³(n-2) / (3n²(n-1)²)
#
# References:
# - Expected triangles: https://tsourakakis.com/2012/04/18/expected-number-of-triangles-in-gnm/
# - Decomposable neighbors: https://pmc.ncbi.nlm.nih.gov/articles/PMC2680312/
#   "for very large graphs the probability that addition/deletion results in
#    decomposable graph becomes vanishingly small"
# =============================================================================

proc expectedTriangles(n: int; level: int): float64 =
  ## Expected number of triangles at given search level for n variables.
  ## Based on random graph theory: E[tri] = C(n,3) * p³
  ## where p = edge density = ~level / maxEdges
  if n < 3 or level < 3:
    return 0.0

  # E[tri] = 4L³(n-2) / (3n²(n-1)²)
  let L = float64(level)
  let nf = float64(n)
  result = 4.0 * L * L * L * (nf - 2.0) / (3.0 * nf * nf * (nf - 1.0) * (nf - 1.0))


proc loopProbability(n: int; level: int; sortBy: string): float64 =
  ## Estimate probability that a model at given level has loops.
  ## Uses Poisson approximation: P(loop) ≈ 1 - exp(-E[triangles])
  ##
  ## CRITICAL: Sort method dramatically affects loop probability!
  ## - DDF sorting: stays with simpler models, avoids loops
  ## - BIC/AIC sorting: favors better-fitting models, hits loops early
  if level <= 2:
    return 0.0  # Levels 1-2 cannot have loops (need 3+ edges for a cycle)

  let expectedTri = expectedTriangles(n, level)

  # Sort-dependent bias:
  # - DDF: keeps search on simpler models, loop probability stays low
  # - BIC/AIC: better fit = more associations = more loops
  let sortMultiplier = case sortBy
    of "ddf": 0.5  # DDF stays loopless longer
    of "aic": 5.0  # AIC moderately favors loops
    else: 10.0    # BIC strongly favors loops (default)

  let adjustedTri = expectedTri * sortMultiplier

  # Poisson approximation for "at least one triangle"
  result = 1.0 - exp(-adjustedTri)

  # Cap at reasonable maximum
  result = min(result, 0.95)


proc estimateModelsAtLevel(n: int; level: int; width: int; isDown: bool): int =
  ## Estimate number of models evaluated at a given level.
  ## More accurate than simple decay formula.
  let maxEdges = n * (n - 1) div 2

  if level == 1:
    # Level 1: neighbors of starting model
    if isDown:
      return n  # Removing each variable from saturated
    else:
      return maxEdges  # All possible pairs

  # For subsequent levels: width seeds × neighbors per seed
  # Neighbors decrease as models become more specific
  var neighborsPerSeed: int
  if isDown:
    # Going down: neighbors = edges that can be removed
    # Decreases as model gets simpler
    neighborsPerSeed = max(maxEdges - level * width, n)
  else:
    # Going up: neighbors = edges that can be added + extensions
    # Initially grows, then decreases as model fills up
    let edgesUsed = level * 2  # Rough estimate
    neighborsPerSeed = min(maxEdges - edgesUsed + level, maxEdges)
    neighborsPerSeed = max(neighborsPerSeed, n)

  result = width * neighborsPerSeed

proc processHealthCheck*(): HealthResponse =
  ## Return health check response
  result.status = "ok"
  result.version = VERSION


proc processDataInfo*(dataJson: string): DataInfoResponse =
  ## Parse data and return info about variables
  let spec = parseDataSpec(dataJson)
  let varList = spec.toVariableList()
  let table = spec.toTable(varList)

  result.name = spec.name
  result.variableCount = varList.len
  result.sampleSize = table.sum

  for idx, v in varList.pairs:
    result.variables.add(VariableInfo(
      name: v.name,
      abbrev: v.abbrev,
      cardinality: v.cardinality.int,
      isDependent: v.isDependent
    ))


proc processFitModel*(req: FitRequest): FitResponse =
  ## Fit a model and return statistics
  let spec = parseDataSpec(req.data)
  let varList = spec.toVariableList()
  let table = spec.toTable(varList)

  var mgr = initVBManager(varList, table)
  let model = mgr.parseModel(req.model)
  let fit = mgr.fitModel(model)

  result.model = req.model
  result.h = fit.h
  result.t = fit.t
  result.df = fit.df
  result.ddf = fit.ddf
  result.lr = fit.lr
  result.aic = fit.aic
  result.bic = fit.bic
  result.alpha = fit.alpha
  result.hasLoops = fit.hasLoops
  result.ipfIterations = fit.ipfIterations
  result.ipfError = fit.ipfError


proc processSearch*(req: SearchRequest): SearchResponse =
  ## Run model search and return results
  let spec = parseDataSpec(req.data)
  let varList = spec.toVariableList()
  let table = spec.toTable(varList)

  var mgr = initVBManager(varList, table)

  # Set search direction on manager (critical for neighbor generation)
  if req.direction == "down":
    mgr.setSearchDirection(Direction.Descending)
  else:
    mgr.setSearchDirection(Direction.Ascending)

  # Determine search filter (using parallel module's enum)
  let filter = case req.filter
    of "full": SearchFull
    of "disjoint": SearchDisjoint
    else: SearchLoopless

  # Determine sort statistic
  let stat = case req.sortBy
    of "aic": SearchAIC
    of "ddf": SearchDDF
    else: SearchBIC

  # Get starting model - use custom reference model if provided, otherwise default
  var startModel: Model
  if req.referenceModel.len > 0:
    let validation = mgr.validateReferenceModel(req.referenceModel)
    if not validation.isValid:
      raise newException(ValueError, "Invalid reference model: " & validation.errorMessage)
    startModel = validation.model
  else:
    startModel = if req.direction == "down":
      mgr.topRefModel
    else:
      mgr.bottomRefModel

  # Run parallel search
  let searchDir = if req.direction == "down": Direction.Descending else: Direction.Ascending
  let candidates = parallelSearch(
    varList, table, startModel,
    filter, stat,
    req.width, req.levels,
    direction = searchDir
  )

  result.totalEvaluated = candidates.len

  for candidate in candidates:
    let item = SearchResultItem(
      model: candidate.model.printName(varList),
      h: mgr.computeH(candidate.model),
      ddf: mgr.computeDDF(candidate.model),
      aic: mgr.computeAIC(candidate.model),
      bic: mgr.computeBIC(candidate.model),
      hasLoops: candidate.model.hasLoops(varList)
    )
    result.results.add(item)


proc processSearchWithProgress*(req: SearchRequest; progressConfig: ProgressConfig): SearchResponse =
  ## Run model search with progress reporting
  ##
  ## This variant accepts a ProgressConfig for streaming progress events
  ## during long-running searches (used by WebSocket handler).
  let spec = parseDataSpec(req.data)
  let varList = spec.toVariableList()
  let table = spec.toTable(varList)

  # Diagnostic logging for table size
  let rawRows = spec.data.len
  let tableRows = table.len
  if rawRows != tableRows:
    stderr.writeLine("[Data] Raw rows: " & $rawRows & " -> Aggregated: " & $tableRows & " (" & $(rawRows - tableRows) & " duplicates merged)")
  else:
    stderr.writeLine("[Data] " & $tableRows & " unique rows (no duplicates)")

  var mgr = initVBManager(varList, table)

  # Set search direction on manager (critical for neighbor generation)
  if req.direction == "down":
    mgr.setSearchDirection(Direction.Descending)
  else:
    mgr.setSearchDirection(Direction.Ascending)

  # Determine search filter
  let filter = case req.filter
    of "full": SearchFull
    of "disjoint": SearchDisjoint
    else: SearchLoopless

  # Determine sort statistic
  let stat = case req.sortBy
    of "aic": SearchAIC
    of "ddf": SearchDDF
    else: SearchBIC

  # Get starting model - use custom reference model if provided, otherwise default
  var startModel: Model
  if req.referenceModel.len > 0:
    let validation = mgr.validateReferenceModel(req.referenceModel)
    if not validation.isValid:
      raise newException(ValueError, "Invalid reference model: " & validation.errorMessage)
    startModel = validation.model
  else:
    startModel = if req.direction == "down":
      mgr.topRefModel
    else:
      mgr.bottomRefModel

  # Run parallel search with progress AND timing
  let searchDir = if req.direction == "down": Direction.Descending else: Direction.Ascending
  let (candidates, _) = parallelSearchTimed(
    varList, table, startModel,
    filter, stat,
    req.width, req.levels,
    progress = progressConfig,
    direction = searchDir
  )

  result.totalEvaluated = candidates.len

  for candidate in candidates:
    let item = SearchResultItem(
      model: candidate.model.printName(varList),
      h: mgr.computeH(candidate.model),
      ddf: mgr.computeDDF(candidate.model),
      aic: mgr.computeAIC(candidate.model),
      bic: mgr.computeBIC(candidate.model),
      hasLoops: candidate.model.hasLoops(varList)
    )
    result.results.add(item)


proc processSearchEstimate*(req: SearchEstimateRequest): SearchEstimateResponse =
  ## Estimate search time and complexity before running
  ##
  ## Returns timing estimates, warnings, and recommendations.
  ## Uses math-based loop probability estimation for Full search.
  let spec = parseDataSpec(req.data)
  let varList = spec.toVariableList()
  let n = varList.len
  let numCores = countProcessors()

  # Calculate data complexity factors
  var maxCardinality = 1
  var stateSpace = 1.0'f64  # Use float64 to avoid overflow!
  for v in varList:
    if v.cardinality.int > maxCardinality:
      maxCardinality = v.cardinality.int
    stateSpace *= float64(v.cardinality)
  let dataRows = spec.data.len  # Number of frequency table rows

  let isDown = req.direction == "down"
  let isFull = req.filter == "full"
  let isLoopless = req.filter == "loopless" or req.filter == "disjoint"
  let sortBy = if req.sortBy.len > 0: req.sortBy else: "bic"  # Default to BIC

  # Calculate level 1 neighbors
  let level1Neighbors = if isDown: n else: n * (n - 1) div 2

  # Data complexity factor (larger tables take more time)
  let dataComplexity = 1.0 + float64(dataRows) / 1000.0 + float64(n) / 10.0

  # Time estimates per model type (in milliseconds)
  # Based on empirical testing: BP is ~50-250x faster than IPF
  let msLoopless = 5.0 * dataComplexity      # BP: fast closed-form
  let msLooplessHigh = 20.0 * dataComplexity
  let msLoop = 500.0 * dataComplexity        # IPF: iterative, slow
  let msLoopHigh = 2000.0 * dataComplexity   # IPF can be very slow

  # For down direction, relations start large (IPF even slower)
  let msLoopDown = if n > 12: 2000.0 * dataComplexity else: msLoop
  let msLoopDownHigh = if n > 12: 10000.0 * dataComplexity else: msLoopHigh

  # Account for parallelization - Amdahl's law with 70% efficiency
  let parallelEfficiency = 0.7
  let effectiveCores = 1.0 + (float64(numCores) - 1.0) * parallelEfficiency

  # Estimate time and model count per level
  var totalMs = 0.0'f64
  var totalMsLow = 0.0'f64
  var totalMsHigh = 0.0'f64
  var totalModels = 0
  var levelBreakdown: seq[LevelEstimate] = @[]

  for level in 1..req.levels:
    let modelsAtLevel = estimateModelsAtLevel(n, level, req.width, isDown)
    totalModels += modelsAtLevel

    var levelMs = 0.0'f64
    var pLoop = 0.0'f64

    if isLoopless:
      # All models are loopless - fast BP
      levelMs = float64(modelsAtLevel) * msLoopless
      totalMs += levelMs
      totalMsLow += float64(modelsAtLevel) * msLoopless * 0.5
      totalMsHigh += float64(modelsAtLevel) * msLooplessHigh
      pLoop = 0.0
    elif isFull:
      # Mix of loopless and loop models based on level
      # Sort method dramatically affects loop probability!
      pLoop = loopProbability(n, level, sortBy)
      let loopModels = float64(modelsAtLevel) * pLoop
      let looplessModels = float64(modelsAtLevel) * (1.0 - pLoop)

      let msLoopActual = if isDown: msLoopDown else: msLoop
      let msLoopActualHigh = if isDown: msLoopDownHigh else: msLoopHigh

      levelMs = looplessModels * msLoopless + loopModels * msLoopActual
      totalMs += levelMs
      totalMsLow += looplessModels * msLoopless * 0.5 + loopModels * msLoopActual * 0.3
      totalMsHigh += looplessModels * msLooplessHigh + loopModels * msLoopActualHigh
    else:
      # Default: assume loopless-like timing
      levelMs = float64(modelsAtLevel) * msLoopless
      totalMs += levelMs
      totalMsLow += float64(modelsAtLevel) * msLoopless * 0.5
      totalMsHigh += float64(modelsAtLevel) * msLooplessHigh
      pLoop = 0.0

    levelBreakdown.add(LevelEstimate(
      level: level,
      estimatedModels: modelsAtLevel,
      loopProbability: pLoop,
      estimatedMs: levelMs
    ))

  # Apply parallelization
  totalMs /= effectiveCores
  totalMsLow /= effectiveCores
  totalMsHigh /= effectiveCores

  result.estimatedSeconds = totalMs / 1000.0
  result.estimatedSecondsLow = totalMsLow / 1000.0
  result.estimatedSecondsHigh = totalMsHigh / 1000.0
  result.level1Neighbors = level1Neighbors
  result.totalModelsEstimate = totalModels
  result.stateSpace = stateSpace
  result.levelBreakdown = levelBreakdown

  # Determine complexity category
  if result.estimatedSeconds < 5:
    result.complexity = "fast"
  elif result.estimatedSeconds < 30:
    result.complexity = "moderate"
  elif result.estimatedSeconds < 300:  # 5 minutes
    result.complexity = "slow"
  elif result.estimatedSeconds < 3600:  # 1 hour
    result.complexity = "very_slow"
  else:
    result.complexity = "infeasible"

  # Generate warnings
  result.warnings = @[]
  result.recommendations = @[]

  if n > 20:
    result.warnings.add("Large number of variables (" & $n & ") will result in many candidate models")

  # State space warnings - critical for memory usage
  let stateSpaceBillions = stateSpace / 1e9
  if isFull and stateSpace > 1e9:
    result.warnings.add("DANGER: State space is " &
      (if stateSpaceBillions >= 1000: $(int(stateSpaceBillions / 1000)) & " trillion"
       else: $(int(stateSpaceBillions)) & " billion") &
      " states - loop models may cause out-of-memory crash!")
    result.recommendations.add("Use 'Loopless' filter for this dataset - it's safe and usually finds good models")
    result.complexity = "infeasible"  # Override to prevent running

  if isFull and stateSpace > 1e6 and stateSpace <= 1e9:
    result.warnings.add("Large state space (" & $(int(stateSpace / 1e6)) & " million) - full search will be slow")
    result.recommendations.add("Consider 'Loopless' filter for faster results")

  if isFull and isDown and n > 15:
    result.warnings.add("Full search going down from " & $n & " variables creates very complex loop models")
    result.warnings.add("Models with relations >15 variables will be skipped (too slow for IPF)")
    result.recommendations.add("Use 'Loopless' filter instead - much faster and usually finds good models")
    result.recommendations.add("Or use 'Up' direction - starts with simple models")

  if isFull and isDown and n > 10:
    result.recommendations.add("Consider selecting a subset of 10-12 key variables for full search")

  if result.complexity == "very_slow" or result.complexity == "infeasible":
    result.recommendations.add("Reduce width to " & $(max(req.width - 1, 2)) & " for faster search")
    result.recommendations.add("Reduce levels to " & $(max(req.levels - 2, 3)) & " for faster search")

  if isDown and isLoopless:
    result.warnings.add("Down search from saturated model may terminate quickly if no simpler loopless models exist")

  # Loop probability warnings for Full search
  if isFull and not isDown:
    # Warn about BIC/AIC sorting creating loops
    if sortBy == "bic" or sortBy == "aic":
      result.warnings.add("Full search with " & sortBy.toUpperAscii & " sorting hits loop models at level 3+")
      result.warnings.add("Loop models require slow IPF fitting (~100-1000x slower than loopless)")
      if n >= 6:
        result.recommendations.add("Use 'DDF' sorting to stay loopless and run MUCH faster")
        result.recommendations.add("Or use 'Loopless' filter which is always fast")

    # Check if later levels have high loop probability
    var highLoopLevel = 0
    for le in levelBreakdown:
      if le.loopProbability > 0.3 and highLoopLevel == 0:
        highLoopLevel = le.level
      if le.loopProbability > 0.5:
        result.warnings.add("Level " & $le.level & " has ~" &
          $(int(le.loopProbability * 100)) & "% loop models - IPF will slow down significantly")
        break

    if highLoopLevel > 0 and highLoopLevel <= req.levels:
      result.recommendations.add("Consider limiting to " & $(highLoopLevel - 1) &
        " levels to avoid slow loop model fitting")