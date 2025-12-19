## OCCAM Binning Module for JavaScript/WASM
##
## Pure binning functions for client-side data preprocessing.
## Compile: nim js -d:release -o:src/static/public/binning.js src/occam_binning_js.nim
##
## No file I/O - all data passed through JSON strings.

{.push raises: [].}

import std/[json, strutils, algorithm, sequtils, tables, math, strformat, sets]

# ============ Types ============

type
  BinStrategy* = enum
    bsNone = "none"
    bsEqualWidth = "equalWidth"
    bsEqualFrequency = "equalFrequency"
    bsCustomBreaks = "customBreaks"
    bsTopN = "topN"
    bsFrequencyThreshold = "frequencyThreshold"

  MissingHandling* = enum
    mvhSeparateBin = "separateBin"
    mvhExclude = "exclude"
    mvhIgnore = "ignore"

  LabelStyle* = enum
    blsRange = "range"
    blsSemantic = "semantic"
    blsIndex = "index"
    blsCustom = "custom"

  ColumnAnalysis = object
    name: string
    index: int
    isNumeric: bool
    uniqueCount: int
    totalCount: int
    missingCount: int
    minVal: float64
    maxVal: float64
    topValues: seq[(string, int)]
    needsBinning: bool
    suggestedStrategy: BinStrategy

  BinConfig = object
    strategy: BinStrategy
    numBins: int
    breakpoints: seq[float64]
    topN: int
    minFrequency: float64
    minFrequencyIsRatio: bool
    labelStyle: LabelStyle
    customLabels: seq[string]
    otherLabel: string
    missingHandling: MissingHandling
    missingLabel: string

  VariableSpec = object
    name: string
    abbrev: string
    cardinality: int
    values: seq[string]
    isDependent: bool

# ============ Constants ============

const
  MissingValueIndicators = [
    "", "NA", "na", "N/A", "n/a", "NaN", "nan",
    "null", "NULL", "Null", "nil", "NIL",
    ".", "-", "?", "None", "none", "NONE",
    "#N/A", "#NA", "#NULL!"
  ]
  CardinalityThreshold = 10

# ============ Missing Value Detection ============

proc isMissingValue(val: string): bool =
  val.strip() in MissingValueIndicators

# ============ Parsing Helpers ============

proc tryParseFloat(s: string): (bool, float64) =
  try:
    result = (true, parseFloat(s))
  except ValueError:
    result = (false, 0.0)

# ============ Column Analysis ============

proc analyzeColumnData(data: seq[string]): ColumnAnalysis =
  result.totalCount = data.len
  result.missingCount = 0
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
      if numVal < result.minVal: result.minVal = numVal
      if numVal > result.maxVal: result.maxVal = numVal
    else:
      allNumeric = false

  result.isNumeric = allNumeric and numericValues.len > 0
  result.uniqueCount = valueCounts.len

  # Build frequencies sorted by count descending
  for val, count in valueCounts.pairs:
    result.topValues.add((val, count))
  result.topValues.sort(proc(a, b: (string, int)): int =
    if a[1] != b[1]: b[1] - a[1]
    else: cmp(a[0], b[0])
  )

  if result.minVal == high(float64):
    result.minVal = 0.0
    result.maxVal = 0.0

  result.needsBinning = result.uniqueCount > CardinalityThreshold
  if result.needsBinning:
    result.suggestedStrategy = if result.isNumeric: bsEqualWidth else: bsTopN
  else:
    result.suggestedStrategy = bsNone

# ============ Binning Algorithms ============

proc computeEqualWidthBreaks(minVal, maxVal: float64; numBins: int): seq[float64] =
  if abs(maxVal - minVal) < 1e-10:
    return @[minVal - 0.5, minVal + 0.5]

  let binWidth = (maxVal - minVal) / numBins.float64
  result = newSeq[float64](numBins + 1)
  for i in 0..numBins:
    result[i] = minVal + i.float64 * binWidth

proc assignToBin(value: float64; breaks: seq[float64]): int =
  if breaks.len < 2: return 0
  let numBins = breaks.len - 1
  if value <= breaks[0]: return 0
  if value >= breaks[numBins]: return numBins - 1
  for i in 0..<numBins:
    if value >= breaks[i] and value < breaks[i + 1]:
      return i
  return numBins - 1

proc generateRangeLabels(breaks: seq[float64]): seq[string] =
  if breaks.len < 2: return @["0"]
  let numBins = breaks.len - 1
  result = newSeq[string](numBins)
  for i in 0..<numBins:
    result[i] = &"{breaks[i]:.1f}-{breaks[i+1]:.1f}"

proc generateIndexLabels(numBins: int): seq[string] =
  result = newSeq[string](numBins)
  for i in 0..<numBins:
    result[i] = $i

proc generateAbbrev(name: string; existing: var seq[string]): string =
  # Try first letter uppercase
  result = name[0..0].toUpperAscii()
  if result notin existing:
    existing.add(result)
    return

  # Try first two letters
  if name.len > 1:
    result = name[0..1].toUpperAscii()
    if result notin existing:
      existing.add(result)
      return

  # Increment through alphabet
  for i in 0..25:
    result = $chr(ord('A') + i)
    if result notin existing:
      existing.add(result)
      return

  # Fallback to numbered
  var n = 1
  while true:
    result = "V" & $n
    if result notin existing:
      existing.add(result)
      return
    n += 1

# ============ JSON Export Functions ============

proc analyzeColumnsJson*(inputJson: cstring): cstring {.exportc, cdecl.} =
  ## Analyze CSV data columns
  ##
  ## Input: { "columns": ["A", "B"], "data": [["1", "2"], ["3", "4"]] }
  ## Output: { "columns": [{ "name": "A", "isNumeric": true, ... }], "success": true }
  try:
    let input = parseJson($inputJson)
    let columns = input["columns"]
    let data = input["data"]

    var resultColumns = newJArray()

    for colIdx in 0..<columns.len:
      let colName = columns[colIdx].getStr()

      # Extract column data
      var colData: seq[string]
      for row in data:
        if colIdx < row.len:
          colData.add(row[colIdx].getStr())
        else:
          colData.add("")

      let analysis = analyzeColumnData(colData)

      var colJson = newJObject()
      colJson["name"] = %colName
      colJson["index"] = %colIdx
      colJson["isNumeric"] = %analysis.isNumeric
      colJson["uniqueCount"] = %analysis.uniqueCount
      colJson["totalCount"] = %analysis.totalCount
      colJson["missingCount"] = %analysis.missingCount
      colJson["minVal"] = if analysis.isNumeric: %analysis.minVal else: newJNull()
      colJson["maxVal"] = if analysis.isNumeric: %analysis.maxVal else: newJNull()
      colJson["needsBinning"] = %analysis.needsBinning
      colJson["suggestedStrategy"] = %($analysis.suggestedStrategy)

      var topVals = newJArray()
      for (val, count) in analysis.topValues[0..min(9, analysis.topValues.len - 1)]:
        topVals.add(%*{"value": val, "count": count})
      colJson["topValues"] = topVals

      resultColumns.add(colJson)

    let resultNode = %*{"columns": resultColumns, "success": true}
    return cstring($resultNode)

  except CatchableError as e:
    let errResult = %*{"success": false, "error": e.msg}
    return cstring($errResult)


proc suggestBinConfigsJson*(inputJson: cstring; threshold: cint = 10): cstring {.exportc, cdecl.} =
  ## Suggest binning configurations based on column analysis
  ##
  ## Input: { "columns": [{ "name": "A", "isNumeric": true, "uniqueCount": 100, ... }] }
  ## Output: { "configs": { "A": { "strategy": "equalWidth", "numBins": 5, ... } }, "success": true }
  try:
    let input = parseJson($inputJson)
    let columns = input["columns"]

    var configs = newJObject()

    for col in columns:
      let name = col["name"].getStr()
      let uniqueCount = col["uniqueCount"].getInt()
      let isNumeric = col["isNumeric"].getBool()

      var config = newJObject()

      if uniqueCount > threshold:
        if isNumeric:
          config["strategy"] = %"equalWidth"
          config["numBins"] = %5
          config["labelStyle"] = %"range"
        else:
          config["strategy"] = %"topN"
          config["topN"] = %5
          config["labelStyle"] = %"index"
      else:
        config["strategy"] = %"none"
        config["numBins"] = %uniqueCount

      config["otherLabel"] = %"Other"
      config["missingHandling"] = %"separateBin"
      config["missingLabel"] = %"Missing"

      configs[name] = config

    let resultNode = %*{"configs": configs, "success": true}
    return cstring($resultNode)

  except CatchableError as e:
    let errResult = %*{"success": false, "error": e.msg}
    return cstring($errResult)


proc applyBinningJson*(dataJson: cstring; configsJson: cstring): cstring {.exportc, cdecl.} =
  ## Apply binning and aggregate to frequency table
  ##
  ## Input data: { "columns": ["A", "B"], "data": [["1", "2"], ...] }
  ## Input configs: { "configs": { "A": { "strategy": "equalWidth", ... } } }
  ## Output: { "variables": [...], "data": [...], "counts": [...], "success": true }
  try:
    let dataInput = parseJson($dataJson)
    let configsInput = parseJson($configsJson)

    let columns = dataInput["columns"]
    let data = dataInput["data"]
    let configs = configsInput["configs"]

    # First pass: analyze each column
    var analyses: seq[ColumnAnalysis]
    for colIdx in 0..<columns.len:
      let colName = columns[colIdx].getStr()
      var colData: seq[string]
      for row in data:
        if colIdx < row.len:
          colData.add(row[colIdx].getStr())
        else:
          colData.add("")
      var analysis = analyzeColumnData(colData)
      analysis.name = colName
      analysis.index = colIdx
      analyses.add(analysis)

    # Build variables and value mappers
    var variables = newJArray()
    var usedAbbrevs: seq[string]
    var valueMappers: seq[proc(val: string): string]
    var binLabels: seq[seq[string]]

    for colIdx, analysis in analyses:
      let colName = analysis.name
      let abbrev = generateAbbrev(colName, usedAbbrevs)

      var config: JsonNode
      if configs.hasKey(colName):
        config = configs[colName]
      else:
        config = %*{"strategy": "none"}

      let strategy = config.getOrDefault("strategy").getStr("none")
      let numBins = config.getOrDefault("numBins").getInt(5)
      let topN = config.getOrDefault("topN").getInt(5)
      let labelStyle = config.getOrDefault("labelStyle").getStr("range")
      let otherLabel = config.getOrDefault("otherLabel").getStr("Other")
      let missingLabel = config.getOrDefault("missingLabel").getStr("Missing")
      let missingHandling = config.getOrDefault("missingHandling").getStr("separateBin")

      var labels: seq[string]
      var mapper: proc(val: string): string

      if strategy == "none":
        # No binning - use original values
        for (v, _) in analysis.topValues:
          labels.add(v)
        let valueSet = labels.toHashSet()
        mapper = proc(val: string): string =
          if isMissingValue(val):
            if missingHandling == "separateBin": missingLabel else: ""
          elif val in valueSet: val
          else: otherLabel

      elif strategy == "equalWidth" and analysis.isNumeric:
        let breaks = computeEqualWidthBreaks(analysis.minVal, analysis.maxVal, numBins)
        labels = if labelStyle == "index": generateIndexLabels(numBins)
                 else: generateRangeLabels(breaks)

        # Capture breaks for closure
        let capturedBreaks = breaks
        let capturedLabels = labels
        mapper = proc(val: string): string =
          if isMissingValue(val):
            if missingHandling == "separateBin": missingLabel else: ""
          else:
            let (ok, num) = tryParseFloat(val)
            if ok:
              let binIdx = assignToBin(num, capturedBreaks)
              if binIdx < capturedLabels.len: capturedLabels[binIdx]
              else: otherLabel
            else:
              otherLabel

      elif strategy == "topN":
        let n = min(topN, analysis.topValues.len)
        for i in 0..<n:
          labels.add(analysis.topValues[i][0])
        labels.add(otherLabel)
        let topSet = labels[0..<n].toHashSet()
        mapper = proc(val: string): string =
          if isMissingValue(val):
            if missingHandling == "separateBin": missingLabel else: ""
          elif val in topSet: val
          else: otherLabel

      else:
        # Fallback - treat as categorical
        for (v, _) in analysis.topValues:
          labels.add(v)
        let valueSet = labels.toHashSet()
        mapper = proc(val: string): string =
          if isMissingValue(val):
            if missingHandling == "separateBin": missingLabel else: ""
          elif val in valueSet: val
          else: otherLabel

      # Add missing label if needed
      if missingHandling == "separateBin" and analysis.missingCount > 0:
        labels.add(missingLabel)

      binLabels.add(labels)
      valueMappers.add(mapper)

      var varJson = newJObject()
      varJson["name"] = %colName
      varJson["abbrev"] = %abbrev
      varJson["cardinality"] = %labels.len
      varJson["values"] = %labels
      varJson["isDependent"] = %false
      variables.add(varJson)

    # Apply binning and aggregate
    var freqMap = initCountTable[string]()
    for row in data:
      var binnedRow: seq[string]
      var skipRow = false
      for colIdx in 0..<columns.len:
        let val = if colIdx < row.len: row[colIdx].getStr() else: ""
        let binnedVal = valueMappers[colIdx](val)
        if binnedVal == "":
          skipRow = true
          break
        binnedRow.add(binnedVal)

      if not skipRow:
        freqMap.inc(binnedRow.join("|"))

    # Build output
    var outData = newJArray()
    var outCounts = newJArray()
    for key, count in freqMap.pairs:
      var rowArr = newJArray()
      for val in key.split("|"):
        rowArr.add(%val)
      outData.add(rowArr)
      outCounts.add(%count)

    let resultNode = %*{
      "name": "binned_data",
      "variables": variables,
      "data": outData,
      "counts": outCounts,
      "success": true
    }
    return cstring($resultNode)

  except CatchableError as e:
    let errResult = %*{"success": false, "error": e.msg}
    return cstring($errResult)


when isMainModule:
  # Test harness
  let testData = """{
    "columns": ["Age", "Income", "Category"],
    "data": [
      ["25", "50000", "A"],
      ["30", "60000", "B"],
      ["35", "70000", "A"],
      ["40", "80000", "C"],
      ["45", "90000", "A"]
    ]
  }"""

  echo "Analyzing columns..."
  let analysisResult = analyzeColumnsJson(cstring(testData))
  echo analysisResult

  echo "\nSuggesting configs..."
  let suggestResult = suggestBinConfigsJson(analysisResult, 3)
  echo suggestResult

  echo "\nApplying binning..."
  let configs = """{
    "configs": {
      "Age": {"strategy": "equalWidth", "numBins": 3, "labelStyle": "range"},
      "Income": {"strategy": "equalWidth", "numBins": 3, "labelStyle": "range"},
      "Category": {"strategy": "none"}
    }
  }"""
  let binResult = applyBinningJson(cstring(testData), cstring(configs))
  echo binResult
