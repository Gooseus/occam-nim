## Tests for long-model notation parsing

import std/unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table as coretable
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/manager/vb

suite "Long-Model Notation":

  setup:
    # Create 4-variable system: A(2), B(2), C(2), D(2)
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))
    discard varList.add(newVariable("D", "D", Cardinality(2)))

    # Create minimal input data
    var inputTable = initTable(varList.keySize)
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0), (VariableIndex(2), 0), (VariableIndex(3), 0)]), 1.0)
    inputTable.sort()
    inputTable.normalize()

  test "short notation AB:BC stays the same":
    var mgr = newVBManager(varList, inputTable)
    let model = mgr.makeModel("AB:BC")
    check model.relationCount == 2
    check model.printName(varList) == "AB:BC"

  test "long notation A:B:C:AB:BC simplifies to AB:BC":
    var mgr = newVBManager(varList, inputTable)
    let model = mgr.makeModel("A:B:C:AB:BC")
    # After simplification, should only have AB and BC (maximal relations)
    check model.relationCount == 2
    check model.printName(varList) == "AB:BC"

  test "long notation A:B:C:D stays as independence model":
    var mgr = newVBManager(varList, inputTable)
    let model = mgr.makeModel("A:B:C:D")
    check model.relationCount == 4
    check model.printName(varList) == "A:B:C:D"

  test "long notation A:B:AB simplifies to AB":
    var mgr = newVBManager(varList, inputTable)
    let model = mgr.makeModel("A:B:AB")
    check model.relationCount == 1
    check model.printName(varList) == "AB"

  test "long notation with all components":
    var mgr = newVBManager(varList, inputTable)
    let model = mgr.makeModel("A:B:C:AB:AC:BC:ABC")
    # All subsumed by ABC
    check model.relationCount == 1
    check model.printName(varList) == "ABC"

  test "mixed order still works":
    var mgr = newVBManager(varList, inputTable)
    let model = mgr.makeModel("AB:A:BC:B:C")
    check model.relationCount == 2
    check model.printName(varList) == "AB:BC"
