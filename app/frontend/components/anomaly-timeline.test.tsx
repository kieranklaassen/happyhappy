import { render, screen, within } from '@testing-library/react'
import { type ReactNode } from 'react'
import { describe, expect, it, vi } from 'vitest'
import { formatDateTime } from '../lib/format'
import { anomaly, goodNews } from '../test/anomaly-fixture'
import AnomalyTimeline from './anomaly-timeline'

vi.mock('@inertiajs/react', () => ({
  Link: ({ href, children, ...rest }: { href: string; children: ReactNode }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}))

describe('AnomalyTimeline', () => {
  it('shows an empty state when there are no anomalies', () => {
    render(<AnomalyTimeline anomalies={[]} />)

    expect(screen.getByText('Nothing unusual in the last 30 days.')).toBeInTheDocument()
    expect(screen.queryByRole('list')).not.toBeInTheDocument()
  })

  it('renders an anomaly with its label, source, metric window, formatted times, and links', () => {
    const entry = anomaly({
      id: 12,
      source: { id: 1, kind: 'slack', name: 'Community Slack' },
      item_ids: [7, 8],
      incident_id: 4,
    })
    render(<AnomalyTimeline anomalies={[entry]} />)

    const items = screen.getAllByRole('listitem')
    expect(items).toHaveLength(1)
    const item = items[0]

    expect(within(item).getByText('Bug messages')).toBeInTheDocument()
    expect(within(item).getByText('on Community Slack')).toBeInTheDocument()
    expect(within(item).getByText('Active')).toHaveClass('bg-red-50', 'text-red-700')
    expect(within(item).getByText('High severity')).toBeInTheDocument()
    expect(item).toHaveTextContent('9 against an expected 0.4 per hour')

    const times = item.querySelectorAll('time')
    expect(times).toHaveLength(2)
    expect(times[0]).toHaveAttribute('datetime', entry.window_start)
    expect(times[0]).toHaveTextContent(formatDateTime(entry.window_start))
    expect(times[1]).toHaveAttribute('datetime', entry.window_end)
    expect(times[1]).toHaveTextContent(formatDateTime(entry.window_end))

    expect(within(item).getByRole('link', { name: '2 items' })).toHaveAttribute('href', '/items?anomaly=12')
    expect(within(item).getByRole('link', { name: 'Resolve incident' })).toHaveAttribute('href', '/incidents/4')
  })

  it('omits the source when absent and formats share metrics as percentages', () => {
    render(
      <AnomalyTimeline
        anomalies={[
          anomaly({
            metric: 'complaint_share',
            label: 'Complaint share',
            share: true,
            actual: 0.62,
            expected: 0.18,
            granularity: 'day',
            source: null,
          }),
        ]}
      />,
    )

    const item = screen.getByRole('listitem')
    expect(item).not.toHaveTextContent('on ')
    expect(item).toHaveTextContent('62% against an expected 18% per day')
  })

  it('orders status badges as Resolved, then History, then Active or Ended', () => {
    render(
      <AnomalyTimeline
        anomalies={[
          anomaly({ id: 1, label: 'Resolved anomaly', resolved_at: '2026-09-24T12:00:00Z', historical: true, status: 'active' }),
          anomaly({ id: 2, label: 'Historical anomaly', resolved_at: null, historical: true, status: 'active' }),
          anomaly({ id: 3, label: 'Ended anomaly', resolved_at: null, historical: false, status: 'ended' }),
          goodNews({ id: 4, label: 'Active positive', status: 'active' }),
          anomaly({ id: 5, label: 'Active neutral', polarity: 'neutral', severity: null, status: 'active' }),
        ]}
      />,
    )

    const items = screen.getAllByRole('listitem')
    expect(within(items[0]).getByText('Resolved')).toHaveClass('bg-gray-100', 'text-gray-700')
    expect(within(items[1]).getByText('History')).toHaveClass('bg-gray-100', 'text-gray-600')
    expect(within(items[2]).getByText('Ended')).toHaveClass('bg-gray-100', 'text-gray-700')
    expect(within(items[3]).getByText('Active')).toHaveClass('bg-green-50', 'text-green-700')
    expect(within(items[3]).getByText('Good news')).toBeInTheDocument()
    expect(within(items[4]).getByText('Active')).toHaveClass('bg-sky-50', 'text-sky-700')
    expect(within(items[4]).getByText('Busier than usual')).toBeInTheDocument()
  })

  it.each([
    ['positive', goodNews(), 'bg-green-400'],
    ['neutral', anomaly({ polarity: 'neutral', severity: null }), 'bg-sky-300'],
    ['high-severity negative', anomaly({ polarity: 'negative', severity: 'high' }), 'bg-red-500'],
    ['medium-severity negative', anomaly({ polarity: 'negative', severity: 'medium' }), 'bg-orange-400'],
    ['low-severity negative', anomaly({ polarity: 'negative', severity: 'low' }), 'bg-yellow-300'],
    ['ungraded negative', anomaly({ polarity: 'negative', severity: null }), 'bg-yellow-300'],
  ])('colors the decorative timeline dot for %s anomalies', (_name, entry, expectedClass) => {
    render(<AnomalyTimeline anomalies={[entry]} />)

    const dot = screen.getByRole('listitem').querySelector('[aria-hidden="true"]')
    expect(dot).toHaveClass(expectedClass)
  })

  it('pluralizes the items link and hides it when item_ids is empty', () => {
    render(
      <AnomalyTimeline
        anomalies={[
          anomaly({ id: 1, item_ids: [] }),
          anomaly({ id: 2, item_ids: [42] }),
          anomaly({ id: 3, item_ids: [42, 43, 44] }),
        ]}
      />,
    )

    const items = screen.getAllByRole('listitem')
    expect(within(items[0]).queryByRole('link')).not.toBeInTheDocument()
    expect(within(items[1]).getByRole('link', { name: '1 item' })).toHaveAttribute('href', '/items?anomaly=2')
    expect(within(items[2]).getByRole('link', { name: '3 items' })).toHaveAttribute('href', '/items?anomaly=3')
  })

  it('labels incident links by status and hides them when showIncident is false or incident_id is null', () => {
    const { rerender } = render(
      <AnomalyTimeline
        anomalies={[
          anomaly({ id: 1, status: 'active', incident_id: 4, item_ids: [] }),
          anomaly({ id: 2, status: 'ended', incident_id: 5, item_ids: [] }),
          anomaly({ id: 3, status: 'active', incident_id: null, item_ids: [] }),
        ]}
      />,
    )

    const items = screen.getAllByRole('listitem')
    expect(within(items[0]).getByRole('link', { name: 'Resolve incident' })).toHaveAttribute('href', '/incidents/4')
    expect(within(items[1]).getByRole('link', { name: 'Incident' })).toHaveAttribute('href', '/incidents/5')
    expect(within(items[2]).queryByRole('link')).not.toBeInTheDocument()

    rerender(<AnomalyTimeline anomalies={[anomaly({ id: 1, status: 'active', incident_id: 4, item_ids: [7] })]} showIncident={false} />)
    expect(screen.getByRole('link', { name: '1 item' })).toBeInTheDocument()
    expect(screen.queryByRole('link', { name: /incident/i })).not.toBeInTheDocument()
  })
})
