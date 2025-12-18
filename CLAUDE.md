# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OCCAM-Nim is a Nim library for Reconstructability Analysis (RA) - discrete multivariate modeling using information theory and graph theory. It computes entropy, transmission, model search, and supports both decomposable models (via belief propagation) and loop models (via IPF).

## Build Commands

```bash
# Install dependencies
nimble install -d

# Run all tests
nimble test

# Run a single test file
nim c -r --threads:on tests/test_parser.nim

# Build CLI (release mode)
nimble cli

# Build web server (requires packages/occam_web deps first)
cd packages/occam_web && nimble install -d && cd ../..
nimble web

# Build MCP server (requires packages/occam_mcp deps first)
cd packages/occam_mcp && nimble install -d && cd ../..
nimble mcp

# Run benchmarks
nimble benchmark
nim c -d:release -r --threads:on tests/benchmark_parallel.nim
```

## Architecture

### Multi-Package Monorepo

- `occam.nimble` - Core library (installed via `nimble install occam`)
- `packages/occam_cli/` - CLI package (cligen dependency)
- `packages/occam_web/` - Web server (prologue, chronicles)
- `packages/occam_mcp/` - MCP server for AI integration

### Module Organization (src/occam/)

| Directory | Purpose |
|-----------|---------|
| `core/` | Types (Variable, Table, Relation, Model), Key encoding, Graph/Junction tree |
| `math/` | Entropy, statistics (DF, LR, AIC, BIC), IPF, belief propagation |
| `manager/` | VBManager coordinates fitting; analysis.nim for confusion matrix |
| `search/` | loopless, full, disjoint, chain search algorithms; parallel.nim for malebolgia parallelization |
| `io/` | parser.nim (JSON loading), formats.nim (OCCAM .in), binning.nim |
| `parallel/` | eval.nim for model-level parallel evaluation |

### Key Types

- `VariableList` - Collection of variables with abbreviations and cardinalities
- `Table` - Contingency table (sparse, uses Key for addressing)
- `Key` - Packed integer representation of variable states
- `Model` - Set of Relations representing variable associations
- `VBManager` - Main API for model fitting and statistics

### Parallelization

Uses **malebolgia** (not deprecated std/threadpool). Two approaches:
- Search-level (`search/parallel.nim`): Parallelizes across seed models, best for width>2
- Model-level (`parallel/eval.nim`): Parallelizes individual model evaluations

**Important**: Always measure with wall clock time (`getMonoTime()`), not `cpuTime()`.

## CLI Usage

```bash
# Analyze CSV structure
./bin/cli analyze-csv -i data.csv

# Convert CSV to JSON (column 3 as DV)
./bin/cli csv-to-json -i data.csv --dv 3 -o data.json

# Model search (parallel by default)
./bin/cli search -i data.json --direction up --filter loopless --width 5 --levels 7

# Fit specific model
./bin/cli fit -i data.json -m "AB:BC:AC"

# Preprocess (aggregate + optional binning)
./bin/cli preprocess -i data.csv -o processed.json --autoBin --targetCard=5
```

## Testing

- Unit tests: `tests/test_*.nim` - run with `nimble test`
- E2E tests: `tests/e2e/test_uci_*.nim` - uses UCI ML datasets (auto-downloaded)
- Benchmarks: `tests/benchmark_*.nim` - run individually with release mode

## Model Notation

- `A:B:C` - Independence (no associations)
- `AB:BC` - Chain (A-B-C, conditional independence)
- `AB:BC:AC` - Triangle (loop model, requires IPF)
- `ABC` - Saturated (all associated)

For directed systems with DV Z: `AB:AZ` means A predicts Z.

## JSON Data Format

```json
{
  "name": "Dataset",
  "variables": [
    {"name": "Age", "abbrev": "A", "cardinality": 3, "isDependent": false, "values": ["Y","M","O"]}
  ],
  "data": [["Y","No"], ["M","Yes"]],
  "counts": [45, 32]
}
```

Pre-aggregated format uses `"format": "aggregated"` with integer indices instead of string values.

## Custom Agents

This project includes specialized Claude Code agents in `.claude/agents/`:
- `tdd-enforcer` - Invoke before implementation to ensure tests drive design
- `nim-idioms` - Review code for idiomatic Nim patterns (especially for C++ ports)
- `architect` - Module organization and dependency structure
- `perf-analyst` - Benchmarking and performance analysis
