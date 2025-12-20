# Legacy OCCAM Cross-Validation Testing

This document describes how to run the legacy PSU OCCAM implementation for cross-validation testing against the Nim implementation.

## Docker Setup

The legacy OCCAM is available as a Docker container built from the original C++ source code.

### Building the Container

```bash
cd /path/to/occam/podman
docker build -t occam-legacy .
```

This builds Ubuntu 16.04 with Python 2.7 and all OCCAM dependencies. The build takes ~2-3 minutes.

### Running Legacy OCCAM CLI

The CLI binary is at `/var/www/occam/install/cl/occ` inside the container.

```bash
# Basic usage
docker run --rm occam-legacy /var/www/occam/install/cl/occ [options] datafile

# Options:
#   -a search | fit    Action (default: search)
#   -L levels          Search levels
#   -w width           Search width
#   -m model           Model to fit (required with -a fit)

# Examples:

# Fit a model
docker run --rm occam-legacy /var/www/occam/install/cl/occ \
    -a fit -m "ABD:BCD:ACD" /var/www/occam/examples/fit.in

# Search with custom width/levels
docker run --rm occam-legacy /var/www/occam/install/cl/occ \
    -a search -L 3 -w 3 /var/www/occam/examples/search.in

# Run with local .in file (mount volume)
docker run --rm -v $(pwd):/data occam-legacy /var/www/occam/install/cl/occ \
    -a fit -m "AB:BC" /data/myfile.in
```

### Output Format

Legacy OCCAM outputs:
- Basic statistics (state space, sample size, H(data))
- Model statistics (H, DF, T, LR, Alpha, AIC, BIC)
- Residual tables (with -a fit)
- Search results table (with -a search)

## Legacy .in File Format

The legacy format embeds analysis options in the file frontmatter:

```
:action
search                    # fit | search | lattice | tables,entropy,transmission

:nominal
varname,cardinality,type,abbrev
# type: 0=IV, 1=IV, 2=DV

:optimize-search-width
3                         # Search width (beam width)

:search-levels
7                         # Number of search levels

:no-frequency            # Flag: data rows are individual obs, not aggregated

:short-model
AB:BC:CD                  # Model notation for fit

:data
1 2 1 1  45              # state values + count (unless :no-frequency)
```

## Available Test Datasets

| File | Action | Variables | DV | Sample Size | Special Options |
|------|--------|-----------|----|----|-----------------|
| `search.in` | search | 4 (A:3, B:2, C:2, D:2) | none | 1008 | - |
| `fit.in` | fit | 4 (A:3, B:2, C:2, D:2) | none | 1008 | model=ABD:BCD:ACD |
| `stat.in` | tables,entropy,transmission | 4 | A (type=2) | 1008 | - |
| `lat.in` | lattice | 4 | none | - | :long-model |
| `bw21t08.in` | search | 15 | Z (LBW2) | ~1000 | :no-frequency, w=2, L=3 |
| `crash.in` | search | 15 | Z (LBW2) | ~5000 | :no-frequency, w=25, L=100 |
| `lhs3b.in` | search | 11 | H (health) | ~2000 | :no-frequency, w=2, L=2 |
| `lhs3b2.in` | search | 11 | H (health) | ~2000 | :no-frequency, w=2, L=2 |

## Cross-Validation Workflow

### 1. Generate Reference Values

Run legacy OCCAM and capture output:

```bash
# Fit model and capture statistics
docker run --rm occam-legacy /var/www/occam/install/cl/occ \
    -a fit -m "ABD:BCD:ACD" /var/www/occam/examples/fit.in \
    > reference_fit.txt

# Parse key values:
# H(data), H(model), DF, T, LR, Alpha
```

### 2. Run Nim Implementation

Convert .in to JSON and run:

```bash
./bin/cli convert -i examples/fit.in -o /tmp/fit.json
./bin/cli fit -i /tmp/fit.json -m "ABD:BCD:ACD"
```

### 3. Compare Values

Key statistics to compare:
- **H(data)** - Should match to 4+ decimal places
- **H(model)** - Should match to 4+ decimal places
- **T (transmission)** - Should match to 5+ decimal places
- **LR (likelihood ratio)** - Should match to 2+ decimal places
- **DF** - Known discrepancy: legacy may report +1 for loop models

## Reference Values from Legacy OCCAM

### search.in / fit.in Dataset (N=1008, 4 vars)

```
H(data) = 4.50007
H(A:B:C:D) = 4.5308           # Independence
H(ABD:ACD:BCD) = 4.50158      # Loop model (from fit.in)

# Search results (width=3, levels=3):
IVI:BD       H=4.5161  dDF=1   # Best by BIC
AC:BD:CD     H=4.5086  dDF=4   # Best by AIC
```

### Verified Nim Values (search.in)

| Statistic | Legacy | Nim | Diff |
|-----------|--------|-----|------|
| H(data) | 4.50007 | 4.5000704 | 4e-7 ✓ |
| H(independence) | 4.5308 | 4.5307911 | 9e-6 ✓ |
| H(ABD:ACD:BCD) | 4.50158 | 4.5015837 | 4e-6 ✓ |
| T | 0.00151367 | 0.0015133 | 4e-7 ✓ |
| LR | 2.11518 | 2.11465 | 5e-4 ✓ |

### bw21t08.in Dataset (Directed System, 15 vars defined, 8 used)

```
# Legacy output (7 IVs + DV in use, type=0 vars excluded):
State Space Size: 5832
Sample Size: 1357
H(data): 9.5278
H(IV): 9.45668
H(DV): 0.352049
T(IV:DV): 0.280934
IVs in use: B D F G H I J (type=1 variables only)
DV: Z (type=2)

# Search results (width=2, levels=3):
Best by BIC: IV:Z (independence)
```

Note: Variables with type=0 in .in file are excluded from analysis.

### lhs3b.in Dataset (Directed System, 11 vars)

```
# Legacy output:
State Space Size: 34560
Sample Size: 829
H(data): 9.36402
H(IV): 8.91681
H(DV): 1.81352
T(IV:DV): 1.36632
IVs in use: T M E D G I A W F P
DV: H (health)

# Search results (width=2, levels=2):
Best by BIC: IV:HD:HG
```

### stat.in Dataset (Directed System, 4 vars)

```
# Same data as search.in but soft(A) marked as DV
H(data): 4.50007
H(IV): 2.92585    # H of IVs only (B:C:D)
H(DV): 1.5846     # H of A marginal
T(IV:DV): 0.0103808
```

## Known Differences

1. **DF for loop models**: Legacy reports 19, Nim reports 18 for ABD:ACD:BCD
2. **Model notation**: Legacy uses "IVI:BD" for independence+BD, Nim uses "A:C:BD"
3. **Transmission sign**: Legacy shows positive T, Nim may show negative (H(data) - H(model))

## Variable Type Semantics in .in Files

In the `:nominal` section, the third field is the variable type:

| Type | Meaning | Legacy Behavior | Nim Behavior |
|------|---------|-----------------|--------------|
| 0 | Excluded IV | Excluded from search | ✓ Excluded by default |
| 1 | Active IV | Included as IV | Included as IV |
| 2 | Dependent Variable | Included as DV | Included as DV |

The Nim parser now properly tracks variable types and excludes type=0 variables during conversion:

```nim
import occam/io/formats

let parsed = parseOccamInFile("data.in")

# Check counts
echo parsed.variables.len        # All variables (including excluded)
echo parsed.activeVariableCount  # Only type=1 and type=2

# Get only active variables
let active = parsed.activeVariables

# Convert to JSON (excludes type=0 by default)
let json = parsed.toJson()

# Include all variables (for debugging)
let jsonAll = parsed.toJson(excludeType0 = false)
```

## Running Automated Tests

```bash
# Reference value tests
nim c -r tests/test_reference_values.nim

# BP vs IPF equivalence
nim c -r tests/test_bp_ipf_equivalence.nim

# Full test suite
nimble test
```
