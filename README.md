# OCCAM-Nim

A Nim library for Reconstructability Analysis (RA) - a methodology for discrete multivariate modeling based on information theory and graph theory.

## Overview

OCCAM-Nim provides:
- **Model fitting**: Compute entropy, transmission, degrees of freedom, likelihood ratio, AIC, BIC
- **Model search**: Find optimal models using loopless, full, disjoint, or chain search strategies
- **Decomposable models**: Exact inference via junction tree and belief propagation
- **Loop models**: Iterative Proportional Fitting (IPF) for non-decomposable models
- **Directed systems**: Conditional entropy, confusion matrix, prediction accuracy
- **Data preprocessing**: Binning, discretization, format conversion

## Installation

### As a Library

```bash
nimble install occam
```

### From Source

```bash
git clone https://github.com/yourrepo/occam-nim
cd occam-nim
nimble install -d   # Install dependencies
nimble test         # Run tests
```

### Building Components

OCCAM-Nim is organized as a multi-package monorepo. Build only what you need:

```bash
# Core library only (installed with nimble install)
nimble test         # Run library tests

# CLI tool
nimble cli          # Build CLI to bin/cli

# Web server (requires prologue, chronicles)
cd packages/occam_web && nimble install -d
nimble web          # Build to bin/web

# MCP server (for AI tool integration)
cd packages/occam_mcp && nimble install -d
nimble mcp          # Build to bin/mcp
```

## Library Usage

### Quick Start

```nim
import occam

# Load data from JSON file
let data = loadDataSpec("mydata.json")
let varList = data.toVariableList()
let table = data.toTable(varList)

# Create a manager and fit a model
var mgr = initVBManager(varList, table)
let model = mgr.parseModel("AB:BC:C")  # A model with three relations
let result = mgr.fitModel(model)

echo "Entropy: ", result.h
echo "AIC: ", result.aic
echo "BIC: ", result.bic
echo "Has loops: ", model.isDecomposable(varList)
```

### Model Search

```nim
import occam

let data = loadDataSpec("data.json")
let varList = data.toVariableList()
let table = data.toTable(varList)

var mgr = initVBManager(varList, table)

# Search for best models using BIC
let results = parallelSearch(
  varList, table,
  mgr.bottomRefModel,  # Start from independence model
  SearchFilter.Loopless,
  SearchStatistic.BIC,
  Direction.Ascending,
  width = 5,
  maxLevels = 7
)

for candidate in results:
  echo candidate.model.printName(varList), " BIC=", mgr.computeBIC(candidate.model)
```

### Building Data Programmatically

```nim
import occam

# Create variables
var varList = initVariableList()
discard varList.add(initVariable("Gender", "G", Cardinality(2)))
discard varList.add(initVariable("Age", "A", Cardinality(3)))
discard varList.add(initVariable("Outcome", "O", Cardinality(2), isDependent = true))

# Build contingency table
var table = initTable(varList.keySize)
table.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0), (VariableIndex(2), 0)]), 45.0)
table.add(varList.buildKey(@[(VariableIndex(0), 0), (VariableIndex(1), 0), (VariableIndex(2), 1)]), 32.0)
# ... add more observations
table.sort()
table.normalize()

# Analyze
var mgr = initVBManager(varList, table)
let model = mgr.parseModel("GA:AO")
let fit = mgr.fitModel(model)
```

### Module Organization

- `occam/core/*` - Core types: Variable, Table, Relation, Model
- `occam/math/*` - Entropy, statistics, IPF, belief propagation
- `occam/manager/*` - VBManager coordinates fitting and analysis
- `occam/search/*` - Model search algorithms
- `occam/io/*` - Data loading and format conversion

For advanced access to graph algorithms or inference:
```nim
import occam/core/[graph, junction_tree]
import occam/math/[ipf, belief_propagation]
```

---

## CLI Usage

OCCAM-Nim also provides a command-line interface for interactive analysis.

### Build CLI

```bash
nimble build
```

### Quick Start

#### 1. Analyze a CSV file
```bash
./bin/cli analyze-csv -i data.csv
```

Output shows column structure, cardinalities, and unique values:
```
CSV Analysis: data.csv
============================================================
Rows: 100
Columns: 4

Column Details:
  #    Header               Cardinality  Abbrev   Values
  ----------------------------------------------------------------------
  0    Gender               2            G        F, M
  1    Education            3            E        High, Low, Medium
  2    Income               3            I        High, Low, Medium
  3    Satisfied            2            S        No, Yes
```

### 2. Convert to JSON format
```bash
# CSV with Satisfied (column 3) as dependent variable
./bin/cli csv-to-json -i data.csv --dv 3 -o data.json

# Or convert from OCCAM .in format
./bin/cli convert -i data.in -o data.json
```

### 3. Run model search
```bash
./bin/cli search -i data.json --direction up --width 5 --levels 7
```

## CLI Commands

### `search` - Search model space
```bash
./bin/cli search -i data.json [options]

Options:
  -i, --input     Input JSON file (required)
  --direction     Search direction: up or down (default: up)
  --filter        Search filter: loopless, full, disjoint, chain (default: loopless)
  --width         Models to keep per level (default: 3)
  --levels        Maximum search levels (default: 7)
  --sort          Sort by: ddf, aic, bic (default: ddf)
  --parallel      Use parallel search (default: true)
  --verbose       Show detailed output
```

**Parallelization**: Search runs in parallel by default using all available CPU cores. This provides 2-6x speedup on datasets with >50 unique states. Use `--parallel=false` to disable.

**Search Filters:**
- `loopless` - Only decomposable models (no loops)
- `full` - All models including those with loops (uses IPF)
- `disjoint` - Models where relations don't share variables
- `chain` - Path/chain models only (e.g., AB:BC:CD)

### `fit` - Fit a single model
```bash
./bin/cli fit -i data.json -m "AB:BC:AC" [options]

Options:
  -i, --input         Input JSON file (required)
  -m, --model         Model specification (required)
  --residuals         Show residuals table
  --conditional-dv    Show P(DV|IVs) table (directed systems)
  --confusion-matrix  Show confusion matrix (directed systems)
  --compare           Compare to another model for incremental alpha
  --verbose           Show detailed output
```

The `fit` command computes detailed statistics for any model, including models with loops. For loop models, it uses Iterative Proportional Fitting (IPF) to compute the maximum entropy distribution.

**Example: Neutral system with loop**
```
Model Fit Report
============================================================
Model:        AB:AC:BC
System:       Neutral
Has Loops:    true
IPF Iters:    4
IPF Error:    1.51e-09

Statistics:
------------------------------------------------------------
  H (entropy):     4.524764
  T (transmission):-0.024694
  DF:              9
  DDF (delta DF):  14
  LR (vs top):     34.5070
  Alpha (p-value): 0.001738
  AIC:             16.5070
  BIC:             -27.7345
```

**Example: Directed system with predictions**
```bash
./bin/cli fit -i data.json -m "AZ:B" --conditional-dv --confusion-matrix
```
```
Conditional DV Table P(DV|IVs):
------------------------------------------------------------
A  B  |  P(Z=0)  P(Z=1)  | Pred  Correct
0  0  |  0.750   0.250   | 0     15/20
0  1  |  0.750   0.250   | 0     18/24
1  0  |  0.400   0.600   | 1     12/20
1  1  |  0.400   0.600   | 1     14/22

Percent Correct: 68.6%

Confusion Matrix:
------------------------------------------------------------
             Predicted Z
             0       1
Actual Z  0  33      10
           1  17      26

Accuracy:  0.686
```

### `lattice` - Enumerate model lattice
```bash
./bin/cli lattice -i data.json [options]

Options:
  -i, --input       Input JSON file (required)
```

Example:
```bash
./bin/cli lattice -i data.json

# Output shows all models organized by level
Lattice Enumeration
============================================================
Variables: 4
Models in lattice: 15

Level 0: A:B:C:D
Level 1: AB:C:D, AC:B:D, AD:B:C, A:BC:D, A:BD:C, A:B:CD
Level 2: ABC:D, ABD:C, AB:CD, ACD:B, AC:BD, AD:BC, A:BCD
Level 3: ABCD
```

### `generate` - Generate synthetic data
```bash
./bin/cli generate [options]

Options:
  --variables     Variable spec: A:2,B:2,C:2 (required)
  --model         Model structure: AB:BC (required)
  --samples       Number of samples (default: 1000)
  --strength      Association strength 0-1 (default: 0.8)
  -o, --output    Output JSON file (required)
```

Example:
```bash
# Generate chain data
./bin/cli generate --variables "A:2,B:2,C:2" --model "AB:BC" --samples 500 -o chain.json

# Search the generated data - should recover the original structure
./bin/cli search -i chain.json --filter chain --sort bic
```

### `info` - Display dataset information
```bash
./bin/cli info -i data.json [options]

Options:
  -i, --input     Input JSON file (required)
  --variables     Show variable details
  --sampleSize    Show sample size
  --summary       Show summary (default)
```

### `convert` - Convert OCCAM .in to JSON
```bash
./bin/cli convert -i data.in [options]

Options:
  -i, --input     OCCAM .in file (required)
  -o, --output    Output JSON file (stdout if empty)
  --inferVals     Infer value labels from data (default: true)
```

### `analyze-csv` - Analyze CSV structure
```bash
./bin/cli analyze-csv -i data.csv [options]

Options:
  -i, --input       CSV file (required)
  --hasHeader       CSV has header row (default: true)
  --delimiter       Column delimiter (default: ,)
  --interactive     Interactive configuration mode
```

### `csv-to-json` - Convert CSV to JSON
```bash
./bin/cli csv-to-json -i data.csv [options]

Options:
  -i, --input       CSV file (required)
  -o, --output      Output JSON file (stdout if empty)
  --columns         Column indices to include (comma-separated)
  --dv              Dependent variable column (-1 for neutral)
  --hasHeader       CSV has header row (default: true)
  --delimiter       Column delimiter (default: ,)
  --abbrevs         Custom abbreviations (comma-separated)
  --names           Custom variable names (comma-separated)
```

### `bin` - Discretize continuous variables
```bash
./bin/cli bin -i data.csv [options]

Options:
  -i, --input       Input CSV or JSON file (required)
  -o, --output      Output JSON file (stdout if empty)
  --var             Per-variable binning spec (repeatable)
  --auto            Auto-detect and bin high-cardinality columns
  --targetCard      Target cardinality for auto-binning (default: 5)
  --threshold       Cardinality threshold for auto-binning (default: 10)
  --verbose         Show detailed output
```

OCCAM requires discrete categorical data, but real-world datasets often have continuous or high-cardinality variables. The `bin` command transforms these into discrete categories.

**Binning strategies (--var format):**
| Strategy | Syntax | Description |
|----------|--------|-------------|
| Equal-width | `"Age:width:5"` | Divide range into N equal-width intervals |
| Equal-frequency | `"Age:freq:4"` | N bins with approximately equal counts |
| Custom breaks | `"Score:breaks:0,50,70,100"` | User-specified bin edges |
| Top-N | `"City:top:5"` | Keep N most frequent categories, merge rest to "Other" |
| Frequency threshold | `"Cat:thresh:0.05"` | Collapse categories below threshold (ratio or count) |

**Examples:**
```bash
# Auto-bin all high-cardinality columns (>10 unique values)
./bin/cli bin -i data.csv --auto --verbose

# Per-variable binning with specific strategies
./bin/cli bin -i data.csv -o binned.json \
  --var "Age:freq:4" \
  --var "Income:breaks:0,40000,70000,100000" \
  --var "City:top:5"

# Full pipeline: bin continuous data then search
./bin/cli bin -i raw.csv -o prepped.json --auto
./bin/cli search -i prepped.json -s loopless-up --levels 5
```

**Missing value handling:**
The binning module detects missing values (empty strings, "NA", "N/A", "null", ".", "-") and can:
- Create a separate "Missing" bin (default)
- Exclude rows with missing values
- Pass through as-is

### `preprocess` - Convert and optimize data for analysis

The `preprocess` command converts raw data files (CSV, JSON, OCCAM .in format) into an optimized pre-aggregated JSON format that loads 4x faster and compresses 100-500x smaller.

```bash
./bin/cli preprocess -i data.csv [options]

Options:
  -i, --input        Input file (required) - CSV, JSON, or OCCAM .in format
  -o, --output       Output JSON file (stdout if empty)
  -f, --format       Input format: auto, json, csv, occam (default: auto)
  -c, --columns      Columns to include (see below)
  -a, --autoBin      Auto-bin high-cardinality columns
  -t, --targetCard   Target cardinality for auto-binning (default: 5)
  -b, --binThreshold Only bin columns with cardinality > threshold (default: 10)
  --hasHeader        CSV has header row (default: true)
  -d, --delimiter    CSV column delimiter (default: ,)
  --dv               Dependent variable column index for CSV (-1 for none)
  -n, --name         Dataset name (defaults to filename)
  -v, --verbose      Show detailed output
```

**Column Selection (`--columns`):**
- By index: `--columns="0,2,4"`
- By range: `--columns="0-3"`
- By name: `--columns="Age,Gender,Target"`
- Mixed: `--columns="0,2-4,Age,Target"`
- All columns: `--columns="*"` (default)

**Examples:**
```bash
# Basic preprocessing - convert CSV to optimized JSON
./bin/cli preprocess -i data.csv -o data.json -v

# Select specific columns by index
./bin/cli preprocess -i data.json -o subset.json --columns="0,1,2,5" -v

# Select columns by name from CSV
./bin/cli preprocess -i data.csv -o output.json --columns="Age,Income,Target" --dv=2 -v

# Auto-bin high-cardinality columns
./bin/cli preprocess -i data.csv -o binned.json --autoBin --targetCard=3 -v

# Full pipeline: select columns + bin + aggregate
./bin/cli preprocess -i rawdata.csv -o processed.json \
  --columns="Age,Income,Education,Target" \
  --autoBin --targetCard=5 --binThreshold=10 \
  --dv=3 -v
```

**Performance Benefits:**
| Input | Output | Compression | Load Time |
|-------|--------|-------------|-----------|
| 41MB raw JSON (3M rows) | 6.7MB (92K states) | 6x | 4x faster |
| Same → 4 columns | 170KB (2.9K states) | 248x | 10x faster |
| + binning to card=3 | 1KB (8 states) | 542x | instant |

**When to use preprocess:**
- Large datasets (>10K rows) - aggregation dramatically reduces file size
- High-cardinality variables - binning reduces state space
- Column selection - analyze subsets without modifying original data
- Format conversion - convert legacy OCCAM .in files to modern JSON

---

## Web Server

OCCAM-Nim includes a REST API server built with [Prologue](https://github.com/planety/prologue) for integration with web frontends.

### Running the Server

```bash
# Install dependencies and build
cd packages/occam_web && nimble install -d
cd ../.. && nimble web

# Run the server
./bin/web
# Server starts on http://localhost:8080
```

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/health` | GET | Health check, returns server status |
| `/api/data/info` | POST | Get dataset information (variables, sample size) |
| `/api/model/fit` | POST | Fit a model and return statistics |
| `/api/search` | POST | Run model search |

### Example Requests

**Health Check:**
```bash
curl http://localhost:8080/api/health
# {"status":"ok","version":"0.1.0"}
```

**Fit a Model:**
```bash
curl -X POST http://localhost:8080/api/model/fit \
  -H "Content-Type: application/json" \
  -d '{
    "data": "{\"name\":\"test\",\"variables\":[{\"name\":\"A\",\"abbrev\":\"A\",\"cardinality\":2},{\"name\":\"B\",\"abbrev\":\"B\",\"cardinality\":2}],\"data\":[[\"0\",\"0\"],[\"0\",\"1\"],[\"1\",\"0\"],[\"1\",\"1\"]],\"counts\":[10,20,30,40]}",
    "model": "AB"
  }'
```

**Search for Models:**
```bash
curl -X POST http://localhost:8080/api/search \
  -H "Content-Type: application/json" \
  -d '{
    "data": "<json-data-string>",
    "direction": "up",
    "filter": "loopless",
    "width": 3,
    "levels": 7,
    "sortBy": "bic"
  }'
```

### CORS Support

The server includes CORS middleware for React/frontend development. All origins are allowed by default.

---

## MCP Server (AI Integration)

OCCAM-Nim provides a [Model Context Protocol](https://modelcontextprotocol.io/) server for integration with AI tools like Claude.

### Building the MCP Server

```bash
cd packages/occam_mcp && nimble install -d
cd ../.. && nimble mcp
```

### Configuration

Add to your Claude Desktop configuration (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "occam": {
      "command": "/path/to/occam-nim/bin/mcp"
    }
  }
}
```

### Available Tools

| Tool | Description |
|------|-------------|
| `occam_load_data` | Load a dataset from JSON format |
| `occam_info` | Get information about the loaded dataset |
| `occam_fit_model` | Fit a model and compute statistics |
| `occam_search` | Search for optimal models |

### Example MCP Interaction

```json
// Request: Initialize
{"jsonrpc":"2.0","method":"initialize","id":1}

// Response
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","serverInfo":{"name":"occam-mcp","version":"0.1.0"},"capabilities":{"tools":{}}}}

// Request: List tools
{"jsonrpc":"2.0","method":"tools/list","id":2}

// Request: Load data
{"jsonrpc":"2.0","method":"tools/call","id":3,"params":{
  "name":"occam_load_data",
  "arguments":{"data":"<json-dataset>"}
}}

// Request: Fit a model
{"jsonrpc":"2.0","method":"tools/call","id":4,"params":{
  "name":"occam_fit_model",
  "arguments":{"model":"AB:BC"}
}}
```

### Tool Input Schemas

**occam_load_data:**
```json
{
  "data": "JSON string containing dataset with name, variables, data, counts"
}
```

**occam_fit_model:**
```json
{
  "model": "Model notation using variable abbreviations (e.g., 'AB:BC:AC')"
}
```

**occam_search:**
```json
{
  "direction": "up|down (default: up)",
  "filter": "loopless|full|disjoint (default: loopless)",
  "width": "integer (default: 3)",
  "levels": "integer (default: 7)"
}
```

---

## Testing

### Run All Unit Tests

```bash
# Core library tests
nimble test

# Web handler tests (after building)
./tests/web/test_handlers

# MCP tests (after building)
./tests/mcp/test_jsonrpc
./tests/mcp/test_protocol
```

### Test Web Server Manually

```bash
# Start the server
./bin/web

# In another terminal:
curl http://localhost:8080/api/health
# Expected: {"status":"ok","version":"0.1.0"}
```

### Test MCP Server Manually

```bash
# Initialize
echo '{"jsonrpc":"2.0","method":"initialize","id":1}' | ./bin/mcp
# Expected: {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05",...}}

# List tools
echo '{"jsonrpc":"2.0","method":"tools/list","id":2}' | ./bin/mcp
```

### Quick Smoke Test

```bash
nimble test && \
  ./tests/web/test_handlers && \
  ./tests/mcp/test_jsonrpc && \
  ./tests/mcp/test_protocol && \
  echo '{"jsonrpc":"2.0","method":"initialize","id":1}' | ./bin/mcp | grep -q "occam-mcp" && \
  echo "✓ All tests passed!"
```

---

## JSON Input Format

OCCAM-Nim uses a JSON format for data input:

```json
{
  "name": "Dataset Name",
  "variables": [
    {
      "name": "Gender",
      "abbrev": "G",
      "cardinality": 2,
      "isDependent": false,
      "values": ["Female", "Male"]
    },
    {
      "name": "Outcome",
      "abbrev": "O",
      "cardinality": 2,
      "isDependent": true,
      "values": ["No", "Yes"]
    }
  ],
  "data": [
    ["Female", "Yes"],
    ["Male", "No"]
  ],
  "counts": [45, 32]
}
```

### Fields
- **name**: Dataset description
- **variables**: Array of variable definitions
  - **name**: Full variable name
  - **abbrev**: Single-letter abbreviation (used in model notation)
  - **cardinality**: Number of possible values
  - **isDependent**: true for dependent variables (directed systems)
  - **values**: Array of value labels
- **data**: Array of observations (each row is an array of values)
- **counts**: Frequency of each observation (same length as data)

### Pre-Aggregated Format

The `preprocess` command outputs an optimized pre-aggregated format that stores unique state combinations with their frequency counts:

```json
{
  "name": "processed_data",
  "format": "aggregated",
  "variables": [
    {"name": "Age", "abbrev": "A", "cardinality": 3, "values": ["Young", "Middle", "Old"]},
    {"name": "Target", "abbrev": "Z", "cardinality": 2, "isDependent": true, "values": ["No", "Yes"]}
  ],
  "data": [[0, 0], [0, 1], [1, 0], [1, 1], [2, 0], [2, 1]],
  "counts": [45.0, 32.0, 28.0, 41.0, 19.0, 35.0],
  "sampleSize": 200.0,
  "uniqueStates": 6
}
```

**Key differences from raw format:**
- `"format": "aggregated"` - Signals 0-indexed integer data (no lookup needed)
- **data** - Contains 0-indexed integers instead of string values
- **counts** - Frequency of each unique state combination
- **sampleSize** - Total observations (sum of counts)
- **uniqueStates** - Number of unique state combinations

**Benefits:**
- 100-500x smaller file size (stores states, not observations)
- 4x faster loading (no string parsing, direct integer indexing)
- Identical analysis results (frequency-weighted)

## Model Notation

Models are expressed using colon-separated relations:
- `A:B:C` - Independence model (no associations)
- `AB:C` - A and B are associated, C is independent
- `AB:BC` - Chain: A-B-C (A and C conditionally independent given B)
- `AB:BC:AC` - Triangle (loop model - requires IPF)
- `ABC` - Saturated model (all variables associated)

For directed systems with dependent variable Z:
- `AB:Z` - Independence (IVs associated, DV independent)
- `AB:AZ` - A predicts Z
- `AB:ABZ` - Both A and B predict Z (saturated)

## Statistics

### Core Statistics
| Statistic | Description |
|-----------|-------------|
| H | Shannon entropy (bits) |
| T | Transmission (reduction in uncertainty) |
| DF | Degrees of freedom |
| DDF | Delta DF (difference from reference) |
| LR | Likelihood ratio statistic |
| Alpha | p-value from chi-squared distribution |
| AIC | Akaike Information Criterion |
| BIC | Bayesian Information Criterion |

### Directed System Statistics
| Statistic | Description |
|-----------|-------------|
| H(DV\|IVs) | Conditional entropy of DV given IVs |
| ΔH | Uncertainty reduction: H(DV) - H(DV\|IVs) |
| % Correct | Prediction accuracy |
| Coverage | % of state space with observations |
| Incr. Alpha | p-value comparing two models |

## Examples

### Example 1: Neutral System Search
```bash
# Convert example file
./bin/cli convert -i examples/occam-format/search.in -o /tmp/search.json

# Run search
./bin/cli search -i /tmp/search.json --verbose
```

### Example 2: CSV with Dependent Variable
```bash
# Analyze CSV structure first
./bin/cli analyze-csv -i mydata.csv

# Convert with column 3 as DV, only use columns 0,1,2,3
./bin/cli csv-to-json -i mydata.csv --columns 0,1,2,3 --dv 3 -o mydata.json

# Search for predictive models
./bin/cli search -i mydata.json --direction up --sort bic
```

### Example 3: Interactive CSV Conversion
```bash
./bin/cli analyze-csv -i mydata.csv --interactive
```
This prompts you to:
1. Select which columns to include
2. Specify the dependent variable
3. Save the generated JSON

## E2E Tests with UCI Machine Learning Datasets

OCCAM-Nim includes comprehensive end-to-end tests using real-world datasets from the [UCI Machine Learning Repository](https://archive.ics.uci.edu/). These tests validate that the RA algorithms correctly compute entropy, transmission, degrees of freedom, and find meaningful structure in real data.

### Running E2E Tests

```bash
nimble test  # Runs all tests including E2E
```

Or run individual dataset tests:
```bash
nim c -r tests/e2e/test_uci_car.nim
nim c -r tests/e2e/test_uci_zoo.nim
```

### Dataset Overview

| Dataset | Instances | Variables | Target | State Space | Coverage |
|---------|-----------|-----------|--------|-------------|----------|
| Car Evaluation | 1,728 | 7 (6 IV + 1 DV) | Acceptability (4 classes) | 6,912 | 25% |
| Tic-Tac-Toe | 958 | 10 (9 IV + 1 DV) | Win/Lose (binary) | 39,366 | 2.4% |
| Zoo | 101 | 17 (16 IV + 1 DV) | Animal type (7 classes) | 1.4M+ | <0.01% |
| Mushroom | 8,124 | 23 (22 IV + 1 DV) | Edible/Poisonous (binary) | 244 trillion | ~0% |
| Nursery | 12,960 | 9 (8 IV + 1 DV) | Recommendation (5 classes) | 64,800 | 20% |

### What OCCAM Discovers

#### Car Evaluation Dataset
Tests model search and entropy analysis on a decision-making dataset.

```
Data Characteristics:
  Variables: buying, maint, doors, persons, lug_boot, safety → class
  Cardinalities: 4,4,4,3,3,3,4
  Data entropy: 10.75 bits (84.3% of maximum)

Key Findings:
  - Class (acceptability) has lowest marginal entropy (1.206 bits)
  - All IV features are uniformly distributed (100% efficiency)
  - Reference models span DF=1,730 (independence) to DF=6,911 (saturated)
```

**Algorithm Verification**: Tests that BIC correctly penalizes overly complex models, that loopless search generates valid decomposable neighbors, and that IPF converges for loop models.

#### Tic-Tac-Toe Dataset
Tests symmetry detection and game position analysis.

```
Data Characteristics:
  9 board positions (x/o/blank) + binary outcome
  State space: 39,366 possible boards
  Observed: 958 end-game configurations (2.4% coverage)

Key Findings - Position Importance (MI with outcome):
  Center (E): 0.0872 bits - highest predictive power
  Corners (A,C,G,I): 0.0136 bits each - symmetric importance
  Edges (B,D,F,H): 0.0070 bits each - lowest importance
```

**Algorithm Verification**: Confirms entropy calculations detect the known symmetry of tic-tac-toe (corners equivalent, edges equivalent, center unique). The mutual information correctly identifies center control as the most important factor.

#### Zoo Dataset
Tests small-scale analysis with mostly binary features.

```
Data Characteristics:
  101 animals, 15 binary features + legs (int) + type (7 classes)
  Most features binary (hair, feathers, eggs, milk, etc.)
  7 animal types: mammal, bird, reptile, fish, amphibian, insect, invertebrate

Key Findings - Feature Entropies (max 1.0 for binary):
  predator (P): 0.991 - nearly 50/50 split
  hair (H): 0.984 - well-distributed
  venomous (V): 0.399 - highly skewed (few venomous)
  Type (DV) entropy: 2.39 bits (85.2% of max 2.81 bits)
```

**Algorithm Verification**: Tests reference model computation on a small, tractable dataset where full lattice enumeration is feasible. Validates that loopless and full search produce consistent results.

#### Mushroom Dataset
Stress tests with high-dimensional sparse data.

```
Data Characteristics:
  8,124 mushroom samples
  22 features (cap shape, odor, habitat, etc.)
  Binary outcome: edible (51.8%) vs poisonous (48.2%)
  Theoretical state space: 244 trillion states

Key Findings:
  - State space is astronomically larger than sample size
  - Missing values in stalk-root handled as separate category
  - High-cardinality variables: gill-color (12), cap-color (10), odor (9)
  - Class is nearly perfectly balanced
```

**Algorithm Verification**: Tests handling of extremely sparse data where the state space dwarfs available samples. Validates that statistics remain numerically stable with very large degrees of freedom (>10^14).

#### Nursery Dataset
Medium-scale test with multi-class prediction.

```
Data Characteristics:
  12,960 nursery school applications
  8 features → 5-class recommendation
  20% coverage of state space (dense for RA)

Key Findings - Variable Importance (MI with recommendation):
  health (L): 0.9588 bits - dominant predictor
  has_nurs (N): 0.1964 bits - moderate importance
  parents (P): 0.0729 bits
  finance (I): 0.0043 bits - least predictive

Class Distribution:
  not_recom: 33.3%, priority: 32.9%, spec_prior: 31.2%
  very_recom: 2.5%, recommend: 0.0%

All IVs at 100% entropy efficiency (uniform distributions)
```

**Algorithm Verification**: Tests chain model enumeration (181,440 possible chains), validates that marginal entropy calculations correctly identify uniform vs. skewed distributions, and confirms MI rankings match domain knowledge (health is most important for nursery admission).

### Test Coverage Matrix

| Feature | Car | TTT | Zoo | Mush | Nurs |
|---------|-----|-----|-----|------|------|
| CSV loading & JSON conversion | ✓ | ✓ | ✓ | ✓ | ✓ |
| Reference model computation | ✓ | ✓ | ✓ | ✓ | ✓ |
| Loopless search | ✓ | ✓ | ✓ | ✓ | ✓ |
| Full search (with IPF) | ✓ | | ✓ | | |
| Entropy bounds validation | ✓ | ✓ | ✓ | ✓ | ✓ |
| Mutual information | | ✓ | | ✓ | ✓ |
| Missing value handling | | | | ✓ | |
| Chain model enumeration | | | | | ✓ |
| Large state space handling | | | ✓ | ✓ | |
| Binary variable analysis | | | ✓ | | |
| Multi-class DV | ✓ | | ✓ | | ✓ |
| Symmetry detection | | ✓ | | | |

### Dataset Auto-Download

The E2E tests automatically download and convert UCI datasets on first run. Datasets are cached in `tests/fixtures/uci/` as both CSV (raw) and JSON (OCCAM format).

If download fails (e.g., SSL issues), manually download with:
```bash
curl -o tests/fixtures/uci/car.csv https://archive.ics.uci.edu/ml/machine-learning-databases/car/car.data
# Repeat for other datasets...
```

The test framework will auto-convert CSV to JSON on next run.

## Project Structure

```
occam-nim/
├── packages/                   # Sub-packages for optional components
│   ├── occam_cli/              # CLI package
│   │   └── occam_cli.nimble
│   ├── occam_web/              # Web server package
│   │   └── occam_web.nimble
│   └── occam_mcp/              # MCP server package
│       └── occam_mcp.nimble
├── src/
│   ├── occam.nim               # Library entry point
│   ├── cli.nim                 # CLI entry point
│   ├── web.nim                 # Web server entry point
│   ├── mcp.nim                 # MCP server entry point
│   ├── cli_lib/                # CLI command implementations
│   │   ├── cmd_search.nim      # Search command (parallel by default)
│   │   ├── cmd_fit.nim         # Fit command
│   │   ├── cmd_convert.nim     # Format conversion commands
│   │   ├── cmd_generate.nim    # Data generation commands
│   │   ├── cmd_preprocess.nim  # Preprocess command (column selection, binning)
│   │   └── formatting.nim      # Output formatting utilities
│   ├── web_lib/                # Web server components
│   │   ├── models.nim          # Request/response types
│   │   └── logic.nim           # Business logic (testable)
│   ├── mcp_lib/                # MCP server components
│   │   ├── jsonrpc.nim         # JSON-RPC 2.0 implementation
│   │   └── protocol.nim        # MCP protocol handlers
│   └── occam/
│       ├── core/
│       │   ├── types.nim       # Core types (Cardinality, Key, etc.)
│       │   ├── variable.nim    # Variable and VariableList
│       │   ├── key.nim         # Key encoding/decoding
│       │   ├── table.nim       # Contingency tables
│       │   ├── relation.nim    # Relations (variable sets)
│       │   ├── model.nim       # Models (relation sets)
│       │   ├── graph.nim       # Graph representation, MCS algorithm
│       │   └── junction_tree.nim # Junction tree construction
│       ├── math/
│       │   ├── entropy.nim     # Entropy calculations
│       │   ├── statistics.nim  # DF, LR, AIC, BIC
│       │   ├── ipf.nim         # Iterative Proportional Fitting
│       │   └── belief_propagation.nim # BP for decomposable models
│       ├── search/
│       │   ├── loopless.nim    # Loopless search algorithm
│       │   ├── full.nim        # Full search (includes loops)
│       │   ├── disjoint.nim    # Disjoint search algorithm
│       │   ├── chain.nim       # Chain model generation
│       │   ├── lattice.nim     # Lattice enumeration
│       │   └── parallel.nim    # Parallel search (malebolgia)
│       ├── parallel/
│       │   └── eval.nim        # Parallel model evaluation
│       ├── manager/
│       │   ├── vb.nim          # Variable-Based manager
│       │   ├── analysis.nim    # Confusion matrix, conditional DV
│       │   ├── statistics.nim  # Pure entropy/statistics functions
│       │   └── fitting.nim     # Pure model fitting functions
│       └── io/
│           ├── parser.nim      # JSON input parsing + loadAndAggregate
│           ├── formats.nim     # Format conversion
│           ├── binning.nim     # Variable binning/discretization
│           └── synthetic.nim   # Synthetic data generation
├── tests/
│   ├── *.nim                   # Unit test files
│   ├── test_preprocess.nim     # Column selection & binning tests
│   ├── test_parallel_search.nim # Parallel search correctness tests
│   ├── benchmark_*.nim         # Performance benchmarks
│   ├── web/                    # Web server tests
│   │   └── test_handlers.nim   # Handler logic tests (8 tests)
│   ├── mcp/                    # MCP server tests
│   │   ├── test_jsonrpc.nim    # JSON-RPC 2.0 tests (10 tests)
│   │   └── test_protocol.nim   # MCP protocol tests (6 tests)
│   ├── e2e/                    # End-to-end tests
│   │   ├── uci_helpers.nim     # UCI dataset download/convert utilities
│   │   ├── test_uci_car.nim    # Car Evaluation tests
│   │   ├── test_uci_tictactoe.nim
│   │   ├── test_uci_zoo.nim
│   │   ├── test_uci_mushroom.nim
│   │   └── test_uci_nursery.nim
│   └── fixtures/
│       └── uci/                # Cached UCI datasets (auto-populated)
├── data/                       # Large datasets for benchmarking
│   ├── primes_R3_R17.json      # 92K states, 3M primes
│   └── primes_R3_R17_agg.json  # Pre-aggregated version
├── docs/
│   ├── PARALLELIZATION.md      # Parallelization guidelines
│   ├── PREPROCESS.md           # Preprocessing guide
│   └── IPF_VS_BP.md            # Iteratove Proportional Fitting vs Belief Propagation docs
├── examples/
│   ├── occam-format/           # Original OCCAM .in files
│   └── json/                   # Converted JSON examples
└── README.md
```

## References

- Zwick, M. (2004). An Overview of Reconstructability Analysis. *Kybernetes*, 33(5/6), 877-905.
- Krippendorff, K. (1986). *Information Theory: Structural Models for Qualitative Data*. Sage.
- OCCAM original: https://github.com/occam-ra/occam (source code and documentation)

## License

MIT License
