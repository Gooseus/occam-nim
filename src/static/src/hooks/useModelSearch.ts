import { useCallback, useRef, useMemo } from 'react';
import { useWebSocket, type WebSocketHandle } from './useWebSocket';
import { useAppStore } from '../store/useAppStore';
import type { SearchResult } from '../types/dataSpec';

interface SearchMessage {
  type: 'progress' | 'result' | 'error';
  requestId: string;
  event?: string;
  data?: Record<string, unknown>;
  error?: { code: string; message: string };
}

/**
 * Hook for managing model search via WebSocket.
 * Integrates with Zustand store for state management.
 */
export function useModelSearch() {
  const requestIdRef = useRef<string | null>(null);
  const wsHandleRef = useRef<WebSocketHandle | null>(null);

  // Zustand selectors
  const processedDataSpec = useAppStore((s) => s.processedDataSpec);
  const searchParams = useAppStore((s) => s.searchParams);
  const searchStatus = useAppStore((s) => s.searchStatus);
  const setSearchStatus = useAppStore((s) => s.setSearchStatus);
  const setSearchProgress = useAppStore((s) => s.setSearchProgress);
  const setSearchResults = useAppStore((s) => s.setSearchResults);
  const setSearchError = useAppStore((s) => s.setSearchError);
  const resetSearch = useAppStore((s) => s.resetSearch);

  const handleMessage = useCallback(
    (data: unknown) => {
      const msg = data as SearchMessage;

      // Ignore messages for other requests
      if (msg.requestId !== requestIdRef.current) return;

      if (msg.type === 'progress') {
        const eventData = msg.data || {};

        if (msg.event === 'search_started') {
          setSearchProgress({
            currentLevel: 0,
            totalLevels: (eventData.totalLevels as number) || searchParams.levels,
            modelsEvaluated: 0,
            statisticName: eventData.statisticName as string,
          });
        } else if (msg.event === 'level_complete') {
          setSearchProgress({
            currentLevel: (eventData.currentLevel as number) || 0,
            totalLevels: (eventData.totalLevels as number) || searchParams.levels,
            modelsEvaluated:
              (eventData.modelsEvaluated as number) ||
              (eventData.totalModelsEvaluated as number) ||
              0,
            looplessModels: eventData.looplessModels as number | undefined,
            loopModels: eventData.loopModels as number | undefined,
            bestModelName: eventData.bestModelName as string | undefined,
            bestStatistic: eventData.bestStatistic as number | undefined,
            statisticName: eventData.statisticName as string | undefined,
            levelTimeMs: eventData.levelTimeMs as number | undefined,
            elapsedMs: eventData.elapsedMs as number | undefined,
            avgModelTimeMs: eventData.avgModelTimeMs as number | undefined,
          });
        } else if (msg.event === 'search_complete') {
          const prev = useAppStore.getState().searchProgress;
          setSearchProgress({
            currentLevel:
              prev?.totalLevels ||
              (eventData.totalLevels as number) ||
              searchParams.levels,
            totalLevels:
              prev?.totalLevels ||
              (eventData.totalLevels as number) ||
              searchParams.levels,
            modelsEvaluated:
              (eventData.totalModelsEvaluated as number) ||
              prev?.modelsEvaluated ||
              0,
            bestModelName:
              (eventData.bestModelName as string) || prev?.bestModelName,
            bestStatistic:
              (eventData.bestStatistic as number) ?? prev?.bestStatistic,
            statisticName:
              (eventData.statisticName as string) || prev?.statisticName,
            elapsedMs: eventData.elapsedMs as number | undefined,
            avgModelTimeMs: eventData.avgModelTimeMs as number | undefined,
          });
        }
      } else if (msg.type === 'result') {
        const results = (msg.data?.results as SearchResult[]) || [];
        const totalEvaluated = (msg.data?.totalEvaluated as number) || 0;
        setSearchResults(results, totalEvaluated);
        setSearchStatus('complete');
        wsHandleRef.current?.close();
      } else if (msg.type === 'error') {
        setSearchError({
          code: msg.error?.code || 'ERROR',
          message: msg.error?.message || 'Unknown error',
        });
        setSearchStatus('error');
        wsHandleRef.current?.close();
      }
    },
    [searchParams.levels, setSearchProgress, setSearchResults, setSearchStatus, setSearchError]
  );

  const handleOpen = useCallback(() => {
    if (!processedDataSpec || !wsHandleRef.current) return;

    setSearchStatus('searching');
    wsHandleRef.current.send({
      type: 'search_start',
      requestId: requestIdRef.current,
      payload: {
        data: JSON.stringify(processedDataSpec),
        direction: searchParams.direction,
        filter: searchParams.filter,
        width: searchParams.width,
        levels: searchParams.levels,
        sortBy: searchParams.sortBy,
      },
    });
  }, [processedDataSpec, searchParams, setSearchStatus]);

  const handleError = useCallback(() => {
    setSearchError({ code: 'WS_ERROR', message: 'WebSocket connection failed' });
    setSearchStatus('error');
  }, [setSearchError, setSearchStatus]);

  const handleClose = useCallback(() => {
    wsHandleRef.current = null;
  }, []);

  // WebSocket options - only create when actively searching
  const wsOptions = useMemo(() => {
    if (searchStatus !== 'connecting') return null;

    return {
      url: '/api/ws/search',
      onOpen: handleOpen,
      onMessage: handleMessage,
      onError: handleError,
      onClose: handleClose,
      reconnect: false, // Don't auto-reconnect for searches
    };
  }, [searchStatus, handleOpen, handleMessage, handleError, handleClose]);

  const wsHandle = useWebSocket(wsOptions);

  // Store handle ref for use in callbacks
  if (wsOptions) {
    wsHandleRef.current = wsHandle;
  }

  const startSearch = useCallback(() => {
    if (!processedDataSpec) return;

    resetSearch();
    requestIdRef.current = crypto.randomUUID();
    setSearchStatus('connecting');
  }, [processedDataSpec, resetSearch, setSearchStatus]);

  const cancelSearch = useCallback(() => {
    wsHandleRef.current?.close();
    setSearchStatus('idle');
  }, [setSearchStatus]);

  return {
    startSearch,
    cancelSearch,
    resetSearch,
    isSearching: searchStatus === 'connecting' || searchStatus === 'searching',
  };
}
