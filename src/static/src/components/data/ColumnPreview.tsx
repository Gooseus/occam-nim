import React from 'react';
import { useAppStore } from '../../store/useAppStore';

export function ColumnPreview() {
  const columnAnalysis = useAppStore((s) => s.columnAnalysis);
  const excludedColumns = useAppStore((s) => s.excludedColumns);
  const toggleColumnExclusion = useAppStore((s) => s.toggleColumnExclusion);

  if (columnAnalysis.length === 0) return null;

  const includedCount = columnAnalysis.length - excludedColumns.length;

  return (
    <div style={styles.container}>
      <h3 style={styles.heading}>
        Detected Columns
        <span style={styles.columnCount}>
          {includedCount} of {columnAnalysis.length} included
        </span>
      </h3>
      <table style={styles.table}>
        <thead>
          <tr>
            <th style={styles.thCheckbox}>Include</th>
            <th style={styles.th}>Column</th>
            <th style={styles.th}>Type</th>
            <th style={styles.th}>Unique</th>
            <th style={styles.th}>Missing</th>
            <th style={styles.th}>Top Values</th>
          </tr>
        </thead>
        <tbody>
          {columnAnalysis.map((col) => {
            const isExcluded = excludedColumns.includes(col.name);
            return (
              <tr key={col.name} style={{ ...styles.tr, ...(isExcluded ? styles.excludedRow : {}) }}>
                <td style={styles.tdCheckbox}>
                  <input
                    type="checkbox"
                    checked={!isExcluded}
                    onChange={() => toggleColumnExclusion(col.name)}
                    style={styles.checkbox}
                  />
                </td>
                <td style={styles.td}>
                  <span style={{ ...styles.colName, ...(isExcluded ? styles.excludedText : {}) }}>
                    {col.name}
                  </span>
                  {col.needsBinning && !isExcluded && (
                    <span style={styles.binBadge}>high cardinality</span>
                  )}
                </td>
                <td style={styles.td}>
                  <span style={col.isNumeric ? styles.numericTag : styles.categoricalTag}>
                    {col.isNumeric ? 'numeric' : 'categorical'}
                  </span>
                </td>
                <td style={styles.tdCenter}>{col.uniqueCount}</td>
                <td style={styles.tdCenter}>
                  {col.missingCount > 0 ? (
                    <span style={styles.missingCount}>{col.missingCount}</span>
                  ) : (
                    '-'
                  )}
                </td>
                <td style={styles.td}>
                  <span style={styles.topValues}>
                    {col.topValues.slice(0, 3).map((v) => v.value).join(', ')}
                    {col.topValues.length > 3 && '...'}
                  </span>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
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
    gap: '0.75rem',
  },
  columnCount: {
    fontSize: '0.75rem',
    fontWeight: 400,
    color: '#666',
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
  thCheckbox: {
    textAlign: 'center',
    padding: '0.5rem',
    borderBottom: '2px solid #ddd',
    fontWeight: 600,
    color: '#666',
    width: '60px',
  },
  tdCheckbox: {
    textAlign: 'center',
    padding: '0.5rem',
  },
  checkbox: {
    width: '16px',
    height: '16px',
    cursor: 'pointer',
  },
  excludedRow: {
    opacity: 0.5,
    background: '#f8f8f8',
  },
  excludedText: {
    textDecoration: 'line-through',
    color: '#999',
  },
  tr: {
    borderBottom: '1px solid #eee',
  },
  td: {
    padding: '0.5rem',
    verticalAlign: 'middle',
  },
  tdCenter: {
    padding: '0.5rem',
    textAlign: 'center',
  },
  colName: {
    fontWeight: 500,
  },
  binBadge: {
    marginLeft: '0.5rem',
    padding: '0.125rem 0.375rem',
    fontSize: '0.65rem',
    background: '#fff3cd',
    color: '#856404',
    borderRadius: '3px',
  },
  numericTag: {
    padding: '0.125rem 0.375rem',
    fontSize: '0.7rem',
    background: '#d4edda',
    color: '#155724',
    borderRadius: '3px',
  },
  categoricalTag: {
    padding: '0.125rem 0.375rem',
    fontSize: '0.7rem',
    background: '#cce5ff',
    color: '#004085',
    borderRadius: '3px',
  },
  missingCount: {
    color: '#e74c3c',
  },
  topValues: {
    fontFamily: 'monospace',
    fontSize: '0.75rem',
    color: '#666',
  },
};
