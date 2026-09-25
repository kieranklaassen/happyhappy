import type { SourceKind } from './items'

export type AnomalyMetric = 'volume' | 'complaint_share' | 'mean_anger' | 'mood_share' | 'category_volume'
export type AnomalySeverity = 'low' | 'medium' | 'high'
export type AnomalyHighlight = 'notable' | 'big' | 'huge'
export type AnomalyPolarity = 'positive' | 'negative' | 'neutral'

export interface AnomalyProps {
  id: number
  product: { id: number; slug: string; name: string }
  source: { id: number; kind: SourceKind; name: string } | null
  metric: AnomalyMetric
  dimension: string | null
  label: string
  granularity: 'hour' | 'day'
  window_start: string
  window_end: string
  expected: number
  actual: number
  share: boolean
  z_score: number
  polarity: AnomalyPolarity
  severity: AnomalySeverity | null
  highlight: AnomalyHighlight | null
  status: 'active' | 'ended'
  historical: boolean
  item_ids: number[]
  first_seen_at: string
  last_seen_at: string
  ended_at: string | null
}
