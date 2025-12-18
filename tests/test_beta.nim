## Tests for Beta (statistical power) and non-central chi-squared

import std/unittest
import std/math
import ../src/occam/math/statistics

suite "Non-Central Chi-Squared CDF":

  test "central chi-squared (lambda=0) matches regular chi-squared":
    # When noncentrality = 0, should match regular chi-squared CDF
    # P(X <= 5.991 | df=2) ≈ 0.95 for central chi-squared
    let ncCdf = noncentralChiSquaredCDF(5.991, 2.0, 0.0)
    let centralPval = chiSquaredPValue(5.991, 2.0)  # This is upper tail
    let centralCdf = 1.0 - centralPval
    check abs(ncCdf - centralCdf) < 0.01

  test "non-central shifts distribution right":
    # With positive noncentrality, CDF at same point should be smaller
    # (distribution shifted right = less probability in left tail)
    let cdf_central = noncentralChiSquaredCDF(10.0, 5.0, 0.0)
    let cdf_nc = noncentralChiSquaredCDF(10.0, 5.0, 5.0)
    check cdf_nc < cdf_central

  test "known value: df=2, lambda=4, x=10":
    # scipy.stats.ncx2.cdf(10, 2, 4) = 0.831431
    let cdf = noncentralChiSquaredCDF(10.0, 2.0, 4.0)
    check abs(cdf - 0.8314) < 0.01

  test "known value: df=5, lambda=10, x=20":
    # scipy.stats.ncx2.cdf(20, 5, 10) = 0.781070
    let cdf = noncentralChiSquaredCDF(20.0, 5.0, 10.0)
    check abs(cdf - 0.7811) < 0.01

  test "edge case: x=0 returns 0":
    let cdf = noncentralChiSquaredCDF(0.0, 5.0, 5.0)
    check cdf == 0.0

  test "large noncentrality parameter":
    # scipy.stats.ncx2.cdf(50, 10, 30) = 0.808095
    let cdf = noncentralChiSquaredCDF(50.0, 10.0, 30.0)
    check abs(cdf - 0.8081) < 0.01


suite "Statistical Power (Beta)":

  test "power is 1 when effect is very large":
    # With huge noncentrality, power should approach 1
    let power = computePower(df = 5.0, noncentrality = 100.0, alpha = 0.05)
    check power > 0.99

  test "power is low when effect is small":
    # With small noncentrality, power should be low
    let power = computePower(df = 5.0, noncentrality = 1.0, alpha = 0.05)
    check power < 0.20

  test "power increases with noncentrality":
    let power1 = computePower(df = 5.0, noncentrality = 5.0, alpha = 0.05)
    let power2 = computePower(df = 5.0, noncentrality = 10.0, alpha = 0.05)
    let power3 = computePower(df = 5.0, noncentrality = 20.0, alpha = 0.05)
    check power1 < power2
    check power2 < power3

  test "power increases with alpha (less stringent test)":
    let power_01 = computePower(df = 5.0, noncentrality = 10.0, alpha = 0.01)
    let power_05 = computePower(df = 5.0, noncentrality = 10.0, alpha = 0.05)
    let power_10 = computePower(df = 5.0, noncentrality = 10.0, alpha = 0.10)
    check power_01 < power_05
    check power_05 < power_10

  test "known power value":
    # For df=5, alpha=0.05, noncentrality=15
    # Critical value at alpha=0.05, df=5 is 11.0705
    # Power = 1 - ncx2.cdf(11.0705, 5, 15) = 0.8665
    let power = computePower(df = 5.0, noncentrality = 15.0, alpha = 0.05)
    check abs(power - 0.8665) < 0.02
