import { afterEach, describe, expect, it, vi } from 'vitest'
import { formatPercent, formatTime, safeLink, sentimentLabel } from './feed-format'

describe('safeLink', () => {
  it.each(['https://intercom.com/c/1', 'http://intercom.com/c/1'])('keeps the web link %s', (link) => {
    expect(safeLink(link)).toBe(link)
  })

  it.each([
    ['a script that mentions a web link', 'javascript:alert("https://intercom.com")'],
    ['a data URL', 'data:text/html,<p>hi</p>'],
    ['a host without a scheme', '//intercom.com/c/1'],
    ['a relative path', '/items/1'],
    ['an empty string', ''],
    ['a missing value', undefined],
    ['a list holding a web link', ['https://intercom.com/c/1']],
  ])('refuses %s', (_name, value) => {
    expect(safeLink(value)).toBeNull()
  })
})

describe('formatPercent', () => {
  it('tells a missing probability from zero', () => {
    expect(formatPercent(null)).toBe('n/a')
    expect(formatPercent(0)).toBe('0%')
  })

  it.each([
    [0.004, '0%'],
    [0.005, '1%'],
    [0.994, '99%'],
    [1, '100%'],
  ])('rounds %d to the nearest whole percent, %s', (probability, shown) => {
    expect(formatPercent(probability)).toBe(shown)
  })
})

describe('formatTime', () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  // Stands in for the viewer's settings. A locale or zone the code passes itself still wins.
  function viewFrom(timeZone: string) {
    const original = Date.prototype.toLocaleString
    vi.spyOn(Date.prototype, 'toLocaleString').mockImplementation(function (this: Date, locale, options) {
      return original.call(this, locale ?? 'en-US', { timeZone, ...options })
    })
  }

  it.each([
    ['America/New_York', /^Dec 31, 2025, 9:30\sPM$/],
    ['UTC', /^Jan 1, 2026, 2:30\sAM$/],
    ['Asia/Kolkata', /^Jan 1, 2026, 8:00\sAM$/],
  ])("shows the day and time on the viewer's clock in %s", (timeZone, shown) => {
    viewFrom(timeZone)
    expect(formatTime('2026-01-01T02:30:00Z')).toMatch(shown)
  })
})

describe('sentimentLabel', () => {
  it('says so when an item has no sentiment yet', () => {
    expect(sentimentLabel(null)).toBe('Unclassified')
  })
})
