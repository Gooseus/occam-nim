import React, { useState, useMemo, useCallback } from 'react';
import { ModelLatticeCanvas } from './ModelLatticeCanvas';
import { LatticeControls } from './LatticeControls';
import { LatticeModelPanel } from './LatticeModelPanel';
import type { LatticeNode, LatticeEdge, LatticeData } from '../../types/lattice';
import {
  parseModelRelations,
  calculateModelLevel,
  areModelsNeighbors,
} from '../../types/lattice';
import type { SearchResult } from '../../types/dataSpec';
import { colors, spacing } from '../../lib/theme';

interface ModelLatticeContainerProps {
  searchResults: SearchResult[];
  currentBest?: string;
  width?: number;
  height?: number;
  onFitModel: (model: string) => void;
}

/**
 * Builds lattice data from search results.
 * Creates nodes for each evaluated model and edges between related models.
 */
function buildLatticeData(
  results: SearchResult[],
  currentBest?: string
): LatticeData {
  const nodes: LatticeNode[] = [];
  const edges: LatticeEdge[] = [];

  // Create nodes from results
  for (const result of results) {
    const relations = parseModelRelations(result.model);
    const level = calculateModelLevel(relations);

    const node: LatticeNode = {
      id: result.model,
      level,
      relations,
      status: result.model === currentBest ? 'best' : 'evaluated',
      stats: {
        h: result.h,
        aic: result.aic,
        bic: result.bic,
        ddf: result.ddf,
        hasLoops: result.hasLoops,
      },
    };

    nodes.push(node);
  }

  // Create edges between models that are neighbors
  for (let i = 0; i < nodes.length; i++) {
    for (let j = i + 1; j < nodes.length; j++) {
      const nodeA = nodes[i];
      const nodeB = nodes[j];

      // Check if models are neighbors (differ by one relation complexity)
      if (Math.abs(nodeA.level - nodeB.level) === 1) {
        const [parent, child] =
          nodeA.level > nodeB.level ? [nodeA, nodeB] : [nodeB, nodeA];

        if (areModelsNeighbors(parent.relations, child.relations)) {
          edges.push({
            id: `${parent.id}-${child.id}`,
            source: parent.id,
            target: child.id,
          });
        }
      }
    }
  }

  // Find extremes
  let independenceModel = '';
  let saturatedModel = '';
  let minLevel = Infinity;
  let maxLevel = -Infinity;

  for (const node of nodes) {
    if (node.level < minLevel) {
      minLevel = node.level;
      independenceModel = node.id;
    }
    if (node.level > maxLevel) {
      maxLevel = node.level;
      saturatedModel = node.id;
    }
  }

  return {
    nodes,
    edges,
    independenceModel,
    saturatedModel,
    totalLevels: maxLevel - minLevel + 1,
    currentBestModel: currentBest,
  };
}

export function ModelLatticeContainer({
  searchResults,
  currentBest,
  width = 800,
  height = 500,
  onFitModel,
}: ModelLatticeContainerProps) {
  const [showLoopsOnly, setShowLoopsOnly] = useState(false);
  const [selectedNode, setSelectedNode] = useState<LatticeNode | null>(null);
  const [, setForceUpdate] = useState(0);

  const latticeData = useMemo(
    () => buildLatticeData(searchResults, currentBest),
    [searchResults, currentBest]
  );

  const filteredNodes = useMemo(() => {
    if (showLoopsOnly) {
      return latticeData.nodes.filter((n) => n.stats?.hasLoops === true);
    }
    return latticeData.nodes;
  }, [latticeData.nodes, showLoopsOnly]);

  const filteredEdges = useMemo(() => {
    const nodeIds = new Set(filteredNodes.map((n) => n.id));
    return latticeData.edges.filter((e) => {
      const sourceId = typeof e.source === 'string' ? e.source : e.source.id;
      const targetId = typeof e.target === 'string' ? e.target : e.target.id;
      return nodeIds.has(sourceId) && nodeIds.has(targetId);
    });
  }, [latticeData.edges, filteredNodes]);

  const handleZoomIn = useCallback(() => {
    // Zoom is handled via D3 in canvas - this could be enhanced
    // to programmatically zoom if needed
  }, []);

  const handleZoomOut = useCallback(() => {
    // Zoom is handled via D3 in canvas
  }, []);

  const handleResetView = useCallback(() => {
    // Reset zoom/pan - could be enhanced to reset programmatically
  }, []);

  const handleReheat = useCallback(() => {
    setForceUpdate((n) => n + 1);
  }, []);

  const handleNodeClick = useCallback((node: LatticeNode) => {
    setSelectedNode(node);
  }, []);

  const handleClosePanel = useCallback(() => {
    setSelectedNode(null);
  }, []);

  const handleFitModel = useCallback(
    (model: string) => {
      onFitModel(model);
      setSelectedNode(null);
    },
    [onFitModel]
  );

  if (searchResults.length === 0) {
    return (
      <div style={styles.empty}>
        <p>No search results to visualize.</p>
        <p style={styles.hint}>Run a model search to see the lattice.</p>
      </div>
    );
  }

  // Calculate canvas width accounting for panel
  const canvasWidth = selectedNode ? width - 280 : width;

  return (
    <div style={styles.container}>
      <LatticeControls
        onZoomIn={handleZoomIn}
        onZoomOut={handleZoomOut}
        onResetView={handleResetView}
        onReheat={handleReheat}
        showLoopsOnly={showLoopsOnly}
        onToggleLoopsOnly={() => setShowLoopsOnly(!showLoopsOnly)}
        nodeCount={filteredNodes.length}
        edgeCount={filteredEdges.length}
      />

      <div style={styles.canvasContainer}>
        <ModelLatticeCanvas
          nodes={filteredNodes}
          edges={filteredEdges}
          width={canvasWidth}
          height={height - 40} // Account for controls
          onNodeClick={handleNodeClick}
        />

        <LatticeModelPanel
          node={selectedNode}
          onFitModel={handleFitModel}
          onClose={handleClosePanel}
        />
      </div>

      {/* Legend */}
      <div style={styles.legend}>
        <div style={styles.legendItem}>
          <span style={{ ...styles.legendDot, background: colors.primary }} />
          Best Model
        </div>
        <div style={styles.legendItem}>
          <span style={{ ...styles.legendDot, background: colors.success }} />
          Evaluated
        </div>
        <div style={styles.legendItem}>
          <span
            style={{
              ...styles.legendDot,
              background: colors.loopYes,
              width: 6,
              height: 6,
            }}
          />
          Has Loops
        </div>
      </div>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    border: `1px solid ${colors.borderMedium}`,
    borderRadius: '4px',
    overflow: 'hidden',
    background: colors.bgCard,
  },
  empty: {
    padding: spacing.xxl,
    textAlign: 'center',
    color: colors.textMuted,
  },
  hint: {
    fontSize: '0.8rem',
    marginTop: spacing.sm,
  },
  canvasContainer: {
    position: 'relative',
    display: 'flex',
  },
  legend: {
    display: 'flex',
    gap: spacing.lg,
    padding: spacing.sm,
    borderTop: `1px solid ${colors.borderLight}`,
    fontSize: '0.75rem',
    color: colors.textMuted,
  },
  legendItem: {
    display: 'flex',
    alignItems: 'center',
    gap: spacing.xs,
  },
  legendDot: {
    width: 10,
    height: 10,
    borderRadius: '50%',
    display: 'inline-block',
  },
};
