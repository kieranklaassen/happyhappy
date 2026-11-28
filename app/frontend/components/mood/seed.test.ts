import { describe, expect, it } from 'vitest'
import { between, hashSeed, pick, seededRandom } from './seed'

describe('hashSeed', () => {
  it('returns a deterministic unsigned 32-bit integer for every key', () => {
    const keys = ['', 'a', 'b', 'ab', 'ba', 'person-1', 'flora:cora', 'unicode-☀️-🎉']

    for (const key of keys) {
      const hash = hashSeed(key)
      expect(Number.isInteger(hash)).toBe(true)
      expect(hash).toBeGreaterThanOrEqual(0)
      expect(hash).toBeLessThanOrEqual(0xffffffff)
      expect(hashSeed(key)).toBe(hash)
    }

    expect(new Set(keys.map(hashSeed)).size).toBe(keys.length)
  })
})

describe('seededRandom', () => {
  it('replays the exact sequence for identical keys and diverges for different keys', () => {
    const a1 = seededRandom('cora')
    const a2 = seededRandom('cora')
    const b = seededRandom('thesis')

    const seqA1 = Array.from({ length: 20 }, () => a1())
    const seqA2 = Array.from({ length: 20 }, () => a2())
    const seqB = Array.from({ length: 20 }, () => b())

    expect(seqA1).toEqual(seqA2)
    expect(seqA1).not.toEqual(seqB)
  })

  it('produces varied values strictly inside [0, 1)', () => {
    const rand = seededRandom('spread-check')
    const samples = Array.from({ length: 200 }, () => rand())

    for (const value of samples) {
      expect(value).toBeGreaterThanOrEqual(0)
      expect(value).toBeLessThan(1)
    }
    expect(new Set(samples).size).toBeGreaterThan(190)
  })

  it('keeps independent generators isolated', () => {
    const first = seededRandom('same')
    const second = seededRandom('same')

    const expectedFirst = first()
    first()
    first()

    expect(second()).toBe(expectedFirst)
  })
})

describe('pick', () => {
  const options = ['grass', 'daisy', 'tulip', 'pebble'] as const

  it('maps boundary random values to the expected index', () => {
    expect(pick(() => 0, options)).toBe('grass')
    expect(pick(() => 0.5, options)).toBe('tulip')
    expect(pick(() => 0.999999, options)).toBe('pebble')
  })

  it('selects across all options when driven by seededRandom', () => {
    const rand = seededRandom('pick-all')
    const chosen = new Set(Array.from({ length: 100 }, () => pick(rand, options)))

    expect(chosen).toEqual(new Set(options))
  })
})

describe('between', () => {
  it('interpolates linearly between min and max', () => {
    expect(between(() => 0, 6, 34)).toBe(6)
    expect(between(() => 0.5, 6, 34)).toBe(20)
    expect(between(() => 0.5, -10, 10)).toBe(0)
    expect(between(() => 0.75, 5, 5)).toBe(5)
  })

  it('stays within [min, max) when driven by seededRandom', () => {
    const rand = seededRandom('range-check')
    for (let i = 0; i < 200; i++) {
      const value = between(rand, 16, 24)
      expect(value).toBeGreaterThanOrEqual(16)
      expect(value).toBeLessThan(24)
    }
  })
})
