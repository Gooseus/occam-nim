## Data Generation Commands
##
## Implements commands for generating synthetic and sequence data:
## - generate: Generate synthetic data with known structure
## - sequence: Generate dataset from integer sequences
## - samplesize: Calculate sample size requirements
## - lattice: Enumerate model lattice

import std/[strformat, strutils, random, json]
import ../occam/core/types
import ../occam/core/variable
import ../occam/core/model
import ../occam/core/table
import ../occam/core/key
import ../occam/io/parser
import ../occam/io/synthetic
import ../occam/search/lattice
import ../occam/io/sequences
import ../occam/io/sequences_occam
import formatting


proc generate*(variables = "A:2,B:2,C:2";
               model = "";
               samples = 1000;
               strength = 0.8;
               seed = -1;
               output = ""): int =
  ## Generate synthetic data with known structure
  ##
  ## Arguments:
  ##   variables: Variable specification as "name:card,..." (e.g., "A:2,B:2,C:2")
  ##   model: Model structure (e.g., "AB:BC" for chain, "AB:BC:AC" for triangle)
  ##   samples: Number of samples to generate
  ##   strength: Dependency strength (0.5=independent, 1.0=deterministic)
  ##   seed: Random seed (-1 for random)
  ##   output: Output JSON file (stdout if empty)

  # Set random seed
  if seed >= 0:
    randomize(seed)
  else:
    randomize()

  # Parse variable specification
  var varList: VariableList
  try:
    varList = parseVariableSpec(variables)
  except ValueError as e:
    echo &"Error parsing variables: {e.msg}"
    return 1

  if varList.len == 0:
    echo "Error: No variables specified"
    return 1

  # Determine model to use
  var modelSpec = model
  if modelSpec == "":
    # Default to chain model
    var parts: seq[string]
    for i in 0..<(varList.len - 1):
      let a = varList[VariableIndex(i)].abbrev
      let b = varList[VariableIndex(i + 1)].abbrev
      parts.add(a & b)
    modelSpec = parts.join(":")
    echo &"No model specified, using default chain: {modelSpec}"

  # Create graphical model
  var gm: GraphicalModel
  var hasLoops: bool
  try:
    (gm, hasLoops) = createModelFromSpec(varList, modelSpec, strength)
  except ValueError as e:
    echo &"Error creating model: {e.msg}"
    return 1

  printHeader("Generating Synthetic Data")
  echo &"Variables: {variables}"
  echo &"Model: {modelSpec}"
  echo &"Has Loops: {hasLoops}"
  echo &"Samples: {samples}"
  echo &"Strength: {strength}"
  if seed >= 0:
    echo &"Seed: {seed}"
  echo ""

  # Generate samples
  let sampleData = gm.generateSamples(samples)
  let dataTable = gm.samplesToTable(sampleData)

  # Build JSON output
  var varsJson = newJArray()
  for i in 0..<varList.len:
    let v = varList[VariableIndex(i)]
    var valuesJson = newJArray()
    for j in 0..<v.cardinality.toInt:
      valuesJson.add(newJString($j))

    varsJson.add(%*{
      "name": v.name,
      "abbrev": v.abbrev,
      "cardinality": v.cardinality.toInt,
      "isDependent": v.isDependent,
      "values": valuesJson
    })

  var dataJson = newJArray()
  var countsJson = newJArray()

  for tup in dataTable:
    var rowJson = newJArray()
    for i in 0..<varList.len:
      let val = tup.key.getValue(varList, VariableIndex(i))
      rowJson.add(newJString($val))
    dataJson.add(rowJson)
    countsJson.add(newJInt(int(tup.value)))

  let outputJson = %*{
    "name": &"Synthetic data: {modelSpec}",
    "variables": varsJson,
    "data": dataJson,
    "counts": countsJson
  }

  let jsonStr = pretty(outputJson)

  if output == "":
    echo jsonStr
  else:
    writeFile(output, jsonStr)
    echo &"Saved to {output}"
    echo &"Data rows: {dataTable.len}"
    echo &"Total samples: {int(dataTable.sum())}"

  return 0


proc latticeCmd*(input = "";
                 variables = "";
                 loopless = false;
                 maxModels = 1000;
                 showLoops = true): int =
  ## Enumerate all models in the lattice
  ##
  ## Arguments:
  ##   input: Path to JSON data file (optional, can use --variables instead)
  ##   variables: Variable specification as "name:card,name:card,..." (e.g., "A:2,B:2,C:2")
  ##   loopless: Only show loopless (decomposable) models
  ##   maxModels: Maximum number of models to enumerate
  ##   showLoops: Show which models have loops

  var varList: VariableList

  if input != "":
    # Load from file
    let spec = loadDataSpec(input)
    varList = spec.toVariableList()
  elif variables != "":
    # Parse variable specification
    varList = initVariableList()
    for part in variables.split(','):
      let trimmed = part.strip
      if trimmed.len == 0:
        continue

      let parts = trimmed.split(':')
      if parts.len >= 2:
        let name = parts[0].strip
        let card = try: parseInt(parts[1].strip) except ValueError: 2

        # Check for DV marker
        var isDV = false
        if parts.len >= 3 and parts[2].strip.toLowerAscii in ["dv", "d", "1", "true"]:
          isDV = true

        let abbrev = if name.len > 0: $name[0].toUpperAscii else: "X"
        discard varList.add(initVariable(name, abbrev, Cardinality(card), isDependent = isDV))
      else:
        # Just a name, assume cardinality 2
        let name = trimmed
        let abbrev = if name.len > 0: $name[0].toUpperAscii else: "X"
        discard varList.add(initVariable(name, abbrev, Cardinality(2)))
  else:
    echo "Error: Either --input or --variables required"
    return 1

  printHeader("Lattice Enumeration")
  echo &"Variables: {varList.len}"
  echo &"Directed: {varList.isDirected}"
  echo &"State space: {varList.stateSpace}"
  if loopless:
    echo "Filter: loopless only"
  echo ""

  # Print variable summary
  echo "Variables:"
  for idx, v in varList.pairs:
    let dvMark = if v.isDependent: " (DV)" else: ""
    echo &"  {v.abbrev}: {v.name} (card={v.cardinality.toInt}){dvMark}"
  echo ""

  # Enumerate lattice
  let models = if varList.isDirected:
    enumerateDirectedLattice(varList, loopless, maxModels)
  else:
    enumerateLattice(varList, loopless, maxModels)

  echo &"Models in lattice: {models.len}"
  if models.len >= maxModels:
    echo &"  (limited to {maxModels}, may be more)"
  echo ""

  # Group by level
  var currentLevel = -1
  var looplessCount = 0
  var loopCount = 0

  echo "Model Lattice:"
  printSeparator()

  for lm in models:
    if lm.level != currentLevel:
      currentLevel = lm.level
      echo &"\nLevel {currentLevel}:"

    let loopMark = if lm.hasLoops: " [LOOP]" else: ""
    if lm.hasLoops:
      loopCount += 1
    else:
      looplessCount += 1

    if showLoops or not lm.hasLoops:
      echo &"  {lm.model.printName(varList)}{loopMark}"

  echo ""
  printSeparator()
  echo &"Total: {models.len} models"
  echo &"  Loopless: {looplessCount}"
  echo &"  With loops: {loopCount}"

  return 0


proc sequenceCmd*(kind = "primes";
                  limit = 100000;
                  count = 0;
                  start = 0;
                  columns = "R3,R5,R7";
                  target = "R3";
                  output = "";
                  format = "json";
                  includeValues = false;
                  consecutive = true;
                  verbose = false): int =
  ## Generate dataset from integer sequences with configurable columns
  ##
  ## Arguments:
  ##   kind: Sequence type (primes, naturals, odds)
  ##   limit: Upper bound for sequence generation
  ##   count: Alternative: generate this many numbers (overrides limit)
  ##   start: Start value (only include sequence values >= start)
  ##   columns: Comma-separated column specs (R3, R5, collatz, digits, factors)
  ##   target: Target column for DV (e.g., R3)
  ##   output: Output file path (stdout if empty)
  ##   format: Output format (json or csv)
  ##   includeValues: Include actual number values in output
  ##   consecutive: Use consecutive pairs (prev→next) vs single rows
  ##   verbose: Show detailed output

  # Parse sequence kind
  let seqKind = case kind.toLowerAscii
    of "primes", "prime": skPrimes
    of "naturals", "natural": skNaturals
    of "odds", "odd": skOdds
    else:
      echo &"Error: Unknown sequence kind '{kind}'. Use: primes, naturals, odds"
      return 1

  # Generate the sequence
  if verbose:
    printHeader("Generating Integer Sequence Dataset")
    echo &"Kind: {kind}"
    if count > 0:
      echo &"Count: {count}"
    else:
      echo &"Limit: {limit}"
    if start > 0:
      echo &"Start: {start}"
    echo &"Columns: {columns}"
    echo &"Target: {target}"
    echo &"Consecutive pairs: {consecutive}"
    echo ""

  let seq = generateSequence(seqKind, limit, count, start)

  if verbose:
    echo &"Generated {seq.len} numbers"
    if seq.len > 0:
      echo &"Range: {seq[0]} to {seq[^1]}"
    echo ""

  if seq.len < 2:
    echo "Error: Need at least 2 numbers to build dataset"
    return 1

  # Parse column specifications
  var ivColumns: seq[ColumnDef]
  try:
    ivColumns = parseColumnsSpec(columns)
  except ValueError as e:
    echo &"Error parsing columns: {e.msg}"
    return 1

  # Parse target column
  var dvColumn: ColumnDef
  try:
    dvColumn = parseColumnSpec(target, "Z")
  except ValueError as e:
    echo &"Error parsing target: {e.msg}"
    return 1

  if verbose:
    echo "Columns:"
    for col in ivColumns:
      echo &"  {col.abbrev}: {col.name}"
    echo &"  Z (DV): {dvColumn.name}"
    echo ""

  # Build dataset
  let ds = if consecutive:
    buildConsecutivePairDataset(seq, ivColumns, dvColumn, includeValues,
                                &"{kind}_residues")
  else:
    # For single-row, we need all columns including the DV
    var allCols = ivColumns
    allCols.add(dvColumn)
    buildSingleRowDataset(seq, allCols, allCols.len - 1, includeValues,
                          &"{kind}_residues")

  if verbose:
    echo ds.summary()
    echo ""

  # Generate output
  let outputStr = case format.toLowerAscii
    of "csv":
      ds.toCSV()
    of "json", "occam":
      ds.toOccamJSON()
    else:
      echo &"Error: Unknown format '{format}'. Use: json, csv"
      return 1

  if output == "":
    echo outputStr
  else:
    writeFile(output, outputStr)
    echo &"Saved to {output}"
    echo &"Rows: {ds.rows.len}"

  return 0


proc samplesizeCmd*(samples = 0;
                    kind = "primes";
                    limit = 0;
                    start = 0;
                    targetObsPerCell = 10.0;
                    required = false;
                    maxVars = 10): int =
  ## Calculate sample size requirements for prime residue analysis
  ##
  ## Arguments:
  ##   samples: Number of observations (if known)
  ##   kind: Sequence type to estimate sample size from (primes, naturals)
  ##   limit: Upper bound for sequence (to estimate sample size)
  ##   start: Start value for range (to estimate sample size)
  ##   targetObsPerCell: Minimum observations per cell for adequacy
  ##   required: Show required sample sizes for each number of IVs
  ##   maxVars: Maximum number of variables to show in table

  # If --required flag, show required samples table
  if required:
    printRequiredSamplesTable(maxVars, targetObsPerCell)
    echo ""
    echo "Formula: RequiredN = StateSpace × TargetObsPerCell"
    echo "         StateSpace = Product(base_i - 1) × 2"
    echo ""
    echo "Est. Prime Limit uses prime number theorem: π(n) ≈ n / ln(n)"
    return 0

  var sampleSize = samples

  # Estimate sample size from sequence parameters if not provided
  if sampleSize == 0:
    if limit > 0:
      let seqKind = case kind.toLowerAscii
        of "primes", "prime": skPrimes
        of "naturals", "natural": skNaturals
        else: skPrimes

      let seq = generateSequence(seqKind, limit, 0, start)
      sampleSize = seq.len - 1  # consecutive pairs
      echo &"Estimated sample size for {kind} in [{start}, {limit}): {sampleSize} pairs"
      echo ""
    else:
      echo "Error: Provide --samples, --limit, or --required"
      return 1

  # Print the adequacy table
  printAdequacyTable(sampleSize, maxVars)

  echo ""
  let maxAnalyzable = maxResidueClasses(sampleSize, targetObsPerCell)
  echo &"Recommended: Use up to {maxAnalyzable} prime residue IVs for reliable analysis"
  echo &"  (targeting {targetObsPerCell:.0f} observations per cell)"

  # Show the formula
  echo ""
  echo "Formula: StateSpace = Product(base_i - 1) × DV_cardinality"
  echo "         ObsPerCell = SampleSize / StateSpace"
  echo "         Adequacy: >= 5/cell (chi-squared valid), >= 10/cell (recommended)"

  return 0
