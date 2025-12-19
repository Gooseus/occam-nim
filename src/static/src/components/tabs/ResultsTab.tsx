import React from 'react';
import { useAppStore } from '../../store/useAppStore';

export function ResultsTab() {
  const searchResults = useAppStore((s) => s.searchResults);
  const searchTotalEvaluated = useAppStore((s) => s.searchTotalEvaluated);
  const fitHistory = useAppStore((s) => s.fitHistory);
  const selectModelFromResults = useAppStore((s) => s.selectModelFromResults);
  const setActiveTab = useAppStore((s) => s.setActiveTab);

  const hasSearchResults = searchResults.length > 0;
  const hasFitHistory = fitHistory.length > 0;

  if (!hasSearchResults && !hasFitHistory) {
    return (
      <div style={styles.container}>
        <div style={styles.empty}>
          <p>No results yet. Run a search or fit a model first.</p>
          <div style={styles.emptyActions}>
            <button onClick={() => setActiveTab('search')} style={styles.linkBtn}>
              Go to Search
            </button>
            <button onClick={() => setActiveTab('fit')} style={styles.linkBtn}>
              Go to Fit
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div style={styles.container}>
      {hasSearchResults && (
        <div style={styles.section}>
          <h3 style={styles.heading}>
            Search Results
            <span style={styles.count}>
              {searchResults.length} models ({searchTotalEvaluated} evaluated)
            </span>
          </h3>
          <table style={styles.table}>
            <thead>
              <tr>
                <th style={styles.th}>#</th>
                <th style={styles.th}>Model</th>
                <th style={styles.th}>H</th>
                <th style={styles.th}>AIC</th>
                <th style={styles.th}>BIC</th>
                <th style={styles.th}>Loops</th>
                <th style={styles.th}></th>
              </tr>
            </thead>
            <tbody>
              {searchResults.map((r, i) => (
                <tr key={r.model} style={i % 2 === 0 ? {} : styles.altRow}>
                  <td style={styles.tdRank}>{i + 1}</td>
                  <td style={styles.tdModel}>{r.model}</td>
                  <td style={styles.td}>{r.h.toFixed(4)}</td>
                  <td style={styles.td}>{r.aic.toFixed(2)}</td>
                  <td style={styles.td}>{r.bic.toFixed(2)}</td>
                  <td style={styles.td}>
                    <span style={r.hasLoops ? styles.loopsYes : styles.loopsNo}>
                      {r.hasLoops ? 'Yes' : 'No'}
                    </span>
                  </td>
                  <td style={styles.td}>
                    <button
                      onClick={() => selectModelFromResults(r.model)}
                      style={styles.fitBtn}
                    >
                      Fit
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {hasFitHistory && (
        <div style={styles.section}>
          <h3 style={styles.heading}>
            Fit History
            <span style={styles.count}>{fitHistory.length} fits</span>
          </h3>
          <table style={styles.table}>
            <thead>
              <tr>
                <th style={styles.th}>Model</th>
                <th style={styles.th}>H</th>
                <th style={styles.th}>T</th>
                <th style={styles.th}>DF</th>
                <th style={styles.th}>LR</th>
                <th style={styles.th}>AIC</th>
                <th style={styles.th}>BIC</th>
                <th style={styles.th}>p-value</th>
              </tr>
            </thead>
            <tbody>
              {fitHistory.map((r, i) => (
                <tr key={`${r.model}-${r.timestamp}`} style={i % 2 === 0 ? {} : styles.altRow}>
                  <td style={styles.tdModel}>{r.model}</td>
                  <td style={styles.td}>{r.h.toFixed(4)}</td>
                  <td style={styles.td}>{r.t.toFixed(4)}</td>
                  <td style={styles.td}>{r.df}</td>
                  <td style={styles.td}>{r.lr.toFixed(2)}</td>
                  <td style={styles.td}>{r.aic.toFixed(2)}</td>
                  <td style={styles.td}>{r.bic.toFixed(2)}</td>
                  <td style={styles.td}>{r.alpha.toExponential(2)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <div style={styles.export}>
        <button
          onClick={() => exportResults(searchResults, fitHistory)}
          style={styles.exportBtn}
        >
          Export as CSV
        </button>
      </div>
    </div>
  );
}

function exportResults(searchResults: any[], fitHistory: any[]) {
  let csv = '';

  if (searchResults.length > 0) {
    csv += 'Search Results\n';
    csv += 'Rank,Model,H,AIC,BIC,HasLoops\n';
    searchResults.forEach((r, i) => {
      csv += `${i + 1},"${r.model}",${r.h},${r.aic},${r.bic},${r.hasLoops}\n`;
    });
    csv += '\n';
  }

  if (fitHistory.length > 0) {
    csv += 'Fit History\n';
    csv += 'Model,H,T,DF,DDF,LR,AIC,BIC,Alpha,HasLoops\n';
    fitHistory.forEach((r) => {
      csv += `"${r.model}",${r.h},${r.t},${r.df},${r.ddf},${r.lr},${r.aic},${r.bic},${r.alpha},${r.hasLoops}\n`;
    });
  }

  const blob = new Blob([csv], { type: 'text/csv' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'occam_results.csv';
  a.click();
  URL.revokeObjectURL(url);
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    padding: '1rem',
  },
  empty: {
    textAlign: 'center',
    padding: '2rem',
    color: '#666',
  },
  emptyActions: {
    display: 'flex',
    gap: '1rem',
    justifyContent: 'center',
    marginTop: '1rem',
  },
  linkBtn: {
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
    display: 'flex',
    alignItems: 'center',
    gap: '0.75rem',
  },
  count: {
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
  td: {
    padding: '0.5rem',
    borderBottom: '1px solid #eee',
  },
  tdRank: {
    padding: '0.5rem',
    borderBottom: '1px solid #eee',
    color: '#999',
    width: '2rem',
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
  loopsYes: {
    color: '#e74c3c',
  },
  loopsNo: {
    color: '#27ae60',
  },
  fitBtn: {
    padding: '0.25rem 0.5rem',
    fontSize: '0.7rem',
    border: '1px solid #3498db',
    borderRadius: '3px',
    background: 'white',
    color: '#3498db',
    cursor: 'pointer',
  },
  export: {
    borderTop: '1px solid #eee',
    paddingTop: '1rem',
  },
  exportBtn: {
    padding: '0.5rem 1rem',
    fontSize: '0.8rem',
    border: '1px solid #ccc',
    borderRadius: '4px',
    background: 'white',
    cursor: 'pointer',
  },
};
