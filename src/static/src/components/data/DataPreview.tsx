import React from 'react';
import { useAppStore } from '../../store/useAppStore';

export function DataPreview() {
  const processedDataSpec = useAppStore((s) => s.processedDataSpec);

  if (!processedDataSpec) return null;

  const { variables, data, counts } = processedDataSpec;
  const previewRows = data.slice(0, 10);
  const totalCount = counts.reduce((a, b) => a + b, 0);

  return (
    <div style={styles.container}>
      <h3 style={styles.heading}>
        Frequency Table Preview
        <span style={styles.stats}>
          {data.length} unique states, {totalCount} total observations
        </span>
      </h3>
      <div style={styles.tableWrapper}>
        <table style={styles.table}>
          <thead>
            <tr>
              {variables.map((v) => (
                <th key={v.abbrev} style={styles.th} title={v.name}>
                  {v.abbrev}
                </th>
              ))}
              <th style={styles.thCount}>Count</th>
            </tr>
          </thead>
          <tbody>
            {previewRows.map((row, i) => (
              <tr key={i} style={i % 2 === 0 ? {} : styles.altRow}>
                {row.map((val, j) => (
                  <td key={j} style={styles.td}>
                    {val}
                  </td>
                ))}
                <td style={styles.tdCount}>{counts[i]}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {data.length > 10 && (
        <p style={styles.more}>... and {data.length - 10} more rows</p>
      )}
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    marginBottom: '1rem',
  },
  heading: {
    fontSize: '0.9rem',
    fontWeight: 600,
    marginBottom: '0.5rem',
    display: 'flex',
    alignItems: 'center',
    gap: '1rem',
  },
  stats: {
    fontSize: '0.75rem',
    fontWeight: 400,
    color: '#666',
  },
  tableWrapper: {
    overflowX: 'auto',
  },
  table: {
    width: '100%',
    borderCollapse: 'collapse',
    fontSize: '0.8rem',
    fontFamily: 'monospace',
  },
  th: {
    textAlign: 'left',
    padding: '0.5rem',
    borderBottom: '2px solid #ddd',
    fontWeight: 600,
    color: '#666',
    whiteSpace: 'nowrap',
  },
  thCount: {
    textAlign: 'right',
    padding: '0.5rem',
    borderBottom: '2px solid #ddd',
    fontWeight: 600,
    color: '#666',
    background: '#f8f9fa',
  },
  td: {
    padding: '0.5rem',
    borderBottom: '1px solid #eee',
  },
  tdCount: {
    padding: '0.5rem',
    borderBottom: '1px solid #eee',
    textAlign: 'right',
    fontWeight: 500,
    background: '#f8f9fa',
  },
  altRow: {
    background: '#fafafa',
  },
  more: {
    fontSize: '0.75rem',
    color: '#999',
    textAlign: 'center',
    marginTop: '0.5rem',
  },
};
