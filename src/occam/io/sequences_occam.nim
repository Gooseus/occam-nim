## OCCAM adapter for sequence datasets
## Converts SequenceDataset to OCCAM's DataSpec format

{.push raises: [].}

import std/[algorithm, tables, json]
import ./sequences
import ./parser
import ../core/variable

proc computeValueLabels(col: ColumnDef; values: CountTable[int]): seq[string] =
  ## Generate value labels for a column based on observed values
  ## Sorted by value
  var sortedVals: seq[int] = @[]
  for val in values.keys:
    sortedVals.add(val)
  sortedVals.sort()

  result = @[]
  for val in sortedVals:
    case col.kind
    of ckResidue:
      result.add($val)
    of ckCollatzDist:
      result.add("k" & $val)  # k0, k1, k2, ...
    of ckDigitSum:
      result.add("d" & $val)  # d0, d1, d2, ...
    of ckPrimeFactor:
      result.add("f" & $val)  # f0, f1, f2, ...
    of ckCustom:
      result.add("c" & $val)


proc toDataSpec*(ds: SequenceDataset): DataSpec =
  ## Convert a SequenceDataset to OCCAM's DataSpec format
  result.name = ds.name
  result.variables = @[]
  result.data = @[]
  result.counts = @[]

  # Collect all observed values for each column
  var ivValueSets = newSeq[CountTable[int]](ds.columns.len)
  for i in 0..<ds.columns.len:
    ivValueSets[i] = initCountTable[int]()
  var dvValueSet = initCountTable[int]()

  for row in ds.rows:
    for i, val in row.ivValues:
      ivValueSets[i].inc(val)
    dvValueSet.inc(row.dvValue)

  # Create value-to-index mappings (sorted by value)
  var ivValueMaps = newSeq[Table[int, int]](ds.columns.len)
  for i in 0..<ds.columns.len:
    ivValueMaps[i] = initTable[int, int]()
    var sortedVals: seq[int] = @[]
    for val in ivValueSets[i].keys:
      sortedVals.add(val)
    sortedVals.sort()
    for idx, val in sortedVals:
      ivValueMaps[i][val] = idx

  var dvValueMap = initTable[int, int]()
  var dvSortedVals: seq[int] = @[]
  for val in dvValueSet.keys:
    dvSortedVals.add(val)
  dvSortedVals.sort()
  for idx, val in dvSortedVals:
    dvValueMap[val] = idx

  # Create variable specifications for IVs
  for i, col in ds.columns:
    let valueLabels = computeValueLabels(col, ivValueSets[i])
    let vspec = VariableSpec(
      name: col.name,
      abbrev: col.abbrev,
      cardinality: valueLabels.len,
      values: valueLabels,
      isDependent: false
    )
    result.variables.add(vspec)

  # Create variable specification for DV
  let dvValueLabels = computeValueLabels(ds.targetColumn, dvValueSet)
  let dvSpec = VariableSpec(
    name: ds.targetColumn.name,
    abbrev: "Z",  # Always use Z for DV
    cardinality: dvValueLabels.len,
    values: dvValueLabels,
    isDependent: true
  )
  result.variables.add(dvSpec)

  # Convert data rows to string labels and aggregate counts
  var rowCounts = initTable[seq[string], float64]()

  for row in ds.rows:
    var rowLabels: seq[string] = @[]

    # IV values
    for i, val in row.ivValues:
      try:
        let idx = ivValueMaps[i][val]
        let labels = computeValueLabels(ds.columns[i], ivValueSets[i])
        rowLabels.add(labels[idx])
      except KeyError:
        rowLabels.add($val)  # Fallback to string representation

    # DV value
    try:
      let dvIdx = dvValueMap[row.dvValue]
      rowLabels.add(dvValueLabels[dvIdx])
    except KeyError:
      rowLabels.add($row.dvValue)  # Fallback

    # Aggregate counts
    if rowLabels in rowCounts:
      try:
        rowCounts[rowLabels] += 1.0
      except KeyError:
        rowCounts[rowLabels] = 1.0
    else:
      rowCounts[rowLabels] = 1.0

  # Convert aggregated rows to DataSpec format
  for rowLabels, count in rowCounts:
    result.data.add(rowLabels)
    result.counts.add(count)


proc toOccamJSON*(ds: SequenceDataset): string =
  ## Convert dataset to OCCAM JSON format
  let spec = ds.toDataSpec()

  var obj = newJObject()
  obj["name"] = %spec.name

  var varsArray = newJArray()
  for v in spec.variables:
    var vObj = newJObject()
    vObj["name"] = %v.name
    vObj["abbrev"] = %v.abbrev
    vObj["cardinality"] = %v.cardinality
    vObj["values"] = %v.values
    vObj["isDependent"] = %v.isDependent
    varsArray.add(vObj)
  obj["variables"] = varsArray

  var dataArray = newJArray()
  for row in spec.data:
    dataArray.add(%row)
  obj["data"] = dataArray

  obj["counts"] = %spec.counts

  result = $obj


proc toVariableList*(ds: SequenceDataset): VariableList =
  ## Convert dataset column definitions to VariableList
  ## Uses observed cardinalities from the dataset
  let spec = ds.toDataSpec()
  result = spec.toVariableList()
