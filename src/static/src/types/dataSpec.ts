/**
 * Types mirroring Nim DataSpec/VariableSpec from src/occam/io/parser.nim
 * This is the single source of truth for all data and search types.
 */

// =============================================================================
// Data Types
// =============================================================================

export interface VariableSpec {
  name: string;
  abbrev: string;
  cardinality: number;
  values: string[];
  isDependent: boolean;
}

export interface DataSpec {
  name: string;
  variables: VariableSpec[];
  data: string[][];
  counts: number[];
}

export interface DataInfo {
  name: string;
  variableCount: number;
  sampleSize: number;
  variables: VariableSpec[];
}

// =============================================================================
// Search Types
// =============================================================================

/** Search parameter configuration */
export interface SearchParams {
  direction: 'up' | 'down';
  filter: 'loopless' | 'full' | 'disjoint';
  width: number;
  levels: number;
  sortBy: 'bic' | 'aic' | 'ddf';
}

/** For WebSocket requests - includes data payload */
export interface SearchRequest extends SearchParams {
  data: string;
}

/** Individual model result from search */
export interface SearchResult {
  model: string;
  h: number;
  aic: number;
  bic: number;
  ddf: number;
  hasLoops: boolean;
}

/** Search status state */
export type SearchStatus = 'idle' | 'connecting' | 'searching' | 'complete' | 'error';

/** Search error information */
export interface SearchError {
  code: string;
  message: string;
}

/** Progress updates during search */
export interface SearchProgress {
  currentLevel: number;
  totalLevels: number;
  modelsEvaluated: number;
  looplessModels?: number;  // Models without loops (fast BP)
  loopModels?: number;      // Models with loops (slow IPF)
  bestModelName?: string;
  bestStatistic?: number;
  statisticName?: string;
  // Timing info
  levelTimeMs?: number;     // Time for this level in ms
  elapsedMs?: number;       // Total elapsed time in ms
  avgModelTimeMs?: number;  // Average time per model in ms
}

// =============================================================================
// Fit Types
// =============================================================================

/** Result from fitting a specific model */
export interface FitResult {
  model: string;
  h: number;
  t: number;
  df: number;
  ddf: number;
  lr: number;
  aic: number;
  bic: number;
  alpha: number;
  hasLoops: boolean;
  ipfIterations: number;
  ipfError: number;
  timestamp: number;
}
