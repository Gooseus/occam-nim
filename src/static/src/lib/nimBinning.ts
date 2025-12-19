// TypeScript wrapper for Nim-compiled binning module
// This provides type-safe access to the Nim JS functions

import type { ColumnAnalysis, BinConfig } from '../types/binning';
import type { DataSpec } from '../types/dataSpec';

interface NimBinningModule {
  analyzeColumnsJson: (input: string) => string;
  suggestBinConfigsJson: (input: string, threshold: number) => string;
  applyBinningJson: (data: string, configs: string) => string;
}

// Module state
let nimModule: NimBinningModule | null = null;
let loadPromise: Promise<boolean> | null = null;
let loadFailed = false;

/**
 * Load the Nim-compiled binning module
 * Returns true if loaded successfully, false if unavailable
 */
export async function loadNimBinning(): Promise<boolean> {
  if (nimModule) return true;
  if (loadFailed) return false;

  if (loadPromise) return loadPromise;

  loadPromise = new Promise<boolean>((resolve) => {
    const script = document.createElement('script');
    script.src = '/binning.js';
    script.async = true;

    script.onload = () => {
      // Nim JS exports to global scope
      const win = window as any;
      if (win.analyzeColumnsJson && win.applyBinningJson) {
        nimModule = {
          analyzeColumnsJson: win.analyzeColumnsJson,
          suggestBinConfigsJson: win.suggestBinConfigsJson,
          applyBinningJson: win.applyBinningJson,
        };
        console.log('[NimBinning] Module loaded successfully');
        resolve(true);
      } else {
        console.warn('[NimBinning] Module loaded but functions not found');
        loadFailed = true;
        resolve(false);
      }
    };

    script.onerror = () => {
      console.warn('[NimBinning] Failed to load binning.js, using TS fallback');
      loadFailed = true;
      resolve(false);
    };

    document.head.appendChild(script);
  });

  return loadPromise;
}

/**
 * Check if Nim binning module is available
 */
export function isNimBinningAvailable(): boolean {
  return nimModule !== null;
}

interface NimAnalysisResult {
  columns: Array<{
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
    suggestedStrategy: string;
  }>;
  success: boolean;
  error?: string;
}

interface NimConfigResult {
  configs: Record<string, any>;
  success: boolean;
  error?: string;
}

interface NimDataSpecResult {
  name: string;
  variables: Array<{
    name: string;
    abbrev: string;
    cardinality: number;
    values: string[];
    isDependent: boolean;
  }>;
  data: string[][];
  counts: number[];
  success: boolean;
  error?: string;
}

/**
 * Analyze columns using Nim module
 * Returns null if Nim module not available
 */
export function nimAnalyzeColumns(
  columns: string[],
  data: string[][]
): { analysis: ColumnAnalysis[]; suggestedConfigs: Record<string, BinConfig> } | null {
  if (!nimModule) return null;

  try {
    const input = JSON.stringify({ columns, data });
    const resultStr = nimModule.analyzeColumnsJson(input);
    const result: NimAnalysisResult = JSON.parse(resultStr);

    if (!result.success) {
      console.error('[NimBinning] analyzeColumns error:', result.error);
      return null;
    }

    // Convert Nim result to our types
    const analysis: ColumnAnalysis[] = result.columns.map((col) => ({
      name: col.name,
      index: col.index,
      isNumeric: col.isNumeric,
      uniqueCount: col.uniqueCount,
      totalCount: col.totalCount,
      missingCount: col.missingCount,
      minVal: col.minVal,
      maxVal: col.maxVal,
      topValues: col.topValues,
      needsBinning: col.needsBinning,
      suggestedStrategy: col.suggestedStrategy as any,
    }));

    // Get suggested configs
    const configResultStr = nimModule.suggestBinConfigsJson(resultStr, 10);
    const configResult: NimConfigResult = JSON.parse(configResultStr);

    const suggestedConfigs: Record<string, BinConfig> = {};
    if (configResult.success) {
      for (const [name, config] of Object.entries(configResult.configs)) {
        suggestedConfigs[name] = {
          strategy: config.strategy || 'none',
          numBins: config.numBins || 5,
          topN: config.topN,
          labelStyle: config.labelStyle || 'range',
          otherLabel: config.otherLabel || 'Other',
          missingHandling: config.missingHandling || 'separateBin',
          missingLabel: config.missingLabel || 'Missing',
        };
      }
    }

    return { analysis, suggestedConfigs };
  } catch (err) {
    console.error('[NimBinning] analyzeColumns exception:', err);
    return null;
  }
}

/**
 * Apply binning using Nim module
 * Returns null if Nim module not available
 */
export function nimApplyBinning(
  columns: string[],
  data: string[][],
  configs: Record<string, BinConfig>
): DataSpec | null {
  if (!nimModule) return null;

  try {
    const dataInput = JSON.stringify({ columns, data });
    const configInput = JSON.stringify({ configs });
    const resultStr = nimModule.applyBinningJson(dataInput, configInput);
    const result: NimDataSpecResult = JSON.parse(resultStr);

    if (!result.success) {
      console.error('[NimBinning] applyBinning error:', result.error);
      return null;
    }

    return {
      name: result.name,
      variables: result.variables,
      data: result.data,
      counts: result.counts,
    };
  } catch (err) {
    console.error('[NimBinning] applyBinning exception:', err);
    return null;
  }
}
