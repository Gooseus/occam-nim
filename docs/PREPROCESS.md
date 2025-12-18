# Data Preprocessing in OCCAM-Nim

The `preprocess` command converts raw data files into an optimized format for fast analysis.

## Quick Start

```bash
# Basic: Convert CSV to optimized JSON
./bin/cli preprocess -i data.csv -o processed.json -v

# With column selection
./bin/cli preprocess -i data.csv -o output.json --columns="Age,Income,Target" -v

# With auto-binning
./bin/cli preprocess -i data.csv -o output.json --autoBin --targetCard=5 -v
```

## Why Preprocess?

| Benefit | Raw Data | Preprocessed |
|---------|----------|--------------|
| File size | 41MB (3M rows) | 6.7MB (92K states) |
| Load time | ~38 seconds | ~10 seconds |
| Format | String values | Integer indices |

Preprocessing aggregates raw observations into unique state combinations with frequency counts. This is mathematically equivalent but much more efficient.

## Features

### 1. Multi-Format Input

Automatically detects and handles:
- **CSV** files (with or without headers)
- **JSON** files (OCCAM format)
- **OCCAM .in** files (legacy format)

```bash
# Auto-detect format
./bin/cli preprocess -i data.csv -o output.json

# Force specific format
./bin/cli preprocess -i data.txt --format=csv -o output.json
```

### 2. Column Selection

Select which columns to include in the analysis:

```bash
# By index (0-based)
--columns="0,2,4"

# By range
--columns="0-3"

# By name (CSV with headers)
--columns="Age,Gender,Target"

# Mixed
--columns="0,2-4,Age,Target"

# All columns (default)
--columns="*"
```

### 3. Auto-Binning

Automatically reduce high-cardinality variables:

```bash
# Enable auto-binning
--autoBin

# Target cardinality for binned columns (default: 5)
--targetCard=3

# Only bin columns with cardinality > threshold (default: 10)
--binThreshold=10
```

Example:
```bash
# Bin any column with >10 unique values down to 5 bins
./bin/cli preprocess -i data.csv -o binned.json \
  --autoBin --targetCard=5 --binThreshold=10 -v
```

### 4. Dependent Variable

Specify which column is the dependent variable (for directed systems):

```bash
# DV is column 3
--dv=3

# No DV (neutral system)
--dv=-1
```

## Output Format

The preprocess command outputs a pre-aggregated JSON format:

```json
{
  "name": "dataset_name",
  "format": "aggregated",
  "variables": [
    {
      "name": "Age",
      "abbrev": "A",
      "cardinality": 3,
      "isDependent": false,
      "values": ["Young", "Middle", "Old"]
    }
  ],
  "data": [[0, 0], [0, 1], [1, 0], [1, 1]],
  "counts": [45.0, 32.0, 28.0, 41.0],
  "sampleSize": 146.0,
  "uniqueStates": 4
}
```

Key fields:
- `"format": "aggregated"` - Signals optimized format (0-indexed integers)
- `data` - Unique state combinations as integer indices
- `counts` - Frequency of each state
- `sampleSize` - Total observations
- `uniqueStates` - Number of unique combinations

## Common Workflows

### Workflow 1: Large Dataset

```bash
# 1. Preprocess large CSV
./bin/cli preprocess -i big_data.csv -o processed.json -v

# 2. Search on preprocessed data (fast!)
./bin/cli search -i processed.json --width=5 --levels=7
```

### Workflow 2: Subset Analysis

```bash
# Analyze specific columns only
./bin/cli preprocess -i full_data.csv -o subset.json \
  --columns="0,1,2,5" --dv=3 -v
./bin/cli search -i subset.json
```

### Workflow 3: High-Cardinality Data

```bash
# Auto-bin continuous variables
./bin/cli preprocess -i survey_data.csv -o binned.json \
  --autoBin --targetCard=3 -v
./bin/cli search -i binned.json
```

### Workflow 4: Format Conversion

```bash
# Convert legacy OCCAM format to modern JSON
./bin/cli preprocess -i legacy.in -o modern.json -v
```

## CLI Options Reference

| Option | Default | Description |
|--------|---------|-------------|
| `-i, --input` | (required) | Input file path |
| `-o, --output` | stdout | Output JSON file |
| `-f, --format` | auto | Input format: auto, json, csv, occam |
| `-c, --columns` | "" (all) | Column selection spec |
| `-a, --autoBin` | false | Enable auto-binning |
| `-t, --targetCard` | 5 | Target cardinality for binning |
| `-b, --binThreshold` | 10 | Only bin if cardinality > threshold |
| `--hasHeader` | true | CSV has header row |
| `-d, --delimiter` | , | CSV column delimiter |
| `--dv` | -1 | Dependent variable column index |
| `-n, --name` | filename | Dataset name |
| `-v, --verbose` | false | Show detailed output |

## Implementation Files

| File | Description |
|------|-------------|
| `src/cli_lib/cmd_preprocess.nim` | Main command implementation |
| `src/occam/io/parser.nim` | Data loading and aggregation |
| `src/occam/io/binning.nim` | Binning algorithms |
| `tests/test_preprocess.nim` | Unit tests |
