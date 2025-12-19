// Pure TypeScript binning implementation (fallback before Nim JS module)

import type { BinConfig, BinStrategy, ColumnAnalysis } from '../types/binning';
import type { DataSpec, VariableSpec } from '../types/dataSpec';
import { DEFAULT_BIN_CONFIG, isMissingValue } from '../types/binning';

const CARDINALITY_THRESHOLD = 10; // Auto-bin if more than this many unique values

interface AnalysisResult {
  analysis: ColumnAnalysis[];
  suggestedConfigs: Record<string, BinConfig>;
}

export function analyzeColumns(columns: string[], data: string[][]): AnalysisResult {
  const analysis: ColumnAnalysis[] = [];
  const suggestedConfigs: Record<string, BinConfig> = {};

  for (let i = 0; i < columns.length; i++) {
    const colName = columns[i];
    const values = data.map((row) => row[i] ?? '');

    // Count frequencies
    const freqMap = new Map<string, number>();
    let missingCount = 0;
    let isNumeric = true;
    let minVal: number | null = null;
    let maxVal: number | null = null;

    for (const val of values) {
      if (isMissingValue(val)) {
        missingCount++;
        continue;
      }

      freqMap.set(val, (freqMap.get(val) || 0) + 1);

      // Check if numeric
      if (isNumeric) {
        const num = parseFloat(val);
        if (isNaN(num)) {
          isNumeric = false;
        } else {
          if (minVal === null || num < minVal) minVal = num;
          if (maxVal === null || num > maxVal) maxVal = num;
        }
      }
    }

    // Get top values sorted by frequency
    const topValues = Array.from(freqMap.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, 10)
      .map(([value, count]) => ({ value, count }));

    const uniqueCount = freqMap.size;
    const needsBinning = uniqueCount > CARDINALITY_THRESHOLD;

    let suggestedStrategy: BinStrategy = 'none';
    if (needsBinning) {
      suggestedStrategy = isNumeric ? 'equalWidth' : 'topN';
    }

    const colAnalysis: ColumnAnalysis = {
      name: colName,
      index: i,
      isNumeric,
      uniqueCount,
      totalCount: values.length,
      missingCount,
      minVal: isNumeric ? minVal : null,
      maxVal: isNumeric ? maxVal : null,
      topValues,
      needsBinning,
      suggestedStrategy,
    };

    analysis.push(colAnalysis);

    // Create suggested config
    const config: BinConfig = {
      ...DEFAULT_BIN_CONFIG,
      strategy: suggestedStrategy,
      numBins: needsBinning ? 5 : uniqueCount,
    };

    if (suggestedStrategy === 'topN') {
      config.topN = 5;
    }

    suggestedConfigs[colName] = config;
  }

  return { analysis, suggestedConfigs };
}

export function generateAbbrev(name: string, existingAbbrevs: Set<string>): string {
  // Try first letter uppercase
  let abbrev = name.charAt(0).toUpperCase();
  if (!existingAbbrevs.has(abbrev)) {
    return abbrev;
  }

  // Try first two letters
  abbrev = name.substring(0, 2).toUpperCase();
  if (!existingAbbrevs.has(abbrev)) {
    return abbrev;
  }

  // Try incrementing letters
  for (let i = 0; i < 26; i++) {
    abbrev = String.fromCharCode(65 + i); // A-Z
    if (!existingAbbrevs.has(abbrev)) {
      return abbrev;
    }
  }

  // Fallback to numbered
  let counter = 1;
  while (existingAbbrevs.has(`V${counter}`)) {
    counter++;
  }
  return `V${counter}`;
}

function computeEqualWidthBreaks(min: number, max: number, numBins: number): number[] {
  const breaks: number[] = [];
  const width = (max - min) / numBins;
  for (let i = 1; i < numBins; i++) {
    breaks.push(min + i * width);
  }
  return breaks;
}

function assignToBin(value: number, breaks: number[]): number {
  for (let i = 0; i < breaks.length; i++) {
    if (value < breaks[i]) return i;
  }
  return breaks.length;
}

function generateRangeLabels(breaks: number[], min: number, max: number): string[] {
  const labels: string[] = [];
  let prev = min;
  for (const bp of breaks) {
    labels.push(`${prev.toFixed(1)}-${bp.toFixed(1)}`);
    prev = bp;
  }
  labels.push(`${prev.toFixed(1)}-${max.toFixed(1)}`);
  return labels;
}

function generateIndexLabels(numBins: number): string[] {
  return Array.from({ length: numBins }, (_, i) => i.toString());
}

export function applyBinning(
  columns: string[],
  data: string[][],
  configs: Record<string, BinConfig>,
  analysis: ColumnAnalysis[]
): DataSpec {
  const usedAbbrevs = new Set<string>();
  const variables: VariableSpec[] = [];
  const binnedData: string[][] = [];
  const valueMappers: Array<(val: string) => string> = [];

  // Build variable specs and mappers
  for (let i = 0; i < columns.length; i++) {
    const colName = columns[i];
    const config = configs[colName] || DEFAULT_BIN_CONFIG;
    const colAnalysis = analysis[i];
    const abbrev = generateAbbrev(colName, usedAbbrevs);
    usedAbbrevs.add(abbrev);

    let values: string[];
    let mapper: (val: string) => string;

    if (config.strategy === 'none') {
      // No binning - use original values
      values = colAnalysis.topValues.map((v) => v.value);
      if (colAnalysis.missingCount > 0 && config.missingHandling === 'separateBin') {
        values.push(config.missingLabel);
      }
      const valueSet = new Set(values);
      mapper = (val) => {
        if (isMissingValue(val)) {
          return config.missingHandling === 'separateBin' ? config.missingLabel : '';
        }
        return valueSet.has(val) ? val : config.otherLabel;
      };
    } else if (config.strategy === 'equalWidth' && colAnalysis.isNumeric) {
      const min = colAnalysis.minVal ?? 0;
      const max = colAnalysis.maxVal ?? 1;
      const breaks = computeEqualWidthBreaks(min, max, config.numBins);
      values = config.labelStyle === 'index'
        ? generateIndexLabels(config.numBins)
        : generateRangeLabels(breaks, min, max);

      if (colAnalysis.missingCount > 0 && config.missingHandling === 'separateBin') {
        values.push(config.missingLabel);
      }

      mapper = (val) => {
        if (isMissingValue(val)) {
          return config.missingHandling === 'separateBin' ? config.missingLabel : '';
        }
        const num = parseFloat(val);
        if (isNaN(num)) return config.otherLabel;
        const binIdx = assignToBin(num, breaks);
        return values[binIdx] || config.otherLabel;
      };
    } else if (config.strategy === 'topN') {
      const topN = config.topN || 5;
      const topVals = colAnalysis.topValues.slice(0, topN).map((v) => v.value);
      values = [...topVals, config.otherLabel];
      if (colAnalysis.missingCount > 0 && config.missingHandling === 'separateBin') {
        values.push(config.missingLabel);
      }
      const topSet = new Set(topVals);
      mapper = (val) => {
        if (isMissingValue(val)) {
          return config.missingHandling === 'separateBin' ? config.missingLabel : '';
        }
        return topSet.has(val) ? val : config.otherLabel;
      };
    } else {
      // Fallback - treat as categorical
      values = colAnalysis.topValues.map((v) => v.value);
      mapper = (val) => val;
    }

    variables.push({
      name: colName,
      abbrev,
      cardinality: values.length,
      values,
      isDependent: false,
    });
    valueMappers.push(mapper);
  }

  // Apply binning to data
  for (const row of data) {
    const binnedRow = row.map((val, i) => valueMappers[i](val));
    // Skip rows with empty values (excluded missing)
    if (binnedRow.some((v) => v === '')) continue;
    binnedData.push(binnedRow);
  }

  // Aggregate to frequency table
  const freqMap = new Map<string, number>();
  for (const row of binnedData) {
    const key = row.join('|');
    freqMap.set(key, (freqMap.get(key) || 0) + 1);
  }

  const aggregatedData: string[][] = [];
  const counts: number[] = [];
  for (const [key, count] of freqMap) {
    aggregatedData.push(key.split('|'));
    counts.push(count);
  }

  return {
    name: 'uploaded_data',
    variables,
    data: aggregatedData,
    counts,
  };
}
