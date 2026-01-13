import React, { useRef, useEffect, useState, useCallback, useMemo } from 'react';
import * as d3 from 'd3';
import { useLatticeSimulation } from './useLatticeSimulation';
import { LatticeTooltip } from './LatticeTooltip';
import type { LatticeNode, LatticeEdge, LatticeNodeStatus } from '../../types/lattice';
import { colors } from '../../lib/theme';

interface ModelLatticeCanvasProps {
  nodes: LatticeNode[];
  edges: LatticeEdge[];
  width: number;
  height: number;
  onNodeClick?: (node: LatticeNode) => void;
}

// Node colors by status
const nodeColors: Record<LatticeNodeStatus, string> = {
  pending: '#e0e0e0',
  evaluating: colors.warning,
  evaluated: colors.success,
  best: colors.primary,
  pruned: '#f0f0f0',
};

/**
 * SVG canvas for the model lattice visualization.
 * Uses D3 for force simulation math, React for rendering.
 */
export function ModelLatticeCanvas({
  nodes,
  edges,
  width,
  height,
  onNodeClick,
}: ModelLatticeCanvasProps) {
  const svgRef = useRef<SVGSVGElement>(null);
  const gRef = useRef<SVGGElement>(null);

  // Force re-render on simulation tick
  const [, setTick] = useState(0);

  // Tooltip state
  const [hoveredNode, setHoveredNode] = useState<LatticeNode | null>(null);
  const [tooltipPos, setTooltipPos] = useState({ x: 0, y: 0 });

  // D3 zoom behavior
  const zoomRef = useRef<d3.ZoomBehavior<SVGSVGElement, unknown> | null>(null);

  const simulationConfig = useMemo(
    () => ({
      width,
      height,
      onTick: () => setTick((t) => t + 1),
    }),
    [width, height]
  );

  const { createDragBehavior } = useLatticeSimulation(nodes, edges, simulationConfig);

  // Setup zoom
  useEffect(() => {
    if (!svgRef.current || !gRef.current) return;

    const svg = d3.select(svgRef.current);
    const g = d3.select(gRef.current);

    const zoom = d3
      .zoom<SVGSVGElement, unknown>()
      .scaleExtent([0.1, 4])
      .on('zoom', (event) => {
        g.attr('transform', event.transform);
      });

    svg.call(zoom);
    zoomRef.current = zoom;

    return () => {
      svg.on('.zoom', null);
    };
  }, []);

  // Setup drag on nodes
  useEffect(() => {
    if (!gRef.current) return;

    const drag = createDragBehavior();
    if (!drag) return;

    const g = d3.select(gRef.current);
    g.selectAll<SVGGElement, LatticeNode>('.node-group').call(drag);
  }, [nodes, createDragBehavior]);

  const handleNodeMouseEnter = useCallback(
    (event: React.MouseEvent, node: LatticeNode) => {
      setHoveredNode(node);
      setTooltipPos({ x: event.clientX, y: event.clientY });
    },
    []
  );

  const handleNodeMouseMove = useCallback((event: React.MouseEvent) => {
    setTooltipPos({ x: event.clientX, y: event.clientY });
  }, []);

  const handleNodeMouseLeave = useCallback(() => {
    setHoveredNode(null);
  }, []);

  // Create edge path data
  const edgePaths = useMemo(() => {
    const nodeMap = new Map(nodes.map((n) => [n.id, n]));

    return edges
      .map((edge) => {
        const source = nodeMap.get(
          typeof edge.source === 'string' ? edge.source : edge.source.id
        );
        const target = nodeMap.get(
          typeof edge.target === 'string' ? edge.target : edge.target.id
        );

        if (
          !source ||
          !target ||
          source.x === undefined ||
          target.x === undefined
        ) {
          return null;
        }

        return {
          id: edge.id,
          d: `M${source.x},${source.y}L${target.x},${target.y}`,
          sourceStatus: source.status,
          targetStatus: target.status,
        };
      })
      .filter(Boolean) as Array<{
      id: string;
      d: string;
      sourceStatus: LatticeNodeStatus;
      targetStatus: LatticeNodeStatus;
    }>;
  }, [nodes, edges]);

  return (
    <div style={{ position: 'relative', width, height }}>
      <svg
        ref={svgRef}
        width={width}
        height={height}
        style={{ background: '#fafafa', cursor: 'grab' }}
      >
        <g ref={gRef}>
          {/* Edges */}
          <g className="edges">
            {edgePaths.map((edge) => (
              <path
                key={edge.id}
                d={edge.d}
                stroke={
                  edge.sourceStatus === 'evaluated' &&
                  edge.targetStatus === 'evaluated'
                    ? colors.success
                    : colors.borderLight
                }
                strokeWidth={1.5}
                strokeOpacity={0.6}
                fill="none"
              />
            ))}
          </g>

          {/* Nodes */}
          <g className="nodes">
            {nodes.map((node) => (
              <g
                key={node.id}
                className="node-group"
                transform={`translate(${node.x ?? 0},${node.y ?? 0})`}
                style={{ cursor: 'pointer' }}
                onClick={() => onNodeClick?.(node)}
                onMouseEnter={(e) => handleNodeMouseEnter(e, node)}
                onMouseMove={handleNodeMouseMove}
                onMouseLeave={handleNodeMouseLeave}
              >
                {/* Node circle */}
                <circle
                  r={node.status === 'best' ? 12 : 8}
                  fill={nodeColors[node.status]}
                  stroke={
                    node.status === 'best' ? colors.primaryDark : colors.borderMedium
                  }
                  strokeWidth={node.status === 'best' ? 3 : 1}
                />

                {/* Loop indicator */}
                {node.stats?.hasLoops && (
                  <circle r={3} cx={6} cy={-6} fill={colors.loopYes} />
                )}

                {/* Label for evaluated nodes */}
                {(node.status === 'evaluated' || node.status === 'best') && (
                  <text
                    dy={-14}
                    textAnchor="middle"
                    fontSize="9"
                    fontFamily="monospace"
                    fill={colors.text}
                  >
                    {node.id.length > 12 ? node.id.slice(0, 12) + '...' : node.id}
                  </text>
                )}
              </g>
            ))}
          </g>
        </g>
      </svg>

      <LatticeTooltip node={hoveredNode} x={tooltipPos.x} y={tooltipPos.y} />
    </div>
  );
}
