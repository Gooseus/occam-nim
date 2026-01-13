/**
 * Design tokens for consistent styling across the application.
 * Extracted from existing component styles to establish a single source of truth.
 */

export const colors = {
  // Primary palette
  primary: '#3498db',
  primaryDark: '#2980b9',

  // Semantic colors
  success: '#27ae60',
  warning: '#f39c12',
  error: '#e74c3c',
  errorDark: '#c0392b',
  errorBg: '#fde8e8',

  // Neutral palette
  text: '#333',
  textMuted: '#666',
  textLight: '#999',

  // Backgrounds
  bgPage: '#f5f5f5',
  bgCard: '#ffffff',
  bgMuted: '#f8f9fa',
  bgHover: '#fafafa',
  bgInfo: '#e8f4f8',

  // Borders
  border: '#ccc',
  borderMedium: '#ddd',
  borderLight: '#eee',

  // Status indicators (for loops/model types)
  loopYes: '#e74c3c',
  loopNo: '#27ae60',
} as const;

export const spacing = {
  xs: '0.25rem',   // 4px
  sm: '0.5rem',    // 8px
  md: '0.75rem',   // 12px
  lg: '1rem',      // 16px
  xl: '1.5rem',    // 24px
  xxl: '2rem',     // 32px
} as const;

export const fontSize = {
  xs: '0.7rem',    // 11.2px
  sm: '0.75rem',   // 12px
  base: '0.8rem',  // 12.8px
  md: '0.875rem',  // 14px
  lg: '0.9rem',    // 14.4px
  xl: '1rem',      // 16px
  xxl: '1.1rem',   // 17.6px
} as const;

export const fontWeight = {
  normal: 400,
  medium: 500,
  semibold: 600,
  bold: 700,
} as const;

export const borderRadius = {
  sm: '3px',
  md: '4px',
  lg: '8px',
} as const;

export const shadows = {
  sm: '0 1px 3px rgba(0,0,0,0.1)',
  md: '0 2px 4px rgba(0,0,0,0.1)',
} as const;

/**
 * Common style patterns for React.CSSProperties.
 * These can be spread into component styles.
 */
export const commonStyles = {
  // Buttons
  buttonBase: {
    padding: `${spacing.md} ${spacing.xl}`,
    fontSize: fontSize.md,
    fontWeight: fontWeight.semibold,
    border: `1px solid ${colors.border}`,
    borderRadius: borderRadius.md,
    background: colors.bgCard,
    cursor: 'pointer',
  } as React.CSSProperties,

  buttonPrimary: {
    background: colors.primary,
    borderColor: colors.primary,
    color: 'white',
  } as React.CSSProperties,

  buttonSmall: {
    padding: `${spacing.xs} ${spacing.sm}`,
    fontSize: fontSize.sm,
  } as React.CSSProperties,

  // Link-style button (no border, primary bg)
  linkButton: {
    padding: `${spacing.sm} ${spacing.lg}`,
    fontSize: fontSize.md,
    background: colors.primary,
    border: 'none',
    borderRadius: borderRadius.md,
    color: 'white',
    cursor: 'pointer',
  } as React.CSSProperties,

  // Error display
  errorBox: {
    padding: spacing.lg,
    marginBottom: spacing.lg,
    background: colors.errorBg,
    border: `1px solid ${colors.error}`,
    borderRadius: borderRadius.md,
    color: colors.errorDark,
    fontSize: fontSize.md,
  } as React.CSSProperties,

  // Tables
  tableBase: {
    width: '100%',
    borderCollapse: 'collapse' as const,
    fontSize: fontSize.base,
  } as React.CSSProperties,

  th: {
    textAlign: 'left' as const,
    padding: spacing.sm,
    borderBottom: `2px solid ${colors.borderMedium}`,
    fontWeight: fontWeight.semibold,
    color: colors.textMuted,
  } as React.CSSProperties,

  td: {
    padding: spacing.sm,
    borderBottom: `1px solid ${colors.borderLight}`,
  } as React.CSSProperties,

  tdModel: {
    padding: spacing.sm,
    borderBottom: `1px solid ${colors.borderLight}`,
    fontFamily: 'monospace',
    fontWeight: fontWeight.medium,
  } as React.CSSProperties,

  altRow: {
    background: colors.bgHover,
  } as React.CSSProperties,

  // Section containers
  section: {
    marginBottom: spacing.xl,
  } as React.CSSProperties,

  sectionHeading: {
    fontSize: fontSize.lg,
    fontWeight: fontWeight.semibold,
    marginBottom: spacing.md,
  } as React.CSSProperties,

  // Input fields
  input: {
    padding: spacing.md,
    fontSize: fontSize.lg,
    fontFamily: 'monospace',
    border: `1px solid ${colors.border}`,
    borderRadius: borderRadius.md,
  } as React.CSSProperties,

  // Container padding
  container: {
    padding: spacing.lg,
  } as React.CSSProperties,

  // Empty state
  emptyState: {
    textAlign: 'center' as const,
    padding: spacing.xxl,
    color: colors.textMuted,
  } as React.CSSProperties,

  // Loops indicator styles
  loopsYes: {
    color: colors.loopYes,
  } as React.CSSProperties,

  loopsNo: {
    color: colors.loopNo,
  } as React.CSSProperties,
} as const;
