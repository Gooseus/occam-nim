import React, { useState } from 'react';
import { useAppStore } from '../../store/useAppStore';
import type { FitResult } from '../../types/dataSpec';

export function FitTab() {
  const processedDataSpec = useAppStore((s) => s.processedDataSpec);
  const searchResults = useAppStore((s) => s.searchResults);
  const currentFitModel = useAppStore((s) => s.currentFitModel);
  const setCurrentFitModel = useAppStore((s) => s.setCurrentFitModel);
  const isFitting = useAppStore((s) => s.isFitting);
  const setIsFitting = useAppStore((s) => s.setIsFitting);
  const fitError = useAppStore((s) => s.fitError);
  const setFitError = useAppStore((s) => s.setFitError);
  const fitHistory = useAppStore((s) => s.fitHistory);
  const addFitResult = useAppStore((s) => s.addFitResult);
  const clearFitHistory = useAppStore((s) => s.clearFitHistory);
  const setActiveTab = useAppStore((s) => s.setActiveTab);

  const [latestResult, setLatestResult] = useState<FitResult | null>(null);

  const submitFit = async () => {
    if (!processedDataSpec || !currentFitModel.trim()) return;

    setIsFitting(true);
    setFitError(null);
    setLatestResult(null);

    try {
      const response = await fetch('/api/model/fit', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          data: JSON.stringify(processedDataSpec),
          model: currentFitModel.trim(),
        }),
      });

      if (!response.ok) {
        const err = await response.json();
        throw new Error(err.error || 'Fit failed');
      }

      const result = await response.json();
      const fitResult: FitResult = {
        ...result,
        timestamp: Date.now(),
      };
      setLatestResult(fitResult);
      addFitResult(fitResult);
    } catch (err) {
      setFitError(err instanceof Error ? err.message : 'Unknown error');
    } finally {
      setIsFitting(false);
    }
  };

  if (!processedDataSpec) {
    return (
      <div style={styles.container}>
        <div style={styles.noData}>
          <p>No data loaded. Please upload a CSV file first.</p>
          <button onClick={() => setActiveTab('data')} style={styles.linkBtn}>
            Go to Data tab
          </button>
        </div>
      </div>
    );
  }

  return (
    <div style={styles.container}>
      <div style={styles.section}>
        <h3 style={styles.heading}>Fit Model</h3>
        <div style={styles.inputRow}>
          <input
            type="text"
            value={currentFitModel}
            onChange={(e) => setCurrentFitModel(e.target.value)}
            placeholder="Enter model (e.g., AB:BC:AC)"
            disabled={isFitting}
            style={styles.input}
          />
          <button
            onClick={submitFit}
            disabled={isFitting || !currentFitModel.trim()}
            style={{
              ...styles.button,
              ...styles.primaryButton,
              opacity: isFitting || !currentFitModel.trim() ? 0.6 : 1,
            }}
          >
            {isFitting ? 'Fitting...' : 'Fit Model'}
          </button>
        </div>
        <p style={styles.hint}>
          Variables: {processedDataSpec.variables.map((v) => v.abbrev).join(', ')}
        </p>
      </div>

      {fitError && (
        <div style={styles.error}>
          <strong>Error:</strong> {fitError}
        </div>
      )}

      {latestResult && (
        <div style={styles.section}>
          <h3 style={styles.heading}>Latest Result</h3>
          <FitResultDisplay result={latestResult} />
        </div>
      )}

      {searchResults.length > 0 && (
        <div style={styles.section}>
          <h3 style={styles.heading}>Quick Fit from Search Results</h3>
          <div style={styles.suggestions}>
            {searchResults.slice(0, 5).map((r) => (
              <button
                key={r.model}
                onClick={() => setCurrentFitModel(r.model)}
                style={styles.suggestionBtn}
              >
                {r.model}
                <span style={styles.suggestionStat}>BIC: {r.bic.toFixed(2)}</span>
              </button>
            ))}
          </div>
        </div>
      )}

      {fitHistory.length > 0 && (
        <div style={styles.section}>
          <div style={styles.historyHeader}>
            <h3 style={styles.heading}>Fit History</h3>
            <button onClick={clearFitHistory} style={styles.clearBtn}>
              Clear
            </button>
          </div>
          <table style={styles.table}>
            <thead>
              <tr>
                <th style={styles.th}>Model</th>
                <th style={styles.th}>H</th>
                <th style={styles.th}>DF</th>
                <th style={styles.th}>BIC</th>
                <th style={styles.th}>AIC</th>
                <th style={styles.th}>Loops</th>
              </tr>
            </thead>
            <tbody>
              {fitHistory.map((r, i) => (
                <tr key={i} style={i % 2 === 0 ? {} : styles.altRow}>
                  <td style={styles.tdModel}>{r.model}</td>
                  <td style={styles.td}>{r.h.toFixed(4)}</td>
                  <td style={styles.td}>{r.df}</td>
                  <td style={styles.td}>{r.bic.toFixed(2)}</td>
                  <td style={styles.td}>{r.aic.toFixed(2)}</td>
                  <td style={styles.td}>{r.hasLoops ? 'Yes' : 'No'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

function FitResultDisplay({ result }: { result: FitResult }) {
  return (
    <div style={resultStyles.container}>
      <div style={resultStyles.model}>{result.model}</div>
      <div style={resultStyles.grid}>
        <div style={resultStyles.stat}>
          <span style={resultStyles.label}>H</span>
          <span style={resultStyles.value}>{result.h.toFixed(4)}</span>
        </div>
        <div style={resultStyles.stat}>
          <span style={resultStyles.label}>T</span>
          <span style={resultStyles.value}>{result.t.toFixed(4)}</span>
        </div>
        <div style={resultStyles.stat}>
          <span style={resultStyles.label}>DF</span>
          <span style={resultStyles.value}>{result.df}</span>
        </div>
        <div style={resultStyles.stat}>
          <span style={resultStyles.label}>DDF</span>
          <span style={resultStyles.value}>{result.ddf}</span>
        </div>
        <div style={resultStyles.stat}>
          <span style={resultStyles.label}>LR</span>
          <span style={resultStyles.value}>{result.lr.toFixed(2)}</span>
        </div>
        <div style={resultStyles.stat}>
          <span style={resultStyles.label}>AIC</span>
          <span style={resultStyles.value}>{result.aic.toFixed(2)}</span>
        </div>
        <div style={resultStyles.stat}>
          <span style={resultStyles.label}>BIC</span>
          <span style={resultStyles.value}>{result.bic.toFixed(2)}</span>
        </div>
        <div style={resultStyles.stat}>
          <span style={resultStyles.label}>p-value</span>
          <span style={resultStyles.value}>{result.alpha.toExponential(2)}</span>
        </div>
      </div>
      {result.hasLoops && (
        <div style={resultStyles.loopInfo}>
          IPF: {result.ipfIterations} iterations, error: {result.ipfError.toExponential(2)}
        </div>
      )}
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    padding: '1rem',
  },
  noData: {
    textAlign: 'center',
    padding: '2rem',
    color: '#666',
  },
  linkBtn: {
    marginTop: '1rem',
    padding: '0.5rem 1rem',
    fontSize: '0.875rem',
    background: '#3498db',
    border: 'none',
    borderRadius: '4px',
    color: 'white',
    cursor: 'pointer',
  },
  section: {
    marginBottom: '1.5rem',
  },
  heading: {
    fontSize: '0.9rem',
    fontWeight: 600,
    marginBottom: '0.75rem',
  },
  inputRow: {
    display: 'flex',
    gap: '0.5rem',
  },
  input: {
    flex: 1,
    padding: '0.75rem',
    fontSize: '0.9rem',
    fontFamily: 'monospace',
    border: '1px solid #ccc',
    borderRadius: '4px',
  },
  button: {
    padding: '0.75rem 1.5rem',
    fontSize: '0.875rem',
    fontWeight: 600,
    border: '1px solid #ccc',
    borderRadius: '4px',
    background: 'white',
    cursor: 'pointer',
  },
  primaryButton: {
    background: '#3498db',
    borderColor: '#3498db',
    color: 'white',
  },
  hint: {
    marginTop: '0.5rem',
    fontSize: '0.75rem',
    color: '#666',
  },
  error: {
    padding: '1rem',
    marginBottom: '1rem',
    background: '#fde8e8',
    border: '1px solid #e74c3c',
    borderRadius: '4px',
    color: '#c0392b',
    fontSize: '0.875rem',
  },
  suggestions: {
    display: 'flex',
    flexWrap: 'wrap',
    gap: '0.5rem',
  },
  suggestionBtn: {
    padding: '0.5rem 0.75rem',
    fontSize: '0.8rem',
    fontFamily: 'monospace',
    border: '1px solid #ddd',
    borderRadius: '4px',
    background: '#f8f9fa',
    cursor: 'pointer',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'flex-start',
    gap: '0.25rem',
  },
  suggestionStat: {
    fontSize: '0.7rem',
    color: '#666',
  },
  historyHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  clearBtn: {
    padding: '0.25rem 0.5rem',
    fontSize: '0.7rem',
    border: '1px solid #ccc',
    borderRadius: '3px',
    background: 'white',
    cursor: 'pointer',
  },
  table: {
    width: '100%',
    borderCollapse: 'collapse',
    fontSize: '0.8rem',
  },
  th: {
    textAlign: 'left',
    padding: '0.5rem',
    borderBottom: '2px solid #ddd',
    fontWeight: 600,
    color: '#666',
  },
  td: {
    padding: '0.5rem',
    borderBottom: '1px solid #eee',
  },
  tdModel: {
    padding: '0.5rem',
    borderBottom: '1px solid #eee',
    fontFamily: 'monospace',
    fontWeight: 500,
  },
  altRow: {
    background: '#fafafa',
  },
};

const resultStyles: Record<string, React.CSSProperties> = {
  container: {
    padding: '1rem',
    background: '#f8f9fa',
    borderRadius: '4px',
  },
  model: {
    fontFamily: 'monospace',
    fontSize: '1.1rem',
    fontWeight: 600,
    marginBottom: '0.75rem',
  },
  grid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(4, 1fr)',
    gap: '0.75rem',
  },
  stat: {
    display: 'flex',
    flexDirection: 'column',
  },
  label: {
    fontSize: '0.7rem',
    color: '#666',
    marginBottom: '0.125rem',
  },
  value: {
    fontSize: '0.9rem',
    fontWeight: 500,
  },
  loopInfo: {
    marginTop: '0.75rem',
    fontSize: '0.75rem',
    color: '#666',
  },
};
