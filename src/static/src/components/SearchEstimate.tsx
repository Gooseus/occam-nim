import React, { useEffect, useState } from 'react';
import { DataSpec } from '../types/dataSpec';

interface SearchEstimateResponse {
  estimatedSeconds: number;
  estimatedSecondsLow: number;
  estimatedSecondsHigh: number;
  level1Neighbors: number;
  totalModelsEstimate: number;
  complexity: 'fast' | 'moderate' | 'slow' | 'very_slow' | 'infeasible';
  warnings: string[];
  recommendations: string[];
}

interface SearchEstimateProps {
  data: DataSpec;
  direction: string;
  filter: string;
  width: number;
  levels: number;
}

function formatDuration(seconds: number): string {
  if (seconds < 1) {
    return '< 1 second';
  } else if (seconds < 60) {
    return `~${Math.round(seconds)} seconds`;
  } else if (seconds < 3600) {
    const mins = Math.round(seconds / 60);
    return `~${mins} minute${mins !== 1 ? 's' : ''}`;
  } else {
    const hours = Math.round(seconds / 3600);
    return `~${hours} hour${hours !== 1 ? 's' : ''}`;
  }
}

function formatRange(low: number, high: number): string {
  if (high < 60) {
    return `${Math.round(low)}-${Math.round(high)} seconds`;
  } else if (high < 3600) {
    return `${Math.round(low / 60)}-${Math.round(high / 60)} minutes`;
  } else {
    return `${(low / 3600).toFixed(1)}-${(high / 3600).toFixed(1)} hours`;
  }
}

const complexityColors: Record<string, string> = {
  fast: '#27ae60',
  moderate: '#f39c12',
  slow: '#e67e22',
  very_slow: '#e74c3c',
  infeasible: '#8e44ad',
};

const complexityLabels: Record<string, string> = {
  fast: 'Fast',
  moderate: 'Moderate',
  slow: 'Slow',
  very_slow: 'Very Slow',
  infeasible: 'Infeasible',
};

export function SearchEstimate({ data, direction, filter, width, levels }: SearchEstimateProps) {
  const [estimate, setEstimate] = useState<SearchEstimateResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function fetchEstimate() {
      setLoading(true);
      setError(null);

      try {
        const response = await fetch('/api/search/estimate', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            data: JSON.stringify(data),
            direction,
            filter,
            width,
            levels,
          }),
        });

        if (!response.ok) {
          throw new Error('Failed to get estimate');
        }

        const result = await response.json();
        if (!cancelled) {
          setEstimate(result);
        }
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : 'Unknown error');
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    // Debounce the request
    const timer = setTimeout(fetchEstimate, 300);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [data, direction, filter, width, levels]);

  if (loading) {
    return (
      <div style={styles.container}>
        <div style={styles.loading}>Estimating search time...</div>
      </div>
    );
  }

  if (error) {
    return null; // Silently fail - estimate is not critical
  }

  if (!estimate) {
    return null;
  }

  const complexityColor = complexityColors[estimate.complexity] || '#666';

  return (
    <div style={styles.container}>
      <div style={styles.header}>
        <span style={styles.icon}>&#9202;</span>
        <strong>Estimated Time:</strong>{' '}
        <span style={styles.time}>{formatDuration(estimate.estimatedSeconds)}</span>
        <span
          style={{
            ...styles.complexity,
            backgroundColor: complexityColor,
          }}
        >
          {complexityLabels[estimate.complexity]}
        </span>
      </div>

      <div style={styles.details}>
        <span>Range: {formatRange(estimate.estimatedSecondsLow, estimate.estimatedSecondsHigh)}</span>
        <span style={styles.separator}>|</span>
        <span>~{estimate.totalModelsEstimate.toLocaleString()} models</span>
        <span style={styles.separator}>|</span>
        <span>Level 1: {estimate.level1Neighbors} neighbors</span>
      </div>

      {estimate.warnings.length > 0 && (
        <div style={styles.warnings}>
          {estimate.warnings.map((warning, i) => (
            <div key={i} style={styles.warning}>
              <span style={styles.warningIcon}>&#9888;</span> {warning}
            </div>
          ))}
        </div>
      )}

      {estimate.recommendations.length > 0 && (
        <div style={styles.recommendations}>
          <strong>Suggestions:</strong>
          <ul style={styles.recommendationList}>
            {estimate.recommendations.map((rec, i) => (
              <li key={i}>{rec}</li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    padding: '0.75rem',
    marginBottom: '1rem',
    background: '#f8f9fa',
    borderRadius: '4px',
    border: '1px solid #e9ecef',
    fontSize: '0.875rem',
  },
  loading: {
    color: '#666',
    fontStyle: 'italic',
  },
  header: {
    display: 'flex',
    alignItems: 'center',
    gap: '0.5rem',
  },
  icon: {
    fontSize: '1rem',
  },
  time: {
    fontSize: '1rem',
    fontWeight: 600,
  },
  complexity: {
    marginLeft: 'auto',
    padding: '0.25rem 0.5rem',
    borderRadius: '4px',
    color: 'white',
    fontSize: '0.75rem',
    fontWeight: 600,
    textTransform: 'uppercase',
  },
  details: {
    marginTop: '0.5rem',
    color: '#666',
    fontSize: '0.8rem',
  },
  separator: {
    margin: '0 0.5rem',
    color: '#ccc',
  },
  warnings: {
    marginTop: '0.75rem',
    padding: '0.5rem',
    background: '#fff3cd',
    borderRadius: '4px',
    border: '1px solid #ffc107',
  },
  warning: {
    color: '#856404',
    marginBottom: '0.25rem',
  },
  warningIcon: {
    color: '#ffc107',
    marginRight: '0.25rem',
  },
  recommendations: {
    marginTop: '0.75rem',
    padding: '0.5rem',
    background: '#e7f3ff',
    borderRadius: '4px',
    border: '1px solid #b6d4fe',
    color: '#084298',
  },
  recommendationList: {
    margin: '0.25rem 0 0 1.25rem',
    padding: 0,
  },
};
