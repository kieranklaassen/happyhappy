import { describe, expect, it } from 'vitest'
import { type Mood, MOODS, moodBlurb, moodLabel } from './moods'

describe('MOODS', () => {
  it('lists all seven moods in display order', () => {
    expect(MOODS).toEqual(['beaming', 'content', 'relieved', 'meh', 'grumpy', 'furious', 'pending'])
  })
})

describe('moodLabel', () => {
  const expected: Record<Mood, string> = {
    beaming: 'Beaming',
    content: 'Content',
    relieved: 'Relieved',
    meh: 'Meh',
    grumpy: 'Grumpy',
    furious: 'Furious',
    pending: 'Still reading',
  }

  it.each(MOODS)('returns the display label for %s', (mood) => {
    expect(moodLabel(mood)).toBe(expected[mood])
  })
})

describe('moodBlurb', () => {
  const expected: Record<Mood, string> = {
    beaming: 'over the moon',
    content: 'quietly pleased',
    relieved: 'breathing easy again',
    meh: 'shrugging',
    grumpy: 'not impressed',
    furious: 'steaming',
    pending: 'we are still reading this one',
  }

  it.each(MOODS)('returns the short blurb for %s', (mood) => {
    expect(moodBlurb(mood)).toBe(expected[mood])
  })
})
