## JSON parser for OCCAM data format
## Converts JSON input to VariableList and Table

{.push raises: [].}

import std/[strutils, json]
import std/tables as stdtables
import ../core/types
import ../core/variable
import ../core/key
import ../core/table as coretable

type
  VariableSpec* = object
    ## Variable specification from JSON
    name*: string
    abbrev*: string
    cardinality*: int
    values*: seq[string]
    isDependent*: bool

  DataSpec* = object
    ## Complete data specification from JSON
    name*: string
    sampleSize*: float64  # Optional, some formats include it
    variables*: seq[VariableSpec]
    data*: seq[seq[string]]
    counts*: seq[float64]

proc parseDataSpec*(jsonStr: string): DataSpec {.raises: [IOError, OSError, JsonParsingError, ValueError].} =
  ## Parse JSON string to DataSpec
  ## Handles both string and integer data values
  let js = parseJson(jsonStr)

  result.name = js{"name"}.getStr("")
  result.sampleSize = js{"sampleSize"}.getFloat(0.0)

  # Parse variables
  for v in js["variables"]:
    var vspec: VariableSpec
    vspec.name = v["name"].getStr()
    vspec.abbrev = v["abbrev"].getStr()
    vspec.cardinality = v["cardinality"].getInt()
    vspec.isDependent = v{"isDependent"}.getBool(false)
    if v.hasKey("values"):
      for val in v["values"]:
        vspec.values.add(val.getStr())
    else:
      # Generate default values if not provided
      for i in 0..<vspec.cardinality:
        vspec.values.add($i)
    result.variables.add(vspec)

  # Parse data - handle both string and integer values
  # For large datasets, we don't store raw data - we aggregate directly
  let dataNode = js["data"]
  let dataLen = dataNode.len

  # For very large datasets (>100K rows), warn user
  if dataLen > 100_000:
    stderr.writeLine "Note: Large dataset (" & $dataLen & " rows) - aggregating to frequency table..."

  for row in dataNode:
    var rowData: seq[string]
    for item in row:
      case item.kind
      of JString:
        rowData.add(item.getStr())
      of JInt:
        rowData.add($item.getInt())
      of JFloat:
        rowData.add($item.getFloat().int)
      else:
        rowData.add($item)
    result.data.add(rowData)

  # Parse counts if present
  if js.hasKey("counts"):
    for c in js["counts"]:
      result.counts.add(c.getFloat())


proc loadDataSpec*(filename: string): DataSpec {.raises: [IOError, OSError, JsonParsingError, ValueError].} =
  ## Load DataSpec from file
  let content = readFile(filename)
  parseDataSpec(content)


proc loadAndAggregate*(filename: string): (DataSpec, stdtables.Table[seq[int], float64]) {.raises: [IOError, OSError, JsonParsingError, ValueError].} =
  ## Load large dataset and aggregate directly to frequency counts
  ## Much more efficient for datasets with millions of rows
  ## Returns (spec with empty data, frequency map)
  ##
  ## Handles two formats:
  ## 1. Raw format with 1-indexed integers (R17 style)
  ## 2. Pre-aggregated format with 0-indexed integers and counts array
  let content = readFile(filename)
  let js = parseJson(content)

  var spec: DataSpec
  spec.name = js{"name"}.getStr("")
  spec.sampleSize = js{"sampleSize"}.getFloat(0.0)

  # Check if this is already aggregated
  let isAggregated = js{"format"}.getStr("") == "aggregated"

  # Parse variables
  for v in js["variables"]:
    var vspec: VariableSpec
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
    spec.variables.add(vspec)

  # Aggregate data directly to frequency map
  var freqMap = stdtables.initTable[seq[int], float64]()
  let dataNode = js["data"]

  # Check for counts array (pre-aggregated format)
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
        # Only convert from 1-indexed if not pre-aggregated
        if not isAggregated and val > 0:
          val -= 1  # Convert 1-indexed to 0-indexed
      of JString:
        val = parseInt(item.getStr())
        if not isAggregated and val > 0:
          val -= 1  # Assume 1-indexed if > 0
      else:
        val = 0
      # Clamp to valid range
      if colIdx < spec.variables.len:
        let card = spec.variables[colIdx].cardinality
        if val < 0 or val >= card:
          val = val mod card
          if val < 0: val += card
      indices.add(val)
      colIdx += 1

    # Use count from counts array if available, otherwise 1.0
    let count = if hasCounts and rowIdx < countsNode.len:
      countsNode[rowIdx].getFloat()
    else:
      1.0
    freqMap.mgetOrPut(indices, 0.0) += count
    rowIdx += 1

  (spec, freqMap)


proc toTableFromFreqMap*(spec: DataSpec; freqMap: stdtables.Table[seq[int], float64]; varList: VariableList): coretable.ContingencyTable =
  ## Convert frequency map to Table
  result = coretable.initContingencyTable(varList.keySize, freqMap.len)

  for indices, count in freqMap:
    var k = initKey(varList.keySize)
    for varIdx, valIdx in indices:
      k.setValue(varList, VariableIndex(varIdx), valIdx)
    result.add(k, count)

  result.sort()


proc sampleSize*(spec: DataSpec): float64 =
  ## Get total sample size (sum of all counts)
  result = 0.0
  for c in spec.counts:
    result += c


proc toVariableList*(spec: DataSpec): VariableList =
  ## Convert DataSpec to VariableList
  result = initVariableList(spec.variables.len)

  for vspec in spec.variables:
    var v = initVariable(
      vspec.name,
      vspec.abbrev,
      Cardinality(vspec.cardinality),
      vspec.isDependent
    )
    # Store value map
    for i, val in vspec.values:
      if i < v.valueMap.len:
        v.valueMap[i] = val

    discard result.add(v)


proc toTable*(spec: DataSpec; varList: VariableList): coretable.ContingencyTable {.raises: [].} =
  ## Convert DataSpec data to Table
  ## Returns table with counts (not normalized)

  # Build value-to-index maps for each variable
  var valueMaps: seq[stdtables.Table[string, int]]
  for i, vspec in spec.variables:
    var vmap = stdtables.initTable[string, int]()
    for idx, val in vspec.values:
      vmap[val] = idx
    valueMaps.add(vmap)

  result = coretable.initContingencyTable(varList.keySize, spec.data.len)

  # Process each data row
  for rowIdx, row in spec.data:
    var k = initKey(varList.keySize)

    # Set value for each variable
    for varIdx, valStr in row:
      var valIndex = -1

      # First try the value map
      if varIdx < valueMaps.len and valStr in valueMaps[varIdx]:
        try:
          valIndex = valueMaps[varIdx][valStr]
        except KeyError:
          discard  # Fall through to integer parsing
      if valIndex < 0:
        # Try parsing as integer (1-indexed, convert to 0-indexed)
        try:
          let intVal = parseInt(valStr)
          # Values in R17 format are 1-indexed, convert to 0-indexed
          valIndex = intVal - 1
          # Ensure it's in valid range
          if varIdx < spec.variables.len:
            let card = spec.variables[varIdx].cardinality
            if valIndex < 0 or valIndex >= card:
              valIndex = valIndex mod card
              if valIndex < 0:
                valIndex += card
        except ValueError:
          # Try as-is (0-indexed)
          try:
            valIndex = parseInt(valStr)
          except ValueError:
            valIndex = 0  # Default fallback

      if valIndex >= 0:
        k.setValue(varList, VariableIndex(varIdx), valIndex)

    # Add tuple with count
    let count = if rowIdx < spec.counts.len: spec.counts[rowIdx] else: 1.0
    result.add(k, count)

  # Sort and merge duplicates
  result.sort()
  result.sumInto()

