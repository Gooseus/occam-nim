import React, { useState } from 'react';
import { useAppStore } from '../../store/useAppStore';
import { ModelLatticeContainer } from '../lattice';
import { colors, spacing, commonStyles } from '../../lib/theme';

type ViewMode = 'table' | 'lattice';

// Column tooltips explaining each statistic
const TOOLTIPS = {
  model: 'Model structure showing variable associations (e.g., AB:BC means A-B and B-C are associated)',
  h: 'Entropy (H): Uncertainty in the fitted distribution. Lower = more deterministic.',
  t: 'Transmission (T): Information gained by the model. Higher = better predictive power.',
  df: 'Degrees of Freedom: Model complexity. Lower = simpler model.',
  ddf: 'Delta DF: Degrees of freedom saved vs saturated model. Higher = simpler.',
  lr: 'Likelihood Ratio (G²): Goodness of fit statistic. Lower = better fit.',
  aic: 'Akaike Information Criterion: Balances fit and complexity. Lower = better.',
  bic: 'Bayesian Information Criterion: Like AIC but penalizes complexity more. Lower = better.',
  deltaBic: 'Difference from best model. 0 = best. <2 = equivalent, 2-6 = weak evidence, >10 = strong.',
  alpha: 'P-value: Probability of observed data under the model. Higher = better fit.',
  loops: 'Whether model contains loops. Loop models require IPF fitting (slower).',
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

function deltaBicStyle(deltaBic: number): React.CSSProperties {
  if (deltaBic < 0.01) return { color: '#27ae60', fontWeight: 600 };
  if (deltaBic < 2) return { color: '#666' };
  if (deltaBic < 6) return { color: '#f39c12' };
  if (deltaBic < 10) return { color: '#e67e22' };
  return { color: '#e74c3c' };
}

export function ResultsTab() {
  const searchResults = useAppStore((s) => s.searchResults);
  const searchTotalEvaluated = useAppStore((s) => s.searchTotalEvaluated);
  const fitHistory = useAppStore((s) => s.fitHistory);
  const selectModelFromResults = useAppStore((s) => s.selectModelFromResults);
  const setReferenceModelFromResults = useAppStore((s) => s.setReferenceModelFromResults);
  const setActiveTab = useAppStore((s) => s.setActiveTab);

  const [viewMode, setViewMode] = useState<ViewMode>('table');

  const hasSearchResults = searchResults.length > 0;
  const hasFitHistory = fitHistory.length > 0;
  const currentBest = searchResults[0]?.model;
  const bestBic = hasSearchResults ? Math.min(...searchResults.map(r => r.bic)) : 0;

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
          <div style={styles.header}>
            <h3 style={styles.heading}>
              Search Results
              <span style={styles.count}>
                {searchResults.length} models ({searchTotalEvaluated} evaluated)
              </span>
            </h3>

            {/* View toggle */}
            <div style={styles.viewToggle}>
              <button
                onClick={() => setViewMode('table')}
                style={{
                  ...styles.toggleBtn,
                  ...(viewMode === 'table' ? styles.toggleBtnActive : {}),
                }}
              >
                Table
              </button>
              <button
                onClick={() => setViewMode('lattice')}
                style={{
                  ...styles.toggleBtn,
                  ...(viewMode === 'lattice' ? styles.toggleBtnActive : {}),
                }}
              >
                Lattice
              </button>
            </div>
          </div>

          {viewMode === 'table' ? (
            <>
              <table style={styles.table}>
                <thead>
                  <tr>
                    <th style={styles.th}>#</th>
                    <th style={styles.th}><Tooltip text={TOOLTIPS.model}>Model</Tooltip></th>
                    <th style={styles.th}><Tooltip text={TOOLTIPS.h}>H</Tooltip></th>
                    <th style={styles.th}><Tooltip text={TOOLTIPS.ddf}>ΔDF</Tooltip></th>
                    <th style={styles.th}><Tooltip text={TOOLTIPS.aic}>AIC</Tooltip></th>
                    <th style={styles.th}><Tooltip text={TOOLTIPS.deltaBic}>ΔBIC</Tooltip></th>
                    <th style={styles.th}><Tooltip text={TOOLTIPS.loops}>Loops</Tooltip></th>
                    <th style={styles.th}></th>
                  </tr>
                </thead>
                <tbody>
                  {searchResults.map((r, i) => {
                    const deltaBic = r.bic - bestBic;
                    return (
                      <tr key={r.model} style={i % 2 === 0 ? {} : styles.altRow}>
                        <td style={styles.tdRank}>{i + 1}</td>
                        <td style={styles.tdModel}>{r.model}</td>
                        <td style={styles.td}>{r.h.toFixed(4)}</td>
                        <td style={styles.td}>{r.ddf}</td>
                        <td style={styles.td}>{r.aic.toFixed(2)}</td>
                        <td style={styles.td}>
                          <span style={deltaBicStyle(deltaBic)}>
                            {deltaBic < 0.01 ? '0' : deltaBic.toFixed(2)}
                          </span>
                        </td>
                        <td style={styles.td}>
                          <span style={r.hasLoops ? styles.loopsYes : styles.loopsNo}>
                            {r.hasLoops ? 'Yes' : 'No'}
                          </span>
                        </td>
                        <td style={styles.td}>
                          <div style={styles.actionBtns}>
                            <button
                              onClick={() => selectModelFromResults(r.model)}
                              style={styles.fitBtn}
                            >
                              Fit
                            </button>
                            <button
                              onClick={() => setReferenceModelFromResults(r.model)}
                              style={styles.refBtn}
                              title="Use this model as reference for next search"
                            >
                              Ref
                            </button>
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
              <div style={styles.legend}>
                <span style={styles.legendTitle}>ΔBIC:</span>
                <span style={{ ...styles.legendItem, color: '#27ae60' }}>0 = best</span>
                <span style={{ ...styles.legendItem, color: '#666' }}>&lt;2 = equiv</span>
                <span style={{ ...styles.legendItem, color: '#f39c12' }}>2-6 = weak</span>
                <span style={{ ...styles.legendItem, color: '#e74c3c' }}>&gt;10 = strong</span>
              </div>
            </>
          ) : (
            <ModelLatticeContainer
              searchResults={searchResults}
              currentBest={currentBest}
              width={950}
              height={450}
              onFitModel={selectModelFromResults}
            />
          )}
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
                <th style={styles.th}><Tooltip text={TOOLTIPS.model}>Model</Tooltip></th>
                <th style={styles.th}><Tooltip text={TOOLTIPS.h}>H</Tooltip></th>
                <th style={styles.th}><Tooltip text={TOOLTIPS.t}>T</Tooltip></th>
                <th style={styles.th}><Tooltip text={TOOLTIPS.ddf}>ΔDF</Tooltip></th>
                <th style={styles.th}><Tooltip text={TOOLTIPS.lr}>LR</Tooltip></th>
                <th style={styles.th}><Tooltip text={TOOLTIPS.bic}>BIC</Tooltip></th>
                <th style={styles.th}><Tooltip text={TOOLTIPS.alpha}>p-value</Tooltip></th>
              </tr>
            </thead>
            <tbody>
              {fitHistory.map((r, i) => (
                <tr
                  key={`${r.model}-${r.timestamp}`}
                  style={i % 2 === 0 ? {} : styles.altRow}
                >
                  <td style={styles.tdModel}>{r.model}</td>
                  <td style={styles.td}>{r.h.toFixed(4)}</td>
                  <td style={styles.td}>{r.t.toFixed(4)}</td>
                  <td style={styles.td}>{r.ddf}</td>
                  <td style={styles.td}>{r.lr.toFixed(2)}</td>
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

function exportResults(searchResults: unknown[], fitHistory: unknown[]) {
  let csv = '';

  if (searchResults.length > 0) {
    csv += 'Search Results\n';
    csv += 'Rank,Model,H,AIC,BIC,HasLoops\n';
    (searchResults as Array<{ model: string; h: number; aic: number; bic: number; hasLoops: boolean }>).forEach((r, i) => {
      csv += `${i + 1},"${r.model}",${r.h},${r.aic},${r.bic},${r.hasLoops}\n`;
    });
    csv += '\n';
  }

  if (fitHistory.length > 0) {
    csv += 'Fit History\n';
    csv += 'Model,H,T,DF,DDF,LR,AIC,BIC,Alpha,HasLoops\n';
    (fitHistory as Array<{ model: string; h: number; t: number; df: number; ddf: number; lr: number; aic: number; bic: number; alpha: number; hasLoops: boolean }>).forEach((r) => {
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
    padding: spacing.lg,
  },
  empty: {
    textAlign: 'center',
    padding: spacing.xxl,
    color: colors.textMuted,
  },
  emptyActions: {
    display: 'flex',
    gap: spacing.lg,
    justifyContent: 'center',
    marginTop: spacing.lg,
  },
  linkBtn: {
    ...commonStyles.linkButton,
  },
  section: {
    marginBottom: spacing.xl,
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: spacing.md,
  },
  heading: {
    fontSize: '0.9rem',
    fontWeight: 600,
    display: 'flex',
    alignItems: 'center',
    gap: spacing.md,
    margin: 0,
  },
  count: {
    fontSize: '0.75rem',
    fontWeight: 400,
    color: colors.textMuted,
  },
  viewToggle: {
    display: 'flex',
    gap: '1px',
    background: colors.borderMedium,
    borderRadius: '4px',
    overflow: 'hidden',
  },
  toggleBtn: {
    padding: `${spacing.xs} ${spacing.md}`,
    fontSize: '0.75rem',
    border: 'none',
    background: colors.bgCard,
    cursor: 'pointer',
  },
  toggleBtnActive: {
    background: colors.primary,
    color: 'white',
  },
  table: {
    ...commonStyles.tableBase,
  },
  th: {
    ...commonStyles.th,
  },
  td: {
    ...commonStyles.td,
  },
  tdRank: {
    ...commonStyles.td,
    color: colors.textLight,
    width: '2rem',
  },
  tdModel: {
    ...commonStyles.tdModel,
  },
  altRow: {
    ...commonStyles.altRow,
  },
  loopsYes: {
    ...commonStyles.loopsYes,
  },
  loopsNo: {
    ...commonStyles.loopsNo,
  },
  fitBtn: {
    padding: `${spacing.xs} ${spacing.sm}`,
    fontSize: '0.7rem',
    border: `1px solid ${colors.primary}`,
    borderRadius: '3px',
    background: colors.bgCard,
    color: colors.primary,
    cursor: 'pointer',
  },
  refBtn: {
    padding: `${spacing.xs} ${spacing.sm}`,
    fontSize: '0.7rem',
    border: '1px solid #666',
    borderRadius: '3px',
    background: colors.bgCard,
    color: '#666',
    cursor: 'pointer',
  },
  actionBtns: {
    display: 'flex',
    gap: '4px',
  },
  export: {
    borderTop: `1px solid ${colors.borderLight}`,
    paddingTop: spacing.lg,
  },
  exportBtn: {
    ...commonStyles.buttonBase,
  },
  legend: {
    marginTop: spacing.sm,
    padding: `${spacing.xs} ${spacing.sm}`,
    background: colors.bgHover,
    borderRadius: '4px',
    fontSize: '0.7rem',
    display: 'flex',
    alignItems: 'center',
    gap: spacing.md,
    flexWrap: 'wrap',
  },
  legendTitle: {
    fontWeight: 600,
    color: colors.text,
  },
  legendItem: {
    whiteSpace: 'nowrap',
  },
};
