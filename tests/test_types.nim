## Test suite for core types module
## Tests distinct types, operators, and constants

import unittest
import ../src/occam/core/types

suite "Cardinality type":
  test "can create and compare":
    let c1 = Cardinality(3)
    let c2 = Cardinality(3)
    let c3 = Cardinality(5)
    check c1 == c2
    check c1 != c3
    check c1 < c3

  test "arithmetic operations":
    let c1 = Cardinality(3)
    let c2 = Cardinality(2)
    check c1 - c2 == Cardinality(1)
    check c1 * c2 == Cardinality(6)

  test "conversion to int":
    let c = Cardinality(42)
    check c.toInt == 42

  test "string representation":
    let c = Cardinality(7)
    check $c == "7"

suite "KeySegment type":
  test "can create and compare":
    let k1 = KeySegment(0xFFFF'u32)
    let k2 = KeySegment(0xFFFF'u32)
    let k3 = KeySegment(0x0000'u32)
    check k1 == k2
    check k1 != k3

  test "bitwise operations":
    let k1 = KeySegment(0b1100'u32)
    let k2 = KeySegment(0b1010'u32)
    check (k1 and k2) == KeySegment(0b1000'u32)
    check (k1 or k2) == KeySegment(0b1110'u32)
    check (k1 xor k2) == KeySegment(0b0110'u32)
    check (not KeySegment(0'u32)) == KeySegment(0xFFFFFFFF'u32)

  test "shift operations":
    let k = KeySegment(1'u32)
    check (k shl 4) == KeySegment(16'u32)
    check (KeySegment(16'u32) shr 2) == KeySegment(4'u32)

suite "VariableIndex type":
  test "can create and compare":
    let v1 = VariableIndex(0)
    let v2 = VariableIndex(0)
    let v3 = VariableIndex(1)
    check v1 == v2
    check v1 != v3
    check v1 < v3

  test "conversion to int":
    let v = VariableIndex(5)
    check v.toInt == 5

suite "Constants":
  test "DontCare is all bits on":
    check DontCare == KeySegment(0xFFFFFFFF'u32)

  test "KeySegmentBits is 32":
    check KeySegmentBits == 32

  test "ProbMin is small positive":
    check ProbMin > 0.0
    check ProbMin < 1e-30

  test "MaxNameLen and MaxAbbrevLen":
    check MaxNameLen == 32
    check MaxAbbrevLen == 8

suite "Direction enum":
  test "has Ascending and Descending":
    check Direction.Ascending != Direction.Descending

suite "SearchFilter enum":
  test "has all filter types":
    check SearchFilter.Full != SearchFilter.Loopless
    check SearchFilter.Loopless != SearchFilter.Disjoint
    check SearchFilter.Disjoint != SearchFilter.Chain

suite "TableKind enum":
  test "has InformationTheoretic and SetTheoretic":
    check TableKind.InformationTheoretic != TableKind.SetTheoretic
