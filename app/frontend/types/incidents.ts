import type { AnomalyProps } from './anomalies'
import type { SourceKind } from './items'

export type IncidentStatus = 'open' | 'resolved'

export interface IncidentProps {
  id: number
  product: { id: number; slug: string; name: string }
  status: IncidentStatus
  opened_at: string
  last_anomaly_at: string
  resolved_at: string | null
  resolved_by: string | null
  resolution_note: string | null
  items_handled: boolean
  item_ids: number[]
  sources: { id: number; kind: SourceKind; name: string }[]
  slack_posted: boolean
  url: string
  anomalies: AnomalyProps[]
}
