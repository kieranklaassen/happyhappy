import { afterEach, describe, expect, it, vi } from 'vitest'
import { MOOD_COLORS, plural, timeAgo } from './format'
import { MOODS } from './moods'

describe('MOOD_COLORS', () => {
  it('assigns a distinct hex color to every mood', () => {
    expect(Object.keys(MOOD_COLORS).sort()).toEqual([...MOODS].sort())

    const colors = MOODS.map((mood) => MOOD_COLORS[mood])
    for (const color of colors) {
      expect(color).toMatch(/^#[0-9A-F]{6}$/i)
    }
    expect(new Set(colors).size).toBe(MOODS.length)
  })
})

describe('timeAgo', () => {
  const now = new Date('2026-06-15T12:00:00Z')

  afterEach(() => {
    vi.useRealTimers()
  })

  it.each([
    ['same instant', '2026-06-15T12:00:00Z', 'just now'],
    ['under half a minute ago', '2026-06-15T11:59:31Z', 'just now'],
    ['future timestamp clamped to zero', '2026-06-15T12:15:00Z', 'just now'],
    ['rounds 30 seconds up to 1 minute', '2026-06-15T11:59:30Z', '1m ago'],
    ['just under an hour', '2026-06-15T11:00:31Z', '59m ago'],
    ['rounds 59m30s into 1 hour', '2026-06-15T11:00:30Z', '1h ago'],
    ['rounds 89 minutes down to 1 hour', '2026-06-15T10:31:00Z', '1h ago'],
    ['rounds 90 minutes up to 2 hours', '2026-06-15T10:30:00Z', '2h ago'],
    ['stays in hours below 23.5 hours', '2026-06-14T12:31:00Z', '23h ago'],
    ['rounds 23.5 hours into 1 day', '2026-06-14T12:30:00Z', '1d ago'],
    ['rounds 36 hours into 2 days', '2026-06-14T00:00:00Z', '2d ago'],
    ['multi-day elapsed time', '2026-06-10T12:00:00Z', '5d ago'],
  ])('formats %s as %s', (_label, iso, expected) => {
    expect(timeAgo(iso, now)).toBe(expected)
  })

  it('defaults the reference time to the current clock', () => {
    vi.useFakeTimers()
    vi.setSystemTime(now)

    expect(timeAgo('2026-06-15T11:48:00Z')).toBe('12m ago')
  })
})

describe('plural', () => {
  it.each([
    [0, 'thread', undefined, '0 threads'],
    [1, 'thread', undefined, '1 thread'],
    [3, 'thread', undefined, '3 threads'],
    [0, 'person', 'people', '0 people'],
    [1, 'person', 'people', '1 person'],
    [2, 'person', 'people', '2 people'],
  ])('formats (%d, %s, %s) as %s', (count, one, many, expected) => {
    expect(plural(count, one, many)).toBe(expected)
  })
})
