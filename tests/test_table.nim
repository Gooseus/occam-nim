## Test suite for table module
## Tests sparse contingency table functionality

import std/options
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table

suite "Table creation":
  test "create empty table":
    let t = initContingencyTable(1)
    check t.len == 0
    check t.keySize == 1

  test "create table with capacity":
    let t = initContingencyTable(2, capacity = 100)
    check t.len == 0
    check t.keySize == 2

suite "Table add operations":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(3)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))

  test "add single tuple":
    var t = initContingencyTable(varList.keySize)
    let k = varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 0)])
    t.add(k, 10.0)
    check t.len == 1

  test "add multiple tuples":
    var t = initContingencyTable(varList.keySize)
    let k1 = varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)])
    let k2 = varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)])
    let k3 = varList.buildKey(@[(VariableIndex(0), 2), (VariableIndex(1), 0)])
    t.add(k1, 5.0)
    t.add(k2, 10.0)
    t.add(k3, 15.0)
    check t.len == 3

  test "add tuple with key-value pair":
    var t = initContingencyTable(varList.keySize)
    let k = varList.buildKey(@[(VariableIndex(0), 2), (VariableIndex(1), 1)])
    t.add(k, 42.0)
    check t.len == 1

suite "Table sort and find":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(4)))
    discard varList.add(newVariable("B", "B", Cardinality(4)))

  test "sort puts tuples in key order":
    var t = initContingencyTable(varList.keySize)
    # Add in reverse order
    let k3 = varList.buildKey(@[(VariableIndex(0), 3), (VariableIndex(1), 0)])
    let k1 = varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 0)])
    let k2 = varList.buildKey(@[(VariableIndex(0), 2), (VariableIndex(1), 0)])
    t.add(k3, 30.0)
    t.add(k1, 10.0)
    t.add(k2, 20.0)

    t.sort()

    # Verify order
    var prev = t[0].key
    for i in 1..<t.len:
      check prev < t[i].key
      prev = t[i].key

  test "find returns correct index after sort":
    var t = initContingencyTable(varList.keySize)
    let k1 = varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 1)])
    let k2 = varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 2)])
    let k3 = varList.buildKey(@[(VariableIndex(0), 2), (VariableIndex(1), 3)])
    t.add(k1, 100.0)
    t.add(k2, 200.0)
    t.add(k3, 300.0)
    t.sort()

    let found = t.find(k2)
    check found.isSome
    check t[found.get].value == 200.0

  test "find returns none for missing key":
    var t = initContingencyTable(varList.keySize)
    let k1 = varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)])
    let k2 = varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)])
    t.add(k1, 100.0)
    t.sort()

    let found = t.find(k2)
    check found.isNone

  test "find works with single element":
    var t = initContingencyTable(varList.keySize)
    let k = varList.buildKey(@[(VariableIndex(0), 2), (VariableIndex(1), 2)])
    t.add(k, 42.0)
    t.sort()

    let found = t.find(k)
    check found.isSome
    check t[found.get].value == 42.0

suite "Table value operations":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(3)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))

  test "sum returns total of all values":
    var t = initContingencyTable(varList.keySize)
    let k1 = varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)])
    let k2 = varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)])
    let k3 = varList.buildKey(@[(VariableIndex(0), 2), (VariableIndex(1), 0)])
    t.add(k1, 10.0)
    t.add(k2, 20.0)
    t.add(k3, 30.0)

    check t.sum == 60.0

  test "normalize converts counts to probabilities":
    var t = initContingencyTable(varList.keySize)
    let k1 = varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)])
    let k2 = varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 0)])
    t.add(k1, 25.0)
    t.add(k2, 75.0)

    t.normalize()

    check abs(t.sum - 1.0) < 1e-10
    # Check individual values
    var foundK1 = false
    var foundK2 = false
    for tup in t:
      if tup.key == k1:
        check abs(tup.value - 0.25) < 1e-10
        foundK1 = true
      elif tup.key == k2:
        check abs(tup.value - 0.75) < 1e-10
        foundK2 = true
    check foundK1 and foundK2

  test "normalize handles zero total":
    var t = initContingencyTable(varList.keySize)
    let k = varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)])
    t.add(k, 0.0)

    # Should not crash
    t.normalize()
    check t[0].value == 0.0

suite "Table projection":
  setup:
    var varList = initVariableList()
    # A has 3 values, B has 2 values
    discard varList.add(newVariable("A", "A", Cardinality(3)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))

  test "project to single variable":
    var t = initContingencyTable(varList.keySize)
    # A=0, B=0 -> 10
    # A=0, B=1 -> 20
    # A=1, B=0 -> 30
    # A=1, B=1 -> 40
    t.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)]), 10.0)
    t.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 1)]), 20.0)
    t.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 0)]), 30.0)
    t.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)]), 40.0)
    t.sort()

    # Project to just A (marginalize out B)
    let projected = t.project(varList, @[VariableIndex(0)])

    # Should have 2 tuples: A=0 (30) and A=1 (70)
    check projected.len == 2
    check projected.sum == 100.0

  test "project preserves total":
    var t = initContingencyTable(varList.keySize)
    t.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)]), 15.0)
    t.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)]), 25.0)
    t.add(varList.buildKey(@[(VariableIndex(0), 2), (VariableIndex(1), 0)]), 35.0)
    t.sort()

    let projA = t.project(varList, @[VariableIndex(0)])
    let projB = t.project(varList, @[VariableIndex(1)])

    check abs(projA.sum - 75.0) < 1e-10
    check abs(projB.sum - 75.0) < 1e-10

  test "project to all variables returns copy":
    var t = initContingencyTable(varList.keySize)
    t.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)]), 50.0)
    t.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)]), 50.0)
    t.sort()

    let projected = t.project(varList, @[VariableIndex(0), VariableIndex(1)])

    check projected.len == t.len
    check projected.sum == t.sum

suite "Table sumInto":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(3)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))

  test "sumInto combines matching keys":
    var t = initContingencyTable(varList.keySize)
    let k = varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 0)])
    t.add(k, 10.0)
    t.add(k, 20.0)  # Same key
    t.add(k, 30.0)  # Same key again

    t.sumInto()

    check t.len == 1
    check t[0].value == 60.0

  test "sumInto preserves distinct keys":
    var t = initContingencyTable(varList.keySize)
    let k1 = varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)])
    let k2 = varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)])
    t.add(k1, 10.0)
    t.add(k2, 20.0)

    t.sumInto()

    check t.len == 2

  test "sumInto works on empty table":
    var t = initContingencyTable(varList.keySize)
    t.sumInto()
    check t.len == 0

suite "Table iteration":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(3)))

  test "iterate over tuples":
    var t = initContingencyTable(varList.keySize)
    t.add(varList.buildKey(@[(VariableIndex(0), 0)]), 1.0)
    t.add(varList.buildKey(@[(VariableIndex(0), 1)]), 2.0)
    t.add(varList.buildKey(@[(VariableIndex(0), 2)]), 3.0)

    var total = 0.0
    for tup in t:
      total += tup.value

    check total == 6.0

  test "iterate with indices":
    var t = initContingencyTable(varList.keySize)
    t.add(varList.buildKey(@[(VariableIndex(0), 0)]), 10.0)
    t.add(varList.buildKey(@[(VariableIndex(0), 1)]), 20.0)

    var indices: seq[int]
    for i, tup in t.pairs:
      indices.add(i)

    check indices == @[0, 1]

suite "Table with multiple segments":
  setup:
    var varList = initVariableList()
    # Create enough variables to require 2 segments
    for i in 0..<17:
      discard varList.add(newVariable("V" & $i, "V" & $i, Cardinality(4)))

  test "table handles multi-segment keys":
    check varList.keySize == 2

    var t = initContingencyTable(varList.keySize)
    var k1 = newKey(varList.keySize)
    k1.setValue(varList, VariableIndex(0), 1)
    k1.setValue(varList, VariableIndex(16), 2)

    var k2 = newKey(varList.keySize)
    k2.setValue(varList, VariableIndex(0), 2)
    k2.setValue(varList, VariableIndex(16), 1)

    t.add(k1, 100.0)
    t.add(k2, 200.0)
    t.sort()

    let found1 = t.find(k1)
    let found2 = t.find(k2)

    check found1.isSome
    check found2.isSome
    check t[found1.get].value == 100.0
    check t[found2.get].value == 200.0


suite "Table edge cases and error paths":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(3)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))

  test "should handle find on empty table":
    let t = initContingencyTable(varList.keySize)
    let k = varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 0)])
    check t.find(k).isNone

  test "should handle sum on empty table":
    let t = initContingencyTable(varList.keySize)
    check t.sum == 0.0

  test "should handle project on empty table":
    let t = initContingencyTable(varList.keySize)
    let projected = t.project(varList, @[VariableIndex(0)])
    check projected.len == 0

  test "should handle normalize on empty table":
    var t = initContingencyTable(varList.keySize)
    t.normalize()  # Should not crash
    check t.len == 0

  test "should handle sort on empty table":
    var t = initContingencyTable(varList.keySize)
    t.sort()  # Should not crash
    check t.len == 0

  test "should handle project to empty variable list":
    var t = initContingencyTable(varList.keySize)
    t.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)]), 10.0)
    t.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)]), 20.0)
    t.sort()

    let projected = t.project(varList, @[])
    # Projecting to no variables should sum everything into one tuple
    check projected.len == 1
    check abs(projected.sum - 30.0) < 1e-10

  test "should handle table with all zero values":
    var t = initContingencyTable(varList.keySize)
    t.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)]), 0.0)
    t.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)]), 0.0)
    t.sort()

    check t.sum == 0.0
    t.normalize()  # Should handle zero total gracefully
    check t.len == 2

  test "should handle table with negative values":
    var t = initContingencyTable(varList.keySize)
    t.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)]), -10.0)
    t.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)]), 20.0)

    check t.sum == 10.0

  test "should handle very small values":
    var t = initContingencyTable(varList.keySize)
    t.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)]), 1e-300)
    t.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)]), 1e-300)

    check t.sum > 0.0
    t.normalize()
    check abs(t.sum - 1.0) < 1e-10

  test "should handle duplicate keys correctly with sumInto":
    var t = initContingencyTable(varList.keySize)
    let k = varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)])
    # Add same key 100 times
    for i in 0..<100:
      t.add(k, 1.0)

    t.sort()
    t.sumInto()

    check t.len == 1
    check t[0].value == 100.0

  test "should handle single-tuple table operations":
    var t = initContingencyTable(varList.keySize)
    let k = varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 0)])
    t.add(k, 42.0)
    t.sort()

    check t.find(k).isSome
    check t.sum == 42.0

    t.normalize()
    check abs(t[0].value - 1.0) < 1e-10

    let projected = t.project(varList, @[VariableIndex(0)])
    check projected.len == 1

  test "should handle repeated sort calls":
    var t = initContingencyTable(varList.keySize)
    t.add(varList.buildKey(@[(VariableIndex(0), 2), (VariableIndex(1), 1)]), 30.0)
    t.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)]), 10.0)
    t.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)]), 20.0)

    t.sort()
    t.sort()  # Should be idempotent
    t.sort()

    check t[0].value == 10.0  # First after sort
    check t[2].value == 30.0  # Last after sort
