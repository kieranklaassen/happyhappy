import type { Mood } from './moods'
import type { SourceKind } from '../../types/mood'

export const MOOD_COLORS: Record<Mood, string> = {
  beaming: '#F5C862',
  content: '#9FD6AE',
  meh: '#CFC8DA',
  grumpy: '#F2A98A',
  furious: '#E86A6A',
  pending: '#E8E2D6',
}

export function sourceLabel(kind: SourceKind): string {
  switch (kind) {
    case 'slack':
      return 'Slack'
    case 'discord':
      return 'Discord'
    case 'intercom':
      return 'Intercom'
    case 'email':
      return 'email'
    case 'x':
      return 'X'
    default: {
      const unhandled: never = kind
      return unhandled
    }
  }
}

export function timeAgo(iso: string, now: Date = new Date()): string {
  const minutes = Math.max(0, Math.round((now.getTime() - new Date(iso).getTime()) / 60_000))
  if (minutes < 1) return 'just now'
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.round(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  return `${Math.round(hours / 24)}d ago`
}

export function plural(count: number, one: string, many = `${one}s`): string {
  return `${count} ${count === 1 ? one : many}`
}
