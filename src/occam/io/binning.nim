## Binning/Discretization module for OCCAM-Nim
## Transforms continuous variables and high-cardinality categoricals
## into discrete categories suitable for Reconstructability Analysis

{.push raises: [].}

import std/[strutils, algorithm, sequtils, tables, strformat]
import parser

type
  BinStrategy* = enum
    ## How to determine bin boundaries
    bsNone              ## No binning (categorical passthrough)
    bsEqualWidth        ## Equal-width intervals
    bsEqualFrequency    ## Equal-frequency (quantile)
    bsCustomBreaks      ## User-specified breakpoints
    bsTopN              ## Keep top N categories, collapse rest
    bsFrequencyThreshold ## Collapse categories below threshold

  MissingValueHandling* = enum
    ## How to handle missing/invalid values
    mvhSeparateBin      ## Create "Missing" bin
    mvhExclude          ## Exclude rows with missing values
    mvhIgnore           ## Treat as regular value (may cause issues)

  BinLabelStyle* = enum
    ## How to generate bin labels
    blsRange            ## "0-10", "10-20"
    blsSemantic         ## "Low", "Medium", "High"
    blsIndex            ## "0", "1", "2"
    blsCustom           ## User-provided labels

  BinSpec* = object
    ## Specification for binning a single variable
    strategy*: BinStrategy
    numBins*: int                    ## For equal-width/frequency
    breakpoints*: seq[float64]       ## For custom breaks
    topN*: int                       ## For top-N strategy
    minFrequency*: float64           ## For frequency threshold (count or proportion)
    minFrequencyIsRatio*: bool       ## true = proportion, false = count
    labelStyle*: BinLabelStyle
    customLabels*: seq[string]       ## For custom labels
    otherLabel*: string              ## Label for collapsed categories
    missingHandling*: MissingValueHandling
    missingLabel*: string            ## Label for missing bin

  ColumnAnalysis* = object
    ## Analysis of a single column for auto-detection
    isNumeric*: bool
    uniqueCount*: int
    totalCount*: int
    missingCount*: int
    minVal*: float64
    maxVal*: float64
    values*: seq[string]              ## Unique values
    frequencies*: seq[(string, int)]  ## (value, count) sorted by count desc

  BinResult* = object
    ## Result of binning a single column
    originalName*: string
    newValues*: seq[string]          ## Bin labels
    newCardinality*: int
    mapping*: seq[int]               ## Maps original data rows to bin indices (-1 = excluded)
    binEdges*: seq[float64]          ## For numeric binning


# ============ Missing Value Detection ============

const MissingValueIndicators = [
  "", "NA", "na", "N/A", "n/a", "NaN", "nan",
  "null", "NULL", "Null", "nil", "NIL",
  ".", "-", "?", "None", "none", "NONE",
  "#N/A", "#NA", "#NULL!"
]

proc isMissingValue*(val: string): bool =
  ## Check if a value represents a missing/NA value
  val.strip() in MissingValueIndicators


# ============ Column Analysis ============

proc tryParseFloat(s: string): (bool, float64) =
  ## Try to parse a string as float64
  try:
    result = (true, parseFloat(s))
  except ValueError:
    result = (false, 0.0)

proc analyzeColumn*(data: seq[string]): ColumnAnalysis =
  ## Analyze a column to determine type and statistics
  result.totalCount = data.len
  result.missingCount = 0
  result.uniqueCount = 0
  result.minVal = high(float64)
  result.maxVal = low(float64)

  if data.len == 0:
    return

  var valueCounts = initCountTable[string]()
  var numericValues: seq[float64]
  var allNumeric = true

  for val in data:
    if isMissingValue(val):
      result.missingCount += 1
      continue

    valueCounts.inc(val)

    let (isNum, numVal) = tryParseFloat(val)
    if isNum:
      numericValues.add(numVal)
      if numVal < result.minVal:
        result.minVal = numVal
      if numVal > result.maxVal:
        result.maxVal = numVal
    else:
      allNumeric = false

  # Determine if column is numeric
  # Must have at least one non-missing value and all non-missing values must parse as numbers
  result.isNumeric = allNumeric and numericValues.len > 0

  # Collect unique values
  result.uniqueCount = valueCounts.len
  result.values = newSeq[string]()
  for val in valueCounts.keys:
    result.values.add(val)
  result.values.sort()

  # Build frequencies sorted by count descending
  result.frequencies = newSeq[(string, int)]()
  for val, count in valueCounts.pairs:
    result.frequencies.add((val, count))
  result.frequencies.sort(proc(a, b: (string, int)): int =
    # Sort by count descending, then by value ascending for ties
    if a[1] != b[1]:
      b[1] - a[1]
    else:
      cmp(a[0], b[0])
  )

  # Handle edge case where all values are missing
  if result.minVal == high(float64):
    result.minVal = 0.0
    result.maxVal = 0.0


# ============ Equal-Width Binning ============

proc computeEqualWidthBreaks*(values: seq[float64]; numBins: int): seq[float64] =
  ## Compute bin edges for equal-width binning
  ## Returns numBins + 1 edges (e.g., 3 bins -> 4 edges)
  if values.len == 0:
    return @[0.0, 1.0]

  var minVal = values[0]
  var maxVal = values[0]
  for v in values:
    if v < minVal: minVal = v
    if v > maxVal: maxVal = v

  # Handle edge case where all values are the same
  if abs(maxVal - minVal) < 1e-10:
    # Create a small range around the single value
    return @[minVal - 0.5, minVal + 0.5]

  let binWidth = (maxVal - minVal) / numBins.float64

  result = newSeq[float64](numBins + 1)
  for i in 0..numBins:
    result[i] = minVal + i.float64 * binWidth


proc assignToBin*(value: float64; breaks: seq[float64]): int =
  ## Assign a value to a bin index based on breakpoints
  ## Uses left-closed intervals: [a, b)
  ## The last bin includes the right edge: [a, b]
  if breaks.len < 2:
    return 0

  let numBins = breaks.len - 1

  # Handle values at or beyond edges
  if value <= breaks[0]:
    return 0
  if value >= breaks[numBins]:
    return numBins - 1

  # Binary search for the correct bin
  for i in 0..<numBins:
    if value >= breaks[i] and value < breaks[i + 1]:
      return i

  # Shouldn't reach here, but return last bin as fallback
  return numBins - 1


# ============ Label Generation ============

proc generateRangeLabels*(breaks: seq[float64]; precision: int = 0): seq[string] =
  ## Generate range labels like "0-10", "10-20"
  if breaks.len < 2:
    return @["0"]

  let numBins = breaks.len - 1
  result = newSeq[string](numBins)

  for i in 0..<numBins:
    if precision == 0:
      # Integer-style labels
      result[i] = &"{breaks[i].int}-{breaks[i+1].int}"
    else:
      # Decimal labels
      result[i] = formatFloat(breaks[i], ffDecimal, precision) & "-" &
                  formatFloat(breaks[i+1], ffDecimal, precision)


proc generateSemanticLabels*(numBins: int): seq[string] =
  ## Generate semantic labels like "Low", "Medium", "High"
  case numBins
  of 1: @["Single"]
  of 2: @["Low", "High"]
  of 3: @["Low", "Medium", "High"]
  of 4: @["Low", "MediumLow", "MediumHigh", "High"]
  of 5: @["VeryLow", "Low", "Medium", "High", "VeryHigh"]
  of 6: @["VeryLow", "Low", "MediumLow", "MediumHigh", "High", "VeryHigh"]
  of 7: @["VeryLow", "Low", "MediumLow", "Medium", "MediumHigh", "High", "VeryHigh"]
  else:
    # For more bins, use numbered labels
    var labels = newSeq[string](numBins)
    for i in 0..<numBins:
      labels[i] = &"Bin{i+1}"
    labels


proc generateIndexLabels*(numBins: int): seq[string] =
  ## Generate simple index labels "0", "1", "2"
  result = newSeq[string](numBins)
  for i in 0..<numBins:
    result[i] = $i


# ============ Quantile Binning (Equal-Frequency) ============

proc computeQuantileBreaks*(values: seq[float64]; numBins: int): seq[float64] =
  ## Compute bin edges for equal-frequency (quantile) binning
  ## Each bin will have approximately the same number of observations
  if values.len == 0:
    return @[0.0, 1.0]

  var sorted = values.sorted()

  # Handle edge case where all values are the same
  if sorted[0] == sorted[^1]:
    return @[sorted[0] - 0.5, sorted[0] + 0.5]

  result = newSeq[float64](numBins + 1)
  result[0] = sorted[0]
  result[numBins] = sorted[^1]

  # Compute quantile positions
  for i in 1..<numBins:
    let quantile = i.float64 / numBins.float64
    let pos = quantile * (sorted.len - 1).float64
    let lower = pos.int
    let upper = min(lower + 1, sorted.len - 1)
    let frac = pos - lower.float64

    # Linear interpolation
    result[i] = sorted[lower] * (1.0 - frac) + sorted[upper] * frac


# ============ Numeric Column Binning ============

proc binNumericColumn*(data: seq[string]; spec: BinSpec): BinResult =
  ## Bin a numeric column based on specification
  result.mapping = newSeq[int](data.len)

  # 1. Parse values, track missing
  var values: seq[float64]
  var valueIndices: seq[int]  # Original indices of non-missing values
  var missingIndices: seq[int]

  for i, s in data:
    if isMissingValue(s):
      missingIndices.add(i)
    else:
      let (ok, val) = tryParseFloat(s)
      if ok:
        values.add(val)
        valueIndices.add(i)
      else:
        # Non-numeric value in numeric column - treat as missing
        missingIndices.add(i)

  # 2. Compute bin edges based on strategy
  var breaks: seq[float64]
  case spec.strategy
  of bsEqualWidth:
    breaks = computeEqualWidthBreaks(values, spec.numBins)
  of bsEqualFrequency:
    breaks = computeQuantileBreaks(values, spec.numBins)
  of bsCustomBreaks:
    breaks = spec.breakpoints
  else:
    # Shouldn't use this function for non-numeric strategies
    breaks = computeEqualWidthBreaks(values, spec.numBins)

  result.binEdges = breaks
  let numBins = if breaks.len > 1: breaks.len - 1 else: 1

  # 3. Generate labels
  var labels: seq[string]
  case spec.labelStyle
  of blsRange:
    labels = generateRangeLabels(breaks)
  of blsSemantic:
    labels = generateSemanticLabels(numBins)
  of blsIndex:
    labels = generateIndexLabels(numBins)
  of blsCustom:
    labels = spec.customLabels
    # Pad with index labels if not enough custom labels
    while labels.len < numBins:
      labels.add(&"Bin{labels.len}")

  # 4. Assign each value to bin
  for i in 0..<values.len:
    let binIdx = assignToBin(values[i], breaks)
    result.mapping[valueIndices[i]] = binIdx

  # 5. Handle missing values
  let missingBinIdx = labels.len  # Will be after regular bins
  for i in missingIndices:
    case spec.missingHandling
    of mvhSeparateBin:
      result.mapping[i] = missingBinIdx
    of mvhExclude:
      result.mapping[i] = -1  # Mark for exclusion
    of mvhIgnore:
      result.mapping[i] = 0  # Put in first bin (not recommended)

  # 6. Set result metadata
  result.newValues = labels
  if spec.missingHandling == mvhSeparateBin and missingIndices.len > 0:
    let missingLabel = if spec.missingLabel.len > 0: spec.missingLabel else: "Missing"
    result.newValues.add(missingLabel)
  result.newCardinality = result.newValues.len


# ============ Categorical Binning ============

proc binCategoricalColumn*(data: seq[string]; spec: BinSpec;
                           frequencies: seq[(string, int)]): BinResult =
  ## Bin a categorical column based on specification (TopN or Threshold)
  result.mapping = newSeq[int](data.len)

  var keepValues: seq[string]
  var valueToIndex: Table[string, int]

  case spec.strategy
  of bsTopN:
    # Keep top N most frequent values
    let n = min(spec.topN, frequencies.len)
    for i in 0..<n:
      keepValues.add(frequencies[i][0])
      valueToIndex[frequencies[i][0]] = i

  of bsFrequencyThreshold:
    # Keep values above frequency threshold
    let totalCount = frequencies.foldl(a + b[1], 0)
    var idx = 0
    for (val, count) in frequencies:
      let freq = if spec.minFrequencyIsRatio:
        count.float64 / totalCount.float64
      else:
        count.float64
      if freq >= spec.minFrequency:
        keepValues.add(val)
        valueToIndex[val] = idx
        idx += 1

  else:
    # Passthrough - keep all values
    for i, (val, _) in frequencies:
      keepValues.add(val)
      valueToIndex[val] = i

  # Add "Other" category if we're collapsing
  let otherLabel = if spec.otherLabel.len > 0: spec.otherLabel else: "Other"
  let hasOther = keepValues.len < frequencies.len
  let otherIdx = keepValues.len

  # Assign each value
  var missingIndices: seq[int]
  for i, val in data:
    if isMissingValue(val):
      missingIndices.add(i)
    elif val in valueToIndex:
      try:
        result.mapping[i] = valueToIndex[val]
      except KeyError:
        result.mapping[i] = otherIdx
    else:
      result.mapping[i] = otherIdx  # Collapsed to "Other"

  # Build final labels
  result.newValues = keepValues
  if hasOther:
    result.newValues.add(otherLabel)

  # Handle missing values
  let missingBinIdx = result.newValues.len
  for i in missingIndices:
    case spec.missingHandling
    of mvhSeparateBin:
      result.mapping[i] = missingBinIdx
    of mvhExclude:
      result.mapping[i] = -1
    of mvhIgnore:
      result.mapping[i] = otherIdx  # Put in Other

  if spec.missingHandling == mvhSeparateBin and missingIndices.len > 0:
    let missingLabel = if spec.missingLabel.len > 0: spec.missingLabel else: "Missing"
    result.newValues.add(missingLabel)

  result.newCardinality = result.newValues.len


# ============ Auto-Detection & Suggestion ============

proc suggestBinStrategy*(col: ColumnAnalysis; targetCardinality: int = 5): BinSpec =
  ## Suggest a binning strategy based on column analysis
  result.numBins = targetCardinality
  result.topN = targetCardinality
  result.labelStyle = blsRange
  result.missingHandling = mvhSeparateBin
  result.missingLabel = "Missing"
  result.otherLabel = "Other"

  if col.isNumeric:
    result.strategy = bsEqualWidth
    result.labelStyle = blsRange
  elif col.uniqueCount > targetCardinality:
    result.strategy = bsTopN
    result.labelStyle = blsIndex
  else:
    result.strategy = bsNone  # Passthrough


# ============ DataSpec Integration ============

proc extractColumn*(spec: DataSpec; colIdx: int): seq[string] =
  ## Extract a single column from DataSpec data as a sequence
  result = newSeq[string](spec.data.len)
  for i, row in spec.data:
    if colIdx < row.len:
      result[i] = row[colIdx]
    else:
      result[i] = ""


proc applyBinning*(spec: DataSpec; binSpecs: seq[(int, BinSpec)]): DataSpec =
  ## Apply binning transformations to a DataSpec by column index
  ## Returns a new DataSpec with binned data
  ##
  ## Parameters:
  ##   spec: Original data specification
  ##   binSpecs: Sequence of (column_index, BinSpec) pairs
  ##
  ## The resulting DataSpec will have:
  ##   - Updated variable cardinalities and values
  ##   - Transformed data values (bin labels)
  ##   - Combined counts for rows that map to the same binned state

  result.name = spec.name
  result.variables = spec.variables
  result.data = spec.data
  result.counts = spec.counts

  # Build map of column index -> BinSpec
  var binMap: Table[int, BinSpec]
  for (idx, binSpec) in binSpecs:
    binMap[idx] = binSpec

  # Process each column that needs binning
  var binResults: Table[int, BinResult]

  for colIdx, binSpec in binMap.pairs:
    if colIdx >= result.variables.len:
      continue

    let colData = extractColumn(spec, colIdx)
    let analysis = analyzeColumn(colData)

    # Determine binning method based on strategy and data type
    var binResult: BinResult
    if binSpec.strategy == bsNone:
      # Passthrough - no binning
      binResult.newValues = analysis.values
      binResult.newCardinality = analysis.uniqueCount
      binResult.mapping = newSeq[int](colData.len)
      # Build value -> index map
      var valIdx: Table[string, int]
      for i, v in analysis.values:
        valIdx[v] = i
      for i, v in colData:
        if isMissingValue(v):
          if binSpec.missingHandling == mvhSeparateBin:
            binResult.mapping[i] = analysis.values.len
          else:
            binResult.mapping[i] = -1
        elif v in valIdx:
          try:
            binResult.mapping[i] = valIdx[v]
          except KeyError:
            binResult.mapping[i] = 0
        else:
          binResult.mapping[i] = 0
      if binSpec.missingHandling == mvhSeparateBin:
        var hasMissing = false
        for i in colData:
          if isMissingValue(i):
            hasMissing = true
            break
        if hasMissing:
          binResult.newValues.add(if binSpec.missingLabel.len > 0: binSpec.missingLabel else: "Missing")
          binResult.newCardinality = binResult.newValues.len

    elif analysis.isNumeric and binSpec.strategy in {bsEqualWidth, bsEqualFrequency, bsCustomBreaks}:
      binResult = binNumericColumn(colData, binSpec)
    else:
      binResult = binCategoricalColumn(colData, binSpec, analysis.frequencies)

    binResults[colIdx] = binResult

    # Update variable spec
    result.variables[colIdx].cardinality = binResult.newCardinality
    result.variables[colIdx].values = binResult.newValues

  # Transform data rows
  var newData: seq[seq[string]] = @[]
  var newCounts: seq[float64] = @[]
  var rowMap: Table[seq[string], int]  # Map binned row -> index in newData

  for rowIdx in 0..<result.data.len:
    var newRow = newSeq[string](result.variables.len)
    var excludeRow = false

    for colIdx in 0..<result.variables.len:
      if colIdx in binResults:
        try:
          let br = binResults[colIdx]
          let binIdx = br.mapping[rowIdx]
          if binIdx == -1:
            excludeRow = true
            break
          newRow[colIdx] = br.newValues[binIdx]
        except KeyError:
          # No binning for this column - keep original
          if rowIdx < spec.data.len and colIdx < spec.data[rowIdx].len:
            newRow[colIdx] = spec.data[rowIdx][colIdx]
      else:
        # No binning for this column - keep original
        if rowIdx < spec.data.len and colIdx < spec.data[rowIdx].len:
          newRow[colIdx] = spec.data[rowIdx][colIdx]

    if excludeRow:
      continue

    # Check if this binned row already exists (combine counts)
    if newRow in rowMap:
      try:
        let existingIdx = rowMap[newRow]
        let rowCount = if rowIdx < spec.counts.len: spec.counts[rowIdx] else: 1.0
        newCounts[existingIdx] += rowCount
      except KeyError:
        rowMap[newRow] = newData.len
        newData.add(newRow)
        let rowCount = if rowIdx < spec.counts.len: spec.counts[rowIdx] else: 1.0
        newCounts.add(rowCount)
    else:
      rowMap[newRow] = newData.len
      newData.add(newRow)
      let rowCount = if rowIdx < spec.counts.len: spec.counts[rowIdx] else: 1.0
      newCounts.add(rowCount)

  result.data = newData
  result.counts = newCounts


proc applyBinningByName*(spec: DataSpec; binSpecs: seq[(string, BinSpec)]): DataSpec =
  ## Apply binning transformations by variable name
  ## Converts name-based specs to index-based and calls applyBinning

  # Build name -> index map
  var nameToIdx: Table[string, int]
  for i, v in spec.variables:
    nameToIdx[v.name] = i

  # Convert to index-based specs
  var indexSpecs: seq[(int, BinSpec)]
  for (name, binSpec) in binSpecs:
    if name in nameToIdx:
      try:
        indexSpecs.add((nameToIdx[name], binSpec))
      except KeyError:
        discard

  applyBinning(spec, indexSpecs)


proc autoBinDataSpec*(spec: DataSpec; targetCardinality: int = 5;
                      threshold: int = 10): DataSpec =
  ## Automatically bin columns that exceed threshold cardinality
  ##
  ## Parameters:
  ##   spec: Original data specification
  ##   targetCardinality: Target number of bins for high-cardinality columns
  ##   threshold: Only bin columns with cardinality > threshold

  var binSpecs: seq[(int, BinSpec)]

  for i, vspec in spec.variables:
    let colData = extractColumn(spec, i)
    let analysis = analyzeColumn(colData)

    if analysis.uniqueCount > threshold:
      let suggested = suggestBinStrategy(analysis, targetCardinality)
      binSpecs.add((i, suggested))

  if binSpecs.len > 0:
    result = applyBinning(spec, binSpecs)
  else:
    result = spec
