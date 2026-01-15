import React from 'react';
import type { SearchResult } from '../types/dataSpec';

interface ResultsTableProps {
  results: {
    results: SearchResult[];
    totalEvaluated: number;
  } | null;
  onFitModel?: (model: string) => void;
  onSetReference?: (model: string) => void;
}

// Column tooltips explaining each statistic
const TOOLTIPS = {
  model: 'Model structure showing variable associations (e.g., AB:BC means A-B and B-C are associated)',
  h: 'Entropy (H): Uncertainty in the fitted distribution. Lower = more deterministic predictions.',
  ddf: 'Delta DF: Degrees of freedom saved vs saturated model. Higher = simpler model.',
  aic: 'Akaike Information Criterion: Balances fit and complexity. Lower = better.',
  bic: 'Bayesian Information Criterion: Like AIC but penalizes complexity more. Lower = better.',
  deltaBic: 'Difference from best model. 0 = best. <2 = equivalent, 2-6 = weak evidence, >10 = strong evidence against.',
  loops: 'Whether model contains loops (cycles). Loop models require IPF fitting (slower).',
};

function Tooltip({ text, children }: { text: string; children: React.ReactNode }) {
  const [show, setShow] = React.useState(false);
  return (
    <span
      style={{ cursor: 'help', borderBottom: '1px dotted #999', position: 'relative' }}
      onMouseEnter={() => setShow(true)}
      onMouseLeave={() => setShow(false)}
    >
      {children}
      {show && (
        <div style={{
          position: 'absolute',
          bottom: '100%',
          left: '50%',
          transform: 'translateX(-50%)',
          background: '#333',
          color: 'white',
          padding: '6px 10px',
          borderRadius: '4px',
          fontSize: '0.75rem',
          whiteSpace: 'nowrap',
          zIndex: 1000,
          marginBottom: '4px',
          maxWidth: '300px',
          textAlign: 'center',
        }}>
          {text}
        </div>
      )}
    </span>
  );
}

export function ResultsTable({ results, onFitModel, onSetReference }: ResultsTableProps) {
  if (!results || results.results.length === 0) {
    return null;
  }

  // Find best (lowest) BIC to compute ΔBIC
  const bestBic = Math.min(...results.results.map(r => r.bic));

  return (
    <div style={styles.container}>
      <div style={styles.header}>
        <h3 style={styles.title}>Search Results</h3>
        <span style={styles.count}>
          {results.totalEvaluated} models evaluated
        </span>
      </div>

      <div style={styles.tableWrapper}>
        <table style={styles.table}>
          <thead>
            <tr>
              <th style={styles.th}>#</th>
              <th style={{ ...styles.th, textAlign: 'left' }}>
                <Tooltip text={TOOLTIPS.model}>Model</Tooltip>
              </th>
              <th style={styles.th}>
                <Tooltip text={TOOLTIPS.h}>H</Tooltip>
              </th>
              <th style={styles.th}>
                <Tooltip text={TOOLTIPS.ddf}>ΔDF</Tooltip>
              </th>
              <th style={styles.th}>
                <Tooltip text={TOOLTIPS.aic}>AIC</Tooltip>
              </th>
              <th style={styles.th}>
                <Tooltip text={TOOLTIPS.deltaBic}>ΔBIC</Tooltip>
              </th>
              <th style={styles.th}>
                <Tooltip text={TOOLTIPS.loops}>Loops</Tooltip>
              </th>
              {(onFitModel || onSetReference) && <th style={styles.th}></th>}
            </tr>
          </thead>
          <tbody>
            {results.results.map((item, index) => {
              const deltaBic = item.bic - bestBic;
              return (
                <tr key={index} style={index % 2 === 0 ? styles.trEven : styles.trOdd}>
                  <td style={styles.td}>{index + 1}</td>
                  <td style={{ ...styles.td, textAlign: 'left', fontFamily: 'monospace' }}>
                    {item.model}
                  </td>
                  <td style={styles.td}>{item.h.toFixed(4)}</td>
                  <td style={styles.td}>{item.ddf}</td>
                  <td style={styles.td}>{item.aic.toFixed(2)}</td>
                  <td style={styles.td}>
                    <span style={deltaBicStyle(deltaBic)}>
                      {deltaBic < 0.01 ? '0' : deltaBic.toFixed(2)}
                    </span>
                  </td>
                  <td style={styles.td}>
                    {item.hasLoops ? (
                      <span style={styles.loopYes}>Yes</span>
                    ) : (
                      <span style={styles.loopNo}>No</span>
                    )}
                  </td>
                  {(onFitModel || onSetReference) && (
                    <td style={styles.td}>
                      <div style={styles.actionBtns}>
                        {onFitModel && (
                          <button onClick={() => onFitModel(item.model)} style={styles.fitBtn}>
                            Fit
                          </button>
                        )}
                        {onSetReference && (
                          <button
                            onClick={() => onSetReference(item.model)}
                            style={styles.refBtn}
                            title="Use as reference model for next search"
                          >
                            Ref
                          </button>
                        )}
                      </div>
                    </td>
                  )}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <div style={styles.legend}>
        <span style={styles.legendTitle}>ΔBIC interpretation:</span>
        <span style={{ ...styles.legendItem, color: '#27ae60' }}>0 = best</span>
        <span style={{ ...styles.legendItem, color: '#666' }}>&lt;2 = equivalent</span>
        <span style={{ ...styles.legendItem, color: '#f39c12' }}>2-6 = weak evidence</span>
        <span style={{ ...styles.legendItem, color: '#e74c3c' }}>&gt;10 = strong evidence against</span>
      </div>
    </div>
  );
}

// Style ΔBIC based on evidence strength
function deltaBicStyle(deltaBic: number): React.CSSProperties {
  if (deltaBic < 0.01) return { color: '#27ae60', fontWeight: 600 }; // Best
  if (deltaBic < 2) return { color: '#666' }; // Essentially equivalent
  if (deltaBic < 6) return { color: '#f39c12' }; // Weak evidence
  if (deltaBic < 10) return { color: '#e67e22' }; // Moderate evidence
  return { color: '#e74c3c' }; // Strong evidence against
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    marginTop: '1rem',
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '0.5rem',
  },
  title: {
    fontSize: '1rem',
    fontWeight: 600,
    margin: 0,
  },
  count: {
    fontSize: '0.8rem',
    color: '#666',
  },
  tableWrapper: {
    overflowX: 'auto',
    border: '1px solid #ddd',
    borderRadius: '4px',
  },
  table: {
    width: '100%',
    borderCollapse: 'collapse',
    fontSize: '0.875rem',
  },
  th: {
    padding: '0.75rem 0.5rem',
    textAlign: 'right',
    fontWeight: 600,
    background: '#f5f5f5',
    borderBottom: '2px solid #ddd',
    whiteSpace: 'nowrap',
  },
  td: {
    padding: '0.5rem',
    textAlign: 'right',
    borderBottom: '1px solid #eee',
  },
  trEven: {
    background: 'white',
  },
  trOdd: {
    background: '#fafafa',
  },
  loopYes: {
    color: '#e74c3c',
    fontWeight: 600,
  },
  loopNo: {
    color: '#27ae60',
  },
  legend: {
    marginTop: '0.75rem',
    padding: '0.5rem 0.75rem',
    background: '#f8f9fa',
    borderRadius: '4px',
    fontSize: '0.75rem',
    display: 'flex',
    alignItems: 'center',
    gap: '1rem',
    flexWrap: 'wrap',
  },
  legendTitle: {
    fontWeight: 600,
    color: '#333',
  },
  legendItem: {
    whiteSpace: 'nowrap',
  },
  actionBtns: {
    display: 'flex',
    gap: '4px',
    justifyContent: 'flex-end',
  },
  fitBtn: {
    padding: '4px 8px',
    fontSize: '0.7rem',
    border: '1px solid #3498db',
    borderRadius: '3px',
    background: 'white',
    color: '#3498db',
    cursor: 'pointer',
  },
  refBtn: {
    padding: '4px 8px',
    fontSize: '0.7rem',
    border: '1px solid #666',
    borderRadius: '3px',
    background: 'white',
    color: '#666',
    cursor: 'pointer',
  },
}
