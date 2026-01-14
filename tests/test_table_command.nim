## Tests for table command - relation metrics

import std/unittest
import std/math
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table as coretable
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/manager/vb
import ../src/occam/math/entropy

suite "Relation Metrics":

  setup:
    # Create 3-variable system: A(2), B(2), C(2)
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

    # Create input data with known structure
    var inputTable = initContingencyTable(varList.keySize)
    # Strong AB association, weak BC association
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0), (VariableIndex(2), 0)]), 40.0)
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0), (VariableIndex(2), 1)]), 10.0)
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 1), (VariableIndex(2), 0)]), 5.0)
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 1), (VariableIndex(2), 1)]), 5.0)
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 0), (VariableIndex(2), 0)]), 5.0)
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 0), (VariableIndex(2), 1)]), 5.0)
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1), (VariableIndex(2), 0)]), 10.0)
    inputTable.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1), (VariableIndex(2), 1)]), 20.0)
    inputTable.sort()
    inputTable.normalize()

  test "computeRelationH returns entropy of marginal":
    var mgr = initVBManager(varList, inputTable)
    let relAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let h = mgr.computeRelationH(relAB)
    # Should be between 0 and 2 bits (2 binary variables)
    check h > 0.0
    check h <= 2.0

  test "computeRelationT returns transmission for a relation":
    var mgr = initVBManager(varList, inputTable)
    let relAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let t = mgr.computeRelationT(relAB)
    # AB should have positive transmission (strong association)
    check t > 0.0

  test "getRelationMetrics returns all metrics for a relation":
    var mgr = initVBManager(varList, inputTable)
    let relAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let metrics = mgr.getRelationMetrics(relAB)

    check metrics.h > 0.0
    check metrics.t >= -1e-10  # Allow tiny negative due to floating point
    check metrics.df > 0
    check metrics.lr >= -1e-10  # Allow tiny negative due to floating point
    check metrics.p2 >= -1e-10  # Allow tiny negative due to floating point

  test "getModelRelationMetrics returns metrics for all relations in model":
    var mgr = initVBManager(varList, inputTable)
    let model = mgr.makeModel("AB:BC")
    let allMetrics = mgr.getModelRelationMetrics(model)

    check allMetrics.len == 2
    # First relation is AB
    check allMetrics[0].relation.printName(varList) == "AB"
    # Second relation is BC
    check allMetrics[1].relation.printName(varList) == "BC"
