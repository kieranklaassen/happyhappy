import { render, screen } from '@testing-library/react'
import { type ReactNode } from 'react'
import { describe, expect, it, vi } from 'vitest'
import ProductOverview, { type ProductOverviewProps } from './overview'

vi.mock('@inertiajs/react', () => ({
  Head: () => null,
  usePage: () => ({ url: '/products/cora/overview' }),
  Link: ({ href, children, ...rest }: { href: string; children: ReactNode }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}))

const empty = { complaint: 0, praise: 0, question: 0, neutral: 0, relieved: 0, total: 0 }

function props(overrides: Partial<ProductOverviewProps> = {}): ProductOverviewProps {
  return {
    product: { id: 3, name: 'Cora', slug: 'cora', retired: false },
    days: [
      { date: '2026-09-23', ...empty, complaint: 1, praise: 1, total: 3 },
      { date: '2026-09-24', ...empty, complaint: 1, total: 1 },
    ],
    totals: { complaint: 2, praise: 1, question: 0, neutral: 0, relieved: 0, total: 4 },
    notable_complaints: [
      {
        id: 7,
        excerpt: 'Cora deleted half my inbox.',
        author: 'ana_customer',
        source: { id: 1, name: 'Community Slack', kind: 'slack' },
        product: { id: 3, name: 'Cora', slug: 'cora', retired: false },
        category: null,
        sentiment: 'complaint',
        status: 'new',
        relevant: true,
        needs_review: false,
        overdue: false,
        claimed_by: null,
        anger_probability: 0.86,
        last_message_at: '2026-09-24T10:00:00Z',
      },
    ],
    notable_praise: [],
    products: [
      { id: 3, name: 'Cora', slug: 'cora', retired: false },
      { id: 4, name: 'Spiral', slug: 'spiral', retired: false },
    ],
    ...overrides,
  }
}

describe('Product overview page', () => {
  it('shows totals, a labeled bar per day, and notable items', () => {
    render(<ProductOverview {...props()} />)

    expect(screen.getByRole('heading', { level: 1, name: 'Cora overview' })).toBeInTheDocument()
    const bars = screen.getAllByRole('listitem', { name: /^2026-09-2/ })
    expect(bars).toHaveLength(2)
    expect(bars[0]).toHaveAccessibleName('2026-09-23: 3 items (1 complaint, 1 praise, 1 unclassified)')
    expect(screen.getByRole('link', { name: /cora deleted half my inbox/i })).toHaveAttribute('href', '/items/7')
    expect(screen.getByText('No praise in the last 30 days.')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Spiral' })).toHaveAttribute('href', '/products/spiral/overview')
    expect(screen.getByRole('link', { name: 'Open in feed' })).toHaveAttribute('href', '/items?product=3')
  })

  it('shows an empty state for a quiet product', () => {
    render(<ProductOverview {...props({ totals: empty, notable_complaints: [] })} />)

    expect(screen.getByText('No items about Cora in the last 30 days.')).toBeInTheDocument()
    expect(screen.queryByRole('list', { name: 'Items per day by sentiment' })).not.toBeInTheDocument()
  })
})
