## Test suite for statistics module
## Tests degrees of freedom, likelihood ratio, AIC, BIC, and p-values

import std/math
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/math/statistics

suite "Degrees of freedom - Relation":
  setup:
    var varList = initVariableList()
    # A: 3 values, B: 2 values, C: 4 values
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(4)))

  test "df for single variable relation":
    let r = initRelation(@[VariableIndex(0)])
    check relationDF(r, varList) == 2  # 3 - 1

  test "df for two variable relation":
    let r = initRelation(@[VariableIndex(0), VariableIndex(1)])
    check relationDF(r, varList) == 5  # 3*2 - 1

  test "df for full relation":
    let r = initRelation(@[VariableIndex(0), VariableIndex(1), VariableIndex(2)])
    check relationDF(r, varList) == 23  # 3*2*4 - 1

suite "Degrees of freedom - Model":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(4)))

  test "df for independence model":
    # Independence model A:B:C
    # DF = DF(A) + DF(B) + DF(C) = 2 + 1 + 3 = 6
    let m = createIndependenceModel(varList)
    check modelDF(m, varList) == 6

  test "df for saturated model":
    # Saturated model ABC
    # DF = NC - 1 = 3*2*4 - 1 = 23 free parameters
    let m = createSaturatedModel(varList)
    check modelDF(m, varList) == 23

  test "df for intermediate model":
    # Model AB:C
    # DF = NC(ABC) - 1 - (NC(AB) - 1) - (NC(C) - 1)
    # DF = 23 - 5 - 3 = 15
    # Actually for non-orthogonal models it's more complex
    # Let's use the simpler formula: DF(data) - DF(model)
    # where DF(model) = sum of relation DFs minus overlaps
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rC = initRelation(@[VariableIndex(2)])
    let m = initModel(@[rAB, rC])

    # For orthogonal models (no overlaps): sum of relation DFs
    # DF = 5 + 3 = 8
    check modelDF(m, varList) == 8

  test "df for model with overlap":
    # Model AB:BC - has overlap on B
    # This requires more complex calculation
    let rAB = initRelation(@[VariableIndex(0), VariableIndex(1)])
    let rBC = initRelation(@[VariableIndex(1), VariableIndex(2)])
    let m = initModel(@[rAB, rBC])

    # For models with overlaps, use inclusion-exclusion
    # DF = DF(AB) + DF(BC) - DF(B) = 5 + 7 - 1 = 11
    check modelDF(m, varList) == 11

suite "Delta degrees of freedom":
  setup:
    var varList = initVariableList()
    discard varList.add(initVariable("A", "A", Cardinality(3)))
    discard varList.add(initVariable("B", "B", Cardinality(2)))
    discard varList.add(initVariable("C", "C", Cardinality(4)))

  test "ddf from independence to saturated":
    # ΔDF = DF(m1) - DF(m2)
    # DF(indep) = 6, DF(sat) = 23
    # ΔDF = 6 - 23 = -17
    # Negative because saturated model has more parameters
    let indep = createIndependenceModel(varList)
    let sat = createSaturatedModel(varList)

    let ddf = deltaDF(indep, sat, varList)
    check ddf == -17

suite "Likelihood ratio":
  test "LR formula":
    # LR = 2 * N * ln(2) * (Hmax - H)
    # where Hmax = log2(NC)
    let n = 100.0
    let hMax = 2.0  # log2(4)
    let hModel = 1.5
    let expected = 2.0 * n * ln(2.0) * (hMax - hModel)

    check abs(likelihoodRatio(n, hMax, hModel) - expected) < 1e-10

  test "LR is zero when H equals Hmax":
    let n = 100.0
    let h = 2.0
    check abs(likelihoodRatio(n, h, h)) < 1e-10

suite "Chi-squared p-value":
  test "p-value for zero chi-squared":
    # When chi-squared = 0, p-value should be 1.0
    let p = chiSquaredPValue(0.0, 5.0)
    check abs(p - 1.0) < 1e-5

  test "p-value for large chi-squared":
    # Large chi-squared should give small p-value
    let p = chiSquaredPValue(100.0, 5.0)
    check p < 0.001

  test "p-value is between 0 and 1":
    let p = chiSquaredPValue(10.0, 5.0)
    check p >= 0.0
    check p <= 1.0

  test "p-value decreases with larger chi-squared":
    let p1 = chiSquaredPValue(5.0, 5.0)
    let p2 = chiSquaredPValue(10.0, 5.0)
    check p2 < p1

  test "known p-value at df=1":
    # chi-squared = 3.841 at df=1 gives p ≈ 0.05
    let p = chiSquaredPValue(3.841, 1.0)
    check abs(p - 0.05) < 0.01

suite "AIC and BIC":
  test "AIC formula":
    # AIC = LR - 2*DF
    let lr = 50.0
    let df = 10.0
    check abs(aic(lr, df) - 30.0) < 1e-10

  test "BIC formula":
    # BIC = LR - DF*ln(N)
    let lr = 50.0
    let df = 10.0
    let n = 100.0
    let expected = lr - df * ln(n)
    check abs(bic(lr, df, n) - expected) < 1e-10

  test "AIC favors simpler models":
    # Model with lower AIC is preferred
    # More DF (simpler) reduces AIC for same LR
    let lr = 50.0
    let aic1 = aic(lr, 5.0)   # More complex (fewer DF)
    let aic2 = aic(lr, 15.0)  # Simpler (more DF)
    check aic2 < aic1

suite "Uncertainty coefficient":
  test "uncertainty equals 1 for saturated":
    # When H(model) = 0, U = (Hmax - 0) / Hmax = 1
    let hMax = 2.0
    let hModel = 0.0
    check abs(uncertaintyCoefficient(hMax, hModel) - 1.0) < 1e-10

  test "uncertainty equals 0 for independence":
    # When H(model) = Hmax, U = 0
    let hMax = 2.0
    check abs(uncertaintyCoefficient(hMax, hMax)) < 1e-10

  test "uncertainty is between 0 and 1":
    let u = uncertaintyCoefficient(2.0, 1.5)
    check u >= 0.0
    check u <= 1.0

