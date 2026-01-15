import React, { useCallback } from 'react';
import { useDropzone } from 'react-dropzone';
import Papa from 'papaparse';
import { useAppStore } from '../../store/useAppStore';
import { analyzeColumns, applyBinning } from '../../lib/binning';

/**
 * Generate Excel-style column names: A, B, C, ..., Z, AA, AB, ...
 */
function generateExcelColumnName(index: number): string {
  let name = '';
  let n = index;
  while (n >= 0) {
    name = String.fromCharCode(65 + (n % 26)) + name;
    n = Math.floor(n / 26) - 1;
  }
  return name;
}

/**
 * Detect if the first row is a header by checking if its values are unique
 * (don't appear elsewhere in the data). Header labels typically only appear
 * once, while data values repeat across rows.
 */
function detectHeader(allRows: string[][]): boolean {
  if (allRows.length < 2) return false;

  const firstRow = allRows[0];
  const dataRows = allRows.slice(1);

  let uniqueToFirstRow = 0;
  let appearsInData = 0;

  for (let colIdx = 0; colIdx < firstRow.length; colIdx++) {
    const firstRowValue = firstRow[colIdx]?.trim();
    if (!firstRowValue) continue;

    // Check if this value appears anywhere in the rest of the data for this column
    const foundInData = dataRows.some(row => row[colIdx]?.trim() === firstRowValue);

    if (foundInData) {
      appearsInData++;
    } else {
      uniqueToFirstRow++;
    }
  }

  // If most first-row values don't appear elsewhere, it's a header
  // Use > 50% threshold to be confident
  const totalChecked = uniqueToFirstRow + appearsInData;
  if (totalChecked === 0) return false;

  const uniqueRatio = uniqueToFirstRow / totalChecked;
  console.log(`[HeaderDetection] ${uniqueToFirstRow}/${totalChecked} first-row values are unique (${(uniqueRatio * 100).toFixed(1)}%)`);

  return uniqueRatio > 0.5;
}

export function CsvDropzone() {
  const setFileName = useAppStore((s) => s.setFileName);
  const setRawData = useAppStore((s) => s.setRawData);
  const setColumnAnalysis = useAppStore((s) => s.setColumnAnalysis);
  const setBinConfigs = useAppStore((s) => s.setBinConfigs);
  const setProcessedDataSpec = useAppStore((s) => s.setProcessedDataSpec);
  const setIsProcessing = useAppStore((s) => s.setIsProcessing);
  const setDataError = useAppStore((s) => s.setDataError);
  const setExcludedColumns = useAppStore((s) => s.setExcludedColumns);

  const onDrop = useCallback(
    (acceptedFiles: File[]) => {
      const file = acceptedFiles[0];
      if (!file) return;

      setIsProcessing(true);
      setDataError(null);
      setFileName(file.name);

      // First pass: parse without headers to detect if first row is a header
      Papa.parse(file, {
        header: false,
        skipEmptyLines: true,
        worker: true,
        complete: (results) => {
          try {
            const rawData = results.data as string[][];

            if (rawData.length === 0) {
              setDataError('No data found in CSV');
              setIsProcessing(false);
              return;
            }

            const hasHeader = detectHeader(rawData);

            let columns: string[];
            let dataArray: string[][];

            if (hasHeader) {
              // First row is header
              columns = rawData[0];
              dataArray = rawData.slice(1);
              console.log('[CsvDropzone] Detected header row:', columns);
            } else {
              // No header - generate Excel-style column names
              columns = rawData[0].map((_, i) => generateExcelColumnName(i));
              dataArray = rawData;
              console.log('[CsvDropzone] No header detected, generated columns:', columns);
            }

            if (columns.length === 0) {
              setDataError('No columns found in CSV');
              setIsProcessing(false);
              return;
            }

            // Store raw data for re-processing when exclusions change
            setRawData(columns, dataArray);
            setExcludedColumns([]); // Reset exclusions for new file

            // Analyze columns (TypeScript only since Nim binning is disabled)
            const tsResult = analyzeColumns(columns, dataArray);
            const analysis = tsResult.analysis;
            const suggestedConfigs = tsResult.suggestedConfigs;

            // Process with no excluded columns initially
            const dataSpec = applyBinning(columns, dataArray, suggestedConfigs, analysis, []);

            setColumnAnalysis(analysis);
            setBinConfigs(suggestedConfigs);
            dataSpec.name = file.name.replace(/\.[^/.]+$/, '');
            setProcessedDataSpec(dataSpec);

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
    [setFileName, setRawData, setColumnAnalysis, setBinConfigs, setProcessedDataSpec, setIsProcessing, setDataError, setExcludedColumns]
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
