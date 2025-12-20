## Format conversion utilities for OCCAM
## Converts between OCCAM .in format, CSV, and JSON

{.push raises: [].}

import std/[strutils, sequtils, tables, parsecsv, streams, algorithm, os]
import ../core/types
import ../core/variable

type
  OccamInFile* = object
    ## Parsed OCCAM .in file structure
    action*: string
    variables*: seq[VariableSpec]
    data*: seq[seq[string]]
    counts*: seq[float]
    hasFrequency*: bool
    shortModel*: string
    searchWidth*: int
    searchLevels*: int

  VariableType* = enum
    ## Variable type in legacy OCCAM .in format
    vtExcluded = 0  # Type 0: Excluded from analysis
    vtIV = 1        # Type 1: Independent variable (active)
    vtDV = 2        # Type 2: Dependent variable

  VariableSpec* = object
    ## Variable specification for I/O
    name*: string
    abbrev*: string
    cardinality*: int
    isDependent*: bool
    varType*: VariableType  # Original type from .in file (default: vtIV)
    values*: seq[string]

  CsvAnalysis* = object
    ## Analysis results for a CSV file
    headers*: seq[string]
    columnCount*: int
    rowCount*: int
    uniqueValues*: seq[seq[string]]
    cardinalities*: seq[int]
    suggestedAbbrevs*: seq[string]


# ============ OCCAM .in Parser ============

proc parseOccamIn*(content: string): OccamInFile {.raises: [ValueError].} =
  ## Parse OCCAM .in format content
  result.hasFrequency = true  # Default: has frequency column
  result.searchWidth = 3
  result.searchLevels = 7

  var currentSection = ""

  for line in content.splitLines:
    let trimmed = line.strip

    # Skip empty lines and comments
    if trimmed.len == 0 or trimmed.startsWith("#") or trimmed.startsWith("//"):
      continue

    # Check for section headers
    if trimmed.startsWith(":"):
      currentSection = trimmed[1..^1].toLowerAscii

      # Handle flag sections
      if currentSection == "no-frequency":
        result.hasFrequency = false
        currentSection = ""
      continue

    # Process based on current section
    case currentSection
    of "action":
      result.action = trimmed.toLowerAscii

    of "nominal":
      # Parse variable definition: name,cardinality,type,abbrev
      # Type: 0=excluded, 1=IV, 2=DV
      let parts = trimmed.split(',')
      if parts.len >= 4:
        var spec: VariableSpec
        spec.name = parts[0].strip
        spec.cardinality = parseInt(parts[1].strip)
        let varTypeInt = parseInt(parts[2].strip)
        spec.varType = case varTypeInt
          of 0: vtExcluded
          of 2: vtDV
          else: vtIV
        spec.isDependent = (spec.varType == vtDV)
        spec.abbrev = parts[3].strip
        result.variables.add(spec)

    of "short-model":
      result.shortModel = trimmed

    of "optimize-search-width":
      result.searchWidth = parseInt(trimmed)

    of "search-levels":
      result.searchLevels = parseInt(trimmed)

    of "data":
      # Parse data row (space or tab separated)
      var values: seq[string]
      for part in trimmed.splitWhitespace:
        values.add(part)

      if values.len > 0:
        if result.hasFrequency:
          # Last value is count
          let count = parseFloat(values[^1])
          result.data.add(values[0..^2])
          result.counts.add(count)
        else:
          # No frequency column - each row counts as 1
          result.data.add(values)
          result.counts.add(1.0)


proc parseOccamInFile*(path: string): OccamInFile {.raises: [IOError, ValueError].} =
  ## Parse OCCAM .in file from disk
  let content = readFile(path)
  parseOccamIn(content)


proc activeVariableCount*(inFile: OccamInFile): int =
  ## Count variables that are not excluded (type != 0)
  for v in inFile.variables:
    if v.varType != vtExcluded:
      result += 1


proc activeVariables*(inFile: OccamInFile): seq[VariableSpec] =
  ## Get only active (non-excluded) variables
  for v in inFile.variables:
    if v.varType != vtExcluded:
      result.add(v)


proc inferValues*(inFile: OccamInFile; excludeType0: bool = true): OccamInFile =
  ## Infer value labels from data
  ##
  ## Arguments:
  ##   inFile: Parsed OCCAM .in file
  ##   excludeType0: If true (default), only infer values for active variables
  result = inFile

  # Initialize empty value sets for each variable
  var valueSets: seq[OrderedTable[string, bool]]
  for _ in result.variables:
    valueSets.add(initOrderedTable[string, bool]())

  # Collect unique values from data
  for row in result.data:
    for i, val in row:
      if i < valueSets.len:
        valueSets[i][val] = true

  # Sort and assign values
  for i in 0..<result.variables.len:
    # Skip excluded variables if excludeType0 is set
    if excludeType0 and result.variables[i].varType == vtExcluded:
      continue

    var vals: seq[string]
    for key in valueSets[i].keys:
      vals.add(key)
    vals.sort()
    result.variables[i].values = vals
    # Update cardinality if needed
    if result.variables[i].cardinality == 0:
      result.variables[i].cardinality = vals.len


# ============ CSV Analysis ============

proc analyzeCsv*(content: string; hasHeader: bool = true; delimiter: char = ','): CsvAnalysis {.raises: [IOError, OSError, CsvError].} =
  ## Analyze a CSV file to determine structure
  var parser: CsvParser
  parser.open(newStringStream(content), "input.csv", separator = delimiter)

  if hasHeader:
    parser.readHeaderRow()
    result.headers = parser.headers.toSeq
    result.columnCount = result.headers.len

  # Initialize unique value tracking
  var valueSets: seq[OrderedTable[string, bool]]

  while parser.readRow():
    result.rowCount += 1

    # Initialize on first data row
    if valueSets.len == 0:
      if result.columnCount == 0:
        result.columnCount = parser.row.len
      for _ in 0..<result.columnCount:
        valueSets.add(initOrderedTable[string, bool]())

    # Collect unique values
    for i, val in parser.row:
      if i < valueSets.len:
        valueSets[i][val.strip] = true

  parser.close()

  # Extract results
  for i, valueSet in valueSets:
    var vals: seq[string]
    for key in valueSet.keys:
      vals.add(key)
    vals.sort()
    result.uniqueValues.add(vals)
    result.cardinalities.add(vals.len)

  # Generate suggested abbreviations
  if result.headers.len > 0:
    for h in result.headers:
      result.suggestedAbbrevs.add(h[0..0].toUpperAscii)
  else:
    for i in 0..<result.columnCount:
      result.suggestedAbbrevs.add($chr(ord('A') + i))


proc analyzeCsvFile*(path: string; hasHeader: bool = true; delimiter: char = ','): CsvAnalysis {.raises: [IOError, OSError, CsvError].} =
  ## Analyze a CSV file from disk
  let content = readFile(path)
  analyzeCsv(content, hasHeader, delimiter)


# ============ JSON Output ============

proc toJson*(inFile: OccamInFile; excludeType0: bool = true): string =
  ## Convert to JSON format for OCCAM-Nim
  ##
  ## Arguments:
  ##   inFile: Parsed OCCAM .in file
  ##   excludeType0: If true (default), exclude variables with varType=vtExcluded (type=0)
  ##                 This matches legacy OCCAM behavior where type=0 vars are not used in analysis
  var lines: seq[string]
  lines.add("{")
  lines.add("  \"name\": \"Converted from OCCAM .in\",")

  # Build list of active variable indices (for filtering data columns)
  var activeIndices: seq[int]
  var activeVars: seq[VariableSpec]
  for i, v in inFile.variables:
    if not excludeType0 or v.varType != vtExcluded:
      activeIndices.add(i)
      activeVars.add(v)

  # Variables - only include active ones
  lines.add("  \"variables\": [")
  for i, v in activeVars:
    var varLines: seq[string]
    varLines.add("    {")
    varLines.add("      \"name\": \"" & v.name & "\",")
    varLines.add("      \"abbrev\": \"" & v.abbrev & "\",")
    varLines.add("      \"cardinality\": " & $v.cardinality & ",")
    varLines.add("      \"isDependent\": " & $v.isDependent & ",")

    # Values
    var valStrs: seq[string]
    if v.values.len > 0:
      for val in v.values:
        valStrs.add("\"" & val & "\"")
    else:
      for j in 0..<v.cardinality:
        valStrs.add("\"" & $j & "\"")
    varLines.add("      \"values\": [" & valStrs.join(", ") & "]")

    varLines.add("    }" & (if i < activeVars.len - 1: "," else: ""))
    lines.add(varLines.join("\n"))
  lines.add("  ],")

  # Data - only include columns for active variables
  lines.add("  \"data\": [")
  var dataLines: seq[string]
  for row in inFile.data:
    var rowStrs: seq[string]
    for colIdx in activeIndices:
      if colIdx < row.len:
        rowStrs.add("\"" & row[colIdx] & "\"")
      else:
        rowStrs.add("\"\"")
    dataLines.add("    [" & rowStrs.join(", ") & "]")
  lines.add(dataLines.join(",\n"))
  lines.add("  ],")

  # Counts
  var countStrs: seq[string]
  for c in inFile.counts:
    countStrs.add($c)
  lines.add("  \"counts\": [" & countStrs.join(", ") & "]")

  lines.add("}")
  result = lines.join("\n")


proc toJson*(analysis: CsvAnalysis; selectedColumns: seq[int]; dvColumn: int = -1;
             customAbbrevs: seq[string] = @[]; customNames: seq[string] = @[]): string =
  ## Convert CSV analysis to JSON format
  ## selectedColumns: which columns to include (0-indexed)
  ## dvColumn: which column is dependent variable (-1 = none/neutral)
  ## customAbbrevs: override abbreviations
  ## customNames: override names

  var lines: seq[string]
  lines.add("{")
  lines.add("  \"name\": \"Converted from CSV\",")

  # Variables
  lines.add("  \"variables\": [")
  for i, colIdx in selectedColumns:
    var varLines: seq[string]
    varLines.add("    {")

    let name = if i < customNames.len and customNames[i].len > 0:
                 customNames[i]
               elif colIdx < analysis.headers.len:
                 analysis.headers[colIdx]
               else:
                 "Var" & $colIdx

    let abbrev = if i < customAbbrevs.len and customAbbrevs[i].len > 0:
                   customAbbrevs[i]
                 elif colIdx < analysis.suggestedAbbrevs.len:
                   analysis.suggestedAbbrevs[colIdx]
                 else:
                   $chr(ord('A') + i)

    let isDependent = (colIdx == dvColumn)
    let cardinality = if colIdx < analysis.cardinalities.len:
                        analysis.cardinalities[colIdx]
                      else: 2

    varLines.add("      \"name\": \"" & name & "\",")
    varLines.add("      \"abbrev\": \"" & $abbrev & "\",")
    varLines.add("      \"cardinality\": " & $cardinality & ",")
    varLines.add("      \"isDependent\": " & $isDependent & ",")

    # Values
    var valStrs: seq[string]
    if colIdx < analysis.uniqueValues.len:
      for val in analysis.uniqueValues[colIdx]:
        valStrs.add("\"" & val & "\"")
    else:
      for j in 0..<cardinality:
        valStrs.add("\"" & $j & "\"")
    varLines.add("      \"values\": [" & valStrs.join(", ") & "]")

    varLines.add("    }" & (if i < selectedColumns.len - 1: "," else: ""))
    lines.add(varLines.join("\n"))
  lines.add("  ],")

  # Note: CSV data needs to be included separately since analysis doesn't store rows
  lines.add("  \"data\": [],")
  lines.add("  \"counts\": []")
  lines.add("}")
  result = lines.join("\n")


# ============ Full CSV Conversion ============

proc csvToJson*(content: string; selectedColumns: seq[int] = @[];
                dvColumn: int = -1; hasHeader: bool = true;
                delimiter: char = ','; customAbbrevs: seq[string] = @[];
                customNames: seq[string] = @[]): string {.raises: [IOError, OSError, CsvError].} =
  ## Convert CSV content directly to JSON with data
  var parser: CsvParser
  parser.open(newStringStream(content), "input.csv", separator = delimiter)

  var headers: seq[string]
  if hasHeader:
    parser.readHeaderRow()
    headers = parser.headers.toSeq

  # Collect all rows and unique values
  var allRows: seq[seq[string]]
  var valueSets: seq[OrderedTable[string, bool]]

  while parser.readRow():
    var row: seq[string]
    for val in parser.row:
      row.add(val.strip)

    # Initialize value sets
    if valueSets.len == 0:
      for _ in 0..<row.len:
        valueSets.add(initOrderedTable[string, bool]())

    # Track unique values
    for i, val in row:
      if i < valueSets.len:
        valueSets[i][val] = true

    allRows.add(row)

  parser.close()

  # Determine which columns to use
  let cols = if selectedColumns.len > 0:
               selectedColumns
             else:
               toSeq(0..<valueSets.len)

  # Build JSON
  var lines: seq[string]
  lines.add("{")
  lines.add("  \"name\": \"Converted from CSV\",")

  # Variables section
  lines.add("  \"variables\": [")
  for i, colIdx in cols:
    var varLines: seq[string]
    varLines.add("    {")

    let name = if i < customNames.len and customNames[i].len > 0:
                 customNames[i]
               elif colIdx < headers.len:
                 headers[colIdx]
               else:
                 "Var" & $colIdx

    let abbrev = if i < customAbbrevs.len and customAbbrevs[i].len > 0:
                   customAbbrevs[i]
                 elif colIdx < headers.len:
                   headers[colIdx][0..0].toUpperAscii
                 else:
                   $chr(ord('A') + i)

    let isDependent = (colIdx == dvColumn)

    # Get sorted unique values
    var vals: seq[string]
    if colIdx < valueSets.len:
      for key in valueSets[colIdx].keys:
        vals.add(key)
      vals.sort()

    varLines.add("      \"name\": \"" & name & "\",")
    varLines.add("      \"abbrev\": \"" & abbrev & "\",")
    varLines.add("      \"cardinality\": " & $vals.len & ",")
    varLines.add("      \"isDependent\": " & $isDependent & ",")

    var valStrs: seq[string]
    for val in vals:
      valStrs.add("\"" & val & "\"")
    varLines.add("      \"values\": [" & valStrs.join(", ") & "]")

    varLines.add("    }" & (if i < cols.len - 1: "," else: ""))
    lines.add(varLines.join("\n"))
  lines.add("  ],")

  # Data section - extract selected columns
  lines.add("  \"data\": [")
  var dataLines: seq[string]
  for row in allRows:
    var rowVals: seq[string]
    for colIdx in cols:
      if colIdx < row.len:
        rowVals.add("\"" & row[colIdx] & "\"")
      else:
        rowVals.add("\"\"")
    dataLines.add("    [" & rowVals.join(", ") & "]")
  lines.add(dataLines.join(",\n"))
  lines.add("  ],")

  # Counts - each row is 1 observation
  var countStrs: seq[string]
  for _ in allRows:
    countStrs.add("1")
  lines.add("  \"counts\": [" & countStrs.join(", ") & "]")

  lines.add("}")
  result = lines.join("\n")


proc csvFileToJson*(path: string; selectedColumns: seq[int] = @[];
                    dvColumn: int = -1; hasHeader: bool = true;
                    delimiter: char = ','): string {.raises: [IOError, OSError, CsvError].} =
  ## Convert CSV file to JSON
  let content = readFile(path)
  csvToJson(content, selectedColumns, dvColumn, hasHeader, delimiter)
