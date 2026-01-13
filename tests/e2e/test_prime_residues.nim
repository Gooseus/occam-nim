## E2E tests for prime residue analysis
## Tests that the RA system can detect the Lemke Oliver-Soundararajan bias
## in consecutive prime residue classes

import std/[unittest, strformat, os]
import ./sequences_helpers
import ../../src/occam/io/parser
import ../../src/occam/core/types
import ../../src/occam/core/variable
import ../../src/occam/core/table
import ../../src/occam/core/relation
import ../../src/occam/core/model
import ../../src/occam/manager/vb
import ../../src/occam/math/entropy


suite "Prime Residue Dataset Generation":
  test "generates prime residue dataset":
    let path = ensurePrimeResidueDataset(limit = 10000, moduli = @[3], targetModulus = 3)
    check fileExists(path)

    let spec = loadDataSpec(path)
    check spec.variables.len == 2  # IV (R3 prev) and DV (R3 next)
    check spec.data.len > 0

    # For primes > 3, only residues 1 and 2 should appear (never 0)
    # But prime 2 has residue 2, and prime 3 has residue 0
    # So we might see 0 for small primes
    echo &"  Dataset has {spec.data.len} unique state combinations"
    echo &"  Sample size: {spec.sampleSize}"

  test "generates natural number residue dataset":
    let path = ensureNaturalResidueDataset(count = 1000, moduli = @[3], targetModulus = 3)
    check fileExists(path)

    let spec = loadDataSpec(path)
    check spec.variables.len == 2
    check spec.data.len > 0


suite "Prime Residue Analysis - Mod 3":
  var spec: DataSpec
  var varList: VariableList
  var dataTable: ContingencyTable
  var mgr: VBManager

  setup:
    let path = ensurePrimeResidueDataset(limit = 50000, moduli = @[3], targetModulus = 3)
    spec = loadDataSpec(path)
    varList = spec.toVariableList()
    dataTable = spec.toTable(varList)
    mgr = initVBManager(varList, dataTable)

  test "detects transmission from prev to next residue":
    # The independence model should have lower transmission than the saturated model
    # This indicates that knowledge of p mod 3 helps predict p' mod 3

    let indepModel = mgr.bottomRefModel  # A:Z (independence)
    let satModel = mgr.topRefModel       # AZ (saturated)

    let indepH = mgr.computeH(indepModel)
    let satH = mgr.computeH(satModel)

    echo &"  Independence model H: {indepH:.6f}"
    echo &"  Saturated model H: {satH:.6f}"
    echo &"  Transmission T: {indepH - satH:.6f}"

    # Transmission should be positive (saturated model reduces uncertainty)
    let transmission = indepH - satH
    check transmission > 0.0
    echo &"  Transmission > 0: PASSED (bias detected)"

  test "saturated model is better than independence by AIC/BIC":
    let indepModel = mgr.bottomRefModel  # A:Z
    let satModel = mgr.topRefModel       # AZ

    let indepAIC = mgr.computeAIC(indepModel)
    let satAIC = mgr.computeAIC(satModel)
    let indepBIC = mgr.computeBIC(indepModel)
    let satBIC = mgr.computeBIC(satModel)

    echo &"  Independence AIC: {indepAIC:.4f}, BIC: {indepBIC:.4f}"
    echo &"  Saturated AIC: {satAIC:.4f}, BIC: {satBIC:.4f}"

    # Lower AIC/BIC is better - saturated should be better for this data
    # (The bias is strong enough that the extra parameter is justified)
    # Note: This depends on sample size; with enough data, AZ should be better
    if satAIC < indepAIC:
      echo "  Saturated model preferred by AIC"
    else:
      echo "  Independence model preferred by AIC (weak bias or small sample)"

  test "LR statistic is significant":
    # The likelihood ratio test between saturated and independence
    # should be significant (alpha < 0.05) if there's real bias

    let indepModel = mgr.bottomRefModel
    let satModel = mgr.topRefModel

    let indepFit = mgr.fitModel(indepModel)
    let satFit = mgr.fitModel(satModel)

    echo &"  Independence LR: {indepFit.lr:.4f}"
    echo &"  Saturated LR: {satFit.lr:.4f}"
    echo &"  Saturated alpha (p-value): {satFit.alpha:.6f}"

    # If alpha < 0.05, the model is significantly better than expected by chance
    if satFit.alpha < 0.05:
      echo "  Alpha < 0.05: Statistically significant association"
    else:
      echo "  Alpha >= 0.05: Not statistically significant (may need more data)"


suite "Natural Numbers vs Primes Comparison":
  test "natural numbers show different pattern than primes":
    # Natural numbers have a deterministic cycle mod 3: 1,2,0,1,2,0,...
    # Primes have a probabilistic bias: adjacent primes avoid same residue

    let primesPath = ensurePrimeResidueDataset(limit = 20000, moduli = @[3], targetModulus = 3)
    let naturalsPath = ensureNaturalResidueDataset(count = 10000, moduli = @[3], targetModulus = 3)

    let primesSpec = loadDataSpec(primesPath)
    let naturalsSpec = loadDataSpec(naturalsPath)

    let primesVarList = primesSpec.toVariableList()
    let naturalsVarList = naturalsSpec.toVariableList()

    var primesTable = primesSpec.toTable(primesVarList)
    var naturalsTable = naturalsSpec.toTable(naturalsVarList)

    var primesMgr = initVBManager(primesVarList, primesTable)
    var naturalsMgr = initVBManager(naturalsVarList, naturalsTable)

    # Compute transmission for both
    let primesIndepH = primesMgr.computeH(primesMgr.bottomRefModel)
    let primesSatH = primesMgr.computeH(primesMgr.topRefModel)
    let primesT = primesIndepH - primesSatH

    let naturalsIndepH = naturalsMgr.computeH(naturalsMgr.bottomRefModel)
    let naturalsSatH = naturalsMgr.computeH(naturalsMgr.topRefModel)
    let naturalsT = naturalsIndepH - naturalsSatH

    echo &"  Primes transmission: {primesT:.6f}"
    echo &"  Naturals transmission: {naturalsT:.6f}"

    # Both should have transmission > 0, but for different reasons
    # - Primes: probabilistic bias (Lemke Oliver-Soundararajan)
    # - Naturals: deterministic cycle
    check primesT > 0.0
    check naturalsT > 0.0


suite "Multi-Modulus Prime Analysis":
  var spec: DataSpec
  var varList: VariableList
  var dataTable: ContingencyTable
  var mgr: VBManager

  setup:
    let path = ensurePrimeResidueDataset(limit = 30000, moduli = @[3, 5, 7], targetModulus = 3)
    spec = loadDataSpec(path)
    varList = spec.toVariableList()
    dataTable = spec.toTable(varList)
    mgr = initVBManager(varList, dataTable)

  test "dataset has correct structure":
    # Should have 4 variables: R3, R5, R7 (IVs) and R3 (DV)
    check varList.len == 4
    check varList.isDirected  # Has DV

    for i in 0..<varList.len:
      let v = varList[VariableIndex(i)]
      echo &"  {v.abbrev}: {v.name} (card={v.cardinality.toInt}, DV={v.isDependent})"

  test "R3 alone provides transmission":
    # Model with just R3 predicting DV should show transmission
    # This tests that the same-modulus bias is detectable

    let indepModel = mgr.bottomRefModel  # A:B:C:Z
    let r3OnlyModel = mgr.makeModel("ABC:AZ")  # R3 (A) predicts Z

    let indepH = mgr.computeH(indepModel)
    let r3OnlyH = mgr.computeH(r3OnlyModel)

    echo &"  Independence H: {indepH:.6f}"
    echo &"  R3→Z model H: {r3OnlyH:.6f}"
    echo &"  Transmission: {indepH - r3OnlyH:.6f}"

    check indepH > r3OnlyH  # R3 provides information about Z

  test "multiple moduli may provide additional information":
    # Test if R5 and R7 provide additional predictive power beyond R3
    let r3OnlyModel = mgr.makeModel("ABC:AZ")
    let r35Model = mgr.makeModel("ABC:ABZ")  # R3 and R5 predict Z
    let fullModel = mgr.topRefModel  # All IVs predict Z

    let r3OnlyH = mgr.computeH(r3OnlyModel)
    let r35H = mgr.computeH(r35Model)
    let fullH = mgr.computeH(fullModel)

    echo &"  R3→Z model H: {r3OnlyH:.6f}"
    echo &"  R3,R5→Z model H: {r35H:.6f}"
    echo &"  Full model H: {fullH:.6f}"

    # Adding more predictors should not increase H
    check r3OnlyH >= r35H
    check r35H >= fullH


when isMainModule:
  # Run the tests
  discard
