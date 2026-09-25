import type { AnomalyProps } from '../types/anomalies'

export function goodNews(overrides: Partial<AnomalyProps> = {}): AnomalyProps {
  return anomaly({
    id: 21,
    product: { id: 5, slug: 'thesis', name: 'Thesis' },
    dimension: '5',
    label: 'Praise messages',
    granularity: 'day',
    expected: 2,
    actual: 12,
    polarity: 'positive',
    severity: null,
    highlight: 'big',
    ...overrides,
  })
}

export function anomaly(overrides: Partial<AnomalyProps> = {}): AnomalyProps {
  return {
    id: 12,
    product: { id: 3, slug: 'cora', name: 'Cora' },
    source: null,
    metric: 'category_volume',
    dimension: '4',
    label: 'Bug messages',
    granularity: 'hour',
    window_start: '2026-09-24T09:00:00Z',
    window_end: '2026-09-24T10:00:00Z',
    expected: 0.4,
    actual: 9,
    share: false,
    z_score: 12,
    polarity: 'negative',
    severity: 'high',
    highlight: null,
    status: 'active',
    historical: false,
    item_ids: [7, 8],
    first_seen_at: '2026-09-24T10:00:00Z',
    last_seen_at: '2026-09-24T10:00:00Z',
    ended_at: null,
    ...overrides,
  }
}
