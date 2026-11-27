import { describe, expect, it } from 'vitest'
import { anomaly, goodNews } from '../test/anomaly-fixture'
import { anomalyExpected, anomalySummary, anomalyTag, anomalyValue } from './anomaly-format'

const count = { share: false }
const share = { share: true }

describe('anomalyValue', () => {
  it.each([
    [0, '0'],
    [3, '3'],
    [2.34, '2.3'],
    [10.4, '10'],
    [12.6, '13'],
  ])('shows the count %d as %s: a decimal only for small fractions', (value, shown) => {
    expect(anomalyValue(count, value)).toBe(shown)
  })

  it.each([
    [0, '0%'],
    [0.125, '13%'],
    [1, '100%'],
  ])('shows the share %d as %s', (value, shown) => {
    expect(anomalyValue(share, value)).toBe(shown)
  })
})

describe('anomalyExpected', () => {
  it.each([
    [0, 'none'],
    [0.049, 'none'],
    [0.05, 'under 1'],
    [0.999, 'under 1'],
    [1, '1'],
    [1.4, '1'],
    [1.5, '2'],
  ])('says an average of %d messages as "%s"', (value, shown) => {
    expect(anomalyExpected(count, value)).toBe(shown)
  })

  it.each([
    [0, '0%'],
    [0.03, '3%'],
    [1, '100%'],
  ])('keeps the share %d a percentage, %s', (value, shown) => {
    expect(anomalyExpected(share, value)).toBe(shown)
  })
})

describe('anomalyTag', () => {
  it('grades medium bad news, and treats ungraded bad news as low', () => {
    expect(anomalyTag({ polarity: 'negative', severity: 'medium' })).toBe('Medium severity')
    expect(anomalyTag({ polarity: 'negative', severity: null })).toBe('Low severity')
  })
})

describe('anomalySummary', () => {
  it('names the product before the source', () => {
    const source = { id: 1, kind: 'slack' as const, name: 'Community Slack' }
    expect(anomalySummary(anomaly({ source }))).toBe(
      'Bug messages for Cora on Community Slack: 9 in the last hour, usually under 1.',
    )
  })

  it('says plain "messages" for good news about volume', () => {
    expect(anomalySummary(goodNews({ metric: 'volume', label: 'Message volume', highlight: 'notable' }))).toBe(
      'More messages for Thesis: 12 in a day, usually 2.',
    )
  })

  it('falls back to the label for good news without a highlight', () => {
    expect(anomalySummary(goodNews({ highlight: null }))).toBe('Praise messages for Thesis: 12 in a day, usually 2.')
  })
})
