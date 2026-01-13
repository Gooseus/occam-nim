import React from 'react';
import { colors, spacing, fontSize } from '../../lib/theme';

interface LatticeControlsProps {
  onZoomIn: () => void;
  onZoomOut: () => void;
  onResetView: () => void;
  onReheat: () => void;
  showLoopsOnly: boolean;
  onToggleLoopsOnly: () => void;
  nodeCount: number;
  edgeCount: number;
}

export function LatticeControls({
  onZoomIn,
  onZoomOut,
  onResetView,
  onReheat,
  showLoopsOnly,
  onToggleLoopsOnly,
  nodeCount,
  edgeCount,
}: LatticeControlsProps) {
  return (
    <div style={styles.container}>
      <div style={styles.buttonGroup}>
        <button onClick={onZoomIn} style={styles.iconButton} title="Zoom In">
          +
        </button>
        <button onClick={onZoomOut} style={styles.iconButton} title="Zoom Out">
          -
        </button>
        <button onClick={onResetView} style={styles.iconButton} title="Reset View">
          &#8634;
        </button>
        <button onClick={onReheat} style={styles.iconButton} title="Reheat Simulation">
          &#9672;
        </button>
      </div>

      <label style={styles.checkbox}>
        <input
          type="checkbox"
          checked={showLoopsOnly}
          onChange={onToggleLoopsOnly}
        />
        Show loops only
      </label>

      <div style={styles.info}>
        {nodeCount} models, {edgeCount} edges
      </div>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    display: 'flex',
    alignItems: 'center',
    gap: spacing.lg,
    padding: spacing.sm,
    background: colors.bgMuted,
    borderBottom: `1px solid ${colors.borderLight}`,
    fontSize: fontSize.sm,
  },
  buttonGroup: {
    display: 'flex',
    gap: spacing.xs,
  },
  iconButton: {
    width: '28px',
    height: '28px',
    padding: 0,
    fontSize: fontSize.md,
    border: `1px solid ${colors.borderMedium}`,
    borderRadius: '4px',
    background: colors.bgCard,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
  },
  checkbox: {
    display: 'flex',
    alignItems: 'center',
    gap: spacing.xs,
    cursor: 'pointer',
  },
  info: {
    marginLeft: 'auto',
    color: colors.textMuted,
    fontSize: fontSize.xs,
  },
};
