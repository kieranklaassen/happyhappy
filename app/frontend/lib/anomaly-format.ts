import type { AnomalyHighlight, AnomalyProps, AnomalySeverity } from '../types/anomalies'

export function anomalyValue(anomaly: Pick<AnomalyProps, 'share'>, value: number): string {
  if (anomaly.share) return `${Math.round(value * 100)}%`
  return value >= 10 || Number.isInteger(value) ? String(Math.round(value)) : value.toFixed(1)
}

// Expected counts are averages; say them the way a person would ("usually under 1", not "usually 0.4").
export function anomalyExpected(anomaly: Pick<AnomalyProps, 'share'>, value: number): string {
  if (anomaly.share) return anomalyValue(anomaly, value)
  if (value < 0.05) return 'none'
  if (value < 1) return 'under 1'
  return String(Math.round(value))
}

export function anomalyWindow(anomaly: Pick<AnomalyProps, 'granularity'>): string {
  switch (anomaly.granularity) {
    case 'hour':
      return 'in the last hour'
    case 'day':
      return 'in a day'
    default: {
      const unhandled: never = anomaly.granularity
      return unhandled
    }
  }
}

const MORE: Record<AnomalyHighlight, string> = {
  notable: 'More',
  big: 'Way more',
  huge: 'So much more',
}

const SEVERITY: Record<AnomalySeverity, string> = {
  low: 'Low severity',
  medium: 'Medium severity',
  high: 'High severity',
}

// A short tag for lists: good news never reads as a warning, and severity is for bad news only.
export function anomalyTag(anomaly: Pick<AnomalyProps, 'polarity' | 'severity'>): string {
  switch (anomaly.polarity) {
    case 'positive':
      return 'Good news'
    case 'negative':
      return SEVERITY[anomaly.severity ?? 'low']
    case 'neutral':
      return 'Busier than usual'
    default: {
      const unhandled: never = anomaly.polarity
      return unhandled
    }
  }
}

// "Way more praise messages for Thesis: 12 in a day, usually 2." or "Bug messages: 9 in the last hour, usually under 1."
export function anomalySummary(anomaly: AnomalyProps, { withProduct = true }: { withProduct?: boolean } = {}): string {
  const where = [withProduct ? ` for ${anomaly.product.name}` : '', anomaly.source ? ` on ${anomaly.source.name}` : ''].join('')
  const subject =
    anomaly.polarity === 'positive' && anomaly.highlight
      ? `${MORE[anomaly.highlight]} ${anomaly.metric === 'volume' ? 'messages' : anomaly.label.toLowerCase()}`
      : anomaly.label
  return `${subject}${where}: ${anomalyValue(anomaly, anomaly.actual)} ${anomalyWindow(anomaly)}, usually ${anomalyExpected(anomaly, anomaly.expected)}.`
}

export function anomalyItemsHref(anomaly: Pick<AnomalyProps, 'id'>): string {
  return `/items?anomaly=${anomaly.id}`
}
