import { afterEach, describe, expect, it, vi } from 'vitest'
import { formatDateTime, formatHour, formatUsd } from './format'

describe('formatHour', () => {
  it.each([
    [0, '00:00'],
    [7, '07:00'],
    [9, '09:00'],
    [10, '10:00'],
    [23, '23:00'],
  ])('formats hour %d as %s', (hour, expected) => {
    expect(formatHour(hour)).toBe(expected)
  })
})

describe('formatDateTime', () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  function viewFrom(timeZone: string) {
    const original = Date.prototype.toLocaleString
    vi.spyOn(Date.prototype, 'toLocaleString').mockImplementation(function (this: Date, locale, options) {
      return original.call(this, locale ?? 'en-US', { timeZone, ...options })
    })
  }

  it.each([null, ''])('returns "Never" for empty timestamp %j', (value) => {
    expect(formatDateTime(value)).toBe('Never')
  })

  it.each([
    ['America/New_York', /^Dec 31, 2025, 9:30\sPM$/],
    ['UTC', /^Jan 1, 2026, 2:30\sAM$/],
    ['Asia/Kolkata', /^Jan 1, 2026, 8:00\sAM$/],
  ])("formats an ISO timestamp in the viewer's timezone (%s)", (timeZone, expected) => {
    viewFrom(timeZone)
    expect(formatDateTime('2026-01-01T02:30:00Z')).toMatch(expected)
  })
})

describe('formatUsd', () => {
  it.each([
    [0, '$0.00'],
    [5, '$5.00'],
    [1.5, '$1.50'],
    [12.344, '$12.34'],
    [12.346, '$12.35'],
    [1234.5, '$1234.50'],
  ])('formats %d as %s', (amount, expected) => {
    expect(formatUsd(amount)).toBe(expected)
  })
})
