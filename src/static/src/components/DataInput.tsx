import React from 'react'

interface DataInputProps {
  value: string
  onChange: (value: string) => void
  disabled?: boolean
}

// Example data for placeholder
const EXAMPLE_DATA = `{
  "name": "example",
  "variables": [
    {"name": "A", "abbrev": "A", "cardinality": 2},
    {"name": "B", "abbrev": "B", "cardinality": 2},
    {"name": "C", "abbrev": "C", "cardinality": 2}
  ],
  "data": [
    ["0", "0", "0"],
    ["0", "0", "1"],
    ["0", "1", "0"],
    ["0", "1", "1"],
    ["1", "0", "0"],
    ["1", "0", "1"],
    ["1", "1", "0"],
    ["1", "1", "1"]
  ],
  "counts": [10, 20, 15, 25, 30, 10, 20, 35]
}`

export function DataInput({ value, onChange, disabled }: DataInputProps) {
  const handleLoadExample = () => {
    onChange(EXAMPLE_DATA)
  }

  return (
    <div style={styles.container}>
      <div style={styles.header}>
        <label style={styles.label}>Data (JSON)</label>
        <button
          type="button"
          onClick={handleLoadExample}
          disabled={disabled}
          style={styles.exampleBtn}
        >
          Load Example
        </button>
      </div>
      <textarea
        value={value}
        onChange={(e) => onChange(e.target.value)}
        disabled={disabled}
        placeholder="Paste JSON data here..."
        style={styles.textarea}
        rows={12}
      />
    </div>
  )
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    marginBottom: '1rem',
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '0.5rem',
  },
  label: {
    fontWeight: 600,
    fontSize: '0.875rem',
  },
  exampleBtn: {
    padding: '0.25rem 0.5rem',
    fontSize: '0.75rem',
    background: '#e0e0e0',
    border: 'none',
    borderRadius: '4px',
    cursor: 'pointer',
  },
  textarea: {
    width: '100%',
    padding: '0.75rem',
    fontFamily: 'monospace',
    fontSize: '0.875rem',
    border: '1px solid #ccc',
    borderRadius: '4px',
    resize: 'vertical',
    minHeight: '200px',
  },
}
