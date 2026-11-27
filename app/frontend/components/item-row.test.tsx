import { render, screen, within } from '@testing-library/react'
import { type ReactNode } from 'react'
import { describe, expect, it, vi } from 'vitest'
import { formatTime } from '../lib/feed-format'
import type { ActionabilityBand, ItemRowData, ItemStatus, Sentiment, SourceKind } from '../types/items'
import ItemRow from './item-row'

vi.mock('@inertiajs/react', () => ({
  Link: ({ href, children, ...rest }: { href: string; children: ReactNode }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}))

function item(overrides: Partial<ItemRowData> = {}): ItemRowData {
  return {
    id: 7,
    excerpt: 'Cora deleted half my inbox.',
    author: 'ana_customer',
    source: { id: 1, name: 'Community Slack', kind: 'slack' },
    product: { id: 3, name: 'Cora', slug: 'cora', retired: false },
    category: { id: 4, name: 'bug', retired: false },
    sentiment: 'complaint',
    status: 'new',
    relevant: true,
    needs_review: false,
    overdue: false,
    claimed_by: null,
    anger_probability: null,
    actionability: 0.91,
    actionability_band: 'act_now',
    last_message_at: '2026-09-24T10:00:00Z',
    ...overrides,
  }
}

function renderRow(overrides: Partial<ItemRowData> = {}) {
  const view = render(
    <ul>
      <ItemRow item={item(overrides)} />
    </ul>,
  )
  return {
    ...view,
    rerenderRow: (nextOverrides: Partial<ItemRowData> = {}) =>
      view.rerender(
        <ul>
          <ItemRow item={item(nextOverrides)} />
        </ul>,
      ),
  }
}

describe('ItemRow', () => {
  it('links to the item and shows author, source, timestamp, excerpt, and core badges', () => {
    const entry = item()
    renderRow()

    const listItem = screen.getByRole('listitem')
    const link = within(listItem).getByRole('link')
    expect(link).toHaveAttribute('href', '/items/7')
    expect(within(link).getByText('ana_customer')).toBeInTheDocument()
    expect(within(link).getByText('Slack · Community Slack')).toBeInTheDocument()
    expect(within(link).getByText('Cora deleted half my inbox.')).toBeInTheDocument()

    const time = link.querySelector('time')
    expect(time).toHaveAttribute('datetime', entry.last_message_at)
    expect(time).toHaveTextContent(formatTime(entry.last_message_at))
    expect(time?.textContent).toMatch(/2026/)
    expect(time).not.toHaveTextContent(entry.last_message_at)

    expect(within(link).getByText('Act now 91%')).toBeInTheDocument()
    expect(within(link).getByText('Complaint')).toBeInTheDocument()
    expect(within(link).getByText('Cora')).toBeInTheDocument()
    expect(within(link).getByText('bug')).toBeInTheDocument()
    expect(within(link).getByText('New')).toBeInTheDocument()
  })

  it('falls back to a placeholder when the excerpt is empty', () => {
    renderRow({ excerpt: '' })

    expect(screen.getByText('No message text.')).toBeInTheDocument()
  })

  it.each<[SourceKind, string]>([
    ['slack', 'Slack'],
    ['discord', 'Discord'],
    ['intercom', 'Intercom'],
    ['email', 'Email'],
    ['x', 'X'],
    ['custom', 'Custom webhook'],
  ])('formats the %s source kind as %s', (kind, label) => {
    renderRow({ source: { id: 1, name: 'Inbox', kind } })

    expect(screen.getByText(`${label} · Inbox`)).toBeInTheDocument()
  })

  it('shows retired and missing product states and omits a missing category', () => {
    const { rerenderRow } = renderRow({ product: null, category: null })
    expect(screen.getByText('No product')).toBeInTheDocument()
    expect(screen.queryByText('bug')).not.toBeInTheDocument()

    rerenderRow({ product: { id: 9, name: 'Lex', slug: 'lex', retired: true } })
    expect(screen.getByText('Lex (retired)')).toBeInTheDocument()
  })

  it.each<[ActionabilityBand, number | null, string]>([
    ['act_now', 0.91, 'Act now 91%'],
    ['should_reply', null, 'Should reply'],
    ['fyi', 0.34, 'FYI 34%'],
    ['noise', 0, 'Noise 0%'],
  ])('renders the %s actionability badge as %s', (band, score, expectedText) => {
    renderRow({ actionability_band: band, actionability: score })

    expect(screen.getByText(expectedText)).toBeInTheDocument()
  })

  it('omits the actionability badge when actionability_band is null', () => {
    renderRow({ actionability_band: null, actionability: 0.95 })

    expect(screen.queryByText(/Act now|Should reply|FYI|Noise|95%/)).not.toBeInTheDocument()
  })

  it.each<[Sentiment, string]>([
    ['complaint', 'Complaint'],
    ['praise', 'Praise'],
    ['question', 'Question'],
    ['neutral', 'Neutral'],
    ['relieved', 'Relieved'],
  ])('renders the %s sentiment badge', (sentiment, label) => {
    renderRow({ sentiment })

    expect(screen.getByText(label)).toBeInTheDocument()
  })

  it('omits the sentiment badge when sentiment is null', () => {
    renderRow({ sentiment: null })

    expect(screen.queryByText(/Complaint|Praise|Question|Neutral|Relieved|Unclassified/)).not.toBeInTheDocument()
  })

  it.each<[ItemStatus, string]>([
    ['new', 'New'],
    ['claimed', 'Claimed'],
    ['in_progress', 'In progress'],
    ['handled', 'Handled'],
    ['dismissed', 'Dismissed'],
  ])('renders the %s status badge as %s', (status, label) => {
    renderRow({ status })

    expect(screen.getByText(label)).toBeInTheDocument()
  })

  it('shows optional claim, overdue, review, and relevance badges only when active', () => {
    const { rerenderRow } = renderRow({ claimed_by: null, overdue: false, needs_review: false, relevant: true })

    expect(screen.queryByText(/Claimed by/)).not.toBeInTheDocument()
    expect(screen.queryByText('Overdue')).not.toBeInTheDocument()
    expect(screen.queryByText('Needs review')).not.toBeInTheDocument()
    expect(screen.queryByText('Not relevant')).not.toBeInTheDocument()

    rerenderRow({ claimed_by: 'Cursor', overdue: true, needs_review: true, relevant: false })

    expect(screen.getByText('Claimed by Cursor')).toBeInTheDocument()
    expect(screen.getByText('Overdue')).toBeInTheDocument()
    expect(screen.getByText('Needs review')).toBeInTheDocument()
    expect(screen.getByText('Not relevant')).toBeInTheDocument()
  })

  it('shows the anger badge only at or above the 0.5 threshold', () => {
    const { rerenderRow } = renderRow({ anger_probability: null })
    expect(screen.queryByText(/Anger/)).not.toBeInTheDocument()

    rerenderRow({ anger_probability: 0.49 })
    expect(screen.queryByText(/Anger/)).not.toBeInTheDocument()

    rerenderRow({ anger_probability: 0.5 })
    expect(screen.getByText('Anger 50%')).toBeInTheDocument()

    rerenderRow({ anger_probability: 0.864 })
    expect(screen.getByText('Anger 86%')).toBeInTheDocument()
  })
})
