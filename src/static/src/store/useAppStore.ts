import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import type { BinConfig, ColumnAnalysis } from '../types/binning';
import type { DataSpec, SearchParams, SearchResult, SearchProgress, FitResult } from '../types/dataSpec';

export type TabId = 'data' | 'search' | 'fit' | 'results';
export type SearchStatus = 'idle' | 'connecting' | 'searching' | 'complete' | 'error';

interface AppState {
  // Tab navigation
  activeTab: TabId;
  setActiveTab: (tab: TabId) => void;

  // Data state
  fileName: string | null;
  columnAnalysis: ColumnAnalysis[];
  binConfigs: Record<string, BinConfig>;
  processedDataSpec: DataSpec | null;
  isProcessing: boolean;
  dataError: string | null;

  // Data actions
  setFileName: (name: string | null) => void;
  setColumnAnalysis: (analysis: ColumnAnalysis[]) => void;
  setBinConfig: (columnName: string, config: BinConfig) => void;
  setBinConfigs: (configs: Record<string, BinConfig>) => void;
  setProcessedDataSpec: (spec: DataSpec | null) => void;
  setIsProcessing: (processing: boolean) => void;
  setDataError: (error: string | null) => void;
  clearData: () => void;

  // Search state
  searchStatus: SearchStatus;
  searchProgress: SearchProgress | null;
  searchResults: SearchResult[];
  searchTotalEvaluated: number;
  searchError: { code: string; message: string } | null;
  searchParams: SearchParams;

  // Search actions
  setSearchStatus: (status: SearchStatus) => void;
  setSearchProgress: (progress: SearchProgress | null) => void;
  setSearchResults: (results: SearchResult[], totalEvaluated: number) => void;
  setSearchError: (error: { code: string; message: string } | null) => void;
  setSearchParams: (params: Partial<SearchParams>) => void;
  resetSearch: () => void;

  // Fit state
  fitHistory: FitResult[];
  currentFitModel: string;
  isFitting: boolean;
  fitError: string | null;

  // Fit actions
  setCurrentFitModel: (model: string) => void;
  setIsFitting: (fitting: boolean) => void;
  setFitError: (error: string | null) => void;
  addFitResult: (result: FitResult) => void;
  clearFitHistory: () => void;
  selectModelFromResults: (model: string) => void;
}

const DEFAULT_SEARCH_PARAMS: SearchParams = {
  direction: 'up',
  filter: 'loopless',
  width: 3,
  levels: 7,
  sortBy: 'bic',
};

export const useAppStore = create<AppState>()(
  persist(
    (set) => ({
      // Tab navigation
      activeTab: 'data',
      setActiveTab: (tab) => set({ activeTab: tab }),

      // Data state
      fileName: null,
      columnAnalysis: [],
      binConfigs: {},
      processedDataSpec: null,
      isProcessing: false,
      dataError: null,

      // Data actions
      setFileName: (name) => set({ fileName: name }),
      setColumnAnalysis: (analysis) => set({ columnAnalysis: analysis }),
      setBinConfig: (columnName, config) =>
        set((state) => ({
          binConfigs: { ...state.binConfigs, [columnName]: config },
        })),
      setBinConfigs: (configs) => set({ binConfigs: configs }),
      setProcessedDataSpec: (spec) => set({ processedDataSpec: spec }),
      setIsProcessing: (processing) => set({ isProcessing: processing }),
      setDataError: (error) => set({ dataError: error }),
      clearData: () =>
        set({
          fileName: null,
          columnAnalysis: [],
          binConfigs: {},
          processedDataSpec: null,
          dataError: null,
        }),

      // Search state
      searchStatus: 'idle',
      searchProgress: null,
      searchResults: [],
      searchTotalEvaluated: 0,
      searchError: null,
      searchParams: DEFAULT_SEARCH_PARAMS,

      // Search actions
      setSearchStatus: (status) => set({ searchStatus: status }),
      setSearchProgress: (progress) => set({ searchProgress: progress }),
      setSearchResults: (results, totalEvaluated) =>
        set({ searchResults: results, searchTotalEvaluated: totalEvaluated }),
      setSearchError: (error) => set({ searchError: error }),
      setSearchParams: (params) =>
        set((state) => ({
          searchParams: { ...state.searchParams, ...params },
        })),
      resetSearch: () =>
        set({
          searchStatus: 'idle',
          searchProgress: null,
          searchResults: [],
          searchTotalEvaluated: 0,
          searchError: null,
        }),

      // Fit state
      fitHistory: [],
      currentFitModel: '',
      isFitting: false,
      fitError: null,

      // Fit actions
      setCurrentFitModel: (model) => set({ currentFitModel: model }),
      setIsFitting: (fitting) => set({ isFitting: fitting }),
      setFitError: (error) => set({ fitError: error }),
      addFitResult: (result) =>
        set((state) => ({
          fitHistory: [result, ...state.fitHistory],
        })),
      clearFitHistory: () => set({ fitHistory: [] }),
      selectModelFromResults: (model) => {
        set({ currentFitModel: model, activeTab: 'fit' });
      },
    }),
    {
      name: 'occam-app-storage',
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({
        // Persist these fields across page refreshes
        activeTab: state.activeTab,
        fileName: state.fileName,
        columnAnalysis: state.columnAnalysis,
        binConfigs: state.binConfigs,
        processedDataSpec: state.processedDataSpec,
        searchResults: state.searchResults,
        searchTotalEvaluated: state.searchTotalEvaluated,
        searchParams: state.searchParams,
        fitHistory: state.fitHistory,
        currentFitModel: state.currentFitModel,
      }),
    }
  )
);
