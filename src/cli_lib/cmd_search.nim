## Search Command Implementation
##
## Implements the main search command for exploring model space
## Uses parallelization by default for optimal performance.

import std/[strformat, strutils, algorithm, cpuinfo, os]
import ../occam/core/types
import ../occam/core/variable
import ../occam/core/table as coretable
import ../occam/core/model
import ../occam/core/progress
import ../occam/io/parser
import ../occam/manager/vb
import ../occam/search/parallel
import ../occam/search/chain
import formatting
import progress as cliprogress


proc search*(input: string;
             direction = "up";
             filter = "loopless";
             width = 3;
             levels = 7;
             sort = "ddf";
             parallel = true;
             verbose = false;
             showProgress = true): int =
  ## Search model space for best-fitting models
  ##
  ## Arguments:
  ##   input: Path to JSON data file
  ##   direction: Search direction (up or down)
  ##   filter: Search filter (loopless, full, disjoint, chain)
  ##   width: Number of models to keep at each level
  ##   levels: Maximum search levels
  ##   sort: Statistic to sort by (ddf, aic, bic)
  ##   parallel: Use parallel search (default: true, uses all CPU cores)
  ##   verbose: Show detailed output
  ##   showProgress: Show progress during search (default: true)

  if input == "":
    echo "Error: Input file required"
    return 1

  # Load data - use fast path for large files (>1MB)
  let fileSize = getFileSize(input)
  let useFastPath = fileSize > 1_000_000  # > 1MB = likely large dataset

  var varList: VariableList
  var inputTable: coretable.ContingencyTable
  var specName: string

  if useFastPath:
    if verbose:
      echo "Using fast aggregation for large dataset..."
    let (spec, freqMap) = loadAndAggregate(input)
    specName = spec.name
    varList = spec.toVariableList()
    inputTable = spec.toTableFromFreqMap(freqMap, varList)
  else:
    let spec = loadDataSpec(input)
    specName = spec.name
    varList = spec.toVariableList()
    inputTable = spec.toTable(varList)

  if verbose:
    echo &"Loaded {specName}"
    echo &"Variables: {varList.len}"
    echo &"Unique states: {inputTable.len}"
    echo &"Direction: {direction}"
    echo &"Filter: {filter}"
    echo &"Parallel: {parallel} ({countProcessors()} cores)"
    echo ""

  # Create manager for reference models and chain search
  var mgr = newVBManager(varList, inputTable)

  # Set search direction
  if direction == "up":
    mgr.setSearchDirection(Direction.Ascending)
  else:
    mgr.setSearchDirection(Direction.Descending)

  # Validate filter
  if filter notin ["loopless", "full", "disjoint", "chain"]:
    echo &"Error: Unknown filter '{filter}'. Use: loopless, full, disjoint, or chain"
    return 1

  let showLoops = filter == "full"

  echo "Reference Models:"
  echo &"  Top (saturated): {mgr.topRefModel.printName(varList)}"
  echo &"  Bottom (independence): {mgr.bottomRefModel.printName(varList)}"
  echo ""

  # Special handling for chain search - generates all chains at once
  if filter == "chain":
    echo &"Search Filter: {filter}"
    echo ""
    echo "Chain Search Results:"
    printSeparator(80)

    let chains = generateAllChains(varList)
    var chainStats: seq[(Model, float64)]

    for chain in chains:
      let statistic = case sort
        of "aic": mgr.computeAIC(chain)
        of "bic": mgr.computeBIC(chain)
        else: float64(mgr.computeDDF(chain))
      chainStats.add((chain, statistic))

    # Sort chains
    if sort == "ddf":
      chainStats.sort(proc(a, b: (Model, float64)): int = cmp(b[1], a[1]))
    else:
      chainStats.sort(proc(a, b: (Model, float64)): int = cmp(a[1], b[1]))

    # Print all chains
    echo "All Chain Models:"
    for i, (chain, stat) in chainStats:
      printModelStats(chain, mgr, varList, false)

    echo ""
    echo &"Total chain models: {chains.len}"
    return 0

  # Get starting model for non-chain searches
  let startModel = if direction == "up":
    mgr.bottomRefModel
  else:
    mgr.topRefModel

  # Convert filter string to SearchFilter enum
  let searchFilter = case filter
    of "full": SearchFull
    of "disjoint": SearchDisjoint
    else: SearchLoopless

  # Convert sort string to SearchStatistic enum
  let searchStat = case sort
    of "aic": SearchAIC
    of "bic": SearchBIC
    else: SearchDDF

  echo &"Search Filter: {filter}"
  echo "Starting model:"
  printModelStats(startModel, mgr, varList, showLoops)
  echo ""

  echo "Search Results:"
  printSeparator(80)

  # Create progress config
  let progressConfig = if showProgress:
    initProgressConfig(callback = makeCLIProgressCallback(verbose))
  else:
    initProgressConfig()

  # Use parallel search (parallelization enabled by default)
  let results = parallelSearch(
    varList, inputTable, startModel,
    searchFilter, searchStat,
    width, levels,
    useParallel = parallel,
    progress = progressConfig
  )

  echo ""
  echo "Best Models Found:"
  printSeparator(80)

  # Print top models (results already sorted by parallelSearch)
  let showCount = min(10, results.len)
  for i in 0..<showCount:
    printModelStats(results[i].model, mgr, varList, showLoops)

  echo ""
  echo &"Total models explored: {results.len}"

  return 0
