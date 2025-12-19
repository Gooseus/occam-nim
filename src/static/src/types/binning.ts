// Binning configuration types

export type BinStrategy =
  | 'none'
  | 'equalWidth'
  | 'equalFrequency'
  | 'customBreaks'
  | 'topN'
  | 'frequencyThreshold';

export type MissingHandling = 'separateBin' | 'exclude' | 'ignore';

export type LabelStyle = 'range' | 'semantic' | 'index' | 'custom';

export interface BinConfig {
  strategy: BinStrategy;
  numBins: number;
  breakpoints?: number[];
  topN?: number;
  minFrequency?: number;
  minFrequencyIsRatio?: boolean;
  labelStyle: LabelStyle;
  customLabels?: string[];
  otherLabel: string;
  missingHandling: MissingHandling;
  missingLabel: string;
}

export interface ColumnAnalysis {
  name: string;
  index: number;
  isNumeric: boolean;
  uniqueCount: number;
  totalCount: number;
  missingCount: number;
  minVal: number | null;
  maxVal: number | null;
  topValues: Array<{ value: string; count: number }>;
  needsBinning: boolean;
  suggestedStrategy: BinStrategy;
}

export const DEFAULT_BIN_CONFIG: BinConfig = {
  strategy: 'none',
  numBins: 5,
  labelStyle: 'range',
  otherLabel: 'Other',
  missingHandling: 'separateBin',
  missingLabel: 'Missing',
};

export const MISSING_INDICATORS = [
  '', 'NA', 'N/A', 'n/a', 'na', 'NaN', 'nan', 'NULL', 'null',
  'None', 'none', '.', '-', '?', 'missing', 'Missing', 'MISSING',
];

export function isMissingValue(value: string): boolean {
  return MISSING_INDICATORS.includes(value.trim());
}
