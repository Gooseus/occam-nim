## Test suite for entropy module
## Tests Shannon entropy and transmission (KL divergence) calculations

import std/math
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table
import ../src/occam/math/entropy

suite "Shannon entropy":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(4)))

  test "entropy of uniform distribution":
    # Uniform distribution over 4 states: H = log2(4) = 2.0
    var t = initContingencyTable(varList.keySize)
    t.add(varList.buildKey(@[(VariableIndex(0), 0)]), 0.25)
    t.add(varList.buildKey(@[(VariableIndex(0), 1)]), 0.25)
    t.add(varList.buildKey(@[(VariableIndex(0), 2)]), 0.25)
    t.add(varList.buildKey(@[(VariableIndex(0), 3)]), 0.25)

    let h = entropy(t)
    check abs(h - 2.0) < 1e-10

  test "entropy of deterministic distribution":
    # Single state with prob 1: H = 0
    var t = initContingencyTable(varList.keySize)
    t.add(varList.buildKey(@[(VariableIndex(0), 0)]), 1.0)

    let h = entropy(t)
    check abs(h) < 1e-10

  test "entropy of binary 50-50":
    # Binary uniform: H = log2(2) = 1.0
    var t = initContingencyTable(varList.keySize)
    t.add(varList.buildKey(@[(VariableIndex(0), 0)]), 0.5)
    t.add(varList.buildKey(@[(VariableIndex(0), 1)]), 0.5)

    let h = entropy(t)
    check abs(h - 1.0) < 1e-10

  test "entropy of skewed binary":
    # p=0.9, q=0.1: H = -0.9*log2(0.9) - 0.1*log2(0.1)
    var t = initContingencyTable(varList.keySize)
    t.add(varList.buildKey(@[(VariableIndex(0), 0)]), 0.9)
    t.add(varList.buildKey(@[(VariableIndex(0), 1)]), 0.1)

    let expected = -0.9 * log2(0.9) - 0.1 * log2(0.1)
    let h = entropy(t)
    check abs(h - expected) < 1e-10

  test "entropy ignores zero probabilities":
    # Should handle 0 probability without NaN
    var t = initContingencyTable(varList.keySize)
    t.add(varList.buildKey(@[(VariableIndex(0), 0)]), 1.0)
    t.add(varList.buildKey(@[(VariableIndex(0), 1)]), 0.0)

    let h = entropy(t)
    check abs(h) < 1e-10  # Same as deterministic

  test "entropy of empty table":
    var t = initContingencyTable(varList.keySize)
    let h = entropy(t)
    check abs(h) < 1e-10

suite "Transmission (KL divergence)":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(4)))

  test "transmission of identical distributions":
    # KL(P||P) = 0
    var p = initContingencyTable(varList.keySize)
    p.add(varList.buildKey(@[(VariableIndex(0), 0)]), 0.5)
    p.add(varList.buildKey(@[(VariableIndex(0), 1)]), 0.5)
    p.sort()

    var q = initContingencyTable(varList.keySize)
    q.add(varList.buildKey(@[(VariableIndex(0), 0)]), 0.5)
    q.add(varList.buildKey(@[(VariableIndex(0), 1)]), 0.5)
    q.sort()

    let t = transmission(p, q)
    check abs(t) < 1e-10

  test "transmission is non-negative":
    var p = initContingencyTable(varList.keySize)
    p.add(varList.buildKey(@[(VariableIndex(0), 0)]), 0.9)
    p.add(varList.buildKey(@[(VariableIndex(0), 1)]), 0.1)
    p.sort()

    var q = initContingencyTable(varList.keySize)
    q.add(varList.buildKey(@[(VariableIndex(0), 0)]), 0.5)
    q.add(varList.buildKey(@[(VariableIndex(0), 1)]), 0.5)
    q.sort()

    let t = transmission(p, q)
    check t >= 0

  test "transmission calculation":
    # KL(P||Q) where P = (0.9, 0.1), Q = (0.5, 0.5)
    # T = 0.9*log2(0.9/0.5) + 0.1*log2(0.1/0.5)
    var p = initContingencyTable(varList.keySize)
    p.add(varList.buildKey(@[(VariableIndex(0), 0)]), 0.9)
    p.add(varList.buildKey(@[(VariableIndex(0), 1)]), 0.1)
    p.sort()

    var q = initContingencyTable(varList.keySize)
    q.add(varList.buildKey(@[(VariableIndex(0), 0)]), 0.5)
    q.add(varList.buildKey(@[(VariableIndex(0), 1)]), 0.5)
    q.sort()

    let expected = 0.9 * log2(0.9/0.5) + 0.1 * log2(0.1/0.5)
    let t = transmission(p, q)
    check abs(t - expected) < 1e-10

suite "Mutual information (as transmission)":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))

  test "mutual information of independent variables":
    # For independent variables: I(A;B) = H(AB) - H(A|B) * ...
    # Actually: T = H(A) + H(B) - H(AB) for joint distribution
    # If A,B independent: p(a,b) = p(a)*p(b), so H(AB) = H(A) + H(B), T = 0

    # Joint distribution for independent A,B (uniform marginals)
    var joint = initContingencyTable(varList.keySize)
    joint.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)]), 0.25)
    joint.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 1)]), 0.25)
    joint.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 0)]), 0.25)
    joint.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)]), 0.25)
    joint.sort()

    let hJoint = entropy(joint)
    let hA = entropy(joint.project(varList, @[VariableIndex(0)]))
    let hB = entropy(joint.project(varList, @[VariableIndex(1)]))

    # Mutual information I(A;B) = H(A) + H(B) - H(A,B)
    let mi = hA + hB - hJoint
    check abs(mi) < 1e-10  # Should be 0 for independent

  test "mutual information of perfectly correlated variables":
    # Perfect correlation: A = B always
    var joint = initContingencyTable(varList.keySize)
    joint.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0)]), 0.5)
    joint.add(varList.buildKey(@[(VariableIndex(0), 1), (VariableIndex(1), 1)]), 0.5)
    joint.sort()

    let hJoint = entropy(joint)
    let hA = entropy(joint.project(varList, @[VariableIndex(0)]))
    let hB = entropy(joint.project(varList, @[VariableIndex(1)]))

    # I(A;B) = H(A) = H(B) = 1 bit for perfect correlation
    let mi = hA + hB - hJoint
    check abs(mi - 1.0) < 1e-10

suite "Max entropy":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(3)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))

  test "max entropy equals log2 of state space":
    # For 3x2=6 states, max entropy is log2(6)
    let expected = log2(6.0)
    check abs(maxEntropy(varList) - expected) < 1e-10

  test "max entropy from relation":
    # For relation AB with 3x2=6 states
    let expected = log2(6.0)
    check abs(maxEntropyForRelation(varList, @[VariableIndex(0), VariableIndex(1)]) - expected) < 1e-10

  test "max entropy for single variable":
    let expected = log2(3.0)
    check abs(maxEntropyForRelation(varList, @[VariableIndex(0)]) - expected) < 1e-10

