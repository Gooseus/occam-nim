import React, { useRef, useCallback } from 'react';
import { useAppStore } from '../../store/useAppStore';
import { SearchParams as SearchParamsForm } from '../SearchParams';
import { ProgressBar } from '../ProgressBar';
import { ResultsTable } from '../ResultsTable';
import { SearchEstimate } from '../SearchEstimate';

export function SearchTab() {
  const processedDataSpec = useAppStore((s) => s.processedDataSpec);
  const searchStatus = useAppStore((s) => s.searchStatus);
  const searchProgress = useAppStore((s) => s.searchProgress);
  const searchResults = useAppStore((s) => s.searchResults);
  const searchTotalEvaluated = useAppStore((s) => s.searchTotalEvaluated);
  const searchError = useAppStore((s) => s.searchError);
  const searchParams = useAppStore((s) => s.searchParams);
  const setSearchParams = useAppStore((s) => s.setSearchParams);
  const setSearchStatus = useAppStore((s) => s.setSearchStatus);
  const setSearchProgress = useAppStore((s) => s.setSearchProgress);
  const setSearchResults = useAppStore((s) => s.setSearchResults);
  const setSearchError = useAppStore((s) => s.setSearchError);
  const resetSearch = useAppStore((s) => s.resetSearch);
  const setActiveTab = useAppStore((s) => s.setActiveTab);

  const wsRef = useRef<WebSocket | null>(null);
  const requestIdRef = useRef<string | null>(null);

  const isSearching = searchStatus === 'connecting' || searchStatus === 'searching';

  const startSearch = useCallback(() => {
    if (!processedDataSpec) return;

    resetSearch();
    setSearchStatus('connecting');

    const ws = new WebSocket(`ws://${window.location.host}/api/ws/search`);
    wsRef.current = ws;
    requestIdRef.current = crypto.randomUUID();

    ws.onopen = () => {
      setSearchStatus('searching');
      ws.send(
        JSON.stringify({
          type: 'search_start',
          requestId: requestIdRef.current,
          payload: {
            data: JSON.stringify(processedDataSpec),
            direction: searchParams.direction,
            filter: searchParams.filter,
            width: searchParams.width,
            levels: searchParams.levels,
            sortBy: searchParams.sortBy,
            referenceModel: searchParams.referenceModel,
          },
        })
      );
    };

    ws.onmessage = (event) => {
      const msg = JSON.parse(event.data);
      if (msg.requestId !== requestIdRef.current) return;

      if (msg.type === 'progress') {
        const event = msg.event as string;
        const data = msg.data || {};

        if (event === 'search_started') {
          setSearchProgress({
            currentLevel: 0,
            totalLevels: data.totalLevels || searchParams.levels,
            modelsEvaluated: 0,
            bestModelName: undefined,
            bestStatistic: undefined,
            statisticName: data.statisticName,
          });
        } else if (event === 'level_complete') {
          setSearchProgress({
            currentLevel: data.currentLevel || 0,
            totalLevels: data.totalLevels || searchParams.levels,
            modelsEvaluated: data.modelsEvaluated || data.totalModelsEvaluated || 0,
            bestModelName: data.bestModelName,
            bestStatistic: data.bestStatistic,
            statisticName: data.statisticName,
          });
        } else if (event === 'search_complete') {
          // For search_complete, set currentLevel = totalLevels to show completion
          // Use getState() to access previous progress since setSearchProgress doesn't support callbacks
          const prev = useAppStore.getState().searchProgress;
          setSearchProgress({
            currentLevel: prev?.totalLevels || data.totalLevels || searchParams.levels,
            totalLevels: prev?.totalLevels || data.totalLevels || searchParams.levels,
            modelsEvaluated: data.totalModelsEvaluated || prev?.modelsEvaluated || 0,
            bestModelName: data.bestModelName || prev?.bestModelName,
            bestStatistic: data.bestStatistic ?? prev?.bestStatistic,
            statisticName: data.statisticName || prev?.statisticName,
          });
        }
      } else if (msg.type === 'result') {
        // Results are in msg.data.results, not msg.results
        setSearchResults(msg.data?.results || [], msg.data?.totalEvaluated || 0);
        setSearchStatus('complete');
        ws.close();
      } else if (msg.type === 'error') {
        // Error details are in msg.error, not msg directly
        setSearchError({
          code: msg.error?.code || 'ERROR',
          message: msg.error?.message || 'Unknown error'
        });
        setSearchStatus('error');
        ws.close();
      }
    };

    ws.onerror = () => {
      setSearchError({ code: 'WS_ERROR', message: 'WebSocket connection failed' });
      setSearchStatus('error');
    };

    ws.onclose = () => {
      wsRef.current = null;
    };
  }, [processedDataSpec, searchParams, resetSearch, setSearchStatus, setSearchProgress, setSearchResults, setSearchError]);

  const cancelSearch = useCallback(() => {
    if (wsRef.current) {
      wsRef.current.close();
      wsRef.current = null;
    }
    setSearchStatus('idle');
  }, [setSearchStatus]);

  if (!processedDataSpec) {
    return (
      <div style={styles.container}>
        <div style={styles.noData}>
          <p>No data loaded. Please upload a CSV file first.</p>
          <button onClick={() => setActiveTab('data')} style={styles.linkBtn}>
            Go to Data tab
          </button>
        </div>
      </div>
    );
  }

  return (
    <div style={styles.container}>
      <div style={styles.dataSummary}>
        <strong>Data:</strong> {processedDataSpec.variables.length} variables,{' '}
        {processedDataSpec.data.length} states,{' '}
        {processedDataSpec.counts.reduce((a, b) => a + b, 0)} observations
      </div>

      <SearchParamsForm
        params={searchParams}
        onChange={setSearchParams}
        disabled={isSearching}
      />

      {searchStatus === 'idle' && (
        <SearchEstimate
          data={processedDataSpec}
          direction={searchParams.direction}
          filter={searchParams.filter}
          width={searchParams.width}
          levels={searchParams.levels}
        />
      )}

      <div style={styles.actions}>
        <button
          onClick={startSearch}
          disabled={isSearching}
          style={{
            ...styles.button,
            ...styles.primaryButton,
            opacity: isSearching ? 0.6 : 1,
          }}
        >
          {isSearching ? 'Searching...' : 'Start Search'}
        </button>
        {isSearching && (
          <button onClick={cancelSearch} style={styles.button}>
            Cancel
          </button>
        )}
        {searchStatus === 'complete' && (
          <button onClick={resetSearch} style={styles.button}>
            Reset
          </button>
        )}
      </div>

      <ProgressBar status={searchStatus} progress={searchProgress} />

      {searchError && (
        <div style={styles.error}>
          <strong>Error:</strong> {searchError.message} ({searchError.code})
        </div>
      )}

      {searchResults.length > 0 && (
        <ResultsTable
          results={{
            results: searchResults,
            totalEvaluated: searchTotalEvaluated,
          }}
        />
      )}
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    padding: '1rem',
  },
  noData: {
    textAlign: 'center',
    padding: '2rem',
    color: '#666',
  },
  linkBtn: {
    marginTop: '1rem',
    padding: '0.5rem 1rem',
    fontSize: '0.875rem',
    background: '#3498db',
    border: 'none',
    borderRadius: '4px',
    color: 'white',
    cursor: 'pointer',
  },
  dataSummary: {
    padding: '0.75rem',
    marginBottom: '1rem',
    background: '#e8f4f8',
    borderRadius: '4px',
    fontSize: '0.875rem',
  },
  actions: {
    display: 'flex',
    gap: '0.75rem',
    marginBottom: '1rem',
  },
  button: {
    padding: '0.75rem 1.5rem',
    fontSize: '0.875rem',
    fontWeight: 600,
    border: '1px solid #ccc',
    borderRadius: '4px',
    background: 'white',
    cursor: 'pointer',
  },
  primaryButton: {
    background: '#3498db',
    borderColor: '#3498db',
    color: 'white',
  },
  error: {
    padding: '1rem',
    marginBottom: '1rem',
    background: '#fde8e8',
    border: '1px solid #e74c3c',
    borderRadius: '4px',
    color: '#c0392b',
    fontSize: '0.875rem',
  },
};
