## Test suite for Custom Reference Model Validation
## TDD: Tests written before implementation

import std/[unittest, strutils]
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/manager/vb


# Helper to create a standard test setup
proc createTestSetup(): (VariableList, ContingencyTable) =
  var varList = initVariableList()
  discard varList.add(initVariable("VarA", "A", Cardinality(2)))
  discard varList.add(initVariable("VarB", "B", Cardinality(2)))
  discard varList.add(initVariable("VarC", "C", Cardinality(2)))

  var inputTable = initContingencyTable(varList.keySize, 8)
  for a in 0..<2:
    for b in 0..<2:
      for c in 0..<2:
        var k = initKey(varList.keySize)
        k.setValue(varList, VariableIndex(0), a)
        k.setValue(varList, VariableIndex(1), b)
        k.setValue(varList, VariableIndex(2), c)
        inputTable.add(k, 10.0)
  inputTable.sort()

  (varList, inputTable)


suite "Reference Model Parsing with parseModel":
  test "parseModel parses valid model notation AB:BC":
    let (varList, inputTable) = createTestSetup()
    var mgr = initVBManager(varList, inputTable)

    let model = mgr.parseModel("AB:BC")

    # Should have 2 relations: AB and BC
    check model.relationCount == 2

  test "parseModel parses independence model A:B:C":
    let (varList, inputTable) = createTestSetup()
    var mgr = initVBManager(varList, inputTable)

    let model = mgr.parseModel("A:B:C")

    # Should have 3 single-variable relations
    check model.relationCount == 3
    for i in 0..<3:
      check model.relations[i].variableCount == 1

  test "parseModel parses saturated model ABC":
    let (varList, inputTable) = createTestSetup()
    var mgr = initVBManager(varList, inputTable)

    let model = mgr.parseModel("ABC")

    # Should have 1 relation with all 3 variables
    check model.relationCount == 1
    check model.relations[0].variableCount == 3

  test "parseModel handles single relation":
    let (varList, inputTable) = createTestSetup()
    var mgr = initVBManager(varList, inputTable)

    let model = mgr.parseModel("AB")

    check model.relationCount == 1
    check model.relations[0].variableCount == 2


suite "Reference Model Validation":
  test "validateReferenceModel succeeds for valid model AB:BC":
    let (varList, inputTable) = createTestSetup()
    var mgr = initVBManager(varList, inputTable)

    let result = mgr.validateReferenceModel("AB:BC")

    check result.isValid == true
    check result.errorMessage == ""
    check result.model.relationCount == 2

  test "validateReferenceModel handles empty string as valid (use default)":
    let (varList, inputTable) = createTestSetup()
    var mgr = initVBManager(varList, inputTable)

    let result = mgr.validateReferenceModel("")

    check result.isValid == true
    check result.errorMessage == ""

  test "validateReferenceModel handles whitespace-only as valid":
    let (varList, inputTable) = createTestSetup()
    var mgr = initVBManager(varList, inputTable)

    let result = mgr.validateReferenceModel("   ")

    check result.isValid == true
    check result.errorMessage == ""

  test "validateReferenceModel returns error for non-existent variable X":
    let (varList, inputTable) = createTestSetup()
    var mgr = initVBManager(varList, inputTable)

    let result = mgr.validateReferenceModel("AX:BC")

    check result.isValid == false
    check "X" in result.errorMessage

  test "validateReferenceModel returns error for all invalid variables":
    let (varList, inputTable) = createTestSetup()
    var mgr = initVBManager(varList, inputTable)

    let result = mgr.validateReferenceModel("XY:ZW")

    check result.isValid == false
    # Should mention at least one invalid variable
    check result.errorMessage.len > 0

  test "validateReferenceModel works with lowercase variable names (case insensitive)":
    # Variable lookup is case-insensitive, so lowercase should work
    let (varList, inputTable) = createTestSetup()
    var mgr = initVBManager(varList, inputTable)

    let result = mgr.validateReferenceModel("ab:bc")

    # Should succeed because lookup is case-insensitive
    check result.isValid == true
    check result.model.relationCount == 2


suite "Reference Model Validation - Edge Cases":
  test "validateReferenceModel with single variable":
    let (varList, inputTable) = createTestSetup()
    var mgr = initVBManager(varList, inputTable)

    let result = mgr.validateReferenceModel("A")

    check result.isValid == true
    check result.model.relationCount == 1

  test "validateReferenceModel with valid colon-only returns empty model":
    let (varList, inputTable) = createTestSetup()
    var mgr = initVBManager(varList, inputTable)

    # Just colons with no variables
    let result = mgr.validateReferenceModel(":")

    # Should be valid but produce empty model
    check result.isValid == true
    check result.model.relationCount == 0

  test "validateReferenceModel mixed valid and invalid":
    let (varList, inputTable) = createTestSetup()
    var mgr = initVBManager(varList, inputTable)

    # AB is valid, XY is not
    let result = mgr.validateReferenceModel("AB:XY")

    check result.isValid == false


suite "Reference Model with Directed Systems":
  test "validateReferenceModel works with directed system":
    var varList = initVariableList()
    discard varList.add(initVariable("Input1", "I", Cardinality(2)))
    discard varList.add(initVariable("Input2", "J", Cardinality(2)))
    discard varList.add(initVariable("Output", "Z", Cardinality(2), isDependent = true))

    var inputTable = initContingencyTable(varList.keySize, 8)
    for i in 0..<2:
      for j in 0..<2:
        for z in 0..<2:
          var k = initKey(varList.keySize)
          k.setValue(varList, VariableIndex(0), i)
          k.setValue(varList, VariableIndex(1), j)
          k.setValue(varList, VariableIndex(2), z)
          inputTable.add(k, 10.0)
    inputTable.sort()

    var mgr = initVBManager(varList, inputTable)

    let result = mgr.validateReferenceModel("IZ:JZ")

    check result.isValid == true
    check result.model.relationCount == 2
