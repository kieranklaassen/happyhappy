import type { ItemStatus, Sentiment, SourceKind } from '../types/items'

export const SENTIMENTS: readonly Sentiment[] = ['complaint', 'praise', 'question', 'neutral']

export function safeLink(value: unknown): string | null {
  return typeof value === 'string' && /^https?:\/\//.test(value) ? value : null
}

export function formatPercent(probability: number | null): string {
  return probability === null ? 'n/a' : `${Math.round(probability * 100)}%`
}

export function formatTime(iso: string): string {
  return new Date(iso).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })
}

export function statusLabel(status: ItemStatus): string {
  switch (status) {
    case 'new':
      return 'New'
    case 'claimed':
      return 'Claimed'
    case 'in_progress':
      return 'In progress'
    case 'handled':
      return 'Handled'
    case 'dismissed':
      return 'Dismissed'
    default: {
      const unhandled: never = status
      return unhandled
    }
  }
}

export function sourceKindLabel(kind: SourceKind): string {
  switch (kind) {
    case 'slack':
      return 'Slack'
    case 'discord':
      return 'Discord'
    case 'intercom':
      return 'Intercom'
    case 'email':
      return 'Email'
    case 'x':
      return 'X'
    case 'custom':
      return 'Custom webhook'
    default: {
      const unhandled: never = kind
      return unhandled
    }
  }
}

export function sentimentLabel(sentiment: Sentiment | null): string {
  return sentiment === null ? 'Unclassified' : sentiment[0].toUpperCase() + sentiment.slice(1)
}

export const SENTIMENT_COLORS: Record<Sentiment, string> = {
  complaint: 'bg-red-500',
  praise: 'bg-emerald-500',
  question: 'bg-sky-500',
  neutral: 'bg-gray-400',
}

export const SENTIMENT_BADGES: Record<Sentiment, string> = {
  complaint: 'bg-red-50 text-red-700 ring-red-200',
  praise: 'bg-emerald-50 text-emerald-700 ring-emerald-200',
  question: 'bg-sky-50 text-sky-700 ring-sky-200',
  neutral: 'bg-gray-50 text-gray-700 ring-gray-200',
}
