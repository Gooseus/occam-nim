## Test suite for variable module
## Tests Variable and VariableList functionality

import std/options
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key

suite "Variable creation":
  test "create simple variable":
    let v = newVariable("Age", "A", Cardinality(3))
    check v.name == "Age"
    check v.abbrev == "A"
    check v.cardinality == Cardinality(3)
    check v.isDependent == false

  test "create dependent variable":
    let v = newVariable("Output", "Z", Cardinality(2), isDependent = true)
    check v.isDependent == true

  test "abbreviation is capitalized":
    let v = newVariable("test", "abc", Cardinality(2))
    check v.abbrev == "Abc"

  test "bitSize calculated correctly":
    # bitSize includes space for DontCare (all 1s reserved)
    # So we need ceil(log2(cardinality + 1)) bits

    # cardinality 2 needs 2 bits (values 0,1 + DontCare=3)
    let v2 = newVariable("Binary", "B", Cardinality(2))
    check v2.bitSize == 2

    # cardinality 3 needs 2 bits (values 0,1,2 + DontCare=3)
    let v3 = newVariable("Ternary", "T", Cardinality(3))
    check v3.bitSize == 2

    # cardinality 4 needs 3 bits (values 0-3 + DontCare=7)
    let v4 = newVariable("Quad", "Q", Cardinality(4))
    check v4.bitSize == 3

    # cardinality 5 needs 3 bits (values 0-4 + DontCare=7)
    let v5 = newVariable("Five", "F", Cardinality(5))
    check v5.bitSize == 3

    # cardinality 256 needs 9 bits (values 0-255 + DontCare=511)
    let v256 = newVariable("Large", "L", Cardinality(256))
    check v256.bitSize == 9

suite "VariableList basic operations":
  test "create empty list":
    let list = initVariableList()
    check list.len == 0

  test "add single variable":
    var list = initVariableList()
    let idx = list.add(newVariable("Age", "A", Cardinality(3)))
    check list.len == 1
    check idx == VariableIndex(0)

  test "add multiple variables":
    var list = initVariableList()
    discard list.add(newVariable("Var1", "V1", Cardinality(3)))
    discard list.add(newVariable("Var2", "V2", Cardinality(4)))
    discard list.add(newVariable("Var3", "V3", Cardinality(2)))
    check list.len == 3

  test "access by index":
    var list = initVariableList()
    discard list.add(newVariable("Age", "A", Cardinality(3)))
    discard list.add(newVariable("Income", "I", Cardinality(5)))

    check list[VariableIndex(0)].name == "Age"
    check list[VariableIndex(1)].name == "Income"

  test "find by abbreviation":
    var list = initVariableList()
    discard list.add(newVariable("Age", "A", Cardinality(3)))
    discard list.add(newVariable("Income", "I", Cardinality(5)))

    let found = list.findByAbbrev("I")
    check found.isSome
    check found.get == VariableIndex(1)

    let notFound = list.findByAbbrev("X")
    check notFound.isNone

  test "abbreviation lookup is case insensitive":
    var list = initVariableList()
    discard list.add(newVariable("Age", "Age", Cardinality(3)))

    check list.findByAbbrev("age").isSome
    check list.findByAbbrev("AGE").isSome
    check list.findByAbbrev("Age").isSome

suite "VariableList bit-packing":
  test "first variable starts at top of first segment":
    var list = initVariableList()
    # Cardinality 2 now needs 2 bits (to reserve space for DontCare)
    discard list.add(newVariable("Binary", "B", Cardinality(2)))

    let v = list[VariableIndex(0)]
    check v.segment == SegmentIndex(0)
    # 32 bits - 2 bits = shift of 30
    check v.shift == BitShift(30)

  test "second variable follows first in same segment":
    var list = initVariableList()
    # 2 bits for cardinality 3
    discard list.add(newVariable("First", "F", Cardinality(3)))
    # 3 bits for cardinality 4 (needs space for DontCare)
    discard list.add(newVariable("Second", "S", Cardinality(4)))

    let v1 = list[VariableIndex(0)]
    let v2 = list[VariableIndex(1)]

    check v1.segment == SegmentIndex(0)
    check v2.segment == SegmentIndex(0)
    # First: shift = 32 - 2 = 30
    check v1.shift == BitShift(30)
    # Second: shift = 30 - 3 = 27
    check v2.shift == BitShift(27)

  test "new segment when current is full":
    var list = initVariableList()

    # Fill first segment with 10 x 3-bit variables (30 bits)
    # Using cardinality 4 which needs 3 bits
    for i in 0..<10:
      discard list.add(newVariable("Var" & $i, "V" & $i, Cardinality(4)))

    # Next 3-bit variable won't fit (30 + 3 = 33 > 32), goes to segment 1
    let idx = list.add(newVariable("Overflow", "O", Cardinality(4)))
    let v = list[idx]

    check v.segment == SegmentIndex(1)
    check v.shift == BitShift(29)  # 32 - 3 = 29

  test "keySize reflects number of segments needed":
    var list = initVariableList()

    # 16 variables of 2 bits each = 32 bits (using cardinality 3)
    for i in 0..<16:
      discard list.add(newVariable("V" & $i, "V" & $i, Cardinality(3)))
    check list.keySize == 1  # Exactly 32 bits

    # Now overflow to second segment
    discard list.add(newVariable("Over", "O", Cardinality(2)))
    check list.keySize == 2

  test "mask covers correct bits":
    var list = initVariableList()
    # Cardinality 2 needs 2 bits
    discard list.add(newVariable("Binary", "B", Cardinality(2)))

    let v = list[VariableIndex(0)]
    # 2 bits at positions 30-31: mask should be 0xC0000000
    check v.mask == KeySegment(0xC0000000'u32)

suite "VariableList directed/neutral":
  test "isDirected false when no dependent variables":
    var list = initVariableList()
    discard list.add(newVariable("A", "A", Cardinality(2)))
    discard list.add(newVariable("B", "B", Cardinality(2)))
    check list.isDirected == false

  test "isDirected true when has dependent variable":
    var list = initVariableList()
    discard list.add(newVariable("A", "A", Cardinality(2)))
    discard list.add(newVariable("Z", "Z", Cardinality(2), isDependent = true))
    check list.isDirected == true

  test "dependentIndex returns correct index":
    var list = initVariableList()
    discard list.add(newVariable("A", "A", Cardinality(2)))
    discard list.add(newVariable("Z", "Z", Cardinality(2), isDependent = true))

    let dvIdx = list.dependentIndex
    check dvIdx.isSome
    check dvIdx.get == VariableIndex(1)

  test "dependentIndex none when no dependent":
    var list = initVariableList()
    discard list.add(newVariable("A", "A", Cardinality(2)))
    check list.dependentIndex.isNone

suite "VariableList iteration":
  test "iterate over items":
    var list = initVariableList()
    discard list.add(newVariable("A", "A", Cardinality(2)))
    discard list.add(newVariable("B", "B", Cardinality(3)))
    discard list.add(newVariable("C", "C", Cardinality(4)))

    var names: seq[string]
    for v in list:
      names.add(v.name)

    check names == @["A", "B", "C"]

  test "iterate with pairs":
    var list = initVariableList()
    discard list.add(newVariable("A", "A", Cardinality(2)))
    discard list.add(newVariable("B", "B", Cardinality(3)))

    var result: seq[(int, string)]
    for idx, v in list.pairs:
      result.add((idx.toInt, v.name))

    check result == @[(0, "A"), (1, "B")]


suite "Variable edge cases":
  test "should handle cardinality of 1":
    let v = newVariable("Single", "S", Cardinality(1))
    check v.cardinality == Cardinality(1)
    # Cardinality 1 still needs 1 bit (for value 0 + DontCare)
    check v.bitSize >= 1

  test "should handle cardinality of 2 (binary)":
    let v = newVariable("Binary", "B", Cardinality(2))
    check v.cardinality == Cardinality(2)
    check v.bitSize == 2  # Values 0,1 + DontCare

  test "should handle large cardinality":
    let v = newVariable("Large", "L", Cardinality(1000))
    check v.cardinality == Cardinality(1000)
    # 1000 values + DontCare needs 10 bits (2^10 = 1024)
    check v.bitSize == 10

  test "should handle very large cardinality":
    let v = newVariable("VeryLarge", "VL", Cardinality(10000))
    check v.cardinality == Cardinality(10000)
    # 10000 values + DontCare needs 14 bits (2^14 = 16384)
    check v.bitSize == 14

  test "should capitalize single-char abbreviation":
    let v = newVariable("test", "a", Cardinality(2))
    check v.abbrev == "A"

  test "should handle multi-char abbreviation":
    let v = newVariable("test", "abc", Cardinality(2))
    check v.abbrev == "Abc"

  test "should handle already capitalized abbreviation":
    let v = newVariable("test", "ABC", Cardinality(2))
    check v.abbrev == "Abc"

  test "should handle empty name":
    let v = newVariable("", "X", Cardinality(2))
    check v.name == ""
    check v.abbrev == "X"


suite "VariableList edge cases":
  test "should handle empty varList keySize":
    let list = initVariableList()
    check list.keySize == 0  # Empty varList has no segments

  test "should handle empty varList findByAbbrev":
    let list = initVariableList()
    check list.findByAbbrev("A").isNone

  test "should handle empty varList isDirected":
    let list = initVariableList()
    check list.isDirected == false

  test "should handle empty varList dependentIndex":
    let list = initVariableList()
    check list.dependentIndex.isNone

  test "should handle multiple dependent variables":
    var list = initVariableList()
    discard list.add(newVariable("A", "A", Cardinality(2)))
    discard list.add(newVariable("Z1", "Y", Cardinality(2), isDependent = true))
    discard list.add(newVariable("Z2", "Z", Cardinality(2), isDependent = true))

    # Should still be marked as directed
    check list.isDirected == true
    # dependentIndex should return first dependent
    let dvIdx = list.dependentIndex
    check dvIdx.isSome

  test "should handle all variables being dependent":
    var list = initVariableList()
    discard list.add(newVariable("Z1", "A", Cardinality(2), isDependent = true))
    discard list.add(newVariable("Z2", "B", Cardinality(2), isDependent = true))

    check list.isDirected == true

  test "should handle building mask for empty variable indices":
    var list = initVariableList()
    discard list.add(newVariable("A", "A", Cardinality(4)))
    discard list.add(newVariable("B", "B", Cardinality(4)))

    let mask = list.buildMask(@[])
    # Empty mask should be all 1s (DontCare for everything)
    check mask[0] == DontCare

  test "should handle building mask for all variables":
    var list = initVariableList()
    discard list.add(newVariable("A", "A", Cardinality(4)))
    discard list.add(newVariable("B", "B", Cardinality(4)))

    let mask = list.buildMask(@[VariableIndex(0), VariableIndex(1)])
    # Full mask should have 0s for all variable positions
    let vA = list[VariableIndex(0)]
    let vB = list[VariableIndex(1)]
    check (mask[0] and vA.mask) == KeySegment(0)
    check (mask[0] and vB.mask) == KeySegment(0)

  test "should handle many variables filling multiple segments":
    var list = initVariableList()
    # Add 32 binary variables (each needs 2 bits)
    # This should use 64 bits = 2 segments
    for i in 0..<32:
      discard list.add(newVariable("V" & $i, $chr(ord('A') + (i mod 26)) & $i, Cardinality(2)))

    check list.keySize == 2
    check list.len == 32

    # All variables should be accessible
    for i in 0..<32:
      check list[VariableIndex(i)].name == "V" & $i
