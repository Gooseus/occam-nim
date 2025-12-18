## Statistics calculations for OCCAM
## Degrees of freedom, likelihood ratio, chi-squared p-value, AIC, BIC

{.push raises: [].}

import std/math
import std/options
import distributions
import ../core/types
import ../core/variable
import ../core/relation
import ../core/model
import ../core/table as coretable

func relationDF*(r: Relation; varList: VariableList): int64 =
  ## Compute degrees of freedom for a single relation
  ## DF = NC - 1 where NC is the cartesian product of cardinalities
  r.degreesOfFreedom(varList)


func modelDF*(m: Model; varList: VariableList): int64 =
  ## Compute degrees of freedom for a model
  ## DF = number of free parameters in the model
  ## For saturated model: DF = NC - 1 (all cells are parameters)
  ## For independence model: DF = sum of (cardinality - 1) for each variable
  ## For models with overlaps: use inclusion-exclusion principle
  if m.relationCount == 0:
    return 0

  # Check if this is the saturated model (one relation with all variables)
  if m.isSaturatedModel(varList):
    # Saturated model: DF = NC - 1 where NC = product of all cardinalities
    var nc: int64 = 1
    for v in varList:
      nc *= v.cardinality.toInt
    return nc - 1

  # For independence model: sum of individual variable DFs
  if m.isIndependenceModel(varList):
    result = 0
    for v in varList:
      result += v.cardinality.toInt - 1
    return result

  # General case: use inclusion-exclusion for overlapping relations
  # DF = sum(DF_i) - sum(DF_ij) + sum(DF_ijk) - ...
  # where DF_ij is the DF of the intersection of relations i and j

  # First, check for overlaps
  var hasOverlaps = false
  for i in 0..<m.relationCount:
    for j in i+1..<m.relationCount:
      if m[i].overlaps(m[j]):
        hasOverlaps = true
        break
    if hasOverlaps:
      break

  if not hasOverlaps:
    # Simple case: sum of relation DFs
    result = 0
    for r in m:
      result += relationDF(r, varList)
  else:
    # Use inclusion-exclusion for two overlapping relations
    # For now, implement basic case for pairs
    result = 0
    for r in m:
      result += relationDF(r, varList)

    # Subtract overlaps (intersection DFs)
    for i in 0..<m.relationCount:
      for j in i+1..<m.relationCount:
        if m[i].overlaps(m[j]):
          let inter = m[i].intersection(m[j])
          result -= relationDF(inter, varList)


func deltaDF*(m1, m2: Model; varList: VariableList): int64 =
  ## Compute delta degrees of freedom between two models
  ## ΔDF = DF(m1) - DF(m2)
  modelDF(m1, varList) - modelDF(m2, varList)


func likelihoodRatio*(sampleSize: float64; hMax, hModel: float64): float64 =
  ## Compute likelihood ratio statistic
  ## LR = 2 * N * ln(2) * (Hmax - H)
  ## This is the G-squared statistic
  2.0 * sampleSize * ln(2.0) * (hMax - hModel)


proc chiSquaredPValue*(chiSquared: float64; df: float64): float64 {.raises: [].} =
  ## Compute p-value for chi-squared statistic
  ## Returns the upper-tail probability P(X > chiSquared)
  ##
  ## For large df (>= 100), uses Wilson-Hilferty normal approximation
  ## to avoid numerical issues with the incomplete gamma function.
  if chiSquared <= 0.0 or df <= 0.0:
    return 1.0

  # For very large chi-squared values far from the mean, p-value is effectively 0 or 1
  # Chi-squared mean = df, variance = 2*df
  # If chi-squared >> df + 10*sqrt(2*df), p-value is essentially 0
  let stdDev = sqrt(2.0 * df)
  if chiSquared > df + 20.0 * stdDev:
    return 0.0
  if chiSquared < max(0.0, df - 20.0 * stdDev):
    return 1.0

  # For large degrees of freedom, use Wilson-Hilferty normal approximation
  # (χ²/df)^(1/3) is approximately N(1 - 2/(9*df), sqrt(2/(9*df)))
  if df >= 100.0:
    let k = df
    let x = chiSquared
    # Wilson-Hilferty transformation
    let a = 1.0 - 2.0 / (9.0 * k)
    let b = sqrt(2.0 / (9.0 * k))
    let z = (pow(x / k, 1.0 / 3.0) - a) / b

    # Standard normal survival function: 1 - Φ(z) = 0.5 * erfc(z / sqrt(2))
    # For very large z, erfc approaches 0
    if z > 8.0:
      return 0.0
    elif z < -8.0:
      return 1.0
    else:
      return 0.5 * erfc(z / sqrt(2.0))

  # For smaller df, use the distributions library
  try:
    let dist = initChi2Distribution(int(df))
    let pval = dist.sf(chiSquared)
    # Check for NaN and handle gracefully
    if pval.isNaN or pval < 0.0:
      return 0.0
    if pval > 1.0:
      return 1.0
    return pval
  except:
    # Fallback to normal approximation if library fails
    let z = (chiSquared - df) / sqrt(2.0 * df)
    if z > 8.0:
      return 0.0
    return 0.5 * erfc(z / sqrt(2.0))


func aic*(lr: float64; df: float64): float64 =
  ## Compute Akaike Information Criterion
  ## AIC = LR - 2*DF
  ## Lower AIC indicates better model (balancing fit and complexity)
  lr - 2.0 * df


func bic*(lr: float64; ddf: float64; sampleSize: float64): float64 =
  ## Compute Bayesian Information Criterion
  ## BIC = LR - DDF*ln(N)
  ## where DDF = DF_saturated - DF_model (degrees of freedom saved by simpler model)
  ##
  ## Lower BIC indicates better model:
  ## - Lower LR = better fit
  ## - Higher DDF = simpler model = larger penalty subtracted = lower BIC
  ##
  ## Note: This uses DDF (delta DF), not absolute DF, so that simpler models
  ## are properly rewarded for parsimony.
  lr - ddf * ln(sampleSize)


func uncertaintyCoefficient*(hMax: float64; hModel: float64): float64 =
  ## Compute uncertainty coefficient (normalized transmission)
  ## U = (Hmax - H) / Hmax
  ## U = 0 for independence model (H = Hmax)
  ## U = 1 for saturated model (H = 0)
  if hMax <= 0.0:
    return 0.0
  (hMax - hModel) / hMax


func percentReduction*(hMax: float64; hModel: float64): float64 =
  ## Compute percent reduction in uncertainty
  ## Same as uncertainty coefficient * 100
  uncertaintyCoefficient(hMax, hModel) * 100.0


proc noncentralChiSquaredCDF*(x: float64; df: float64; lambda: float64): float64 {.raises: [].} =
  ## Compute CDF of non-central chi-squared distribution
  ## Using Poisson-weighted sum of central chi-squared CDFs:
  ## F(x; df, λ) = Σ [e^(-λ/2) * (λ/2)^i / i!] * F_χ²(x; df+2i)
  ##
  ## Parameters:
  ##   x: value at which to evaluate CDF
  ##   df: degrees of freedom
  ##   lambda: non-centrality parameter
  ##
  ## Returns: P(X <= x) for X ~ ncχ²(df, λ)
  ##
  ## For large df (>= 100), uses normal approximation:
  ##   ncχ²(df, λ) ≈ N(df + λ, 2*(df + 2λ))

  if x <= 0.0:
    return 0.0

  # For large degrees of freedom, use normal approximation
  # Non-central chi-squared: mean = df + λ, variance = 2*(df + 2λ)
  if df >= 100.0:
    let mu = df + lambda
    let sigma = sqrt(2.0 * (df + 2.0 * lambda))
    let z = (x - mu) / sigma

    # Standard normal CDF: Φ(z) = 0.5 * (1 + erf(z / sqrt(2)))
    if z > 8.0:
      return 1.0
    elif z < -8.0:
      return 0.0
    else:
      return 0.5 * (1.0 + erf(z / sqrt(2.0)))

  if lambda <= 0.0:
    # Central chi-squared case
    try:
      let dist = initChi2Distribution(int(df))
      return dist.cdf(x)
    except:
      # Fallback to normal approximation
      let z = (x - df) / sqrt(2.0 * df)
      return 0.5 * (1.0 + erf(z / sqrt(2.0)))

  # Poisson-weighted series expansion
  # For numerical stability, start from modal term (i ≈ λ/2) and work both ways
  let halfLambda = lambda / 2.0
  let maxIter = 2000
  let eps = 1e-15

  var cdfResult = 0.0
  var totalWeight = 0.0

  # Start from i=0 and compute until weights become negligible
  # poissonWeight = e^(-λ/2) * (λ/2)^i / i!
  var poissonWeight = exp(-halfLambda)  # i=0 term
  var i = 0

  # Continue until we've captured 1 - eps of the Poisson mass
  while i < maxIter and totalWeight < (1.0 - eps):
    let currentDf = df + 2.0 * float64(i)
    if currentDf > 0.0:
      try:
        let dist = initChi2Distribution(int(currentDf))
        let centralCdf = dist.cdf(x)
        let term = poissonWeight * centralCdf
        if not centralCdf.isNaN:
          cdfResult += term
          totalWeight += poissonWeight
      except:
        # If chi-squared CDF fails, use normal approximation for this term
        let z = (x - currentDf) / sqrt(2.0 * currentDf)
        let centralCdf = 0.5 * (1.0 + erf(z / sqrt(2.0)))
        let term = poissonWeight * centralCdf
        cdfResult += term
        totalWeight += poissonWeight

    # Update Poisson weight for next term
    i += 1
    poissonWeight *= halfLambda / float64(i)

    # Also break if Poisson weight becomes negligible
    if poissonWeight < 1e-300:
      break

  cdfResult


proc chiSquaredCriticalValue*(alpha: float64; df: float64): float64 {.raises: [].} =
  ## Compute critical value for chi-squared distribution
  ## Returns x such that P(X > x) = alpha
  ## Uses inverse CDF (quantile function)
  ##
  ## For large df (>= 100), uses Wilson-Hilferty normal approximation.
  if df <= 0.0 or alpha <= 0.0 or alpha >= 1.0:
    return 0.0

  # For large degrees of freedom, use Wilson-Hilferty approximation
  # Critical value from: z_alpha = (x/df)^(1/3) transformed to normal
  if df >= 100.0:
    # Inverse normal CDF for 1 - alpha (using erfc inverse approximation)
    let p = 1.0 - alpha
    # Rational approximation for inverse normal CDF
    # For p in (0, 1), compute z such that Φ(z) = p
    var z: float64
    if p >= 0.5:
      # Use symmetry
      let t = sqrt(-2.0 * ln(1.0 - p))
      # Approximation coefficients (Abramowitz & Stegun)
      let c0 = 2.515517
      let c1 = 0.802853
      let c2 = 0.010328
      let d1 = 1.432788
      let d2 = 0.189269
      let d3 = 0.001308
      z = t - (c0 + c1*t + c2*t*t) / (1.0 + d1*t + d2*t*t + d3*t*t*t)
    else:
      let t = sqrt(-2.0 * ln(p))
      let c0 = 2.515517
      let c1 = 0.802853
      let c2 = 0.010328
      let d1 = 1.432788
      let d2 = 0.189269
      let d3 = 0.001308
      z = -(t - (c0 + c1*t + c2*t*t) / (1.0 + d1*t + d2*t*t + d3*t*t*t))

    # Wilson-Hilferty inverse: x/df = (1 - 2/(9*df) + z*sqrt(2/(9*df)))^3
    let a = 1.0 - 2.0 / (9.0 * df)
    let b = sqrt(2.0 / (9.0 * df))
    let ratio = pow(a + z * b, 3.0)
    return df * max(0.0, ratio)

  # For smaller df, use the distributions library
  try:
    let dist = initChi2Distribution(int(df))
    return dist.ppf(1.0 - alpha)
  except:
    # Fallback: use mean + z*stddev approximation
    let z = sqrt(2.0) * 1.645  # approximate z for alpha=0.05
    return df + z * sqrt(2.0 * df)


func computePower*(df: float64; noncentrality: float64; alpha: float64): float64 =
  ## Compute statistical power (1 - beta) for chi-squared test
  ##
  ## Parameters:
  ##   df: degrees of freedom
  ##   noncentrality: non-centrality parameter (typically the test statistic)
  ##   alpha: significance level (e.g., 0.05)
  ##
  ## Returns: probability of rejecting H0 when H1 is true
  ##
  ## Power = 1 - P(X <= critical_value | X ~ ncχ²(df, noncentrality))
  ##       = 1 - F_ncχ²(critical_value; df, noncentrality)

  if df <= 0.0 or alpha <= 0.0 or alpha >= 1.0:
    return 0.0

  # Get critical value at specified alpha
  let criticalValue = chiSquaredCriticalValue(alpha, df)

  # Power = probability of exceeding critical value under H1
  # = 1 - CDF of non-central chi-squared at critical value
  1.0 - noncentralChiSquaredCDF(criticalValue, df, noncentrality)


func pearsonChiSquared*(observed, expected: coretable.ContingencyTable; sampleSize: float64): float64 =
  ## Compute Pearson chi-squared statistic (P2)
  ## P2 = Σ (O - E)² / E
  ## where O = observed count, E = expected count
  ##
  ## Tables contain probabilities, so:
  ##   O = N * p_obs, E = N * p_exp
  ##   P2 = N * Σ (p_obs - p_exp)² / p_exp
  ##
  ## Cells with E=0 are skipped (would cause division by zero)
  result = 0.0

  # Process all cells in expected table
  for expTup in expected:
    let pExp = expTup.value
    if pExp <= 0.0:
      continue  # Skip cells with zero expected probability

    # Find corresponding observed probability (0 if not present)
    var pObs = 0.0
    let obsIdx = observed.find(expTup.key)
    if obsIdx.isSome:
      pObs = observed[obsIdx.get].value

    # Add contribution: N * (p_obs - p_exp)² / p_exp
    let diff = pObs - pExp
    result += sampleSize * (diff * diff) / pExp

