## Tests for preprocess command functionality
##
## Tests column selection, binning integration, and aggregation

import std/[unittest, json, os, tables, strutils, tempfiles]
import ../src/occam/io/parser
import ../src/occam/io/binning


# ============ Column Selection Functions (to be moved to cmd_preprocess) ============

proc parseColumnSpec(spec: string; numCols: int): seq[int] =
  ## Parse column specification string into indices
  if spec.strip() == "" or spec == "*":
    for i in 0..<numCols:
      result.add(i)
    return

  for part in spec.split(','):
    let p = part.strip()
    if '-' in p and not p.startsWith("-"):
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
      try:
        let idx = parseInt(p)
        if idx >= 0 and idx < numCols and idx notin result:
          result.add(idx)
      except ValueError:
        discard


proc parseColumnNames(spec: string; varNames: seq[string]): seq[int] =
  ## Parse column specification with names
  if spec.strip() == "" or spec == "*":
    for i in 0..<varNames.len:
      result.add(i)
    return

  var nameToIdx = initTable[string, int]()
  for i, name in varNames:
    nameToIdx[name.toLowerAscii()] = i

  for part in spec.split(','):
    let p = part.strip()
    if '-' in p and not p.startsWith("-"):
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
      try:
        let idx = parseInt(p)
        if idx >= 0 and idx < varNames.len and idx notin result:
          result.add(idx)
      except ValueError:
        let nameLower = p.toLowerAscii()
        if nameLower in nameToIdx:
          let idx = nameToIdx[nameLower]
          if idx notin result:
            result.add(idx)


# ============ Test Data Helpers ============

proc createTestJson(data: seq[seq[string]]; varNames: seq[string];
                    counts: seq[float64] = @[]): string =
  ## Create a test JSON string with given data
  var js = newJObject()
  js["name"] = %"test_data"

  var varsArr = newJArray()
  for i, name in varNames:
    var vj = newJObject()
    vj["name"] = %name
    vj["abbrev"] = %($chr(ord('A') + i))
    vj["cardinality"] = %0  # Will be computed
    vj["isDependent"] = %(i == varNames.len - 1)
    varsArr.add(vj)
  js["variables"] = varsArr

  var dataArr = newJArray()
  for row in data:
    var rowArr = newJArray()
    for val in row:
      rowArr.add(%val)
    dataArr.add(rowArr)
  js["data"] = dataArr

  if counts.len > 0:
    var countsArr = newJArray()
    for c in counts:
      countsArr.add(%c)
    js["counts"] = countsArr

  $js


proc createTestCsv(data: seq[seq[string]]; headers: seq[string] = @[]): string =
  ## Create a test CSV string
  var lines: seq[string]
  if headers.len > 0:
    lines.add(headers.join(","))
  for row in data:
    lines.add(row.join(","))
  lines.join("\n")


# ============ Column Selection Tests ============

suite "Column Selection":

  test "parseColumnSpec - all columns with empty string":
    # Arrange
    let numCols = 5

    # Act
    let result = parseColumnSpec("", numCols)

    # Assert
    check result == @[0, 1, 2, 3, 4]

  test "parseColumnSpec - all columns with asterisk":
    # Arrange
    let numCols = 3

    # Act
    let result = parseColumnSpec("*", numCols)

    # Assert
    check result == @[0, 1, 2]

  test "parseColumnSpec - comma-separated indices":
    # Arrange
    let numCols = 10

    # Act
    let result = parseColumnSpec("0,2,5,7", numCols)

    # Assert
    check result == @[0, 2, 5, 7]

  test "parseColumnSpec - range":
    # Arrange
    let numCols = 10

    # Act
    let result = parseColumnSpec("2-5", numCols)

    # Assert
    check result == @[2, 3, 4, 5]

  test "parseColumnSpec - mixed indices and ranges":
    # Arrange
    let numCols = 10

    # Act
    let result = parseColumnSpec("0,2-4,7", numCols)

    # Assert
    check result == @[0, 2, 3, 4, 7]

  test "parseColumnSpec - ignores out of range":
    # Arrange
    let numCols = 5

    # Act
    let result = parseColumnSpec("0,3,10,2", numCols)

    # Assert
    check result == @[0, 3, 2]

  test "parseColumnSpec - no duplicates":
    # Arrange
    let numCols = 5

    # Act
    let result = parseColumnSpec("0,1,0,2,1", numCols)

    # Assert
    check result == @[0, 1, 2]


suite "Column Selection by Name":

  test "parseColumnNames - by name":
    # Arrange
    let varNames = @["Age", "Income", "Gender", "Target"]

    # Act
    let result = parseColumnNames("Age,Gender,Target", varNames)

    # Assert
    check result == @[0, 2, 3]

  test "parseColumnNames - case insensitive":
    # Arrange
    let varNames = @["Age", "Income", "Gender"]

    # Act
    let result = parseColumnNames("age,INCOME", varNames)

    # Assert
    check result == @[0, 1]

  test "parseColumnNames - mixed names and indices":
    # Arrange
    let varNames = @["Age", "Income", "Gender", "Target"]

    # Act
    let result = parseColumnNames("0,Gender,3", varNames)

    # Assert
    check result == @[0, 2, 3]


# ============ Aggregation with Column Selection Tests ============

suite "Aggregation with Column Selection":

  test "aggregate selected columns only":
    # Arrange - 4 columns, select only first 2
    let data = @[
      @["A", "X", "1", "foo"],
      @["A", "Y", "2", "bar"],
      @["B", "X", "1", "baz"],
      @["A", "X", "3", "qux"],  # Same as row 0 for cols 0,1
    ]
    let selectedCols = @[0, 1]

    # Act - aggregate only columns 0 and 1
    var freqMap = initTable[seq[string], float64]()
    for row in data:
      var key: seq[string]
      for col in selectedCols:
        key.add(row[col])
      freqMap.mgetOrPut(key, 0.0) += 1.0

    # Assert
    check freqMap.len == 3  # A-X(2), A-Y(1), B-X(1)
    check freqMap[@["A", "X"]] == 2.0
    check freqMap[@["A", "Y"]] == 1.0
    check freqMap[@["B", "X"]] == 1.0

  test "aggregate all columns":
    # Arrange
    let data = @[
      @["A", "X"],
      @["A", "Y"],
      @["A", "X"],  # Duplicate
      @["B", "X"],
    ]

    # Act
    var freqMap = initTable[seq[string], float64]()
    for row in data:
      freqMap.mgetOrPut(row, 0.0) += 1.0

    # Assert
    check freqMap.len == 3
    check freqMap[@["A", "X"]] == 2.0


# ============ Binning Integration Tests ============

suite "Binning Integration":

  test "binning reduces cardinality":
    # Arrange - high cardinality numeric column
    let colData = @["1", "5", "10", "15", "20", "25", "30", "35", "40", "45"]

    # Act
    let analysis = analyzeColumn(colData)
    var binSpec = suggestBinStrategy(analysis, targetCardinality = 3)
    binSpec.labelStyle = blsIndex
    let binResult = binNumericColumn(colData, binSpec)

    # Assert
    check analysis.uniqueCount == 10
    check binResult.newCardinality == 3
    check binResult.newValues.len == 3

  test "categorical binning with top-N":
    # Arrange - many categories, some frequent
    let colData = @["A", "A", "A", "B", "B", "C", "D", "E", "F", "G"]
    let analysis = analyzeColumn(colData)

    # Act - keep top 2
    var binSpec: BinSpec
    binSpec.strategy = bsTopN
    binSpec.topN = 2
    binSpec.otherLabel = "Other"
    binSpec.missingHandling = mvhSeparateBin
    let binResult = binCategoricalColumn(colData, binSpec, analysis.frequencies)

    # Assert
    check binResult.newCardinality == 3  # A, B, Other
    check "A" in binResult.newValues
    check "B" in binResult.newValues
    check "Other" in binResult.newValues


# ============ End-to-End Preprocess Tests ============

suite "End-to-End Preprocessing":

  test "preprocess JSON with column selection":
    # Arrange - Create temp JSON file
    let data = @[
      @["1", "A", "X", "100"],
      @["1", "B", "Y", "200"],
      @["2", "A", "X", "100"],
      @["1", "A", "X", "150"],  # Duplicate for cols 0,1,2
    ]
    let jsonContent = createTestJson(data, @["V1", "V2", "V3", "V4"])

    let (tmpFile, tmpPath) = createTempFile("test_", ".json")
    tmpFile.write(jsonContent)
    tmpFile.close()

    defer: removeFile(tmpPath)

    # Act - Load and aggregate (simulated column selection for cols 0,1,2)
    let spec = loadDataSpec(tmpPath)
    check spec.data.len == 4

    # Aggregate only first 3 columns
    var freqMap = initTable[seq[string], float64]()
    for row in spec.data:
      let key = row[0..2]
      freqMap.mgetOrPut(key, 0.0) += 1.0

    # Assert
    check freqMap.len == 3  # 3 unique combinations
    check freqMap[@["1", "A", "X"]] == 2.0


when isMainModule:
  # Run all tests
  discard
