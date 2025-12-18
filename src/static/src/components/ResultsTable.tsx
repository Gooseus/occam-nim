import React from 'react'
import type { SearchResult } from '../hooks/useSearch'

interface ResultsTableProps {
  results: SearchResult | null
}

export function ResultsTable({ results }: ResultsTableProps) {
  if (!results) {
    return null
  }

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
              <th style={{ ...styles.th, textAlign: 'left' }}>Model</th>
              <th style={styles.th}>H</th>
              <th style={styles.th}>AIC</th>
              <th style={styles.th}>BIC</th>
              <th style={styles.th}>Loops</th>
            </tr>
          </thead>
          <tbody>
            {results.results.map((item, index) => (
              <tr key={index} style={index % 2 === 0 ? styles.trEven : styles.trOdd}>
                <td style={styles.td}>{index + 1}</td>
                <td style={{ ...styles.td, textAlign: 'left', fontFamily: 'monospace' }}>
                  {item.model}
                </td>
                <td style={styles.td}>{item.h.toFixed(4)}</td>
                <td style={styles.td}>{item.aic.toFixed(4)}</td>
                <td style={styles.td}>{item.bic.toFixed(4)}</td>
                <td style={styles.td}>
                  {item.hasLoops ? (
                    <span style={styles.loopYes}>Yes</span>
                  ) : (
                    <span style={styles.loopNo}>No</span>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
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
}
