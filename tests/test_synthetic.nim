## Test suite for synthetic data generator
## Tests generation of data from known graphical models

import std/[random, math, strutils, sequtils]
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/math/entropy
import ../src/occam/io/synthetic
import ../src/occam/manager/vb

# Seed for reproducibility
randomize(42)

suite "Independent model":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

  test "generates valid samples":
    let model = createIndependentModel(varList)
    let samples = model.generateSamples(100)

    check samples.len == 100
    for sample in samples:
      check sample.len == 3
      for i, v in sample:
        check v >= 0
        check v < varList[VariableIndex(i)].cardinality.toInt

  test "samples are roughly uniform for independent model":
    let model = createIndependentModel(varList)
    let samples = model.generateSamples(1000)
    var table = model.samplesToTable(samples)

    # With 8 states and 1000 samples, each state should have ~125 samples
    # Allow large variance for statistical test
    table.normalize()
    let h = entropy(table)
    # Max entropy for 8 states = log2(8) = 3.0
    # Should be close to max for uniform
    check h > 2.5  # Pretty close to uniform

  test "mutual information is near zero for independent variables":
    let model = createIndependentModel(varList)
    let samples = model.generateSamples(5000)
    var table = model.samplesToTable(samples)
    table.normalize()

    # Project to pairs and check mutual information
    let projAB = table.project(varList, @[VariableIndex(0), VariableIndex(1)])
    let projA = table.project(varList, @[VariableIndex(0)])
    let projB = table.project(varList, @[VariableIndex(1)])

    let hAB = entropy(projAB)
    let hA = entropy(projA)
    let hB = entropy(projB)
    let mi = hA + hB - hAB

    # MI should be near 0 for independent variables
    check abs(mi) < 0.1

suite "Chain model (Markov chain)":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

  test "chain model has structure A→B→C":
    let model = createChainModel(varList, 0.9)
    let samples = model.generateSamples(5000)
    var table = model.samplesToTable(samples)
    table.normalize()

    # AB should have high mutual information
    let projAB = table.project(varList, @[VariableIndex(0), VariableIndex(1)])
    let projA = table.project(varList, @[VariableIndex(0)])
    let projB = table.project(varList, @[VariableIndex(1)])
    let miAB = entropy(projA) + entropy(projB) - entropy(projAB)

    # BC should have high mutual information
    let projBC = table.project(varList, @[VariableIndex(1), VariableIndex(2)])
    let projC = table.project(varList, @[VariableIndex(2)])
    let miBC = entropy(projB) + entropy(projC) - entropy(projBC)

    check miAB > 0.2  # Significant dependence
    check miBC > 0.2  # Significant dependence

  test "conditional independence: A ⊥ C | B":
    # In a chain A→B→C, A and C are conditionally independent given B
    # This means I(A;C|B) ≈ 0, or equivalently I(A;C) < I(A;B) and I(A;C) < I(B;C)
    let model = createChainModel(varList, 0.9)
    let samples = model.generateSamples(5000)
    var table = model.samplesToTable(samples)
    table.normalize()

    let projAC = table.project(varList, @[VariableIndex(0), VariableIndex(2)])
    let projA = table.project(varList, @[VariableIndex(0)])
    let projC = table.project(varList, @[VariableIndex(2)])
    let miAC = entropy(projA) + entropy(projC) - entropy(projAC)

    let projAB = table.project(varList, @[VariableIndex(0), VariableIndex(1)])
    let projB = table.project(varList, @[VariableIndex(1)])
    let miAB = entropy(projA) + entropy(projB) - entropy(projAB)

    # AC dependence should be weaker than direct dependencies
    # (A and C are only related through B)
    check miAC < miAB

suite "Star model":
  setup:
    var varList = initVariableList()
    # Center variable must be first (index 0) for correct sampling order
    discard varList.add(initVariable("B", "B", Cardinality(2)))  # Center at index 0
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(2)))

  test "star model with B as center":
    let model = createStarModel(varList, VariableIndex(0), 0.9)  # B is at index 0
    let samples = model.generateSamples(5000)
    var table = model.samplesToTable(samples)
    table.normalize()

    let projB = table.project(varList, @[VariableIndex(0)])  # B
    let projA = table.project(varList, @[VariableIndex(1)])  # A
    let projC = table.project(varList, @[VariableIndex(2)])  # C

    let projAB = table.project(varList, @[VariableIndex(0), VariableIndex(1)])  # BA
    let projBC = table.project(varList, @[VariableIndex(0), VariableIndex(2)])  # BC
    let projAC = table.project(varList, @[VariableIndex(1), VariableIndex(2)])  # AC

    let miAB = entropy(projA) + entropy(projB) - entropy(projAB)
    let miBC = entropy(projB) + entropy(projC) - entropy(projBC)
    let miAC = entropy(projA) + entropy(projC) - entropy(projAC)

    # A and C both depend on B (center), so AB and BC have high MI
    check miAB > 0.2
    check miBC > 0.2

    # A and C are conditionally independent given B, so AC MI is weaker
    check miAC < miAB
    check miAC < miBC

suite "Convert to table":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(2)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))

  test "table has correct sum":
    let model = createIndependentModel(varList)
    let samples = model.generateSamples(100)
    let table = model.samplesToTable(samples)

    check table.sum == 100.0

  test "table is sorted":
    let model = createIndependentModel(varList)
    let samples = model.generateSamples(50)
    let table = model.samplesToTable(samples)

    # Verify sorted order
    for i in 1..<table.len:
      check table[i-1].key < table[i].key

suite "Reproducibility":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(3)))

  test "same seed gives same samples":
    randomize(123)
    let model1 = createChainModel(varList, 0.8)
    let samples1 = model1.generateSamples(10)

    randomize(123)
    let model2 = createChainModel(varList, 0.8)
    let samples2 = model2.generateSamples(10)

    check samples1 == samples2


# ============ Tests for createModelFromSpec() ============

suite "Parse variable specification":
  test "parse A:2,B:2,C:2":
    let varList = parseVariableSpec("A:2,B:2,C:2")
    check varList.len == 3
    check varList[VariableIndex(0)].abbrev == "A"
    check varList[VariableIndex(0)].cardinality.toInt == 2
    check varList[VariableIndex(1)].abbrev == "B"
    check varList[VariableIndex(2)].abbrev == "C"

  test "parse with different cardinalities":
    let varList = parseVariableSpec("X:3,Y:4,Z:2")
    check varList.len == 3
    check varList[VariableIndex(0)].cardinality.toInt == 3
    check varList[VariableIndex(1)].cardinality.toInt == 4
    check varList[VariableIndex(2)].cardinality.toInt == 2


suite "Create model from spec - Independence":
  setup:
    randomize(42)
    let varList = parseVariableSpec("A:2,B:2,C:2")

  test "A:B:C creates independent model":
    let (gm, _) = createModelFromSpec(varList, "A:B:C", strength = 0.9)
    let samples = gm.generateSamples(2000)
    var table = gm.samplesToTable(samples)
    table.normalize()

    # All pairs should have near-zero mutual information
    let projA = table.project(varList, @[VariableIndex(0)])
    let projB = table.project(varList, @[VariableIndex(1)])
    let projAB = table.project(varList, @[VariableIndex(0), VariableIndex(1)])
    let miAB = entropy(projA) + entropy(projB) - entropy(projAB)

    check abs(miAB) < 0.15  # Near-zero MI for independent variables


suite "Create model from spec - Chain":
  setup:
    randomize(42)
    let varList = parseVariableSpec("A:2,B:2,C:2")

  test "AB:BC creates chain A-B-C":
    let (gm, _) = createModelFromSpec(varList, "AB:BC", strength = 0.9)
    let samples = gm.generateSamples(5000)
    var table = gm.samplesToTable(samples)
    table.normalize()

    # AB and BC should have high MI
    let projA = table.project(varList, @[VariableIndex(0)])
    let projB = table.project(varList, @[VariableIndex(1)])
    let projC = table.project(varList, @[VariableIndex(2)])
    let projAB = table.project(varList, @[VariableIndex(0), VariableIndex(1)])
    let projBC = table.project(varList, @[VariableIndex(1), VariableIndex(2)])
    let projAC = table.project(varList, @[VariableIndex(0), VariableIndex(2)])

    let miAB = entropy(projA) + entropy(projB) - entropy(projAB)
    let miBC = entropy(projB) + entropy(projC) - entropy(projBC)
    let miAC = entropy(projA) + entropy(projC) - entropy(projAC)

    check miAB > 0.2  # Strong AB dependence
    check miBC > 0.2  # Strong BC dependence
    check miAC < miAB  # AC weaker (conditional independence)


suite "Create model from spec - Star":
  setup:
    randomize(42)
    let varList = parseVariableSpec("A:2,B:2,C:2,D:2")

  test "AB:AC:AD creates star with A as center":
    let (gm, _) = createModelFromSpec(varList, "AB:AC:AD", strength = 0.9)
    let samples = gm.generateSamples(5000)
    var table = gm.samplesToTable(samples)
    table.normalize()

    # A is connected to B, C, D
    let projA = table.project(varList, @[VariableIndex(0)])
    let projB = table.project(varList, @[VariableIndex(1)])
    let projC = table.project(varList, @[VariableIndex(2)])
    let projD = table.project(varList, @[VariableIndex(3)])

    let projAB = table.project(varList, @[VariableIndex(0), VariableIndex(1)])
    let projAC = table.project(varList, @[VariableIndex(0), VariableIndex(2)])
    let projBC = table.project(varList, @[VariableIndex(1), VariableIndex(2)])

    let miAB = entropy(projA) + entropy(projB) - entropy(projAB)
    let miAC = entropy(projA) + entropy(projC) - entropy(projAC)
    let miBC = entropy(projB) + entropy(projC) - entropy(projBC)

    check miAB > 0.2  # A-B connected
    check miAC > 0.2  # A-C connected
    check miBC < miAB  # B-C weaker (conditionally independent given A)


suite "Create model from spec - Saturated":
  setup:
    randomize(42)
    let varList = parseVariableSpec("A:2,B:2,C:2")

  test "ABC creates saturated model":
    let (gm, _) = createModelFromSpec(varList, "ABC", strength = 0.9)
    let samples = gm.generateSamples(5000)
    var table = gm.samplesToTable(samples)
    table.normalize()

    # The saturated model is a DAG: A -> B, (A,B) -> C
    # AB should have high MI, but BC and AC may have lower MI
    # since dependence flows through the DAG structure
    let projA = table.project(varList, @[VariableIndex(0)])
    let projB = table.project(varList, @[VariableIndex(1)])

    let projAB = table.project(varList, @[VariableIndex(0), VariableIndex(1)])

    let miAB = entropy(projA) + entropy(projB) - entropy(projAB)

    # At minimum, the first pair should have strong dependence
    check miAB > 0.2

    # Total correlation should be significant (variables are not independent)
    let hData = entropy(table)
    let hIndep = entropy(projA) + entropy(projB) + entropy(table.project(varList, @[VariableIndex(2)]))
    let totalCorr = hIndep - hData
    check totalCorr > 0.1  # Significant total correlation


suite "Create model from spec - Loop models":
  setup:
    randomize(42)
    let varList = parseVariableSpec("A:2,B:2,C:2")

  test "AB:BC:AC creates triangle (loop model)":
    let (gm, hasLoops) = createModelFromSpec(varList, "AB:BC:AC", strength = 0.8)
    check hasLoops == true

    let samples = gm.generateSamples(5000)
    var table = gm.samplesToTable(samples)
    table.normalize()

    # All three pairs should have dependence
    let projA = table.project(varList, @[VariableIndex(0)])
    let projB = table.project(varList, @[VariableIndex(1)])
    let projC = table.project(varList, @[VariableIndex(2)])

    let projAB = table.project(varList, @[VariableIndex(0), VariableIndex(1)])
    let projBC = table.project(varList, @[VariableIndex(1), VariableIndex(2)])
    let projAC = table.project(varList, @[VariableIndex(0), VariableIndex(2)])

    let miAB = entropy(projA) + entropy(projB) - entropy(projAB)
    let miBC = entropy(projB) + entropy(projC) - entropy(projBC)
    let miAC = entropy(projA) + entropy(projC) - entropy(projAC)

    # For loop models generated via IPF, the dependencies should exist
    check miAB > 0.1
    check miBC > 0.1
    check miAC > 0.1

  test "AB:BC is loopless":
    let (_, hasLoops) = createModelFromSpec(varList, "AB:BC", strength = 0.8)
    check hasLoops == false

  test "A:B:C is loopless":
    let (_, hasLoops) = createModelFromSpec(varList, "A:B:C", strength = 0.8)
    check hasLoops == false


suite "Create model from spec - Data recovery":
  setup:
    randomize(42)

  test "chain model recoverable by VB search":
    let varList = parseVariableSpec("A:2,B:2,C:2")
    let (gm, _) = createModelFromSpec(varList, "AB:BC", strength = 0.9)
    let samples = gm.generateSamples(5000)
    var table = gm.samplesToTable(samples)

    # Create VB manager and fit the expected model
    var mgr = initVBManager(varList, table)
    let chainModel = mgr.makeModel("AB:BC")
    let fitResult = mgr.fitModel(chainModel)

    # The chain model should fit well (low LR, high p-value)
    check fitResult.alpha > 0.01  # Not rejected at 1% level

  test "loop model recoverable by VB fit":
    let varList = parseVariableSpec("A:2,B:2,C:2")
    let (gm, hasLoops) = createModelFromSpec(varList, "AB:BC:AC", strength = 0.8)
    check hasLoops == true

    let samples = gm.generateSamples(5000)
    var table = gm.samplesToTable(samples)

    # Create VB manager and fit the triangle model
    var mgr = initVBManager(varList, table)
    let triangleModel = mgr.makeModel("AB:BC:AC")
    let fitResult = mgr.fitModel(triangleModel)

    # The triangle model should fit well
    check fitResult.hasLoops == true
    check fitResult.alpha > 0.01  # Not rejected at 1% level

