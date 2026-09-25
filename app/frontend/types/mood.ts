import type { Mood } from '../components/mood/moods'
import type { AnomalyProps } from './anomalies'
import type { ItemStatus, Sentiment, SourceKind } from './items'

export type SettledMood = Exclude<Mood, 'pending'>
export type MoodCounts = Record<Mood, number>

export interface MoodCharacter {
  key: string
  seed: string
  item_id: number
  name: string
  handle: string | null
  mood: Mood
  sentiment: Sentiment | null
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
  relieved: number
  grumpy: number
  updated_at: string
}

export interface MoodDashboardProps {
  scene: MoodGroup[]
  today: MoodSummary
  filters: { range: string; product: string | null }
  options: { ranges: string[]; products: { slug: string; name: string }[] }
  anomalies?: Record<string, AnomalyProps[]>
}
