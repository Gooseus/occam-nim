# Prime Residue Analysis with OCCAM-Nim

This guide walks through analyzing the Lemke Oliver-Soundararajan prime bias using OCCAM's Reconstructability Analysis tools.

## Background

In 2016, Lemke Oliver and Soundararajan discovered that consecutive primes exhibit biases in their residue classes - "adjacent primes don't like being in the same residue class." This provides ground truth for validating RA analysis.

## Quick Start

```bash
# Generate a dataset of primes with residue classes
./bin/cli sequence --kind primes --limit 100000 --columns "R3,R5,R7" --target R3 -o primes.json

# Check what we can analyze with this sample size
./bin/cli samplesize --samples 100000

# Run a search for best models
./bin/cli search -i primes.json --direction up --filter loopless --sort bic

# Fit a specific model and see detailed results
./bin/cli fit -i primes.json --model "AZ" --compare "A:Z" --conditionalDv
```

---

## Step 1: Assess Sample Size Requirements

Before generating data, determine how many residue classes you can meaningfully analyze.

### Check required samples for different numbers of IVs:

```bash
./bin/cli samplesize --required
```

Output:
```
Required Samples for 10 obs/cell:

IVs                    State Space    Required N       Est. Prime Limit
---------------------------------------------------------------------------
R3                     4              40               < 1,000
R3,R5                  16             160              1.K
R3,R5,R7               96             960              8.K
R3,R5,R7,R11           960            9,600            109.K
R3,R5,R7,R11,R13       11520          115,200          1.6M
R3,R5,R7,R11,R13,R17   184320         1,843,200        31.5M
```

### Check adequacy for a specific prime range:

```bash
./bin/cli samplesize --kind primes --limit 1000000
```

This tells you how many residue classes are statistically adequate for primes up to 1 million.

### Key formula:
```
StateSpace = Product(base_i - 1) × DV_cardinality
ObsPerCell = SampleSize / StateSpace
Adequate:  >= 5/cell (chi-squared valid)
Recommended: >= 10/cell (reliable estimates)
```

---

## Step 2: Generate a Dataset

### Basic syntax:

```bash
./bin/cli sequence \
  --kind primes \           # Sequence type: primes, naturals, odds
  --limit 1000000 \         # Upper bound
  --columns "R3,R5,R7" \    # IV columns (comma-separated)
  --target R3 \             # DV column
  -o output.json            # Output file
```

### Available column types:

| Column | Description | Cardinality |
|--------|-------------|-------------|
| `R3`, `R5`, `R7`, ... | Residue class mod N | N-1 for primes > N |
| `collatz` | Steps to reach 1 in Collatz sequence | Variable |
| `digits` | Sum of decimal digits | Variable |
| `factors` | Number of prime factors | Small integers |

### Examples:

```bash
# Simple R3 analysis (prev mod 3 -> next mod 3)
./bin/cli sequence --kind primes --limit 100000 \
  --columns "R3" --target R3 -o primes_R3.json

# Multiple residue classes
./bin/cli sequence --kind primes --limit 1000000 \
  --columns "R3,R5,R7,R11,R13" --target R3 -o primes_multi.json

# Primes in a specific range (e.g., 1M to 10M)
./bin/cli sequence --kind primes --start 1000000 --limit 10000000 \
  --columns "R3,R5,R7" --target R3 -o primes_range.json

# Targeting a different residue class as DV
./bin/cli sequence --kind primes --limit 1000000 \
  --columns "R3,R5,R7,R11,R13" --target R13 -o primes_target_R13.json

# Include Collatz distance as a column
./bin/cli sequence --kind primes --limit 100000 \
  --columns "R3,collatz" --target R3 -o primes_collatz.json
```

### Verbose output:

```bash
./bin/cli sequence --kind primes --limit 100000 \
  --columns "R3,R5,R7" --target R3 -o primes.json --verbose
```

Shows:
- Number of primes generated
- Range of values
- Column abbreviations (A, B, C, ... Z for DV)
- Observed cardinalities

---

## Step 3: Inspect Your Dataset

```bash
./bin/cli info -i primes.json --variables
```

Output:
```
Dataset: primes_residues
Variables: 4
Sample size: 99999.0
Directed: true
State space: 96

Variables:
  Name            Abbrev   Card   DV
  -----------------------------------
  R3              A        2
  R5              B        4
  R7              C        6
  R3              Z        2      *
```

**Key points:**
- `Directed: true` means there's a DV (marked with *)
- Abbreviations A, B, C are IVs; Z is the DV
- State space = product of all cardinalities

---

## Step 4: Search for Best Models

### Upward search (start simple, add complexity):

```bash
./bin/cli search -i primes.json --direction up --filter loopless --sort bic
```

### Options:

| Option | Values | Description |
|--------|--------|-------------|
| `--direction` | `up`, `down` | Start from independence or saturated |
| `--filter` | `loopless`, `full`, `disjoint`, `chain` | Model class restriction |
| `--sort` | `bic`, `aic`, `ddf` | Ranking criterion |
| `--width` | integer | Models to keep at each level |
| `--levels` | integer | Search depth |

### Understanding search output:

```
Reference Models:
  Top (saturated): ABCZ        <- All variables interact
  Bottom (independence): ABC:Z  <- IVs independent of DV

Best Models Found:
  AZ:BC    DF=6   H=5.1234   BIC=-12345   <- A predicts Z, B and C separate
  ABZ:C    DF=12  H=5.0123   BIC=-11234   <- A and B jointly predict Z
```

---

## Step 5: Fit Specific Models

### Basic fit:

```bash
./bin/cli fit -i primes.json --model "AZ:BC"
```

### With comparison to another model:

```bash
./bin/cli fit -i primes.json --model "AZ" --compare "A:Z"
```

### With conditional probability table:

```bash
./bin/cli fit -i primes.json --model "AZ" --conditionalDv
```

### Understanding model notation:

| Notation | Meaning |
|----------|---------|
| `A:Z` | A and Z are independent (no association) |
| `AZ` | A and Z have a 2-way association |
| `AZ:B` | AZ interact, B is separate |
| `ABZ` | A, B, Z have a 3-way interaction |
| `AZ:BZ` | A→Z and B→Z, but A and B don't interact |

---

## Step 6: Interpret Results

### Key statistics:

| Statistic | Meaning | Interpretation |
|-----------|---------|----------------|
| **H** | Entropy of model | Lower = more structure |
| **T** | Transmission | Information from IVs to DV |
| **ΔH** | Entropy reduction | Bits of uncertainty reduced |
| **LR** | Likelihood ratio | Deviation from saturated model |
| **Alpha** | p-value | Statistical significance |
| **BIC** | Bayesian IC | Model selection (lower = better) |
| **DDF** | Delta DF | Degrees of freedom saved (simplicity) |

### Conditional DV table interpretation:

```
Conditional DV Table P(DV|IVs):
A  |  P(Z=0)  P(Z=1)  | Pred  Correct
0  |  0.432   0.568   | 1     166446/292962
1  |  0.568   0.432   | 0     166446/293118

Percent Correct: 56.8%
```

- When prev prime ≡ 1 (mod 3): 56.8% chance next ≡ 2 (mod 3)
- When prev prime ≡ 2 (mod 3): 56.8% chance next ≡ 1 (mod 3)
- **Consecutive primes avoid same residue class** (Lemke Oliver bias!)

### BIC interpretation:

```
BIC = LR - DDF × ln(N)
```

- **Positive BIC**: Model is worse than saturated (poor fit not compensated by simplicity)
- **Negative BIC**: Model is better than saturated (simplicity outweighs fit loss)
- **BIC = 0**: Saturated model (reference point)

---

## Step 7: Compare Multiple Residue Classes

### Individual effects:

```bash
# R3 -> R3 (same class)
./bin/cli fit -i primes_multi.json --model "AZ:BCDE" | grep "ΔH"

# R5 -> R3 (cross class)
./bin/cli fit -i primes_multi.json --model "BZ:ACDE" | grep "ΔH"
```

### Combined effects:

```bash
# Additive (no interaction)
./bin/cli fit -i primes_multi.json --model "AZ:BZ:CDE" | grep "ΔH"

# With interaction
./bin/cli fit -i primes_multi.json --model "ABZ:CDE" | grep "ΔH"
```

### Expected findings:

1. **Same residue class is best predictor**: R3→R3 beats R5→R3, etc.
2. **Interactions are synergistic**: ABZ > AZ + BZ - Z
3. **Higher-cardinality residues show stronger bias**: R13→R13 (0.19 bits) > R3→R3 (0.01 bits)

---

## Example: Complete Analysis Workflow

```bash
# 1. Check what's feasible
./bin/cli samplesize --required --targetObsPerCell 10

# 2. Generate dataset for 5 residue classes (needs ~1.6M primes)
./bin/cli sequence --kind primes --limit 2000000 \
  --columns "R3,R5,R7,R11,R13" --target R3 \
  -o primes_5iv.json --verbose

# 3. Verify adequacy
./bin/cli samplesize --samples $(./bin/cli info -i primes_5iv.json --sampleSize 2>&1 | grep "Sample" | awk '{print $3}' | cut -d. -f1)

# 4. Quick search for best models
./bin/cli search -i primes_5iv.json --direction up --filter loopless --width 5 --sort bic

# 5. Fit the best model with details
./bin/cli fit -i primes_5iv.json --model "AZ:BCDE" --conditionalDv

# 6. Compare to independence
./bin/cli fit -i primes_5iv.json --model "AZ:BCDE" --compare "ABCDE:Z"

# 7. Check if adding more IVs helps
./bin/cli fit -i primes_5iv.json --model "ABZ:CDE" | grep "ΔH"
./bin/cli fit -i primes_5iv.json --model "ABCZ:DE" | grep "ΔH"
```

---

## Troubleshooting

### "Insufficient" in adequacy table
Your sample size is too small for the number of IVs. Either:
- Reduce the number of residue classes
- Generate more primes (increase `--limit`)

### Very small ΔH values
Cross-residue effects are naturally small. The main effect is always same-residue → same-residue.

### Numerical errors with large datasets
Large chi-squared values can cause numerical issues. The system uses Wilson-Hilferty approximation for large degrees of freedom.

### Understanding negative BIC
Negative BIC means the model is preferred over the saturated model - the parsimony reward exceeds the fit penalty. This is expected for good intermediate models.

---

## Reference: Column Abbreviations

When you specify columns, they're assigned abbreviations automatically:

| Position | Abbreviation | Example |
|----------|--------------|---------|
| 1st IV | A | R3 |
| 2nd IV | B | R5 |
| 3rd IV | C | R7 |
| ... | ... | ... |
| DV | Z | R3 (target) |

So `--columns "R3,R5,R7" --target R3` creates:
- A = prev R3
- B = prev R5
- C = prev R7
- Z = next R3
