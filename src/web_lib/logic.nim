## Web API Business Logic
##
## These functions process requests and return responses.
## They are separated from HTTP handling for testability.

import ../occam
import ./models

const VERSION = "0.1.0"

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

  # Get starting model based on direction
  let startModel = if req.direction == "down":
    mgr.topRefModel
  else:
    mgr.bottomRefModel

  # Run parallel search
  let candidates = parallelSearch(
    varList, table, startModel,
    filter, stat,
    req.width, req.levels
  )

  result.totalEvaluated = candidates.len

  for candidate in candidates:
    let item = SearchResultItem(
      model: candidate.model.printName(varList),
      h: mgr.computeH(candidate.model),
      aic: mgr.computeAIC(candidate.model),
      bic: mgr.computeBIC(candidate.model),
      hasLoops: candidate.model.hasLoops(varList)
    )
    result.results.add(item)
