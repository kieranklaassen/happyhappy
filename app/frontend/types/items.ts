export type Sentiment = 'complaint' | 'praise' | 'question' | 'neutral'
export type ItemStatus = 'new' | 'claimed' | 'in_progress' | 'handled' | 'dismissed'
export type SourceKind = 'slack' | 'discord' | 'intercom' | 'email' | 'x'
export type EventKind =
  | 'arrived'
  | 'classified'
  | 'classification_failed'
  | 'corrected'
  | 'claimed'
  | 'released'
  | 'reassigned'
  | 'reported'
  | 'status_changed'
  | 'overdue'
  | 'escalated'

export interface ProductOption {
  id: number
  name: string
  slug: string
  retired: boolean
}

export interface CategoryOption {
  id: number
  name: string
  retired: boolean
}

export interface SourceOption {
  id: number
  name: string
  kind: SourceKind
}

export interface ItemRowData {
  id: number
  excerpt: string
  author: string
  source: SourceOption
  product: ProductOption | null
  category: CategoryOption | null
  sentiment: Sentiment | null
  status: ItemStatus
  relevant: boolean
  needs_review: boolean
  overdue: boolean
  claimed_by: string | null
  anger_probability: number | null
  last_message_at: string
}

export interface Label<T> {
  value: T
  probability: number | null
  human_set: boolean
}

export interface ItemDetail {
  id: number
  author: string
  author_name: string | null
  author_email: string | null
  permalink: string | null
  source: SourceOption
  status: ItemStatus
  needs_review: boolean
  overdue: boolean
  claimed_by: string | null
  claimed_at: string | null
  last_reported_at: string | null
  last_message_at: string
  anger_probability: number | null
  labels: {
    product: Label<ProductOption | null>
    category: Label<CategoryOption | null>
    sentiment: Label<Sentiment | null>
    relevant: Label<boolean>
  }
}

export interface MessageData {
  id: number
  body: string
  occurred_at: string
  anger_probability: number | null
  classified: boolean
}

export interface TimelineEvent {
  id: number
  kind: EventKind
  actor: { type: 'User' | 'Agent' | null; name: string }
  data: Record<string, unknown>
  created_at: string
}

export interface FlashProps {
  flash: { notice?: string; alert?: string }
  [key: string]: unknown
}
