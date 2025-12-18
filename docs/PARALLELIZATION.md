# Parallelization in OCCAM-Nim

## IMPORTANT: Benchmarking Guidelines

**ALWAYS use:**
1. **malebolgia** (not deprecated std/threadpool)
2. **Wall clock time** (`getMonoTime()`) not `cpuTime()`

**Why this matters:**
- `cpuTime()` measures total CPU time across ALL cores
- When 6 threads each use 150ms CPU, `cpuTime()` reports 900ms
- Wall clock time correctly shows 150ms (6x speedup)

This mistake led to incorrectly concluding parallelization provided no benefit.

## Performance Summary

| Approach | Dataset | Speedup | Notes |
|----------|---------|---------|-------|
| Model-level (50 models) | R3-R17 (92K states) | **5.92x** | Best for batch evaluation |
| Search-level (width=7) | R3-R17 (92K states) | **2.02x** | Best for search |
| Search-level (width=3) | R3-R17 (92K states) | **1.63x** | Lower width = less benefit |

## Two Parallelization Approaches

### 1. Search-Level (`src/occam/search/parallel.nim`)

Parallelizes across seed models. Each seed's neighbors are generated and evaluated in parallel.

**Best when:**
- Multiple seed models (width > 2)
- Search operations with depth > 2

### 2. Model-Level (`src/occam/parallel/eval.nim`)

Parallelizes individual model evaluations. Each model is evaluated by a separate task.

**Best when:**
- Batch evaluation of many models
- Single-level operations

## When to Use Parallelization

### Model-Level Parallelization
Based on threshold benchmark with 30 models:

| State Space | Speedup | Recommendation |
|-------------|---------|----------------|
| < 50 states | ~1x | Sequential (overhead dominates) |
| 50-200 states | 2-4x | Parallel provides benefit |
| 200-1000 states | 4-5x | Strong parallelization benefit |
| > 1000 states | 5-6x | Maximum benefit (use parallel) |

**Use parallel when:**
- State space > ~50 states
- Evaluating > 4 models
- Per-model evaluation > ~0.02ms

**Use sequential when:**
- State space < ~50 states
- Very few models (<4)
- Per-model evaluation < 0.01ms

### Search-Level Parallelization
Best when multiple seed models need evaluation (width > 2, depth > 2).

## Implementation Notes

- Uses **malebolgia** (modern work-stealing library)
- Thread-local VBManagers avoid shared mutable state
- Global result arrays with indexed writes for thread safety
- Do NOT nest parallelization (causes thread pool contention)

## CLI Integration

Parallelization is **enabled by default** in the CLI search command:

```bash
# Uses all CPU cores by default
./bin/cli search -i data.json --width=5 --levels=7

# Disable parallelization if needed
./bin/cli search -i data.json --parallel=false
```

The CLI also automatically uses fast aggregation for large files (>1MB), which provides additional speedup.

## Example Usage (Library)

```nim
import occam/search/parallel

# Search-level parallelization
let results = parallelSearch(
  varList, inputTable, startModel, SearchLoopless,
  SearchAIC, width = 5, maxLevels = 4,
  useParallel = true  # Enable parallelization
)

# Model-level parallelization
import occam/parallel/eval

let aicValues = parallelComputeAIC(varList, inputTable, models)
```

## Files

| File | Description |
|------|-------------|
| `src/occam/search/parallel.nim` | Search-level parallelization |
| `src/occam/parallel/eval.nim` | Model-level parallelization |
| `src/cli_lib/cmd_search.nim` | CLI integration (parallel by default) |
| `tests/test_parallel_search.nim` | Correctness tests |
| `tests/benchmark_*.nim` | Performance benchmarks |
