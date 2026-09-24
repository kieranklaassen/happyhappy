export function hashSeed(key: string): number {
  let hash = 0x811c9dc5
  for (let i = 0; i < key.length; i++) {
    hash ^= key.charCodeAt(i)
    hash = Math.imul(hash, 0x01000193)
  }
  return hash >>> 0
}

export type Random = () => number

export function seededRandom(key: string): Random {
  let state = hashSeed(key) || 1
  return () => {
    state = (state + 0x6d2b79f5) | 0
    let t = Math.imul(state ^ (state >>> 15), 1 | state)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

export function pick<T>(random: Random, options: readonly T[]): T {
  return options[Math.floor(random() * options.length)]
}

export function between(random: Random, min: number, max: number): number {
  return min + random() * (max - min)
}
