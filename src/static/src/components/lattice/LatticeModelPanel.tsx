import React from 'react';
import type { LatticeNode } from '../../types/lattice';
import { colors, spacing, fontSize, borderRadius, commonStyles } from '../../lib/theme';

interface LatticeModelPanelProps {
  node: LatticeNode | null;
  onFitModel: (model: string) => void;
  onClose: () => void;
}

export function LatticeModelPanel({
  node,
  onFitModel,
  onClose,
}: LatticeModelPanelProps) {
  if (!node) return null;

  return (
    <div style={styles.container}>
      <div style={styles.header}>
        <div style={styles.modelName}>{node.id}</div>
        <button onClick={onClose} style={styles.closeBtn}>
          &times;
        </button>
      </div>

      <div style={styles.section}>
        <div style={styles.row}>
          <span style={styles.label}>Level:</span>
          <span>{node.level}</span>
        </div>
        <div style={styles.row}>
          <span style={styles.label}>Relations:</span>
          <span style={styles.relations}>{node.relations.join(', ')}</span>
        </div>
      </div>

      {node.stats && (
        <div style={styles.section}>
          <div style={styles.sectionTitle}>Statistics</div>
          <div style={styles.statsGrid}>
            <div style={styles.stat}>
              <span style={styles.statLabel}>H</span>
              <span style={styles.statValue}>{node.stats.h.toFixed(4)}</span>
            </div>
            <div style={styles.stat}>
              <span style={styles.statLabel}>BIC</span>
              <span style={styles.statValue}>{node.stats.bic.toFixed(2)}</span>
            </div>
            <div style={styles.stat}>
              <span style={styles.statLabel}>AIC</span>
              <span style={styles.statValue}>{node.stats.aic.toFixed(2)}</span>
            </div>
            <div style={styles.stat}>
              <span style={styles.statLabel}>DDF</span>
              <span style={styles.statValue}>{node.stats.ddf}</span>
            </div>
          </div>
          <div style={styles.loopStatus}>
            Loops:{' '}
            <span
              style={{ color: node.stats.hasLoops ? colors.loopYes : colors.loopNo }}
            >
              {node.stats.hasLoops ? 'Yes (requires IPF)' : 'No (decomposable)'}
            </span>
          </div>
        </div>
      )}

      <div style={styles.actions}>
        <button
          onClick={() => onFitModel(node.id)}
          style={{
            ...commonStyles.buttonBase,
            ...commonStyles.buttonPrimary,
            width: '100%',
          }}
        >
          Fit This Model
        </button>
      </div>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    position: 'absolute',
    top: 0,
    right: 0,
    width: '280px',
    height: '100%',
    background: colors.bgCard,
    borderLeft: `1px solid ${colors.borderMedium}`,
    boxShadow: '-2px 0 8px rgba(0,0,0,0.1)',
    display: 'flex',
    flexDirection: 'column',
    zIndex: 100,
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    padding: spacing.md,
    borderBottom: `1px solid ${colors.borderLight}`,
  },
  modelName: {
    fontFamily: 'monospace',
    fontSize: fontSize.xxl,
    fontWeight: 600,
    wordBreak: 'break-all',
  },
  closeBtn: {
    background: 'none',
    border: 'none',
    fontSize: '1.5rem',
    color: colors.textMuted,
    cursor: 'pointer',
    padding: 0,
    lineHeight: 1,
  },
  section: {
    padding: spacing.md,
    borderBottom: `1px solid ${colors.borderLight}`,
  },
  sectionTitle: {
    fontSize: fontSize.sm,
    fontWeight: 600,
    color: colors.textMuted,
    marginBottom: spacing.sm,
    textTransform: 'uppercase',
  },
  row: {
    display: 'flex',
    justifyContent: 'space-between',
    marginBottom: spacing.xs,
    fontSize: fontSize.md,
  },
  label: {
    color: colors.textMuted,
  },
  relations: {
    fontFamily: 'monospace',
  },
  statsGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(2, 1fr)',
    gap: spacing.sm,
  },
  stat: {
    display: 'flex',
    flexDirection: 'column',
    background: colors.bgMuted,
    padding: spacing.sm,
    borderRadius: borderRadius.sm,
  },
  statLabel: {
    fontSize: fontSize.xs,
    color: colors.textMuted,
  },
  statValue: {
    fontSize: fontSize.md,
    fontFamily: 'monospace',
    fontWeight: 500,
  },
  loopStatus: {
    marginTop: spacing.sm,
    fontSize: fontSize.sm,
  },
  actions: {
    padding: spacing.md,
    marginTop: 'auto',
  },
};
