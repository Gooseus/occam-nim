## Preprocess Command Implementation
##
## Converts various data formats to pre-aggregated JSON for fast loading.
## Supports: JSON (raw observations), CSV, legacy OCCAM .in format
##
## Features:
## - Column selection: Choose specific columns to include
## - Binning: Reduce high-cardinality variables
## - Aggregation: Combine duplicate states into frequency counts
##
## The output format stores unique state combinations with frequency counts,
## reducing file size by 10-100x for large datasets.

import std/[strformat, strutils, tables, json, os, parsecsv, streams, algorithm, sequtils]
import ../occam/core/types
import ../occam/core/variable
import ../occam/io/formats as ioformats
import ../occam/io/binning
import ../occam/io/parser

type
  InputFormat = enum
    FormatAuto     # Auto-detect from extension
    FormatJson     # Raw JSON with data array
    FormatCsv      # CSV file
    FormatOccam    # Legacy OCCAM .in format

  # Local variable spec for aggregation output
  VarSpec = object
    name: string
    abbrev: string
    cardinality: int
    isDependent: bool
    values: seq[string]


proc parseColumnSpec(spec: string; numCols: int): seq[int] =
  ## Parse column specification string into indices
  ## Supports:
  ##   - Comma-separated indices: "0,1,3,5"
  ##   - Ranges: "0-3" or "2-5"
  ##   - Mixed: "0,2-4,7"
  ##   - Names will be resolved later
  if spec.strip() == "" or spec == "*":
    # All columns
    for i in 0..<numCols:
      result.add(i)
    return

  for part in spec.split(','):
    let p = part.strip()
    if '-' in p and not p.startsWith("-"):
      # Range like "2-5"
      let rangeParts = p.split('-')
      if rangeParts.len == 2:
        try:
          let start = parseInt(rangeParts[0].strip())
          let stop = parseInt(rangeParts[1].strip())
          for i in start..stop:
            if i >= 0 and i < numCols and i notin result:
              result.add(i)
        except ValueError:
          discard
    else:
      # Single index
      try:
        let idx = parseInt(p)
        if idx >= 0 and idx < numCols and idx notin result:
          result.add(idx)
      except ValueError:
        discard  # Might be a name - handled separately


proc parseColumnNames(spec: string; varNames: seq[string]): seq[int] =
  ## Parse column specification with names
  ## Returns indices for matched names
  if spec.strip() == "" or spec == "*":
    for i in 0..<varNames.len:
      result.add(i)
    return

  # Build name -> index map
  var nameToIdx = initTable[string, int]()
  for i, name in varNames:
    nameToIdx[name.toLowerAscii()] = i

  for part in spec.split(','):
    let p = part.strip()
    if '-' in p and not p.startsWith("-"):
      # Range - try numeric first
      let rangeParts = p.split('-')
      if rangeParts.len == 2:
        try:
          let start = parseInt(rangeParts[0].strip())
          let stop = parseInt(rangeParts[1].strip())
          for i in start..stop:
            if i >= 0 and i < varNames.len and i notin result:
              result.add(i)
        except ValueError:
          discard
    else:
      # Try as index first, then as name
      try:
        let idx = parseInt(p)
        if idx >= 0 and idx < varNames.len and idx notin result:
          result.add(idx)
      except ValueError:
        # Try as name
        let nameLower = p.toLowerAscii()
        if nameLower in nameToIdx:
          let idx = nameToIdx[nameLower]
          if idx notin result:
            result.add(idx)


proc detectFormat(filename: string): InputFormat =
  ## Auto-detect input format from file extension
  let ext = filename.splitFile().ext.toLowerAscii()
  case ext
  of ".json": FormatJson
  of ".csv": FormatCsv
  of ".in", ".txt": FormatOccam
  else: FormatJson  # Default to JSON


proc aggregateFromJson(filename: string): (seq[VarSpec], Table[seq[int], float64]) =
  ## Load JSON and aggregate to frequency counts
  let content = readFile(filename)
  let js = parseJson(content)

  var variables: seq[VarSpec]

  # Parse variables
  for v in js["variables"]:
    var vspec: VarSpec
    vspec.name = v["name"].getStr()
    vspec.abbrev = v["abbrev"].getStr()
    vspec.cardinality = v["cardinality"].getInt()
    vspec.isDependent = v{"isDependent"}.getBool(false)
    if v.hasKey("values"):
      for val in v["values"]:
        vspec.values.add(val.getStr())
    else:
      for i in 0..<vspec.cardinality:
        vspec.values.add($i)
    variables.add(vspec)

  # Aggregate data
  var freqMap = initTable[seq[int], float64]()
  let dataNode = js["data"]

  # Check if already has counts (already aggregated)
  let hasCounts = js.hasKey("counts")
  var countsNode: JsonNode
  if hasCounts:
    countsNode = js["counts"]

  var rowIdx = 0
  for row in dataNode:
    var indices: seq[int]
    var colIdx = 0
    for item in row:
      var val: int
      case item.kind
      of JInt:
        val = item.getInt()
        # Check if 1-indexed (values > 0 for all vars suggests 1-indexed)
        if val > 0 and colIdx < variables.len and val <= variables[colIdx].cardinality:
          val -= 1  # Convert to 0-indexed
      of JString:
        let s = item.getStr()
        # Try to find in values list first
        var found = false
        if colIdx < variables.len:
          for i, v in variables[colIdx].values:
            if v == s:
              val = i
              found = true
              break
        if not found:
          try:
            val = parseInt(s)
            if val > 0: val -= 1
          except ValueError:
            val = 0
      else:
        val = 0

      # Clamp to valid range
      if colIdx < variables.len:
        let card = variables[colIdx].cardinality
        if val < 0 or val >= card:
          val = val mod card
          if val < 0: val += card
      indices.add(val)
      colIdx += 1

    let count = if hasCounts and rowIdx < countsNode.len:
      countsNode[rowIdx].getFloat()
    else:
      1.0
    freqMap.mgetOrPut(indices, 0.0) += count
    rowIdx += 1

  (variables, freqMap)


proc aggregateFromCsv(filename: string; hasHeader: bool; delimiter: char;
                      dvColumn: int = -1): (seq[VarSpec], Table[seq[int], float64]) =
  ## Load CSV and aggregate to frequency counts
  var p: CsvParser
  var s = newFileStream(filename, fmRead)
  if s == nil:
    raise newException(IOError, "Cannot open file: " & filename)

  p.open(s, filename, separator = delimiter)

  # Read header or generate column names
  var colNames: seq[string]
  if hasHeader:
    discard p.readRow()
    colNames = p.row

  # First pass: determine cardinalities
  var valuesSeen: seq[Table[string, int]]
  var allRows: seq[seq[string]]

  while p.readRow():
    if valuesSeen.len == 0:
      valuesSeen = newSeq[Table[string, int]](p.row.len)
      for i in 0..<p.row.len:
        valuesSeen[i] = initTable[string, int]()
      if colNames.len == 0:
        for i in 0..<p.row.len:
          colNames.add("V" & $(i + 1))

    allRows.add(p.row)
    for i, val in p.row:
      if val notin valuesSeen[i]:
        valuesSeen[i][val] = valuesSeen[i].len

  p.close()

  # Build variables
  var variables: seq[VarSpec]
  for i in 0..<valuesSeen.len:
    var vspec: VarSpec
    vspec.name = if i < colNames.len: colNames[i] else: "V" & $(i + 1)
    vspec.abbrev = $chr(ord('A') + (i mod 26))
    if i >= 26:
      vspec.abbrev = $chr(ord('A') + (i div 26 - 1)) & vspec.abbrev
    vspec.cardinality = valuesSeen[i].len
    vspec.isDependent = (i == dvColumn)
    # Build values list in order seen
    vspec.values = newSeq[string](vspec.cardinality)
    for val, idx in valuesSeen[i]:
      vspec.values[idx] = val
    variables.add(vspec)

  # Aggregate rows
  var freqMap = initTable[seq[int], float64]()
  for row in allRows:
    var indices: seq[int]
    for i, val in row:
      indices.add(valuesSeen[i][val])
    freqMap.mgetOrPut(indices, 0.0) += 1.0

  (variables, freqMap)


proc aggregateFromOccam(filename: string): (seq[VarSpec], Table[seq[int], float64]) =
  ## Load legacy OCCAM .in format and aggregate
  # Use the existing converter
  let occamFile = ioformats.parseOccamInFile(filename)

  var variables: seq[VarSpec]
  for v in occamFile.variables:
    var vspec: VarSpec
    vspec.name = v.name
    vspec.abbrev = v.abbrev
    vspec.cardinality = v.cardinality
    vspec.isDependent = v.isDependent
    vspec.values = v.values
    variables.add(vspec)

  # If already has counts, use them
  var freqMap = initTable[seq[int], float64]()
  for rowIdx, row in occamFile.data:
    var indices: seq[int]
    for i, val in row:
      # Find value index
      var idx = 0
      if i < variables.len:
        for j, v in variables[i].values:
          if v == val:
            idx = j
            break
      indices.add(idx)
    let count = if rowIdx < occamFile.counts.len: occamFile.counts[rowIdx] else: 1.0
    freqMap.mgetOrPut(indices, 0.0) += count

  (variables, freqMap)


proc writeAggregatedJson(filename: string; name: string;
                         variables: seq[VarSpec];
                         freqMap: Table[seq[int], float64]) =
  ## Write pre-aggregated JSON format
  var js = newJObject()
  js["name"] = %name
  js["format"] = %"aggregated"  # Mark as pre-aggregated

  # Variables
  var varsArr = newJArray()
  for v in variables:
    var vj = newJObject()
    vj["name"] = %v.name
    vj["abbrev"] = %v.abbrev
    vj["cardinality"] = %v.cardinality
    vj["isDependent"] = %v.isDependent
    var valsArr = newJArray()
    for val in v.values:
      valsArr.add(%val)
    vj["values"] = valsArr
    varsArr.add(vj)
  js["variables"] = varsArr

  # Data and counts (sorted for deterministic output)
  var sortedKeys: seq[seq[int]]
  for k in freqMap.keys:
    sortedKeys.add(k)
  # Custom sort for seq[int]
  sortedKeys.sort(proc(a, b: seq[int]): int =
    for i in 0..<min(a.len, b.len):
      if a[i] < b[i]: return -1
      if a[i] > b[i]: return 1
    cmp(a.len, b.len)
  )

  var dataArr = newJArray()
  var countsArr = newJArray()
  var totalSamples = 0.0

  for k in sortedKeys:
    var rowArr = newJArray()
    for idx in k:
      rowArr.add(%idx)  # Store as 0-indexed integers
    dataArr.add(rowArr)
    let count = freqMap[k]
    countsArr.add(%count)
    totalSamples += count

  js["data"] = dataArr
  js["counts"] = countsArr
  js["sampleSize"] = %totalSamples
  js["uniqueStates"] = %sortedKeys.len

  # Write with pretty formatting
  let output = js.pretty()
  if filename == "" or filename == "-":
    echo output
  else:
    writeFile(filename, output)


proc preprocess*(input: string;
                 output = "";
                 format = "auto";
                 columns = "";
                 autoBin = false;
                 targetCard = 5;
                 binThreshold = 10;
                 hasHeader = true;
                 delimiter = ',';
                 dv = -1;
                 name = "";
                 verbose = false): int =
  ## Convert data files to pre-aggregated JSON format
  ##
  ## Arguments:
  ##   input: Input file (JSON, CSV, or OCCAM .in format)
  ##   output: Output JSON file (stdout if empty)
  ##   format: Input format (auto, json, csv, occam)
  ##   columns: Columns to include (e.g., "0,2-4,Age,Target" or "*" for all)
  ##   autoBin: Auto-bin high-cardinality columns
  ##   targetCard: Target cardinality for auto-binning
  ##   binThreshold: Only bin columns with cardinality > threshold
  ##   hasHeader: CSV has header row
  ##   delimiter: CSV column delimiter
  ##   dv: Dependent variable column index for CSV (-1 for none)
  ##   name: Dataset name (defaults to filename)
  ##   verbose: Show detailed output

  if input == "":
    echo "Error: Input file required"
    return 1

  if not fileExists(input):
    echo "Error: File not found: ", input
    return 1

  # Detect format
  let inputFormat = if format == "auto":
    detectFormat(input)
  elif format == "json":
    FormatJson
  elif format == "csv":
    FormatCsv
  elif format == "occam" or format == "in":
    FormatOccam
  else:
    echo "Error: Unknown format '", format, "'. Use: auto, json, csv, occam"
    return 1

  let inputSize = getFileSize(input)
  if verbose:
    echo "Input: ", input, " (", formatSize(inputSize.int), ")"
    echo "Format: ", inputFormat

  # Load and aggregate
  var variables: seq[VarSpec]
  var freqMap: Table[seq[int], float64]

  try:
    case inputFormat
    of FormatJson, FormatAuto:
      if verbose:
        echo "Loading JSON..."
      (variables, freqMap) = aggregateFromJson(input)
    of FormatCsv:
      if verbose:
        echo "Loading CSV..."
      (variables, freqMap) = aggregateFromCsv(input, hasHeader, delimiter, dv)
    of FormatOccam:
      if verbose:
        echo "Loading OCCAM format..."
      (variables, freqMap) = aggregateFromOccam(input)
  except CatchableError as e:
    echo "Error loading file: ", e.msg
    return 1

  if verbose:
    echo "  Loaded ", variables.len, " variables, ", freqMap.len, " unique states"

  # Step 2: Column selection (if specified)
  var varNames: seq[string]
  for v in variables:
    varNames.add(v.name)

  let selectedCols = if columns == "" or columns == "*":
    toSeq(0..<variables.len)
  else:
    parseColumnNames(columns, varNames)

  if selectedCols.len == 0:
    echo "Error: No columns selected"
    return 1

  if selectedCols.len < variables.len:
    if verbose:
      echo "Selecting columns: ", selectedCols.mapIt(variables[it].name).join(", ")

    # Re-aggregate with only selected columns
    var newVariables: seq[VarSpec]
    for idx in selectedCols:
      newVariables.add(variables[idx])

    var newFreqMap = initTable[seq[int], float64]()
    for key, count in freqMap.pairs:
      var newKey: seq[int]
      for idx in selectedCols:
        newKey.add(key[idx])
      newFreqMap.mgetOrPut(newKey, 0.0) += count

    variables = newVariables
    freqMap = newFreqMap

    if verbose:
      echo "  After selection: ", variables.len, " variables, ", freqMap.len, " unique states"

  # Step 3: Auto-binning (if enabled)
  if autoBin:
    if verbose:
      echo "Auto-binning high-cardinality columns (threshold: ", binThreshold, ", target: ", targetCard, ")..."

    # Find columns that need binning
    var binnedAny = false
    for i in 0..<variables.len:
      if variables[i].cardinality > binThreshold:
        binnedAny = true
        if verbose:
          echo "  Binning ", variables[i].name, " (", variables[i].cardinality, " -> ", targetCard, ")"

        # Create mapping from old values to new bins
        let oldCard = variables[i].cardinality
        var valueMapping: seq[int]  # old index -> new bin index

        # Simple equal-width binning for now
        let binSize = (oldCard + targetCard - 1) div targetCard
        for oldIdx in 0..<oldCard:
          valueMapping.add(min(oldIdx div binSize, targetCard - 1))

        # Update frequency map
        var newFreqMap = initTable[seq[int], float64]()
        for key, count in freqMap.pairs:
          var newKey = key
          newKey[i] = valueMapping[key[i]]
          newFreqMap.mgetOrPut(newKey, 0.0) += count
        freqMap = newFreqMap

        # Update variable spec
        variables[i].cardinality = targetCard
        var newValues: seq[string]
        for b in 0..<targetCard:
          let startIdx = b * binSize
          let endIdx = min((b + 1) * binSize - 1, oldCard - 1)
          if startIdx < variables[i].values.len and endIdx < variables[i].values.len:
            newValues.add(variables[i].values[startIdx] & "-" & variables[i].values[endIdx])
          else:
            newValues.add("Bin" & $b)
        variables[i].values = newValues

    if binnedAny and verbose:
      echo "  After binning: ", freqMap.len, " unique states"

  # Calculate stats
  var totalSamples = 0.0
  for count in freqMap.values:
    totalSamples += count

  if verbose:
    echo ""
    echo "Final result:"
    echo "  Variables: ", variables.len
    echo "  Unique states: ", freqMap.len
    echo "  Total samples: ", totalSamples.int
    echo ""

  # Determine output name
  let datasetName = if name != "": name
                    else: input.splitFile().name

  # Write output
  let outFile = if output == "": "" else: output
  writeAggregatedJson(outFile, datasetName, variables, freqMap)

  if output != "" and verbose:
    let outSize = getFileSize(output)
    let ratio = inputSize.float / outSize.float
    echo "Output: ", output, " (", formatSize(outSize.int), ")"
    echo "Compression: ", &"{ratio:.1f}x smaller"

  return 0


proc formatSize(bytes: int): string =
  ## Format byte size as human-readable string
  if bytes < 1024:
    $bytes & " B"
  elif bytes < 1024 * 1024:
    &"{bytes / 1024:.1f} KB"
  elif bytes < 1024 * 1024 * 1024:
    &"{bytes / (1024 * 1024):.1f} MB"
  else:
    &"{bytes / (1024 * 1024 * 1024):.1f} GB"
