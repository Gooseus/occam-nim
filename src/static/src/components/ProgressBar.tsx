import React from 'react'
import type { SearchProgress } from '../types/dataSpec'
import type { SearchStatus } from '../store/useAppStore'

interface ProgressBarProps {
  status: SearchStatus
  progress: SearchProgress | null
}

export function ProgressBar({ status, progress }: ProgressBarProps) {
  if (status === 'idle') {
    return null
  }

  const percentage = progress && progress.totalLevels > 0
    ? Math.round((progress.currentLevel / progress.totalLevels) * 100)
    : 0

  return (
    <div style={styles.container}>
      {/* Status indicator */}
      <div style={styles.statusRow}>
        <span style={styles.statusLabel}>
          {status === 'connecting' && 'Connecting...'}
          {status === 'searching' && 'Searching...'}
          {status === 'complete' && 'Complete'}
          {status === 'error' && 'Error'}
        </span>
        {progress && (
          <span style={styles.levelText}>
            Level {progress.currentLevel} / {progress.totalLevels}
          </span>
        )}
      </div>

      {/* Progress bar */}
      <div style={styles.barOuter}>
        <div
          style={{
            ...styles.barInner,
            width: `${percentage}%`,
            backgroundColor: status === 'error' ? '#e74c3c' : '#3498db',
          }}
        />
      </div>

      {/* Details */}
      {progress && (
        <div style={styles.details}>
          <div style={styles.detailItem}>
            <span style={styles.detailLabel}>Models Evaluated:</span>
            <span style={styles.detailValue}>{progress.modelsEvaluated}</span>
          </div>
          {progress.bestModelName && (
            <>
              <div style={styles.detailItem}>
                <span style={styles.detailLabel}>Best Model:</span>
                <span style={styles.detailValue}>{progress.bestModelName}</span>
              </div>
              <div style={styles.detailItem}>
                <span style={styles.detailLabel}>{progress.statisticName || 'Statistic'}:</span>
                <span style={styles.detailValue}>
                  {progress.bestStatistic?.toFixed(4) || '-'}
                </span>
              </div>
            </>
          )}
        </div>
      )}
    </div>
  )
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    marginBottom: '1rem',
    padding: '1rem',
    background: '#f0f0f0',
    borderRadius: '4px',
  },
  statusRow: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '0.5rem',
  },
  statusLabel: {
    fontWeight: 600,
    fontSize: '0.875rem',
  },
  levelText: {
    fontSize: '0.875rem',
    color: '#666',
  },
  barOuter: {
    height: '8px',
    background: '#ddd',
    borderRadius: '4px',
    overflow: 'hidden',
  },
  barInner: {
    height: '100%',
    transition: 'width 0.3s ease',
    borderRadius: '4px',
  },
  details: {
    marginTop: '0.75rem',
    display: 'flex',
    flexWrap: 'wrap',
    gap: '1rem',
  },
  detailItem: {
    display: 'flex',
    gap: '0.25rem',
    fontSize: '0.8rem',
  },
  detailLabel: {
    color: '#666',
  },
  detailValue: {
    fontWeight: 600,
    fontFamily: 'monospace',
  },
}
