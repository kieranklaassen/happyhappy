import { between, pick, seededRandom } from './seed'

export interface Pigment {
  wash: string
  ink: string
}

export const BODY_PIGMENTS: readonly Pigment[] = [
  { wash: '#F6C3A5', ink: '#B9785A' },
  { wash: '#BFE3CF', ink: '#6E9F86' },
  { wash: '#CDBCE8', ink: '#8973AE' },
  { wash: '#F7E3A1', ink: '#B89C4C' },
  { wash: '#B9D4EE', ink: '#6A8DB3' },
  { wash: '#F4B8C5', ink: '#B56E80' },
  { wash: '#CAD8B0', ink: '#869A63' },
  { wash: '#F8CFA0', ink: '#BE8A52' },
  { wash: '#D5CDE6', ink: '#8E83A8' },
  { wash: '#A9DCDB', ink: '#5E9D9B' },
]

export const HAIR_COLORS = ['#8C6A5A', '#4E4448', '#D98C5F', '#E3C27A', '#E59DB6', '#8FAFD8', '#6F8F6A'] as const
export const ACCENT_COLORS = ['#F28C8C', '#8CB8F2', '#F2C46B', '#9ED39A', '#C69BE8', '#F2A36B'] as const

export type Headwear = 'none' | 'sprout' | 'tuft' | 'beanie' | 'bun' | 'bob' | 'bow' | 'cap' | 'curls' | 'party'
export type Accessory = 'none' | 'glasses' | 'freckles' | 'scarf' | 'mustache'

const HEADWEAR: readonly Headwear[] = [
  'none', 'none', 'sprout', 'tuft', 'beanie', 'bun', 'bob', 'bow', 'cap', 'curls', 'party',
]
const ACCESSORIES: readonly Accessory[] = ['none', 'none', 'none', 'glasses', 'freckles', 'scarf', 'mustache']

export interface Traits {
  body: Pigment
  hair: string
  accent: string
  headwear: Headwear
  accessory: Accessory
  headR: number
  headY: number
  bodyHalfWidth: number
  eyeGap: number
  eyeDrop: number
  scale: number
  lean: number
  filterVariant: number
  tempo: number
  phase: number
}

export function traitsFor(seed: string): Traits {
  const random = seededRandom(seed)
  const headR = between(random, 25, 31)
  return {
    body: pick(random, BODY_PIGMENTS),
    hair: pick(random, HAIR_COLORS),
    accent: pick(random, ACCENT_COLORS),
    headwear: pick(random, HEADWEAR),
    accessory: pick(random, ACCESSORIES),
    headR,
    headY: between(random, 50, 58),
    bodyHalfWidth: between(random, 22, 30),
    eyeGap: headR * between(random, 0.34, 0.46),
    eyeDrop: between(random, -3, 3),
    scale: between(random, 0.86, 1.06),
    lean: between(random, -4, 4),
    filterVariant: Math.floor(random() * 3),
    tempo: between(random, 2.6, 4.2),
    phase: between(random, 0, 3),
  }
}
