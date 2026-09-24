import type { Mood } from '../components/mood/moods'

export type SettledMood = Exclude<Mood, 'pending'>
export type SourceKind = 'slack' | 'discord' | 'intercom' | 'email' | 'x'
export type ItemStatus = 'new' | 'claimed' | 'in_progress' | 'handled' | 'dismissed'
export type MoodCounts = Record<Mood, number>

export interface MoodCharacter {
  key: string
  seed: string
  item_id: number
  name: string
  handle: string | null
  mood: Mood
  sentiment: string | null
  anger: number | null
  source_kind: SourceKind
  status: ItemStatus
  threads: number
  excerpt: string
  last_message_at: string
  mended: boolean
}

export interface MoodGroup {
  product: { slug: string; name: string; retired: boolean } | null
  mood: SettledMood | null
  counts: MoodCounts
  overflow: number
  characters: MoodCharacter[]
}

export interface MoodSummary {
  range: string
  mood: SettledMood | null
  people: number
  counts: MoodCounts
  smiling: number
  grumpy: number
  updated_at: string
}

export interface MoodDashboardProps {
  scene: MoodGroup[]
  today: MoodSummary
  filters: { range: string; product: string | null }
  options: { ranges: string[]; products: { slug: string; name: string }[] }
}
