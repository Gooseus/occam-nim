## Tests for Pearson chi-squared (P2) statistic

import std/unittest
import std/math
import ../src/occam/math/statistics
import ../src/occam/core/table
import ../src/occam/core/types
import ../src/occam/core/key
import ../src/occam/core/variable

suite "Pearson Chi-Squared (P2)":

  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(4)))

  test "P2 formula: sum of (O-E)^2 / E":
    # Simple case: 4 cells
    # Observed: [10, 20, 30, 40]  (total = 100, probs = 0.1, 0.2, 0.3, 0.4)
    # Expected: [25, 25, 25, 25]  (uniform, probs = 0.25 each)
    # P2 = (10-25)^2/25 + (20-25)^2/25 + (30-25)^2/25 + (40-25)^2/25
    #    = 225/25 + 25/25 + 25/25 + 225/25
    #    = 9 + 1 + 1 + 9 = 20

    var observed = initTable(varList.keySize)
    observed.add(varList.buildKey(@[(VariableIndex(0), 0)]), 0.10)
    observed.add(varList.buildKey(@[(VariableIndex(0), 1)]), 0.20)
    observed.add(varList.buildKey(@[(VariableIndex(0), 2)]), 0.30)
    observed.add(varList.buildKey(@[(VariableIndex(0), 3)]), 0.40)
    observed.sort()

    var expected = initTable(varList.keySize)
    expected.add(varList.buildKey(@[(VariableIndex(0), 0)]), 0.25)
    expected.add(varList.buildKey(@[(VariableIndex(0), 1)]), 0.25)
    expected.add(varList.buildKey(@[(VariableIndex(0), 2)]), 0.25)
    expected.add(varList.buildKey(@[(VariableIndex(0), 3)]), 0.25)
    expected.sort()

    let p2 = pearsonChiSquared(observed, expected, sampleSize = 100.0)
    check abs(p2 - 20.0) < 0.001

  test "P2 is zero when observed equals expected":
    var observed = initTable(varList.keySize)
    observed.add(varList.buildKey(@[(VariableIndex(0), 0)]), 0.25)
    observed.add(varList.buildKey(@[(VariableIndex(0), 1)]), 0.25)
    observed.add(varList.buildKey(@[(VariableIndex(0), 2)]), 0.25)
    observed.add(varList.buildKey(@[(VariableIndex(0), 3)]), 0.25)
    observed.sort()

    var expected = initTable(varList.keySize)
    expected.add(varList.buildKey(@[(VariableIndex(0), 0)]), 0.25)
    expected.add(varList.buildKey(@[(VariableIndex(0), 1)]), 0.25)
    expected.add(varList.buildKey(@[(VariableIndex(0), 2)]), 0.25)
    expected.add(varList.buildKey(@[(VariableIndex(0), 3)]), 0.25)
    expected.sort()

    let p2 = pearsonChiSquared(observed, expected, sampleSize = 100.0)
    check abs(p2) < 0.001

  test "P2 handles cells only in expected (observed = 0)":
    # If O=0 and E>0, contribution is (0-E)^2/E = E
    var observed = initTable(varList.keySize)
    observed.add(varList.buildKey(@[(VariableIndex(0), 0)]), 0.50)
    observed.add(varList.buildKey(@[(VariableIndex(0), 1)]), 0.50)
    # No key [2] or [3]
    observed.sort()

    var expected = initTable(varList.keySize)
    expected.add(varList.buildKey(@[(VariableIndex(0), 0)]), 0.25)
    expected.add(varList.buildKey(@[(VariableIndex(0), 1)]), 0.25)
    expected.add(varList.buildKey(@[(VariableIndex(0), 2)]), 0.25)
    expected.add(varList.buildKey(@[(VariableIndex(0), 3)]), 0.25)
    expected.sort()

    # P2 = (50-25)^2/25 + (50-25)^2/25 + (0-25)^2/25 + (0-25)^2/25
    #    = 625/25 + 625/25 + 625/25 + 625/25
    #    = 25 + 25 + 25 + 25 = 100
    let p2 = pearsonChiSquared(observed, expected, sampleSize = 100.0)
    check abs(p2 - 100.0) < 0.001

  test "P2 skips cells with E=0":
    # If E=0 and O>0, skip (would be division by zero)
    var observed = initTable(varList.keySize)
    observed.add(varList.buildKey(@[(VariableIndex(0), 0)]), 0.50)
    observed.add(varList.buildKey(@[(VariableIndex(0), 1)]), 0.50)
    observed.sort()

    var expected = initTable(varList.keySize)
    expected.add(varList.buildKey(@[(VariableIndex(0), 0)]), 1.0)
    # Key [1] has no expected value (E=0)
    expected.sort()

    # Only count cell 0: (50-100)^2/100 = 2500/100 = 25
    let p2 = pearsonChiSquared(observed, expected, sampleSize = 100.0)
    check abs(p2 - 25.0) < 0.001

  test "P2 scales with sample size":
    # P2 = N * sum of (p_obs - p_exp)^2 / p_exp
    var observed = initTable(varList.keySize)
    observed.add(varList.buildKey(@[(VariableIndex(0), 0)]), 0.40)
    observed.add(varList.buildKey(@[(VariableIndex(0), 1)]), 0.60)
    observed.sort()

    var expected = initTable(varList.keySize)
    expected.add(varList.buildKey(@[(VariableIndex(0), 0)]), 0.50)
    expected.add(varList.buildKey(@[(VariableIndex(0), 1)]), 0.50)
    expected.sort()

    # For N=100: P2 = 100 * [(0.4-0.5)^2/0.5 + (0.6-0.5)^2/0.5]
    #               = 100 * [0.01/0.5 + 0.01/0.5]
    #               = 100 * [0.02 + 0.02] = 100 * 0.04 = 4
    let p2_100 = pearsonChiSquared(observed, expected, sampleSize = 100.0)
    check abs(p2_100 - 4.0) < 0.001

    # For N=200: P2 should double
    let p2_200 = pearsonChiSquared(observed, expected, sampleSize = 200.0)
    check abs(p2_200 - 8.0) < 0.001
