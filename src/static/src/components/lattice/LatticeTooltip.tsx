import React from 'react';
import type { LatticeNode, LatticeNodeStatus } from '../../types/lattice';
import { colors, spacing, fontSize, borderRadius } from '../../lib/theme';

interface LatticeTooltipProps {
  node: LatticeNode | null;
  x: number;
  y: number;
}

function getStatusStyle(status: LatticeNodeStatus): React.CSSProperties {
  const statusColors: Record<LatticeNodeStatus, string> = {
    pending: colors.textMuted,
    evaluating: colors.warning,
    evaluated: colors.success,
    best: colors.primary,
    pruned: colors.textLight,
  };

  return {
    color: statusColors[status],
    fontWeight: status === 'best' ? 600 : 400,
  };
}

export function LatticeTooltip({ node, x, y }: LatticeTooltipProps) {
  if (!node) return null;

  return (
    <div
      style={{
        ...styles.container,
        left: x + 15,
        top: y - 10,
      }}
    >
      <div style={styles.modelName}>{node.id}</div>
      <div style={styles.level}>Level {node.level}</div>

      {node.stats && (
        <div style={styles.stats}>
          <div style={styles.statRow}>
            <span>H:</span>
            <span>{node.stats.h.toFixed(4)}</span>
          </div>
          <div style={styles.statRow}>
            <span>BIC:</span>
            <span>{node.stats.bic.toFixed(2)}</span>
          </div>
          <div style={styles.statRow}>
            <span>AIC:</span>
            <span>{node.stats.aic.toFixed(2)}</span>
          </div>
          <div style={styles.statRow}>
            <span>Loops:</span>
            <span
              style={{ color: node.stats.hasLoops ? colors.loopYes : colors.loopNo }}
            >
              {node.stats.hasLoops ? 'Yes' : 'No'}
            </span>
          </div>
        </div>
      )}

      <div style={styles.status}>
        Status: <span style={getStatusStyle(node.status)}>{node.status}</span>
      </div>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    position: 'absolute',
    padding: spacing.sm,
    background: 'rgba(255, 255, 255, 0.95)',
    border: `1px solid ${colors.borderMedium}`,
    borderRadius: borderRadius.md,
    boxShadow: '0 2px 8px rgba(0,0,0,0.15)',
    fontSize: fontSize.sm,
    pointerEvents: 'none',
    zIndex: 1000,
    minWidth: '140px',
  },
  modelName: {
    fontFamily: 'monospace',
    fontWeight: 600,
    fontSize: fontSize.md,
    marginBottom: spacing.xs,
  },
  level: {
    color: colors.textMuted,
    fontSize: fontSize.xs,
    marginBottom: spacing.sm,
  },
  stats: {
    borderTop: `1px solid ${colors.borderLight}`,
    paddingTop: spacing.xs,
    marginTop: spacing.xs,
  },
  statRow: {
    display: 'flex',
    justifyContent: 'space-between',
    gap: spacing.md,
    fontFamily: 'monospace',
  },
  status: {
    marginTop: spacing.sm,
    paddingTop: spacing.xs,
    borderTop: `1px solid ${colors.borderLight}`,
    fontSize: fontSize.xs,
  },
};
