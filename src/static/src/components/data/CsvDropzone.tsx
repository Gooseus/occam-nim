import React, { useCallback, useEffect } from 'react';
import { useDropzone } from 'react-dropzone';
import Papa from 'papaparse';
import { useAppStore } from '../../store/useAppStore';
import { analyzeColumns, applyBinning } from '../../lib/binning';
import { loadNimBinning, isNimBinningAvailable, nimAnalyzeColumns, nimApplyBinning } from '../../lib/nimBinning';

export function CsvDropzone() {
  const setFileName = useAppStore((s) => s.setFileName);
  const setColumnAnalysis = useAppStore((s) => s.setColumnAnalysis);
  const setBinConfigs = useAppStore((s) => s.setBinConfigs);
  const setProcessedDataSpec = useAppStore((s) => s.setProcessedDataSpec);
  const setIsProcessing = useAppStore((s) => s.setIsProcessing);
  const setDataError = useAppStore((s) => s.setDataError);

  // Try to load Nim binning module on mount
  useEffect(() => {
    loadNimBinning().then((success) => {
      if (success) {
        console.log('[CsvDropzone] Nim binning module available');
      } else {
        console.log('[CsvDropzone] Using TypeScript fallback');
      }
    });
  }, []);

  const onDrop = useCallback(
    (acceptedFiles: File[]) => {
      const file = acceptedFiles[0];
      if (!file) return;

      setIsProcessing(true);
      setDataError(null);
      setFileName(file.name);

      Papa.parse(file, {
        header: true,
        skipEmptyLines: true,
        worker: true,
        complete: (results) => {
          try {
            const columns = results.meta.fields || [];
            const data = results.data as Record<string, string>[];

            if (columns.length === 0) {
              setDataError('No columns found in CSV');
              setIsProcessing(false);
              return;
            }

            // Convert to array format for analysis
            const dataArray = data.map((row) =>
              columns.map((col) => row[col] ?? '')
            );

            // Try Nim module first, fall back to TypeScript
            let analysis, suggestedConfigs, dataSpec;

            if (isNimBinningAvailable()) {
              const nimResult = nimAnalyzeColumns(columns, dataArray);
              if (nimResult) {
                analysis = nimResult.analysis;
                suggestedConfigs = nimResult.suggestedConfigs;
                const nimDataSpec = nimApplyBinning(columns, dataArray, suggestedConfigs);
                if (nimDataSpec) {
                  dataSpec = nimDataSpec;
                }
              }
            }

            // Fallback to TypeScript if Nim failed or unavailable
            if (!analysis || !dataSpec) {
              const tsResult = analyzeColumns(columns, dataArray);
              analysis = tsResult.analysis;
              suggestedConfigs = tsResult.suggestedConfigs;
              dataSpec = applyBinning(columns, dataArray, suggestedConfigs, analysis);
            }

            setColumnAnalysis(analysis);
            setBinConfigs(suggestedConfigs!);
            dataSpec!.name = file.name.replace(/\.[^/.]+$/, '');
            setProcessedDataSpec(dataSpec!);

            setIsProcessing(false);
          } catch (err) {
            setDataError(err instanceof Error ? err.message : 'Failed to parse CSV');
            setIsProcessing(false);
          }
        },
        error: (err) => {
          setDataError(err.message);
          setIsProcessing(false);
        },
      });
    },
    [setFileName, setColumnAnalysis, setBinConfigs, setProcessedDataSpec, setIsProcessing, setDataError]
  );

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: {
      'text/csv': ['.csv'],
      'text/plain': ['.txt', '.tsv'],
    },
    maxFiles: 1,
  });

  return (
    <div
      {...getRootProps()}
      style={{
        ...styles.dropzone,
        ...(isDragActive ? styles.dropzoneActive : {}),
      }}
    >
      <input {...getInputProps()} />
      <div style={styles.icon}>
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
          <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
          <polyline points="14 2 14 8 20 8" />
          <line x1="12" y1="18" x2="12" y2="12" />
          <line x1="9" y1="15" x2="12" y2="12" />
          <line x1="15" y1="15" x2="12" y2="12" />
        </svg>
      </div>
      {isDragActive ? (
        <p style={styles.text}>Drop the CSV file here...</p>
      ) : (
        <>
          <p style={styles.text}>Drag & drop a CSV file here</p>
          <p style={styles.subtext}>or click to select a file</p>
        </>
      )}
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  dropzone: {
    border: '2px dashed #ccc',
    borderRadius: '8px',
    padding: '3rem 2rem',
    textAlign: 'center',
    cursor: 'pointer',
    transition: 'all 0.2s',
    background: '#fafafa',
  },
  dropzoneActive: {
    borderColor: '#3498db',
    background: '#ebf5fb',
  },
  icon: {
    color: '#999',
    marginBottom: '1rem',
  },
  text: {
    fontSize: '1rem',
    color: '#333',
    margin: '0 0 0.5rem 0',
  },
  subtext: {
    fontSize: '0.875rem',
    color: '#666',
    margin: 0,
  },
};
