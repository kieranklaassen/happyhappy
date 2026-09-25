import type { ItemRowData } from './items'

export type ChipKind = 'filter' | 'boost' | 'time'
export type EncodingStatus = 'cached' | 'pending' | 'none'
export type InviteReason = 'weak' | 'empty' | 'encoding_pending'
export type SmartBucket = 'strong' | 'possible' | 'unlikely'
export type SmartStatus = 'pending' | 'running' | 'complete' | 'paused' | 'cancelled' | 'expired'

export const SMART_BUCKETS: SmartBucket[] = ['strong', 'possible', 'unlikely']

// Label keys come from truffler ("anger", or "product:cora" for a choice
// option); key "time" is the query's time phrase.
export interface SearchChip {
  key: string
  label: string
  kind: ChipKind
  name: string
}

export interface SearchProps {
  query: string
  chips: SearchChip[]
  removed: string[]
  invite_row: { query: string; reason: InviteReason } | null
  encoding_status: EncodingStatus
  explicit_action: string | null
  run_id: string | null
}

export type SmartRow = ItemRowData & { score: number }

export interface SmartProps {
  run_id: string
  status: SmartStatus
  reserved_slots: number
  paused: boolean
  pending: Record<SmartBucket, boolean>
  collapsed: SmartBucket[]
  no_strong_matches: boolean
  buckets: Record<SmartBucket, SmartRow[]>
}
