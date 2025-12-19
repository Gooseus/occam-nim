import React from 'react';
import { useAppStore } from './store/useAppStore';
import { TabNavigation } from './components/tabs/TabNavigation';
import { DataTab } from './components/data/DataTab';
import { SearchTab } from './components/tabs/SearchTab';
import { FitTab } from './components/tabs/FitTab';
import { ResultsTab } from './components/tabs/ResultsTab';

function App() {
  const activeTab = useAppStore((s) => s.activeTab);

  return (
    <div style={styles.app}>
      <header style={styles.header}>
        <h1 style={styles.title}>OCCAM</h1>
        <p style={styles.subtitle}>Reconstructability Analysis Tool</p>
      </header>

      <main style={styles.main}>
        <TabNavigation />
        <div style={styles.tabContent}>
          {activeTab === 'data' && <DataTab />}
          {activeTab === 'search' && <SearchTab />}
          {activeTab === 'fit' && <FitTab />}
          {activeTab === 'results' && <ResultsTab />}
        </div>
      </main>

      <footer style={styles.footer}>
        <p>OCCAM Web - Built with Prologue + React</p>
      </footer>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  app: {
    maxWidth: '1000px',
    margin: '0 auto',
    padding: '1rem',
    minHeight: '100vh',
    display: 'flex',
    flexDirection: 'column',
  },
  header: {
    textAlign: 'center',
    marginBottom: '1rem',
    paddingBottom: '0.75rem',
    borderBottom: '1px solid #ddd',
  },
  title: {
    fontSize: '1.5rem',
    fontWeight: 700,
    color: '#2c3e50',
    margin: 0,
    letterSpacing: '0.1em',
  },
  subtitle: {
    fontSize: '0.8rem',
    color: '#666',
    margin: '0.25rem 0 0 0',
  },
  main: {
    flex: 1,
    background: 'white',
    borderRadius: '8px',
    boxShadow: '0 1px 3px rgba(0,0,0,0.1)',
    overflow: 'hidden',
  },
  tabContent: {
    minHeight: '400px',
  },
  footer: {
    textAlign: 'center',
    padding: '0.75rem 0',
    marginTop: '1rem',
    color: '#999',
    fontSize: '0.7rem',
  },
};

export default App;
