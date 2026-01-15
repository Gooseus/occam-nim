## Web API Request/Response Models
##
## These types define the JSON structure for API requests and responses.

type
  # Health check
  HealthResponse* = object
    status*: string
    version*: string

  # Data info
  DataInfoRequest* = object
    data*: string  # JSON data string

  DataInfoResponse* = object
    name*: string
    variableCount*: int
    sampleSize*: float64
    variables*: seq[VariableInfo]

  VariableInfo* = object
    name*: string
    abbrev*: string
    cardinality*: int
    isDependent*: bool

  # Model fitting
  FitRequest* = object
    data*: string   # JSON data string
    model*: string  # Model notation like "AB:BC"

  FitResponse* = object
    model*: string
    h*: float64
    t*: float64
    df*: int64
    ddf*: int64
    lr*: float64
    aic*: float64
    bic*: float64
    alpha*: float64
    hasLoops*: bool
    ipfIterations*: int
    ipfError*: float64

  # Search
  SearchRequest* = object
    data*: string
    direction*: string      # "up" or "down"
    filter*: string         # "loopless", "full", "disjoint", "chain"
    width*: int
    levels*: int
    sortBy*: string         # "ddf", "aic", "bic"
    referenceModel*: string # Custom reference model (e.g., "AB:BC"), empty for default

  SearchResponse* = object
    results*: seq[SearchResultItem]
    totalEvaluated*: int

  SearchResultItem* = object
    model*: string
    h*: float64
    ddf*: int64
    aic*: float64
    bic*: float64
    hasLoops*: bool

  # Error response
  ErrorResponse* = object
    error*: string
    message*: string

  # Search estimation
  SearchEstimateRequest* = object
    data*: string
    direction*: string
    filter*: string
    width*: int
    levels*: int
    sortBy*: string  # "bic", "aic", "ddf" - affects loop probability!

  LevelEstimate* = object
    level*: int
    estimatedModels*: int           # Models to evaluate at this level
    loopProbability*: float64       # Probability models have loops (0-1)
    estimatedMs*: float64           # Estimated time for this level (ms)

  SearchEstimateResponse* = object
    estimatedSeconds*: float64      # Estimated time in seconds
    estimatedSecondsLow*: float64   # Lower bound estimate
    estimatedSecondsHigh*: float64  # Upper bound estimate
    level1Neighbors*: int           # Expected neighbors at level 1
    totalModelsEstimate*: int       # Rough estimate of total models to evaluate
    stateSpace*: float64            # Total state space (product of cardinalities)
    complexity*: string             # "fast", "moderate", "slow", "very_slow", "infeasible"
    warnings*: seq[string]          # Warnings about the search
    recommendations*: seq[string]   # Suggestions for faster search
    levelBreakdown*: seq[LevelEstimate]  # Per-level estimates

# Default values for SearchRequest
proc initSearchRequest*(): SearchRequest =
  result.direction = "up"
  result.filter = "loopless"
  result.width = 3
  result.levels = 7
  result.sortBy = "bic"
  result.referenceModel = ""

# jsony hook for SearchRequest defaults
# Note: jsony will use defaults from initSearchRequest if fields are missing
proc newSearchRequest*(): SearchRequest =
  ## Create a SearchRequest with default values
  result = initSearchRequest()
