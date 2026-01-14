## Test suite for key module
## Tests Key encoding, decoding, and manipulation

import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key

suite "Key creation":
  test "create empty key":
    let k = initKey(1)
    check k.len == 1
    check k[0] == DontCare

  test "create multi-segment key":
    let k = initKey(3)
    check k.len == 3
    for i in 0..<3:
      check k[i] == DontCare

suite "Key value operations":
  setup:
    var varList = initVariableList()
    # A: cardinality 4 (2 bits), values 0-3
    discard varList.add(initVariable("VarA", "A", Cardinality(4)))
    # B: cardinality 3 (2 bits), values 0-2
    discard varList.add(initVariable("VarB", "B", Cardinality(3)))
    # C: cardinality 2 (1 bit), values 0-1
    discard varList.add(initVariable("VarC", "C", Cardinality(2)))

  test "set and get single value":
    var k = initKey(varList.keySize)
    k.setValue(varList, VariableIndex(0), 2)
    check k.getValue(varList, VariableIndex(0)) == 2

  test "set and get multiple values":
    var k = initKey(varList.keySize)
    k.setValue(varList, VariableIndex(0), 3)  # A = 3
    k.setValue(varList, VariableIndex(1), 1)  # B = 1
    k.setValue(varList, VariableIndex(2), 1)  # C = 1

    check k.getValue(varList, VariableIndex(0)) == 3
    check k.getValue(varList, VariableIndex(1)) == 1
    check k.getValue(varList, VariableIndex(2)) == 1

  test "values don't interfere with each other":
    var k = initKey(varList.keySize)

    # Set all to max values
    k.setValue(varList, VariableIndex(0), 3)
    k.setValue(varList, VariableIndex(1), 2)
    k.setValue(varList, VariableIndex(2), 1)

    # Change middle value
    k.setValue(varList, VariableIndex(1), 0)

    # Others should be unchanged
    check k.getValue(varList, VariableIndex(0)) == 3
    check k.getValue(varList, VariableIndex(1)) == 0
    check k.getValue(varList, VariableIndex(2)) == 1

  test "build key from pairs":
    let k = varList.buildKey(@[
      (VariableIndex(0), 2),
      (VariableIndex(1), 1),
      (VariableIndex(2), 0)
    ])
    check k.getValue(varList, VariableIndex(0)) == 2
    check k.getValue(varList, VariableIndex(1)) == 1
    check k.getValue(varList, VariableIndex(2)) == 0

suite "Key comparison":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(4)))
    discard varList.add(initVariable("B", "B", Cardinality(4)))

  test "equal keys":
    var k1 = initKey(varList.keySize)
    var k2 = initKey(varList.keySize)
    k1.setValue(varList, VariableIndex(0), 2)
    k2.setValue(varList, VariableIndex(0), 2)
    check k1 == k2

  test "unequal keys":
    var k1 = initKey(varList.keySize)
    var k2 = initKey(varList.keySize)
    k1.setValue(varList, VariableIndex(0), 2)
    k2.setValue(varList, VariableIndex(0), 3)
    check k1 != k2

  test "key ordering":
    var k1 = initKey(varList.keySize)
    var k2 = initKey(varList.keySize)
    k1.setValue(varList, VariableIndex(0), 1)
    k2.setValue(varList, VariableIndex(0), 2)
    check k1 < k2
    check not (k2 < k1)

  test "key hash":
    var k1 = initKey(varList.keySize)
    var k2 = initKey(varList.keySize)
    k1.setValue(varList, VariableIndex(0), 2)
    k2.setValue(varList, VariableIndex(0), 2)
    check hash(k1) == hash(k2)

suite "Key masking":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(4)))
    discard varList.add(initVariable("B", "B", Cardinality(4)))
    discard varList.add(initVariable("C", "C", Cardinality(4)))

  test "build mask for subset of variables":
    # Mask for variables A and C (indices 0 and 2)
    let mask = varList.buildMask(@[VariableIndex(0), VariableIndex(2)])

    # Mask should have 0s where A and C are, 1s elsewhere
    # Variable B should still be DontCare
    let vA = varList[VariableIndex(0)]
    let vB = varList[VariableIndex(1)]
    let vC = varList[VariableIndex(2)]

    # Check that A's bits are 0 in the mask
    check (mask[0] and vA.mask) == KeySegment(0)
    # Check that B's bits are 1 in the mask
    check (mask[0] and vB.mask) == vB.mask
    # Check that C's bits are 0 in the mask
    check (mask[0] and vC.mask) == KeySegment(0)

  test "apply mask to key (project)":
    var k = initKey(varList.keySize)
    k.setValue(varList, VariableIndex(0), 3)  # A = 3
    k.setValue(varList, VariableIndex(1), 2)  # B = 2
    k.setValue(varList, VariableIndex(2), 1)  # C = 1

    # Create mask for just variable A
    let mask = varList.buildMask(@[VariableIndex(0)])

    # Apply mask - should keep A, set others to DontCare
    let projected = k.applyMask(mask)

    check projected.getValue(varList, VariableIndex(0)) == 3
    # B and C should now be DontCare (all 1s in their bit positions)
    let vB = varList[VariableIndex(1)]
    let vC = varList[VariableIndex(2)]
    check (projected[0] and vB.mask) == vB.mask
    check (projected[0] and vC.mask) == vC.mask

suite "Key with multiple segments":
  setup:
    var varList = initVariableList()
    # Fill first segment completely (16 x 2-bit variables)
    for i in 0..<16:
      discard varList.add(initVariable("V" & $i, "V" & $i, Cardinality(4)))
    # Add one more to overflow to second segment
    discard varList.add(initVariable("Overflow", "O", Cardinality(4)))

  test "key spans multiple segments":
    check varList.keySize == 2

    var k = initKey(varList.keySize)
    check k.len == 2

  test "set value in first segment":
    var k = initKey(varList.keySize)
    k.setValue(varList, VariableIndex(0), 3)
    check k.getValue(varList, VariableIndex(0)) == 3

  test "set value in second segment":
    var k = initKey(varList.keySize)
    k.setValue(varList, VariableIndex(16), 2)  # Overflow variable
    check k.getValue(varList, VariableIndex(16)) == 2

  test "values in different segments don't interfere":
    var k = initKey(varList.keySize)
    k.setValue(varList, VariableIndex(0), 3)   # First segment
    k.setValue(varList, VariableIndex(16), 2)  # Second segment

    check k.getValue(varList, VariableIndex(0)) == 3
    check k.getValue(varList, VariableIndex(16)) == 2

suite "Key matching":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(4)))
    discard varList.add(initVariable("B", "B", Cardinality(4)))

  test "exact match":
    var k1 = varList.buildKey(@[(VariableIndex(0), 2), (VariableIndex(1), 3)])
    var k2 = varList.buildKey(@[(VariableIndex(0), 2), (VariableIndex(1), 3)])
    check k1.matchesWithVarList(k2, varList)

  test "no match when different":
    var k1 = varList.buildKey(@[(VariableIndex(0), 2), (VariableIndex(1), 3)])
    var k2 = varList.buildKey(@[(VariableIndex(0), 2), (VariableIndex(1), 1)])
    check not k1.matchesWithVarList(k2, varList)

  test "DontCare matches any value":
    var k1 = initKey(varList.keySize)  # All DontCare
    var k2 = varList.buildKey(@[(VariableIndex(0), 2), (VariableIndex(1), 3)])
    check k1.matchesWithVarList(k2, varList)
    check k2.matchesWithVarList(k1, varList)

  test "partial DontCare matching":
    var k1 = initKey(varList.keySize)
    k1.setValue(varList, VariableIndex(0), 2)  # A=2, B=DontCare

    var k2 = varList.buildKey(@[(VariableIndex(0), 2), (VariableIndex(1), 3)])
    var k3 = varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 3)])

    check k1.matchesWithVarList(k2, varList)      # A matches, B is DontCare
    check not k1.matchesWithVarList(k3, varList)  # A doesn't match


suite "Key value encoding (behavioral)":
  ## These tests verify behavior without testing internal bit patterns
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(8)))   # 3 bits
    discard varList.add(initVariable("B", "B", Cardinality(16)))  # 4 bits
    discard varList.add(initVariable("C", "C", Cardinality(4)))   # 2 bits

  test "should encode and decode all valid values for each variable":
    var k = initKey(varList.keySize)

    # Test all values for variable A (0-7)
    for value in 0..<8:
      k.setValue(varList, VariableIndex(0), value)
      check k.getValue(varList, VariableIndex(0)) == value

    # Test all values for variable B (0-15)
    for value in 0..<16:
      k.setValue(varList, VariableIndex(1), value)
      check k.getValue(varList, VariableIndex(1)) == value

    # Test all values for variable C (0-3)
    for value in 0..<4:
      k.setValue(varList, VariableIndex(2), value)
      check k.getValue(varList, VariableIndex(2)) == value

  test "should not have crosstalk between adjacent variables":
    var k = initKey(varList.keySize)

    # Set all variables to specific values
    k.setValue(varList, VariableIndex(0), 7)   # A max
    k.setValue(varList, VariableIndex(1), 15)  # B max
    k.setValue(varList, VariableIndex(2), 3)   # C max

    # Change middle variable to 0
    k.setValue(varList, VariableIndex(1), 0)

    # Verify neighbors unchanged
    check k.getValue(varList, VariableIndex(0)) == 7
    check k.getValue(varList, VariableIndex(1)) == 0
    check k.getValue(varList, VariableIndex(2)) == 3

    # Change it back and check again
    k.setValue(varList, VariableIndex(1), 10)
    check k.getValue(varList, VariableIndex(0)) == 7
    check k.getValue(varList, VariableIndex(1)) == 10
    check k.getValue(varList, VariableIndex(2)) == 3

  test "should project key preserving values for included variables":
    var k = varList.buildKey(@[
      (VariableIndex(0), 5),
      (VariableIndex(1), 10),
      (VariableIndex(2), 2)
    ])

    # Project to just A and C
    let mask = varList.buildMask(@[VariableIndex(0), VariableIndex(2)])
    let projected = k.applyMask(mask)

    # A and C should preserve their values
    check projected.getValue(varList, VariableIndex(0)) == 5
    check projected.getValue(varList, VariableIndex(2)) == 2


suite "Key boundary conditions":
  test "should handle empty key (size 0)":
    let k = initKey(0)
    check k.len == 0

  test "should handle maximum cardinality variable":
    var varList = initVariableList()
    # 65535 cardinality needs 16 bits (half a segment)
    discard varList.add(initVariable("Big", "B", Cardinality(65535)))

    var k = initKey(varList.keySize)
    k.setValue(varList, VariableIndex(0), 65534)  # Max value
    check k.getValue(varList, VariableIndex(0)) == 65534

    k.setValue(varList, VariableIndex(0), 0)  # Min value
    check k.getValue(varList, VariableIndex(0)) == 0

  test "should handle many small variables packed together":
    var varList = initVariableList()
    # 32 binary variables should all fit
    for i in 0..<32:
      discard varList.add(initVariable("V" & $i, $chr(ord('a') + (i mod 26)), Cardinality(2)))

    var k = initKey(varList.keySize)

    # Set alternating pattern
    for i in 0..<32:
      k.setValue(varList, VariableIndex(i), i mod 2)

    # Verify all values
    for i in 0..<32:
      check k.getValue(varList, VariableIndex(i)) == i mod 2

  test "should match keys with all DontCare":
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(4)))

    let k1 = initKey(varList.keySize)  # All DontCare
    let k2 = initKey(varList.keySize)  # All DontCare

    check k1.matches(k2)
    check k1.matchesWithVarList(k2, varList)


suite "Bitwise matches function (no varList)":
  ## Tests for the simplified matches function that works without variable list
  ## This function uses bitwise logic to determine matches based on DontCare semantics

  test "identical keys match":
    var k1 = initKey(1)
    k1.segments[0] = KeySegment(0b1010101010101010)
    var k2 = initKey(1)
    k2.segments[0] = KeySegment(0b1010101010101010)
    check k1.matches(k2)

  test "all DontCare matches anything":
    var kDontCare = initKey(1)  # All 1s (DontCare)
    var kSpecific = initKey(1)
    kSpecific.segments[0] = KeySegment(0b0000000011110000)
    check kDontCare.matches(kSpecific)
    check kSpecific.matches(kDontCare)

  test "different specific values do not match":
    var k1 = initKey(1)
    k1.segments[0] = KeySegment(0b0000000011110000)
    var k2 = initKey(1)
    k2.segments[0] = KeySegment(0b0000000000001111)
    check not k1.matches(k2)

  test "partial overlap with wildcards can match":
    # k1 has specific bits at positions 0-3, wildcards elsewhere
    var k1 = initKey(1)
    k1.segments[0] = KeySegment(0b1111111111110000)
    # k2 has same specific bits at positions 0-3
    var k2 = initKey(1)
    k2.segments[0] = KeySegment(0b0000000000000000)
    # They should not match because k2 has 0s where k1 has 1s (in non-wildcard positions)
    # Actually: diff = 1111...1110000 xor 0 = 1111...1110000
    # bothOnes = 1111...1110000 and 0 = 0
    # nonWildcard = not 0 = all 1s
    # diff and nonWildcard = 1111...1110000, which is != 0
    check not k1.matches(k2)

  test "partial overlap with same defined bits matches":
    # k1 and k2 have same value in defined (0) positions
    var k1 = initKey(1)
    k1.segments[0] = KeySegment(0b1111111111110000)  # 0000 defined, rest wildcard
    var k2 = initKey(1)
    k2.segments[0] = KeySegment(0b1111111111110000)  # Same pattern
    check k1.matches(k2)

  test "keys with different lengths do not match":
    let k1 = initKey(1)
    let k2 = initKey(2)
    check not k1.matches(k2)

  test "multi-segment keys match segment by segment":
    var k1 = initKey(2)
    k1.segments[0] = KeySegment(0b1010101010101010)
    k1.segments[1] = KeySegment(0b1100110011001100)
    var k2 = initKey(2)
    k2.segments[0] = KeySegment(0b1010101010101010)
    k2.segments[1] = KeySegment(0b1100110011001100)
    check k1.matches(k2)

  test "multi-segment keys mismatch in one segment fails":
    var k1 = initKey(2)
    k1.segments[0] = KeySegment(0b1010101010101010)
    k1.segments[1] = KeySegment(0b1100110011001100)
    var k2 = initKey(2)
    k2.segments[0] = KeySegment(0b1010101010101010)
    k2.segments[1] = KeySegment(0b0011001100110011)  # Different
    check not k1.matches(k2)


suite "Matching semantics verification":
  ## Tests to verify and document the matching semantics for OCCAM keys
  ## These tests establish the expected behavior for DontCare matching

  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(4)))  # 2 bits
    discard varList.add(initVariable("B", "B", Cardinality(4)))  # 2 bits

  test "matchesWithVarList and matches are consistent for full values":
    # Build keys with specific values for all variables
    let k1 = varList.buildKey(@[(VariableIndex(0), 2), (VariableIndex(1), 3)])
    let k2 = varList.buildKey(@[(VariableIndex(0), 2), (VariableIndex(1), 3)])
    let k3 = varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 3)])

    # Both matching methods should agree
    check k1.matchesWithVarList(k2, varList) == k1.matches(k2)
    check k1.matchesWithVarList(k3, varList) == k1.matches(k3)

  test "matchesWithVarList and matches agree for DontCare":
    # k1 with all DontCare
    let k1 = initKey(varList.keySize)
    # k2 with specific value
    let k2 = varList.buildKey(@[(VariableIndex(0), 2), (VariableIndex(1), 3)])

    check k1.matchesWithVarList(k2, varList) == k1.matches(k2)
    check k2.matchesWithVarList(k1, varList) == k2.matches(k1)

  test "partial DontCare matching is symmetric":
    # k1 has A=2, B=DontCare
    var k1 = initKey(varList.keySize)
    k1.setValue(varList, VariableIndex(0), 2)

    # k2 has A=DontCare, B=3
    var k2 = initKey(varList.keySize)
    k2.setValue(varList, VariableIndex(1), 3)

    # Both have wildcards in different places, so they should match
    check k1.matchesWithVarList(k2, varList)
    check k2.matchesWithVarList(k1, varList)

  test "DontCare value is all 1s in bit field":
    # When no value is set, getValue returns DontCare value
    # DontCare is represented as all 1s in the variable's bit field
    let k = initKey(varList.keySize)
    let vA = varList[VariableIndex(0)]
    let dontCareVal = k.getValue(varList, VariableIndex(0))
    # The DontCare value is 2^bits - 1 where bits = ceil(log2(cardinality + 1))
    # This reserves all-1s as DontCare distinct from any valid value
    let expectedDontCare = (1 shl vA.bitSize) - 1
    check dontCareVal == expectedDontCare

  test "matching handles boundary between variables correctly":
    # Set A to max value (3), B to 0
    let k1 = varList.buildKey(@[(VariableIndex(0), 3), (VariableIndex(1), 0)])
    # Set A to 0, B to max value (3)
    let k2 = varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 3)])

    # These should not match - different values in both positions
    check not k1.matchesWithVarList(k2, varList)
    check not k1.matches(k2)
