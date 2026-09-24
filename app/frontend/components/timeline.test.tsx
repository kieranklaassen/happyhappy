import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import type { TimelineEvent } from '../types/items'
import Timeline, { describeEvent } from './timeline'

function event(kind: TimelineEvent['kind'], data: Record<string, unknown> = {}): TimelineEvent {
  return { id: 1, kind, actor: { type: 'Agent', name: 'Cursor' }, data, created_at: '2026-09-24T10:00:00Z' }
}

describe('describeEvent', () => {
  it('describes corrections, status changes, and reports from their data', () => {
    expect(describeEvent(event('corrected', { label: 'product', from: 'Cora', to: null }))).toBe(
      'Changed product from Cora to none',
    )
    expect(describeEvent(event('status_changed', { from: 'claimed', to: 'new', released_agent: 'Cursor' }))).toBe(
      'Status changed from claimed to new, releasing Cursor',
    )
    expect(describeEvent(event('reported', { status: 'in_progress' }))).toBe('Reported back, status in progress')
    expect(describeEvent(event('overdue'))).toBe('Flagged overdue')
  })
})

describe('Timeline', () => {
  it('shows an agent report with its summary and only http links', () => {
    render(
      <Timeline
        events={[
          event('reported', { summary: 'Replied with the refund steps.', link: 'https://intercom.com/c/1' }),
          { ...event('reported', { link: 'javascript:alert(1)' }), id: 2 },
        ]}
      />,
    )

    expect(screen.getByText('Replied with the refund steps.')).toBeInTheDocument()
    expect(screen.getAllByText('(agent)')).toHaveLength(2)
    expect(screen.getAllByRole('link')).toHaveLength(1)
    expect(screen.getByRole('link')).toHaveAttribute('href', 'https://intercom.com/c/1')
  })

  it('has an empty state', () => {
    render(<Timeline events={[]} />)

    expect(screen.getByText('Nothing has happened to this item yet.')).toBeInTheDocument()
  })
})
