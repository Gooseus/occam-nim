import { useState, useRef, useCallback } from 'react'

// Types matching the WebSocket protocol
export interface SearchParams {
  data: string
  direction: 'up' | 'down'
  filter: 'loopless' | 'full' | 'disjoint'
  width: number
  levels: number
  sortBy: 'bic' | 'aic' | 'ddf'
}

export interface Progress {
  currentLevel: number
  totalLevels: number
  modelsEvaluated: number
  looplessModels?: number  // Models without loops (fast BP)
  loopModels?: number      // Models with loops (slow IPF)
  bestModelName: string
  bestStatistic: number
  statisticName: string
  // Timing info
  levelTimeMs?: number     // Time for this level in ms
  elapsedMs?: number       // Total elapsed time in ms
  avgModelTimeMs?: number  // Average time per model in ms
}

export interface ResultItem {
  model: string
  h: number
  aic: number
  bic: number
  ddf: number
  hasLoops: boolean
}

export interface SearchResult {
  totalEvaluated: number
  results: ResultItem[]
}

export type SearchStatus = 'idle' | 'connecting' | 'searching' | 'complete' | 'error'

export interface SearchError {
  code: string
  message: string
}

export function useSearch() {
  const [status, setStatus] = useState<SearchStatus>('idle')
  const [progress, setProgress] = useState<Progress | null>(null)
  const [results, setResults] = useState<SearchResult | null>(null)
  const [error, setError] = useState<SearchError | null>(null)
  const wsRef = useRef<WebSocket | null>(null)
  const requestIdRef = useRef<string>('')

  const startSearch = useCallback((params: SearchParams) => {
    // Reset state
    setStatus('connecting')
    setProgress(null)
    setResults(null)
    setError(null)

    // Generate request ID
    requestIdRef.current = crypto.randomUUID()

    // Connect to WebSocket
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const ws = new WebSocket(`${protocol}//${window.location.host}/api/ws/search`)
    wsRef.current = ws

    ws.onopen = () => {
      setStatus('searching')
      // Send search request
      ws.send(JSON.stringify({
        type: 'search_start',
        requestId: requestIdRef.current,
        payload: params
      }))
    }

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data)

        if (msg.requestId !== requestIdRef.current) {
          return // Ignore messages for other requests
        }

        switch (msg.type) {
          case 'progress':
            if (msg.event === 'search_started') {
              setProgress({
                currentLevel: 0,
                totalLevels: msg.data.totalLevels,
                modelsEvaluated: 0,
                bestModelName: '',
                bestStatistic: 0,
                statisticName: msg.data.statisticName
              })
            } else if (msg.event === 'level_complete') {
              setProgress({
                currentLevel: msg.data.currentLevel,
                totalLevels: msg.data.totalLevels,
                modelsEvaluated: msg.data.modelsEvaluated,
                looplessModels: msg.data.looplessModels,
                loopModels: msg.data.loopModels,
                bestModelName: msg.data.bestModelName,
                bestStatistic: msg.data.bestStatistic,
                statisticName: msg.data.statisticName,
                levelTimeMs: msg.data.levelTimeMs,
                elapsedMs: msg.data.elapsedMs,
                avgModelTimeMs: msg.data.avgModelTimeMs
              })
            } else if (msg.event === 'search_complete') {
              setProgress(prev => prev ? {
                ...prev,
                currentLevel: prev.totalLevels,
                modelsEvaluated: msg.data.totalModelsEvaluated,
                bestModelName: msg.data.bestModelName,
                bestStatistic: msg.data.bestStatistic,
                elapsedMs: msg.data.elapsedMs,
                avgModelTimeMs: msg.data.avgModelTimeMs
              } : null)
            }
            break

          case 'result':
            setResults(msg.data)
            setStatus('complete')
            ws.close()
            break

          case 'error':
            setError(msg.error)
            setStatus('error')
            ws.close()
            break
        }
      } catch (e) {
        console.error('Failed to parse WebSocket message:', e)
      }
    }

    ws.onerror = () => {
      setError({ code: 'connection_error', message: 'WebSocket connection failed' })
      setStatus('error')
    }

    ws.onclose = () => {
      wsRef.current = null
    }
  }, [])

  const cancelSearch = useCallback(() => {
    if (wsRef.current && wsRef.current.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({
        type: 'search_cancel',
        requestId: requestIdRef.current
      }))
      wsRef.current.close()
    }
    setStatus('idle')
    wsRef.current = null
  }, [])

  const reset = useCallback(() => {
    if (wsRef.current) {
      wsRef.current.close()
      wsRef.current = null
    }
    setStatus('idle')
    setProgress(null)
    setResults(null)
    setError(null)
  }, [])

  return {
    status,
    progress,
    results,
    error,
    startSearch,
    cancelSearch,
    reset
  }
}
