import React, { useState } from 'react'
import { useSearch, type SearchParams } from './hooks/useSearch'
import { DataInput } from './components/DataInput'
import { SearchParams as SearchParamsForm } from './components/SearchParams'
import { ProgressBar } from './components/ProgressBar'
import { ResultsTable } from './components/ResultsTable'

const DEFAULT_PARAMS: Omit<SearchParams, 'data'> = {
  direction: 'up',
  filter: 'loopless',
  width: 3,
  levels: 7,
  sortBy: 'bic',
}

function App() {
  const [data, setData] = useState('')
  const [params, setParams] = useState(DEFAULT_PARAMS)

  const { status, progress, results, error, startSearch, reset } = useSearch()

  const isSearching = status === 'connecting' || status === 'searching'

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!data.trim()) {
      alert('Please enter data')
      return
    }
    startSearch({ ...params, data })
  }

  const handleReset = () => {
    reset()
    setData('')
    setParams(DEFAULT_PARAMS)
  }

  return (
    <div style={styles.app}>
      <header style={styles.header}>
        <h1 style={styles.title}>OCCAM Model Search</h1>
        <p style={styles.subtitle}>Reconstructability Analysis Tool</p>
      </header>

      <main style={styles.main}>
        <form onSubmit={handleSubmit}>
          <DataInput
            value={data}
            onChange={setData}
            disabled={isSearching}
          />

          <SearchParamsForm
            params={params}
            onChange={setParams}
            disabled={isSearching}
          />

          <div style={styles.actions}>
            <button
              type="submit"
              disabled={isSearching || !data.trim()}
              style={{
                ...styles.button,
                ...styles.primaryButton,
                opacity: isSearching || !data.trim() ? 0.6 : 1,
              }}
            >
              {isSearching ? 'Searching...' : 'Start Search'}
            </button>

            {(status === 'complete' || status === 'error') && (
              <button
                type="button"
                onClick={handleReset}
                style={styles.button}
              >
                Reset
              </button>
            )}
          </div>
        </form>

        <ProgressBar status={status} progress={progress} />

        {error && (
          <div style={styles.error}>
            <strong>Error:</strong> {error.message} ({error.code})
          </div>
        )}

        <ResultsTable results={results} />
      </main>

      <footer style={styles.footer}>
        <p>OCCAM Web Server - Built with Prologue + React</p>
      </footer>
    </div>
  )
}

const styles: Record<string, React.CSSProperties> = {
  app: {
    maxWidth: '900px',
    margin: '0 auto',
    padding: '1rem',
    minHeight: '100vh',
    display: 'flex',
    flexDirection: 'column',
  },
  header: {
    textAlign: 'center',
    marginBottom: '1.5rem',
    paddingBottom: '1rem',
    borderBottom: '1px solid #ddd',
  },
  title: {
    fontSize: '1.75rem',
    fontWeight: 700,
    color: '#2c3e50',
    margin: 0,
  },
  subtitle: {
    fontSize: '0.875rem',
    color: '#666',
    margin: '0.25rem 0 0 0',
  },
  main: {
    flex: 1,
    background: 'white',
    padding: '1.5rem',
    borderRadius: '8px',
    boxShadow: '0 1px 3px rgba(0,0,0,0.1)',
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
    transition: 'background 0.2s',
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
  footer: {
    textAlign: 'center',
    padding: '1rem 0',
    marginTop: '1rem',
    color: '#999',
    fontSize: '0.75rem',
  },
}

export default App
