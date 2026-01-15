import React, { useState } from 'react';
import { useAppStore } from '../../store/useAppStore';
import type { BinStrategy } from '../../types/binning';

const STRATEGIES: Array<{ value: BinStrategy; label: string }> = [
  { value: 'none', label: 'None (keep original)' },
  { value: 'equalWidth', label: 'Equal Width' },
  { value: 'equalFrequency', label: 'Equal Frequency' },
  { value: 'topN', label: 'Top N Categories' },
  { value: 'frequencyThreshold', label: 'Frequency Threshold' },
];

export function BinningConfig() {
  const [showAdvanced, setShowAdvanced] = useState(false);
  const columnAnalysis = useAppStore((s) => s.columnAnalysis);
  const binConfigs = useAppStore((s) => s.binConfigs);
  const setBinConfig = useAppStore((s) => s.setBinConfig);

  const columnsNeedingBinning = columnAnalysis.filter((c) => c.needsBinning);

  return (
    <div style={styles.container}>
      <div style={styles.header}>
        <h3 style={styles.heading}>Binning Configuration</h3>
        <button
          onClick={() => setShowAdvanced(!showAdvanced)}
          style={styles.toggleBtn}
        >
          {showAdvanced ? 'Simple Mode' : 'Advanced Mode'}
        </button>
      </div>

      {!showAdvanced ? (
        <div style={styles.simpleMode}>
          {columnsNeedingBinning.length === 0 ? (
            <p style={styles.noAction}>
              No binning applied. Use Advanced Mode to bin high-cardinality columns if needed.
            </p>
          ) : (
            <p style={styles.summary}>
              {columnsNeedingBinning.length} column(s) have high cardinality ({'>'}10 values):
              {' '}
              <strong>{columnsNeedingBinning.map((c) => c.name).join(', ')}</strong>
              <br />
              <span style={{ color: '#856404' }}>Consider excluding or binning these columns via Advanced Mode.</span>
            </p>
          )}
        </div>
      ) : (
        <div style={styles.advancedMode}>
          <table style={styles.table}>
            <thead>
              <tr>
                <th style={styles.th}>Column</th>
                <th style={styles.th}>Strategy</th>
                <th style={styles.th}>Bins/Top N</th>
              </tr>
            </thead>
            <tbody>
              {columnAnalysis.map((col) => {
                const config = binConfigs[col.name];
                return (
                  <tr key={col.name}>
                    <td style={styles.td}>{col.name}</td>
                    <td style={styles.td}>
                      <select
                        value={config?.strategy || 'none'}
                        onChange={(e) =>
                          setBinConfig(col.name, {
                            ...config,
                            strategy: e.target.value as BinStrategy,
                          })
                        }
                        style={styles.select}
                      >
                        {STRATEGIES.map((s) => (
                          <option key={s.value} value={s.value}>
                            {s.label}
                          </option>
                        ))}
                      </select>
                    </td>
                    <td style={styles.td}>
                      {(config?.strategy === 'equalWidth' ||
                        config?.strategy === 'equalFrequency') && (
                        <input
                          type="number"
                          min={2}
                          max={20}
                          value={config?.numBins || 5}
                          onChange={(e) =>
                            setBinConfig(col.name, {
                              ...config,
                              numBins: parseInt(e.target.value) || 5,
                            })
                          }
                          style={styles.input}
                        />
                      )}
                      {config?.strategy === 'topN' && (
                        <input
                          type="number"
                          min={2}
                          max={20}
                          value={config?.topN || 5}
                          onChange={(e) =>
                            setBinConfig(col.name, {
                              ...config,
                              topN: parseInt(e.target.value) || 5,
                            })
                          }
                          style={styles.input}
                        />
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    marginBottom: '1rem',
    padding: '1rem',
    background: '#f8f9fa',
    borderRadius: '4px',
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '0.75rem',
  },
  heading: {
    fontSize: '0.9rem',
    fontWeight: 600,
    margin: 0,
  },
  toggleBtn: {
    padding: '0.25rem 0.75rem',
    fontSize: '0.75rem',
    border: '1px solid #ccc',
    borderRadius: '4px',
    background: 'white',
    cursor: 'pointer',
  },
  simpleMode: {
    fontSize: '0.85rem',
  },
  noAction: {
    color: '#27ae60',
    margin: 0,
  },
  summary: {
    margin: 0,
    color: '#666',
  },
  advancedMode: {},
  table: {
    width: '100%',
    borderCollapse: 'collapse',
    fontSize: '0.8rem',
  },
  th: {
    textAlign: 'left',
    padding: '0.5rem',
    borderBottom: '1px solid #ddd',
    fontWeight: 600,
    color: '#666',
  },
  td: {
    padding: '0.5rem',
  },
  select: {
    padding: '0.25rem 0.5rem',
    fontSize: '0.8rem',
    border: '1px solid #ccc',
    borderRadius: '3px',
    width: '100%',
  },
  input: {
    padding: '0.25rem 0.5rem',
    fontSize: '0.8rem',
    border: '1px solid #ccc',
    borderRadius: '3px',
    width: '60px',
  },
};
