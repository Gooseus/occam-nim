import { useEffect, useRef, useCallback } from 'react';
import * as d3 from 'd3';
import type { LatticeNode, LatticeEdge } from '../../types/lattice';

interface SimulationConfig {
  width: number;
  height: number;
  onTick: () => void;
}

/**
 * Hook that manages the D3 force simulation for the lattice visualization.
 * D3 owns the simulation math; React owns the rendering.
 */
export function useLatticeSimulation(
  nodes: LatticeNode[],
  edges: LatticeEdge[],
  config: SimulationConfig
) {
  const simulationRef = useRef<d3.Simulation<LatticeNode, LatticeEdge> | null>(
    null
  );

  const { width, height, onTick } = config;

  // Initialize or update simulation
  useEffect(() => {
    // Create simulation if it doesn't exist
    if (!simulationRef.current) {
      simulationRef.current = d3.forceSimulation<LatticeNode, LatticeEdge>();
    }

    const simulation = simulationRef.current;

    // Calculate max level for positioning
    const maxLevel = nodes.reduce((max, n) => Math.max(max, n.level), 0);

    // Update nodes and forces
    simulation
      .nodes(nodes)
      .force(
        'link',
        d3
          .forceLink<LatticeNode, LatticeEdge>(edges)
          .id((d) => d.id)
          .distance(60)
          .strength(0.5)
      )
      .force(
        'charge',
        d3.forceManyBody<LatticeNode>().strength(-200).distanceMax(300)
      )
      .force(
        'y',
        d3
          .forceY<LatticeNode>()
          .y((d) => {
            // Position nodes by level (independence at bottom, saturated at top)
            const levelRatio = d.level / Math.max(1, maxLevel);
            return height - (levelRatio * (height - 100) + 50);
          })
          .strength(0.8)
      )
      .force('x', d3.forceX<LatticeNode>(width / 2).strength(0.05))
      .force('collision', d3.forceCollide<LatticeNode>(25))
      .on('tick', onTick)
      .alpha(0.3)
      .restart();
  }, [nodes, edges, width, height, onTick]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (simulationRef.current) {
        simulationRef.current.stop();
        simulationRef.current = null;
      }
    };
  }, []);

  // Create drag behavior for nodes
  const createDragBehavior = useCallback(() => {
    const simulation = simulationRef.current;
    if (!simulation) return null;

    return d3
      .drag<SVGGElement, LatticeNode>()
      .on('start', (event, d) => {
        if (!event.active) simulation.alphaTarget(0.3).restart();
        d.fx = d.x;
        d.fy = d.y;
      })
      .on('drag', (event, d) => {
        d.fx = event.x;
        d.fy = event.y;
      })
      .on('end', (event, d) => {
        if (!event.active) simulation.alphaTarget(0);
        d.fx = null;
        d.fy = null;
      });
  }, []);

  // Reheat the simulation
  const reheat = useCallback(() => {
    simulationRef.current?.alpha(0.3).restart();
  }, []);

  // Stop the simulation
  const stop = useCallback(() => {
    simulationRef.current?.stop();
  }, []);

  return {
    simulation: simulationRef.current,
    createDragBehavior,
    reheat,
    stop,
  };
}
