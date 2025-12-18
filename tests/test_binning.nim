## Tests for binning/discretization functionality

import std/unittest
import std/math
import std/algorithm
import std/sequtils
import ../src/occam/io/binning
import ../src/occam/io/parser

suite "Column Analysis":

  test "detect numeric column":
    # Arrange
    let data = @["1.5", "2.3", "4.0", "1.1", "3.5"]
    # Act
    let analysis = analyzeColumn(data)
    # Assert
    check analysis.isNumeric == true
    check analysis.uniqueCount == 5
    check analysis.totalCount == 5

  test "detect categorical column":
    # Arrange
    let data = @["Red", "Blue", "Red", "Green", "Blue"]
    # Act
    let analysis = analyzeColumn(data)
    # Assert
    check analysis.isNumeric == false
    check analysis.uniqueCount == 3

  test "detect integer column as numeric":
    # Arrange
    let data = @["1", "2", "3", "4", "5"]
    # Act
    let analysis = analyzeColumn(data)
    # Assert
    check analysis.isNumeric == true

  test "handle mixed numeric with missing":
    # Arrange - has NA and empty string
    let data = @["1.0", "2.0", "", "3.0", "NA"]
    # Act
    let analysis = analyzeColumn(data)
    # Assert
    check analysis.isNumeric == true  # Still numeric despite missing
    check analysis.missingCount == 2

  test "compute min/max for numeric":
    # Arrange
    let data = @["10", "5", "20", "15"]
    # Act
    let analysis = analyzeColumn(data)
    # Assert
    check analysis.minVal == 5.0
    check analysis.maxVal == 20.0

  test "compute frequency counts":
    # Arrange
    let data = @["A", "B", "A", "A", "C", "B"]
    # Act
    let analysis = analyzeColumn(data)
    # Assert - frequencies sorted by count descending
    check analysis.frequencies[0] == ("A", 3)
    check analysis.frequencies[1] == ("B", 2)
    check analysis.frequencies[2] == ("C", 1)

  test "identify missing values":
    # Arrange
    let data = @["value", "", "NA", "na", "N/A", "null", "NULL", ".", "-"]
    # Act
    let analysis = analyzeColumn(data)
    # Assert - all common missing value indicators should be detected
    check analysis.missingCount == 8  # Everything except "value"

  test "empty column":
    # Arrange
    let data: seq[string] = @[]
    # Act
    let analysis = analyzeColumn(data)
    # Assert
    check analysis.totalCount == 0
    check analysis.uniqueCount == 0

  test "single value column":
    # Arrange
    let data = @["Yes", "Yes", "Yes"]
    # Act
    let analysis = analyzeColumn(data)
    # Assert
    check analysis.uniqueCount == 1
    check analysis.frequencies[0] == ("Yes", 3)


suite "Missing Value Detection":

  test "empty string is missing":
    check isMissingValue("")

  test "NA variants are missing":
    check isMissingValue("NA")
    check isMissingValue("na")
    check isMissingValue("N/A")
    check isMissingValue("n/a")

  test "null variants are missing":
    check isMissingValue("null")
    check isMissingValue("NULL")
    check isMissingValue("Null")

  test "common placeholders are missing":
    check isMissingValue(".")
    check isMissingValue("-")
    check isMissingValue("?")

  test "actual values are not missing":
    check not isMissingValue("0")
    check not isMissingValue("value")
    check not isMissingValue("Yes")
    check not isMissingValue("123")


suite "Equal-Width Binning":

  test "compute breaks for 3 bins":
    # Arrange - range 0 to 30
    let values = @[0.0, 10.0, 20.0, 30.0]
    # Act
    let breaks = computeEqualWidthBreaks(values, 3)
    # Assert - should have 4 edges for 3 bins
    check breaks.len == 4
    check abs(breaks[0] - 0.0) < 0.001
    check abs(breaks[1] - 10.0) < 0.001
    check abs(breaks[2] - 20.0) < 0.001
    check abs(breaks[3] - 30.0) < 0.001

  test "compute breaks for 5 bins":
    # Arrange - range 0 to 100
    let values = @[0.0, 25.0, 50.0, 75.0, 100.0]
    # Act
    let breaks = computeEqualWidthBreaks(values, 5)
    # Assert - should have 6 edges for 5 bins
    check breaks.len == 6
    check abs(breaks[0] - 0.0) < 0.001
    check abs(breaks[5] - 100.0) < 0.001

  test "assign values to bins":
    # Arrange - 3 bins: [0-10), [10-20), [20-30]
    let breaks = @[0.0, 10.0, 20.0, 30.0]
    # Act & Assert
    check assignToBin(5.0, breaks) == 0
    check assignToBin(15.0, breaks) == 1
    check assignToBin(25.0, breaks) == 2

  test "assign edge values to bins":
    # Arrange - left-closed intervals [a,b)
    let breaks = @[0.0, 10.0, 20.0, 30.0]
    # Act & Assert
    check assignToBin(0.0, breaks) == 0   # Left edge -> first bin
    check assignToBin(10.0, breaks) == 1  # 10 goes to second bin
    check assignToBin(30.0, breaks) == 2  # Right edge -> last bin

  test "handle all-same-value edge case":
    # Arrange - all values are 5
    let values = @[5.0, 5.0, 5.0, 5.0]
    # Act
    let breaks = computeEqualWidthBreaks(values, 3)
    # Assert - should handle gracefully (single bin or small range)
    check breaks.len >= 2

  test "bin numeric column equal width":
    # Arrange
    let data = @["5", "15", "25", "8", "22", "12"]
    let spec = BinSpec(
      strategy: bsEqualWidth,
      numBins: 3,
      labelStyle: blsRange,
      missingHandling: mvhSeparateBin,
      missingLabel: "Missing",
      otherLabel: "Other"
    )
    # Act
    let result = binNumericColumn(data, spec)
    # Assert
    check result.newCardinality == 3
    check result.newValues.len == 3
    check result.mapping.len == 6


suite "Label Generation":

  test "generate range labels":
    # Arrange
    let breaks = @[0.0, 10.0, 20.0, 30.0]
    # Act
    let labels = generateRangeLabels(breaks)
    # Assert
    check labels.len == 3
    check labels[0] == "0-10"
    check labels[1] == "10-20"
    check labels[2] == "20-30"

  test "generate range labels with decimals":
    # Arrange
    let breaks = @[0.0, 33.33, 66.67, 100.0]
    # Act
    let labels = generateRangeLabels(breaks, precision = 1)
    # Assert
    check labels[0] == "0.0-33.3"
    check labels[1] == "33.3-66.7"
    check labels[2] == "66.7-100.0"

  test "generate semantic labels for 2 bins":
    # Act
    let labels = generateSemanticLabels(2)
    # Assert
    check labels == @["Low", "High"]

  test "generate semantic labels for 3 bins":
    # Act
    let labels = generateSemanticLabels(3)
    # Assert
    check labels == @["Low", "Medium", "High"]

  test "generate semantic labels for 5 bins":
    # Act
    let labels = generateSemanticLabels(5)
    # Assert
    check labels == @["VeryLow", "Low", "Medium", "High", "VeryHigh"]


suite "Equal-Frequency (Quantile) Binning":

  test "compute quantile breaks for uniform data":
    # Arrange - evenly spaced values
    let values = @[1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
    # Act
    let breaks = computeQuantileBreaks(values, 4)
    # Assert - should divide into quartiles
    check breaks.len == 5
    check breaks[0] == 1.0
    check breaks[4] == 8.0

  test "compute quantile breaks for skewed data":
    # Arrange - many small values, few large
    let values = @[1.0, 1.0, 1.0, 1.0, 10.0, 10.0, 100.0, 100.0]
    # Act
    let breaks = computeQuantileBreaks(values, 4)
    # Assert
    check breaks.len == 5
    check breaks[0] == 1.0
    check breaks[4] == 100.0

  test "bin with quantile strategy":
    # Arrange
    let data = @["1", "2", "3", "4", "5", "6", "7", "8"]
    let spec = BinSpec(
      strategy: bsEqualFrequency,
      numBins: 4,
      labelStyle: blsSemantic,
      missingHandling: mvhSeparateBin,
      missingLabel: "Missing",
      otherLabel: "Other"
    )
    # Act
    let result = binNumericColumn(data, spec)
    # Assert
    check result.newCardinality == 4
    check result.mapping.len == 8


suite "Custom Breakpoint Binning":

  test "apply custom breaks":
    # Arrange
    let data = @["18", "25", "45", "65", "80"]
    let spec = BinSpec(
      strategy: bsCustomBreaks,
      breakpoints: @[0.0, 18.0, 35.0, 55.0, 100.0],
      customLabels: @["Minor", "Young", "Middle", "Senior"],
      labelStyle: blsCustom,
      missingHandling: mvhSeparateBin,
      missingLabel: "Missing",
      otherLabel: "Other"
    )
    # Act
    let result = binNumericColumn(data, spec)
    # Assert
    check result.newCardinality == 4
    check result.newValues == @["Minor", "Young", "Middle", "Senior"]

  test "custom breaks assigns correctly":
    # Arrange
    let breaks = @[0.0, 18.0, 35.0, 55.0, 100.0]
    # Act & Assert
    check assignToBin(17.0, breaks) == 0   # Minor
    check assignToBin(18.0, breaks) == 1   # Young (18 is edge -> next bin)
    check assignToBin(25.0, breaks) == 1   # Young
    check assignToBin(45.0, breaks) == 2   # Middle
    check assignToBin(65.0, breaks) == 3   # Senior


suite "Categorical Binning - TopN":

  test "keep top 3 categories":
    # Arrange
    let data = @["A", "A", "A", "B", "B", "C", "D", "E"]
    let spec = BinSpec(
      strategy: bsTopN,
      topN: 3,
      otherLabel: "Other",
      missingHandling: mvhSeparateBin,
      missingLabel: "Missing"
    )
    let analysis = analyzeColumn(data)
    # Act
    let result = binCategoricalColumn(data, spec, analysis.frequencies)
    # Assert
    check result.newCardinality == 4  # A, B, C, Other
    check "Other" in result.newValues
    check "A" in result.newValues
    check "B" in result.newValues
    check "C" in result.newValues

  test "top N maps other values correctly":
    # Arrange
    let data = @["A", "B", "D"]  # D should map to Other
    let spec = BinSpec(
      strategy: bsTopN,
      topN: 2,
      otherLabel: "Other",
      missingHandling: mvhSeparateBin,
      missingLabel: "Missing"
    )
    let frequencies = @[("A", 5), ("B", 3), ("C", 2), ("D", 1)]
    # Act
    let result = binCategoricalColumn(data, spec, frequencies)
    # Assert
    check result.newValues == @["A", "B", "Other"]
    check result.mapping[2] == 2  # D -> Other (index 2)


suite "Categorical Binning - Frequency Threshold":

  test "frequency threshold with ratio":
    # Arrange - A=50%, B=25%, C=12.5%, D=12.5%
    let data = @["A", "A", "A", "A", "B", "B", "C", "D"]
    let spec = BinSpec(
      strategy: bsFrequencyThreshold,
      minFrequency: 0.2,  # 20% threshold
      minFrequencyIsRatio: true,
      otherLabel: "Rare",
      missingHandling: mvhSeparateBin,
      missingLabel: "Missing"
    )
    let analysis = analyzeColumn(data)
    # Act
    let result = binCategoricalColumn(data, spec, analysis.frequencies)
    # Assert - Only A (50%) and B (25%) meet 20% threshold
    check "A" in result.newValues
    check "B" in result.newValues
    check "Rare" in result.newValues
    check result.newCardinality == 3

  test "frequency threshold with count":
    # Arrange
    let data = @["A", "A", "A", "B", "B", "C"]
    let spec = BinSpec(
      strategy: bsFrequencyThreshold,
      minFrequency: 2.0,  # Must appear at least 2 times
      minFrequencyIsRatio: false,
      otherLabel: "Other",
      missingHandling: mvhSeparateBin,
      missingLabel: "Missing"
    )
    let analysis = analyzeColumn(data)
    # Act
    let result = binCategoricalColumn(data, spec, analysis.frequencies)
    # Assert - A (3) and B (2) meet threshold, C (1) doesn't
    check "A" in result.newValues
    check "B" in result.newValues
    check "Other" in result.newValues


suite "Missing Value Handling":

  test "separate bin for missing values":
    # Arrange
    let data = @["1", "2", "NA", "3", ""]
    let spec = BinSpec(
      strategy: bsEqualWidth,
      numBins: 3,
      labelStyle: blsRange,
      missingHandling: mvhSeparateBin,
      missingLabel: "Missing",
      otherLabel: "Other"
    )
    # Act
    let result = binNumericColumn(data, spec)
    # Assert
    check "Missing" in result.newValues
    check result.mapping[2] == result.newValues.find("Missing")  # NA
    check result.mapping[4] == result.newValues.find("Missing")  # empty

  test "exclude rows with missing":
    # Arrange
    let data = @["1", "2", "NA", "3"]
    let spec = BinSpec(
      strategy: bsEqualWidth,
      numBins: 3,
      labelStyle: blsRange,
      missingHandling: mvhExclude,
      missingLabel: "Missing",
      otherLabel: "Other"
    )
    # Act
    let result = binNumericColumn(data, spec)
    # Assert
    check result.mapping[2] == -1  # NA marked for exclusion
    check "Missing" notin result.newValues

  test "categorical missing values separate bin":
    # Arrange
    let data = @["A", "NA", "B", ""]
    let spec = BinSpec(
      strategy: bsTopN,
      topN: 5,
      missingHandling: mvhSeparateBin,
      missingLabel: "Unknown",
      otherLabel: "Other"
    )
    let frequencies = @[("A", 5), ("B", 3)]
    # Act
    let result = binCategoricalColumn(data, spec, frequencies)
    # Assert
    check "Unknown" in result.newValues


suite "Edge Cases":

  test "all same value - numeric":
    # Arrange
    let data = @["5", "5", "5", "5"]
    let spec = BinSpec(
      strategy: bsEqualWidth,
      numBins: 3,
      labelStyle: blsRange,
      missingHandling: mvhSeparateBin,
      missingLabel: "Missing",
      otherLabel: "Other"
    )
    # Act
    let result = binNumericColumn(data, spec)
    # Assert - should handle gracefully
    check result.newCardinality >= 1
    check result.mapping.len == 4

  test "single unique value categorical":
    # Arrange
    let data = @["Yes", "Yes", "Yes"]
    let spec = BinSpec(strategy: bsTopN, topN: 3, otherLabel: "Other",
                       missingHandling: mvhSeparateBin, missingLabel: "Missing")
    let frequencies = @[("Yes", 3)]
    # Act
    let result = binCategoricalColumn(data, spec, frequencies)
    # Assert
    check result.newCardinality == 1
    check result.newValues == @["Yes"]

  test "more bins requested than unique values":
    # Arrange
    let data = @["1", "2", "3"]
    let spec = BinSpec(
      strategy: bsEqualWidth,
      numBins: 10,
      labelStyle: blsRange,
      missingHandling: mvhSeparateBin,
      missingLabel: "Missing",
      otherLabel: "Other"
    )
    # Act
    let result = binNumericColumn(data, spec)
    # Assert - should create bins even if sparse
    check result.mapping.len == 3


suite "DataSpec Integration":

  test "extract column from DataSpec":
    # Arrange
    let jsonStr = """
    {
      "name": "Test",
      "variables": [
        {"name": "Age", "abbrev": "A", "cardinality": 3, "values": ["20", "30", "40"]},
        {"name": "Gender", "abbrev": "G", "cardinality": 2, "values": ["M", "F"]}
      ],
      "data": [["20", "M"], ["30", "F"], ["40", "M"]],
      "counts": [10, 20, 15]
    }
    """
    let spec = parseDataSpec(jsonStr)
    # Act
    let ageCol = extractColumn(spec, 0)
    let genderCol = extractColumn(spec, 1)
    # Assert
    check ageCol == @["20", "30", "40"]
    check genderCol == @["M", "F", "M"]

  test "apply binning to single column":
    # Arrange
    let jsonStr = """
    {
      "name": "Test",
      "variables": [
        {"name": "Age", "abbrev": "A", "cardinality": 5, "values": ["10", "20", "30", "40", "50"]},
        {"name": "Gender", "abbrev": "G", "cardinality": 2, "values": ["M", "F"]}
      ],
      "data": [["10", "M"], ["20", "F"], ["30", "M"], ["40", "F"], ["50", "M"]],
      "counts": [10, 20, 15, 25, 30]
    }
    """
    let spec = parseDataSpec(jsonStr)
    let binSpec = BinSpec(
      strategy: bsEqualWidth,
      numBins: 2,
      labelStyle: blsRange,
      missingHandling: mvhSeparateBin,
      missingLabel: "Missing",
      otherLabel: "Other"
    )
    # Act
    let binnedSpec = applyBinning(spec, @[(0, binSpec)])
    # Assert
    check binnedSpec.variables[0].cardinality == 2
    check binnedSpec.variables[1].cardinality == 2  # Unchanged

  test "apply binning by variable name":
    # Arrange
    let jsonStr = """
    {
      "name": "Test",
      "variables": [
        {"name": "Age", "abbrev": "A", "cardinality": 5, "values": ["10", "20", "30", "40", "50"]},
        {"name": "Income", "abbrev": "I", "cardinality": 5, "values": ["1000", "2000", "3000", "4000", "5000"]}
      ],
      "data": [["10", "1000"], ["20", "2000"], ["30", "3000"], ["40", "4000"], ["50", "5000"]],
      "counts": [10, 20, 15, 25, 30]
    }
    """
    let spec = parseDataSpec(jsonStr)
    let binSpec = BinSpec(
      strategy: bsEqualWidth,
      numBins: 2,
      labelStyle: blsRange,
      missingHandling: mvhSeparateBin,
      missingLabel: "Missing",
      otherLabel: "Other"
    )
    # Act
    let binnedSpec = applyBinningByName(spec, @[("Age", binSpec)])
    # Assert
    check binnedSpec.variables[0].cardinality == 2
    check binnedSpec.variables[1].cardinality == 5  # Unchanged

  test "combine rows with same binned values":
    # Arrange
    let jsonStr = """
    {
      "name": "Test",
      "variables": [
        {"name": "Score", "abbrev": "S", "cardinality": 4, "values": ["25", "35", "75", "85"]}
      ],
      "data": [["25"], ["35"], ["75"], ["85"]],
      "counts": [10, 20, 15, 25]
    }
    """
    let spec = parseDataSpec(jsonStr)
    let binSpec = BinSpec(
      strategy: bsCustomBreaks,
      breakpoints: @[0.0, 50.0, 100.0],
      labelStyle: blsRange,
      missingHandling: mvhSeparateBin,
      missingLabel: "Missing",
      otherLabel: "Other"
    )
    # Act
    let binnedSpec = applyBinning(spec, @[(0, binSpec)])
    # Assert - should combine 25+35 and 75+85
    check binnedSpec.data.len == 2  # Two bins
    # Counts should be combined: 10+20=30 for first bin, 15+25=40 for second
    check binnedSpec.counts.len == 2
    let totalCount = binnedSpec.counts[0] + binnedSpec.counts[1]
    check totalCount == 70.0

  test "preserve counts during binning":
    # Arrange
    let jsonStr = """
    {
      "name": "Test",
      "variables": [
        {"name": "X", "abbrev": "X", "cardinality": 2, "values": ["A", "B"]}
      ],
      "data": [["A"], ["B"]],
      "counts": [100, 200]
    }
    """
    let spec = parseDataSpec(jsonStr)
    let binSpec = BinSpec(strategy: bsNone, missingHandling: mvhSeparateBin,
                          missingLabel: "Missing", otherLabel: "Other")
    # Act
    let binnedSpec = applyBinning(spec, @[(0, binSpec)])
    # Assert - should preserve original counts
    let totalBefore = spec.counts[0] + spec.counts[1]
    let totalAfter = binnedSpec.counts[0] + binnedSpec.counts[1]
    check totalAfter == totalBefore

  test "update values array correctly":
    # Arrange
    let jsonStr = """
    {
      "name": "Test",
      "variables": [
        {"name": "Score", "abbrev": "S", "cardinality": 3, "values": ["10", "50", "90"]}
      ],
      "data": [["10"], ["50"], ["90"]],
      "counts": [1, 1, 1]
    }
    """
    let spec = parseDataSpec(jsonStr)
    let binSpec = BinSpec(
      strategy: bsEqualWidth,
      numBins: 3,
      labelStyle: blsSemantic,
      missingHandling: mvhSeparateBin,
      missingLabel: "Missing",
      otherLabel: "Other"
    )
    # Act
    let binnedSpec = applyBinning(spec, @[(0, binSpec)])
    # Assert
    check binnedSpec.variables[0].values == @["Low", "Medium", "High"]

  test "auto-bin high cardinality columns":
    # Arrange - create data with high cardinality
    let jsonStr = """
    {
      "name": "Test",
      "variables": [
        {"name": "HighCard", "abbrev": "H", "cardinality": 20, "values": []},
        {"name": "LowCard", "abbrev": "L", "cardinality": 2, "values": ["A", "B"]}
      ],
      "data": [["1", "A"], ["2", "B"], ["3", "A"], ["4", "B"], ["5", "A"],
               ["6", "B"], ["7", "A"], ["8", "B"], ["9", "A"], ["10", "B"],
               ["11", "A"], ["12", "B"], ["13", "A"], ["14", "B"], ["15", "A"]],
      "counts": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
    }
    """
    let spec = parseDataSpec(jsonStr)
    # Act
    let binnedSpec = autoBinDataSpec(spec, targetCardinality = 5, threshold = 10)
    # Assert - high cardinality column should be binned, low cardinality preserved
    check binnedSpec.variables[0].cardinality <= 6  # ~5 bins + possible missing
    check binnedSpec.variables[1].cardinality == 2  # Unchanged
