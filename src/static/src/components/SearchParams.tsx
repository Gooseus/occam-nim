import React from 'react';
import type { SearchParams as SearchParamsType } from '../types/dataSpec';

interface SearchParamsProps {
  params: SearchParamsType;
  onChange: (params: SearchParamsType) => void;
  disabled?: boolean;
}

export function SearchParams({ params, onChange, disabled }: SearchParamsProps) {
  const updateParam = <K extends keyof SearchParamsType>(
    key: K,
    value: SearchParamsType[K]
  ) => {
    onChange({ ...params, [key]: value });
  };

  return (
    <div style={styles.container}>
      <div style={styles.row}>
        {/* Direction */}
        <div style={styles.field}>
          <label style={styles.label}>Direction</label>
          <div style={styles.radioGroup}>
            <label style={styles.radioLabel}>
              <input
                type="radio"
                name="direction"
                value="up"
                checked={params.direction === 'up'}
                onChange={() => updateParam('direction', 'up')}
                disabled={disabled}
              />
              Up (bottom-up)
            </label>
            <label style={styles.radioLabel}>
              <input
                type="radio"
                name="direction"
                value="down"
                checked={params.direction === 'down'}
                onChange={() => updateParam('direction', 'down')}
                disabled={disabled}
              />
              Down (top-down)
            </label>
          </div>
        </div>

        {/* Filter */}
        <div style={styles.field}>
          <label style={styles.label}>Filter</label>
          <select
            value={params.filter}
            onChange={(e) => updateParam('filter', e.target.value as SearchParamsType['filter'])}
            disabled={disabled}
            style={styles.select}
          >
            <option value="loopless">Loopless</option>
            <option value="full">Full</option>
            <option value="disjoint">Disjoint</option>
          </select>
        </div>

        {/* Sort By */}
        <div style={styles.field}>
          <label style={styles.label}>Sort By</label>
          <select
            value={params.sortBy}
            onChange={(e) => updateParam('sortBy', e.target.value as SearchParamsType['sortBy'])}
            disabled={disabled}
            style={styles.select}
          >
            <option value="bic">BIC</option>
            <option value="aic">AIC</option>
            <option value="ddf">DDF</option>
          </select>
        </div>
      </div>

      <div style={styles.row}>
        {/* Width */}
        <div style={styles.field}>
          <label style={styles.label}>Width</label>
          <input
            type="number"
            value={params.width}
            onChange={(e) => updateParam('width', parseInt(e.target.value) || 1)}
            disabled={disabled}
            min={1}
            max={20}
            style={styles.input}
          />
        </div>

        {/* Levels */}
        <div style={styles.field}>
          <label style={styles.label}>Levels</label>
          <input
            type="number"
            value={params.levels}
            onChange={(e) => updateParam('levels', parseInt(e.target.value) || 1)}
            disabled={disabled}
            min={1}
            max={20}
            style={styles.input}
          />
        </div>
      </div>

      {/* Reference Model */}
      <div style={styles.row}>
        <div style={{ ...styles.field, flex: '1 1 100%' }}>
          <label style={styles.label}>
            Reference Model
            <span style={styles.optional}>(optional)</span>
          </label>
          <input
            type="text"
            value={params.referenceModel}
            onChange={(e) => updateParam('referenceModel', e.target.value)}
            disabled={disabled}
            placeholder="e.g., AB:BC or leave empty for default"
            style={styles.input}
          />
          <div style={styles.hint}>
            Custom starting point for search. Leave empty to use default
            ({params.direction === 'up' ? 'independence model' : 'saturated model'}).
            Direction still applies: "{params.direction}" will {params.direction === 'up' ? 'add' : 'remove'} relations.
          </div>
        </div>
      </div>
    </div>
  )
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    marginBottom: '1rem',
  },
  row: {
    display: 'flex',
    gap: '1rem',
    marginBottom: '0.75rem',
    flexWrap: 'wrap',
  },
  field: {
    flex: '1 1 150px',
    minWidth: '120px',
  },
  label: {
    display: 'block',
    fontWeight: 600,
    fontSize: '0.875rem',
    marginBottom: '0.25rem',
  },
  select: {
    width: '100%',
    padding: '0.5rem',
    fontSize: '0.875rem',
    border: '1px solid #ccc',
    borderRadius: '4px',
    background: 'white',
  },
  input: {
    width: '100%',
    padding: '0.5rem',
    fontSize: '0.875rem',
    border: '1px solid #ccc',
    borderRadius: '4px',
  },
  radioGroup: {
    display: 'flex',
    gap: '1rem',
  },
  radioLabel: {
    display: 'flex',
    alignItems: 'center',
    gap: '0.25rem',
    fontSize: '0.875rem',
    cursor: 'pointer',
  },
  optional: {
    fontWeight: 400,
    fontSize: '0.75rem',
    color: '#666',
    marginLeft: '0.5rem',
  },
  hint: {
    fontSize: '0.75rem',
    color: '#666',
    marginTop: '0.25rem',
    lineHeight: 1.4,
  },
}
