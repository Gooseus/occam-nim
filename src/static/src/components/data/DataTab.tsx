import React from 'react';
import { useAppStore } from '../../store/useAppStore';
import { CsvDropzone } from './CsvDropzone';
import { ColumnPreview } from './ColumnPreview';
import { BinningConfig } from './BinningConfig';
import { DataPreview } from './DataPreview';

export function DataTab() {
  const fileName = useAppStore((s) => s.fileName);
  const columnAnalysis = useAppStore((s) => s.columnAnalysis);
  const processedDataSpec = useAppStore((s) => s.processedDataSpec);
  const isProcessing = useAppStore((s) => s.isProcessing);
  const dataError = useAppStore((s) => s.dataError);
  const clearData = useAppStore((s) => s.clearData);
  const setActiveTab = useAppStore((s) => s.setActiveTab);

  const hasData = columnAnalysis.length > 0;
  const isReady = processedDataSpec !== null;

  return (
    <div style={styles.container}>
      {!hasData ? (
        <CsvDropzone />
      ) : (
        <>
          <div style={styles.header}>
            <div style={styles.fileInfo}>
              <span style={styles.fileName}>{fileName}</span>
              <span style={styles.stats}>
                {columnAnalysis.length} columns, {columnAnalysis[0]?.totalCount || 0} rows
              </span>
            </div>
            <button onClick={clearData} style={styles.clearBtn}>
              Clear
            </button>
          </div>

          {dataError && <div style={styles.error}>{dataError}</div>}

          <ColumnPreview />
          <BinningConfig />

          {isReady && (
            <>
              <DataPreview />
              <div style={styles.actions}>
                <button
                  onClick={() => setActiveTab('search')}
                  style={styles.primaryBtn}
                >
                  Continue to Search
                </button>
              </div>
            </>
          )}

          {isProcessing && <div style={styles.processing}>Processing...</div>}
        </>
      )}
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    padding: '1rem',
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '1rem',
    padding: '0.75rem',
    background: '#f8f9fa',
    borderRadius: '4px',
  },
  fileInfo: {
    display: 'flex',
    flexDirection: 'column',
    gap: '0.25rem',
  },
  fileName: {
    fontWeight: 600,
    fontSize: '0.9rem',
  },
  stats: {
    fontSize: '0.8rem',
    color: '#666',
  },
  clearBtn: {
    padding: '0.5rem 1rem',
    fontSize: '0.8rem',
    border: '1px solid #ccc',
    borderRadius: '4px',
    background: 'white',
    cursor: 'pointer',
  },
  error: {
    padding: '0.75rem',
    marginBottom: '1rem',
    background: '#fde8e8',
    border: '1px solid #e74c3c',
    borderRadius: '4px',
    color: '#c0392b',
    fontSize: '0.875rem',
  },
  processing: {
    padding: '1rem',
    textAlign: 'center',
    color: '#666',
  },
  actions: {
    marginTop: '1rem',
    display: 'flex',
    justifyContent: 'flex-end',
  },
  primaryBtn: {
    padding: '0.75rem 1.5rem',
    fontSize: '0.875rem',
    fontWeight: 600,
    background: '#3498db',
    border: 'none',
    borderRadius: '4px',
    color: 'white',
    cursor: 'pointer',
  },
};
