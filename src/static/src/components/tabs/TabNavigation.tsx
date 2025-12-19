import React from 'react';
import { useAppStore, type TabId } from '../../store/useAppStore';

const TABS: Array<{ id: TabId; label: string }> = [
  { id: 'data', label: 'Data' },
  { id: 'search', label: 'Search' },
  { id: 'fit', label: 'Fit' },
  { id: 'results', label: 'Results' },
];

export function TabNavigation() {
  const activeTab = useAppStore((s) => s.activeTab);
  const setActiveTab = useAppStore((s) => s.setActiveTab);
  const processedDataSpec = useAppStore((s) => s.processedDataSpec);
  const searchResults = useAppStore((s) => s.searchResults);
  const fitHistory = useAppStore((s) => s.fitHistory);

  const getBadge = (tabId: TabId): string | null => {
    switch (tabId) {
      case 'data':
        return processedDataSpec ? processedDataSpec.variables.length.toString() : null;
      case 'search':
        return null;
      case 'results':
        return searchResults.length > 0 ? searchResults.length.toString() : null;
      case 'fit':
        return fitHistory.length > 0 ? fitHistory.length.toString() : null;
      default:
        return null;
    }
  };

  return (
    <nav style={styles.nav}>
      {TABS.map((tab) => {
        const isActive = activeTab === tab.id;
        const badge = getBadge(tab.id);
        return (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            style={{
              ...styles.tab,
              ...(isActive ? styles.activeTab : {}),
            }}
          >
            {tab.label}
            {badge && <span style={styles.badge}>{badge}</span>}
          </button>
        );
      })}
    </nav>
  );
}

const styles: Record<string, React.CSSProperties> = {
  nav: {
    display: 'flex',
    gap: '0.25rem',
    padding: '0.5rem',
    background: '#f0f0f0',
    borderRadius: '8px 8px 0 0',
  },
  tab: {
    padding: '0.5rem 1rem',
    fontSize: '0.875rem',
    fontWeight: 500,
    border: 'none',
    borderRadius: '4px 4px 0 0',
    background: 'transparent',
    color: '#666',
    cursor: 'pointer',
    transition: 'all 0.2s',
    display: 'flex',
    alignItems: 'center',
    gap: '0.5rem',
  },
  activeTab: {
    background: 'white',
    color: '#2c3e50',
    fontWeight: 600,
  },
  badge: {
    background: '#3498db',
    color: 'white',
    fontSize: '0.7rem',
    padding: '0.125rem 0.375rem',
    borderRadius: '10px',
    minWidth: '1.25rem',
    textAlign: 'center',
  },
};
