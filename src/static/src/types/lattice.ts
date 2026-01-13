/**
 * Types for the model lattice visualization.
 *
 * In OCCAM, models form a lattice where:
 * - The bottom is the independence model (e.g., "A:B:C:D")
 * - The top is the saturated model (e.g., "ABCD")
 * - Models are connected if they differ by exactly one relation complexity
 */

import type { SimulationNodeDatum, SimulationLinkDatum } from 'd3';

/** Node status in the lattice visualization */
export type LatticeNodeStatus =
  | 'pending'     // Not yet evaluated
  | 'evaluating'  // Currently being evaluated
  | 'evaluated'   // Evaluation complete
  | 'best'        // Current best model
  | 'pruned';     // Pruned from search

/** Statistics for an evaluated model */
export interface LatticeNodeStats {
  h: number;
  aic: number;
  bic: number;
  ddf: number;
  hasLoops: boolean;
}

/**
 * A node in the lattice visualization.
 * Extends D3's SimulationNodeDatum for force simulation compatibility.
 */
export interface LatticeNode extends SimulationNodeDatum {
  /** Model name (e.g., "AB:BC") - used as unique ID */
  id: string;

  /** Level in the lattice (0 = independence model) */
  level: number;

  /** Parsed relations (e.g., ["AB", "BC"]) */
  relations: string[];

  /** Current status in the visualization */
  status: LatticeNodeStatus;

  /** Statistics if model has been evaluated */
  stats?: LatticeNodeStats;

  // D3 simulation will add: x, y, vx, vy, fx, fy
}

/**
 * An edge connecting two models in the lattice.
 * Extends D3's SimulationLinkDatum for force simulation compatibility.
 */
export interface LatticeEdge extends SimulationLinkDatum<LatticeNode> {
  /** Unique edge identifier */
  id: string;

  /** Source node (more complex model) */
  source: string | LatticeNode;

  /** Target node (less complex model) */
  target: string | LatticeNode;
}

/**
 * Complete lattice data structure for visualization.
 */
export interface LatticeData {
  /** All nodes in the lattice */
  nodes: LatticeNode[];

  /** Edges connecting related models */
  edges: LatticeEdge[];

  /** Independence model (bottom of lattice) */
  independenceModel: string;

  /** Saturated model (top of lattice) */
  saturatedModel: string;

  /** Total number of levels */
  totalLevels: number;

  /** Current best model (if search complete) */
  currentBestModel?: string;

  /** Ordered path of search traversal */
  searchPath?: string[];
}

/**
 * Parse a model string into its component relations.
 * @param model - Model string (e.g., "AB:BC:AC")
 * @returns Array of relation strings (e.g., ["AB", "BC", "AC"])
 */
export function parseModelRelations(model: string): string[] {
  return model.split(':').filter((r) => r.length > 0);
}

/**
 * Calculate the level of a model based on its complexity.
 * Level = sum of (relation size - 1) for each relation.
 *
 * Examples:
 * - "A:B:C" → level 0 (independence)
 * - "AB:C" → level 1
 * - "AB:BC" → level 2
 * - "ABC" → level 2 (for 3 variables)
 *
 * @param relations - Array of relation strings
 * @returns Level number (0 = independence)
 */
export function calculateModelLevel(relations: string[]): number {
  return relations.reduce((sum, rel) => sum + rel.length - 1, 0);
}

/**
 * Check if two models are parent-child in the lattice.
 * Parent is more complex (higher level) than child.
 *
 * Models are neighbors if they differ by exactly one "step" in complexity.
 *
 * @param parentRels - Relations of the potential parent
 * @param childRels - Relations of the potential child
 * @returns true if parent contains child with one additional variable pair
 */
export function areModelsNeighbors(
  parentRels: string[],
  childRels: string[]
): boolean {
  const parentLevel = calculateModelLevel(parentRels);
  const childLevel = calculateModelLevel(childRels);

  // Parent must be exactly one level higher
  if (parentLevel !== childLevel + 1) return false;

  // Get all variables from each model
  const parentVars = new Set(parentRels.flatMap((r) => r.split('')));
  const childVars = new Set(childRels.flatMap((r) => r.split('')));

  // All child variables should be in parent
  for (const v of childVars) {
    if (!parentVars.has(v)) return false;
  }

  return true;
}
