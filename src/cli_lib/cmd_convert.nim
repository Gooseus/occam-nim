## Conversion and Data Processing Commands
##
## Implements commands for data format conversion and preprocessing:
## - convert: OCCAM .in to JSON
## - analyze-csv: CSV analysis
## - csv-to-json: CSV to JSON conversion
## - bin: Variable binning/discretization

import std/[strformat, strutils, os, json]
import ../occam/core/types
import ../occam/core/variable
import ../occam/io/parser
import ../occam/io/formats
import ../occam/io/binning
import formatting


proc info*(input: string;
           variables = false;
           sampleSize = false;
           summary = true): int =
  ## Display information about input data
  ##
  ## Arguments:
  ##   input: Path to JSON data file
  ##   variables: Show variable details
  ##   sampleSize: Show sample size
  ##   summary: Show summary (default)

  if input == "":
    echo "Error: Input file required"
    return 1

  let spec = loadDataSpec(input)
  let varList = spec.toVariableList()

  if summary or (not variables and not sampleSize):
    echo &"Dataset: {spec.name}"
    echo &"Variables: {varList.len}"
    echo &"Sample size: {spec.sampleSize}"
    echo &"Directed: {varList.isDirected}"
    echo &"State space: {varList.stateSpace}"
    echo ""

  if variables:
    echo "Variables:"
    echo "  Name            Abbrev   Card   DV"
    echo "  " & "-".repeat(35)
    for idx, v in varList.pairs:
      let dvMark = if v.isDependent: "*" else: ""
      echo &"  {v.name:<15} {v.abbrev:<8} {v.cardinality.toInt:<6} {dvMark}"

  if sampleSize:
    echo &"Sample size: {spec.sampleSize}"

  return 0


proc convert*(input: string;
              output = "";
              inferVals = true;
              includeAll = false): int =
  ## Convert OCCAM .in format to JSON
  ##
  ## Arguments:
  ##   input: Path to OCCAM .in file
  ##   output: Output JSON file (default: stdout)
  ##   inferVals: Infer value labels from data
  ##   includeAll: Include all variables (even type=0 excluded ones)

  if input == "":
    echo "Error: Input file required"
    return 1

  if not fileExists(input):
    echo &"Error: File not found: {input}"
    return 1

  var parsed = parseOccamInFile(input)

  if inferVals:
    parsed = inferValues(parsed, excludeType0 = not includeAll)

  let json = toJson(parsed, excludeType0 = not includeAll)

  if output == "":
    echo json
  else:
    writeFile(output, json)
    let activeCount = parsed.activeVariableCount
    let totalCount = parsed.variables.len
    if includeAll:
      echo &"Converted {input} -> {output} ({totalCount} variables)"
    else:
      echo &"Converted {input} -> {output} ({activeCount} active variables, {totalCount - activeCount} excluded)"

  return 0


proc analyzeCsvCmd*(input: string;
                    hasHeader = true;
                    delimiter = ",";
                    interactive = false): int =
  ## Analyze a CSV file and show its structure
  ##
  ## Arguments:
  ##   input: Path to CSV file
  ##   hasHeader: CSV has header row (default: true)
  ##   delimiter: Column delimiter (default: comma)
  ##   interactive: Interactive mode to configure conversion

  if input == "":
    echo "Error: Input file required"
    return 1

  if not fileExists(input):
    echo &"Error: File not found: {input}"
    return 1

  let delim = if delimiter.len > 0: delimiter[0] else: ','
  let analysis = analyzeCsvFile(input, hasHeader, delim)

  echo &"CSV Analysis: {input}"
  printHeader("")
  echo &"Rows: {analysis.rowCount}"
  echo &"Columns: {analysis.columnCount}"
  echo ""

  echo "Column Details:"
  echo "  #    Header               Cardinality  Abbrev   Values"
  echo "  " & "-".repeat(70)

  for i in 0..<analysis.columnCount:
    let header = if i < analysis.headers.len: analysis.headers[i] else: &"Col{i}"
    let card = if i < analysis.cardinalities.len: analysis.cardinalities[i] else: 0
    let abbrev = if i < analysis.suggestedAbbrevs.len: analysis.suggestedAbbrevs[i] else: "?"

    var values = ""
    if i < analysis.uniqueValues.len:
      let vals = analysis.uniqueValues[i]
      if vals.len <= 5:
        values = vals.join(", ")
      else:
        values = vals[0..4].join(", ") & &" ... ({vals.len} total)"

    echo &"  {i:<4} {header:<20} {card:<12} {abbrev:<8} {values}"

  if interactive:
    echo ""
    echo "Interactive Configuration"
    printSeparator()

    # Get columns to include
    stdout.write "Columns to include (comma-separated, or 'all'): "
    let colInput = stdin.readLine()
    var selectedCols: seq[int]
    if colInput.toLowerAscii == "all" or colInput.strip == "":
      for i in 0..<analysis.columnCount:
        selectedCols.add(i)
    else:
      for part in colInput.split(','):
        let trimmed = part.strip
        if trimmed.len > 0:
          try:
            selectedCols.add(parseInt(trimmed))
          except ValueError:
            discard

    # Get dependent variable
    stdout.write "Dependent variable column (-1 for none/neutral): "
    let dvInput = stdin.readLine()
    var dvCol = -1
    try:
      dvCol = parseInt(dvInput.strip)
    except ValueError:
      dvCol = -1

    # Generate JSON
    let content = readFile(input)
    let json = csvToJson(content, selectedCols, dvCol, hasHeader, delim)

    echo ""
    echo "Generated JSON:"
    printSeparator()
    echo json

    stdout.write "\nSave to file (enter path or leave blank to skip): "
    let savePath = stdin.readLine().strip
    if savePath.len > 0:
      writeFile(savePath, json)
      echo &"Saved to {savePath}"

  return 0


proc csvToJsonCmd*(input: string;
                   output = "";
                   columns = "";
                   dv = -1;
                   hasHeader = true;
                   delimiter = ",";
                   abbrevs = "";
                   names = ""): int =
  ## Convert CSV file to JSON format
  ##
  ## Arguments:
  ##   input: Path to CSV file
  ##   output: Output JSON file (default: stdout)
  ##   columns: Columns to include (comma-separated indices, or empty for all)
  ##   dv: Dependent variable column index (-1 for none/neutral)
  ##   hasHeader: CSV has header row (default: true)
  ##   delimiter: Column delimiter (default: comma)
  ##   abbrevs: Custom abbreviations (comma-separated)
  ##   names: Custom variable names (comma-separated)

  if input == "":
    echo "Error: Input file required"
    return 1

  if not fileExists(input):
    echo &"Error: File not found: {input}"
    return 1

  let delim = if delimiter.len > 0: delimiter[0] else: ','

  # Parse column selection
  var selectedCols: seq[int]
  if columns.len > 0:
    for part in columns.split(','):
      let trimmed = part.strip
      if trimmed.len > 0:
        try:
          selectedCols.add(parseInt(trimmed))
        except ValueError:
          discard

  # Parse custom abbreviations
  var customAbbrevs: seq[string]
  if abbrevs.len > 0:
    for part in abbrevs.split(','):
      customAbbrevs.add(part.strip)

  # Parse custom names
  var customNames: seq[string]
  if names.len > 0:
    for part in names.split(','):
      customNames.add(part.strip)

  let content = readFile(input)
  let json = csvToJson(content, selectedCols, dv, hasHeader, delim, customAbbrevs, customNames)

  if output == "":
    echo json
  else:
    writeFile(output, json)
    echo &"Converted {input} -> {output}"

  return 0


proc parseVarSpec(spec: string): (string, BinSpec) =
  ## Parse a variable binning spec like "Age:width:5" or "City:top:3"
  ## Format: NAME:STRATEGY:PARAM
  let parts = spec.split(':')
  if parts.len < 2:
    return ("", BinSpec())

  let varName = parts[0]
  var binSpec = BinSpec(
    labelStyle: blsRange,
    missingHandling: mvhSeparateBin,
    missingLabel: "Missing",
    otherLabel: "Other"
  )

  if parts.len >= 2:
    let strategy = parts[1].toLowerAscii
    case strategy
    of "width":
      binSpec.strategy = bsEqualWidth
      binSpec.numBins = if parts.len >= 3: parseInt(parts[2]) else: 5
    of "freq", "quantile":
      binSpec.strategy = bsEqualFrequency
      binSpec.numBins = if parts.len >= 3: parseInt(parts[2]) else: 5
    of "breaks":
      binSpec.strategy = bsCustomBreaks
      if parts.len >= 3:
        for bp in parts[2].split(','):
          binSpec.breakpoints.add(parseFloat(bp.strip))
    of "top":
      binSpec.strategy = bsTopN
      binSpec.topN = if parts.len >= 3: parseInt(parts[2]) else: 5
    of "thresh", "threshold":
      binSpec.strategy = bsFrequencyThreshold
      binSpec.minFrequency = if parts.len >= 3: parseFloat(parts[2]) else: 0.05
      binSpec.minFrequencyIsRatio = true
    else:
      binSpec.strategy = bsNone

  return (varName, binSpec)


proc binCmd*(input: string;
             output = "";
             varSpecs: seq[string] = @[];
             auto = false;
             targetCard = 5;
             threshold = 10;
             config = "";
             verbose = false): int =
  ## Bin/discretize continuous or high-cardinality variables
  ##
  ## Arguments:
  ##   input: Path to JSON or CSV data file
  ##   output: Output JSON file (default: stdout)
  ##   varSpecs: Per-variable binning specs (format: NAME:STRATEGY:PARAM)
  ##     Strategies: width:N, freq:N, breaks:v1,v2,v3, top:N, thresh:RATIO
  ##   auto: Auto-detect and bin high-cardinality columns
  ##   targetCard: Target cardinality for auto-binning (default: 5)
  ##   threshold: Only auto-bin columns with cardinality > threshold
  ##   config: JSON config file for binning specifications
  ##   verbose: Show detailed output
  ##
  ## Examples:
  ##   bin -i data.json -o binned.json --var "Age:width:5" --var "City:top:3"
  ##   bin -i data.csv -o binned.json --auto --targetCard 5

  if input == "":
    echo "Error: Input file required"
    return 1

  if not fileExists(input):
    echo &"Error: File not found: {input}"
    return 1

  # Load data - support both JSON and CSV
  var spec: DataSpec
  if input.endsWith(".json"):
    spec = loadDataSpec(input)
  elif input.endsWith(".csv"):
    # Convert CSV to DataSpec first
    let content = readFile(input)
    let jsonStr = csvToJson(content, @[], -1, true, ',', @[], @[])
    spec = parseDataSpec(jsonStr)
  else:
    echo "Error: Input must be .json or .csv file"
    return 1

  if verbose:
    echo &"Loaded {spec.name}"
    echo &"Variables: {spec.variables.len}"
    for i, v in spec.variables:
      let colData = extractColumn(spec, i)
      let analysis = analyzeColumn(colData)
      let typeStr = if analysis.isNumeric: "numeric" else: "categorical"
      echo &"  {v.name}: {typeStr}, {analysis.uniqueCount} unique values"
    echo ""

  # Apply binning
  var binnedSpec: DataSpec

  if auto:
    # Auto-bin high cardinality columns
    if verbose:
      echo &"Auto-binning columns with > {threshold} unique values..."
      echo &"Target cardinality: {targetCard}"
    binnedSpec = autoBinDataSpec(spec, targetCard, threshold)
  elif varSpecs.len > 0:
    # Apply per-variable specs
    var binSpecList: seq[(string, BinSpec)]
    for vs in varSpecs:
      let (name, bs) = parseVarSpec(vs)
      if name.len > 0:
        binSpecList.add((name, bs))
        if verbose:
          echo &"Binning {name}: {bs.strategy}"

    binnedSpec = applyBinningByName(spec, binSpecList)
  else:
    echo "Error: Specify --auto or --var options for binning"
    return 1

  if verbose:
    echo ""
    echo "Result:"
    for i, v in binnedSpec.variables:
      echo &"  {v.name}: {v.cardinality} values -> {v.values}"
    echo &"Data rows: {binnedSpec.data.len}"
    echo ""

  # Build output JSON
  var varsJson = newJArray()
  for v in binnedSpec.variables:
    var valuesJson = newJArray()
    for val in v.values:
      valuesJson.add(newJString(val))
    varsJson.add(%*{
      "name": v.name,
      "abbrev": v.abbrev,
      "cardinality": v.cardinality,
      "isDependent": v.isDependent,
      "values": valuesJson
    })

  var dataJson = newJArray()
  for row in binnedSpec.data:
    var rowJson = newJArray()
    for val in row:
      rowJson.add(newJString(val))
    dataJson.add(rowJson)

  var countsJson = newJArray()
  for c in binnedSpec.counts:
    countsJson.add(newJFloat(c))

  let outputJson = %*{
    "name": binnedSpec.name,
    "variables": varsJson,
    "data": dataJson,
    "counts": countsJson
  }

  let jsonStr = pretty(outputJson)

  if output == "":
    echo jsonStr
  else:
    writeFile(output, jsonStr)
    echo &"Saved binned data to {output}"

  return 0
