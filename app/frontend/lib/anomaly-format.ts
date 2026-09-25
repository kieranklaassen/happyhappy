import type { AnomalyProps } from '../types/anomalies'

const HAPPY_MOODS = new Set(['beaming', 'content', 'relieved'])

export function anomalyValue(anomaly: Pick<AnomalyProps, 'share'>, value: number): string {
  if (anomaly.share) return `${Math.round(value * 100)}%`
  return value >= 10 || Number.isInteger(value) ? String(Math.round(value)) : value.toFixed(1)
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

// A surge of happy customers is good news, so it gets sunshine instead of a storm.
export function isGoodNews(anomaly: Pick<AnomalyProps, 'metric' | 'dimension'>): boolean {
  return anomaly.metric === 'mood_share' && HAPPY_MOODS.has(anomaly.dimension ?? '')
}

export function anomalyItemsHref(anomaly: Pick<AnomalyProps, 'id'>): string {
  return `/items?anomaly=${anomaly.id}`
}
