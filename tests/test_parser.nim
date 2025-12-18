## Test suite for JSON parser module
## Tests parsing of OCCAM data format

import std/os
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/table
import ../src/occam/io/parser

const testDataPath = currentSourcePath.parentDir / "fixtures" / "sample_data.json"

suite "JSON parsing":
  test "parse variable specs":
    let jsonStr = """
    {
      "name": "Test",
      "variables": [
        {"name": "A", "abbrev": "A", "cardinality": 3, "values": ["X", "Y", "Z"]},
        {"name": "B", "abbrev": "B", "cardinality": 2, "values": ["0", "1"]}
      ],
      "data": [],
      "counts": []
    }
    """
    let spec = parseDataSpec(jsonStr)
    check spec.name == "Test"
    check spec.variables.len == 2
    check spec.variables[0].name == "A"
    check spec.variables[0].cardinality == 3
    check spec.variables[1].name == "B"

  test "parse dependent variable":
    let jsonStr = """
    {
      "name": "Test",
      "variables": [
        {"name": "X", "abbrev": "X", "cardinality": 2, "values": ["a", "b"]},
        {"name": "Y", "abbrev": "Y", "cardinality": 2, "values": ["0", "1"], "isDependent": true}
      ],
      "data": [],
      "counts": []
    }
    """
    let spec = parseDataSpec(jsonStr)
    check spec.variables[0].isDependent == false
    check spec.variables[1].isDependent == true

  test "parse data rows":
    let jsonStr = """
    {
      "name": "Test",
      "variables": [
        {"name": "A", "abbrev": "A", "cardinality": 2, "values": ["X", "Y"]}
      ],
      "data": [["X"], ["Y"], ["X"]],
      "counts": [10, 20, 5]
    }
    """
    let spec = parseDataSpec(jsonStr)
    check spec.data.len == 3
    check spec.counts.len == 3
    check spec.counts[0] == 10.0
    check spec.counts[1] == 20.0

suite "Data conversion":
  test "convert spec to variable list":
    let jsonStr = """
    {
      "name": "Test",
      "variables": [
        {"name": "Age", "abbrev": "A", "cardinality": 3, "values": ["Y", "M", "O"]},
        {"name": "Income", "abbrev": "I", "cardinality": 2, "values": ["L", "H"]}
      ],
      "data": [],
      "counts": []
    }
    """
    let spec = parseDataSpec(jsonStr)
    let varList = spec.toVariableList()

    check varList.len == 2
    check varList[VariableIndex(0)].name == "Age"
    check varList[VariableIndex(0)].cardinality == Cardinality(3)
    check varList[VariableIndex(1)].name == "Income"

  test "convert spec to table":
    let jsonStr = """
    {
      "name": "Test",
      "variables": [
        {"name": "A", "abbrev": "A", "cardinality": 2, "values": ["X", "Y"]}
      ],
      "data": [["X"], ["Y"]],
      "counts": [30, 70]
    }
    """
    let spec = parseDataSpec(jsonStr)
    let varList = spec.toVariableList()
    let table = spec.toTable(varList)

    check table.len == 2
    check table.sum == 100.0

  test "convert multi-variable data to table":
    let jsonStr = """
    {
      "name": "Test",
      "variables": [
        {"name": "A", "abbrev": "A", "cardinality": 2, "values": ["0", "1"]},
        {"name": "B", "abbrev": "B", "cardinality": 2, "values": ["0", "1"]}
      ],
      "data": [["0", "0"], ["0", "1"], ["1", "0"], ["1", "1"]],
      "counts": [10, 20, 30, 40]
    }
    """
    let spec = parseDataSpec(jsonStr)
    let varList = spec.toVariableList()
    let table = spec.toTable(varList)

    check table.len == 4
    check table.sum == 100.0

suite "File parsing":
  test "load from file":
    let spec = loadDataSpec(testDataPath)
    check spec.name == "Sample Dataset"
    check spec.variables.len == 3

  test "full conversion pipeline":
    let spec = loadDataSpec(testDataPath)
    let varList = spec.toVariableList()
    let table = spec.toTable(varList)

    check varList.len == 3
    check varList.isDirected == true  # Has dependent variable
    check table.sum == 70.0  # 10+15+8+20+5+12

suite "Value mapping":
  test "value index lookup":
    let jsonStr = """
    {
      "name": "Test",
      "variables": [
        {"name": "Color", "abbrev": "C", "cardinality": 3, "values": ["Red", "Green", "Blue"]}
      ],
      "data": [["Red"], ["Green"], ["Blue"]],
      "counts": [1, 2, 3]
    }
    """
    let spec = parseDataSpec(jsonStr)
    let varList = spec.toVariableList()
    let table = spec.toTable(varList)

    # Check that values are correctly mapped to indices
    check table.len == 3

  test "variable stores value map":
    let jsonStr = """
    {
      "name": "Test",
      "variables": [
        {"name": "Size", "abbrev": "S", "cardinality": 3, "values": ["Small", "Medium", "Large"]}
      ],
      "data": [],
      "counts": []
    }
    """
    let spec = parseDataSpec(jsonStr)
    let varList = spec.toVariableList()

    check varList[VariableIndex(0)].valueMap[0] == "Small"
    check varList[VariableIndex(0)].valueMap[1] == "Medium"
    check varList[VariableIndex(0)].valueMap[2] == "Large"

suite "Sample size":
  test "get sample size from spec":
    let jsonStr = """
    {
      "name": "Test",
      "sampleSize": 100.0,
      "variables": [
        {"name": "A", "abbrev": "A", "cardinality": 2, "values": ["0", "1"]}
      ],
      "data": [["0"], ["1"]],
      "counts": [45, 55]
    }
    """
    let spec = parseDataSpec(jsonStr)
    check spec.sampleSize == 100.0

  test "compute sample size from counts":
    let jsonStr = """
    {
      "name": "Test",
      "variables": [
        {"name": "A", "abbrev": "A", "cardinality": 2, "values": ["0", "1"]}
      ],
      "data": [["0"], ["1"]],
      "counts": [45, 55]
    }
    """
    let spec = parseDataSpec(jsonStr)
    check sampleSize(spec) == 100.0

