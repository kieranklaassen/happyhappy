import { fireEvent, render, screen, within } from '@testing-library/react'
import { type ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { ItemRowData } from '../../types/items'
import ItemsIndex, { type FeedProps, toQuery } from './index'

const get = vi.fn()

vi.mock('@inertiajs/react', () => ({
  Head: () => null,
  usePage: () => ({ url: '/items' }),
  router: { get: (...args: unknown[]) => get(...args) },
  Link: ({ href, children, ...rest }: { href: string; children: ReactNode }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}))

const row: ItemRowData = {
  id: 7,
  excerpt: 'Cora deleted half my inbox.',
  author: 'ana_customer',
  source: { id: 1, name: 'Community Slack', kind: 'slack' },
  product: { id: 3, name: 'Cora', slug: 'cora', retired: false },
  category: { id: 4, name: 'bug', retired: false },
  sentiment: 'complaint',
  status: 'claimed',
  relevant: true,
  needs_review: false,
  overdue: true,
  claimed_by: 'Cursor',
  anger_probability: 0.86,
  last_message_at: '2026-09-24T10:00:00Z',
}

function props(overrides: Partial<FeedProps> = {}): FeedProps {
  return {
    items: [row],
    filters: { relevance: 'relevant' },
    pagination: { page: 1, prev_page: null, next_page: null },
    options: {
      products: [
        { id: 3, name: 'Cora', slug: 'cora', retired: false },
        { id: 9, name: 'Lex', slug: 'lex', retired: true },
      ],
      categories: [{ id: 4, name: 'bug', retired: false }],
      sources: [{ id: 1, name: 'Community Slack', kind: 'slack' }],
      sentiments: ['complaint', 'praise', 'question', 'neutral'],
      statuses: ['new', 'claimed', 'in_progress', 'handled', 'dismissed'],
      ranges: ['24h', '7d', '30d', '90d'],
    },
    error: null,
    ...overrides,
  }
}

describe('Feed page', () => {
  beforeEach(() => get.mockClear())

  it('renders a heading, labeled filters, and item rows linking to the item', () => {
    render(<ItemsIndex {...props()} />)

    expect(screen.getByRole('heading', { level: 1, name: 'Feed' })).toBeInTheDocument()
    for (const name of ['Product', 'Sentiment', 'Category', 'Status', 'Source', 'Time range', 'Relevance']) {
      expect(screen.getByLabelText(name)).toBeInTheDocument()
    }
    const link = screen.getByRole('link', { name: /cora deleted half my inbox/i })
    expect(link).toHaveAttribute('href', '/items/7')
    expect(within(link).getByText('Overdue')).toBeInTheDocument()
    expect(within(link).getByText('Claimed by Cursor')).toBeInTheDocument()
    expect(within(link).getByText('Anger 86%')).toBeInTheDocument()
  })

  it('marks retired products in the product filter', () => {
    render(<ItemsIndex {...props()} />)

    expect(screen.getByRole('option', { name: 'Lex (retired)' })).toBeInTheDocument()
  })

  it('submits the chosen filters as a server visit', () => {
    render(<ItemsIndex {...props()} />)

    fireEvent.change(screen.getByLabelText('Product'), { target: { value: '3' } })
    fireEvent.change(screen.getByLabelText('Sentiment'), { target: { value: 'complaint' } })
    fireEvent.change(screen.getByLabelText('Relevance'), { target: { value: 'all' } })
    fireEvent.click(screen.getByLabelText('Needs review'))
    fireEvent.click(screen.getByRole('button', { name: 'Apply filters' }))

    expect(get).toHaveBeenCalledWith(
      '/items',
      { product: '3', sentiment: 'complaint', relevance: 'all', needs_review: '1' },
      { preserveScroll: true },
    )
  })

  it('starts from the current filters and links to the product overview', () => {
    render(<ItemsIndex {...props({ filters: { product: ['3'], overdue: true, relevance: 'relevant' } })} />)

    expect(screen.getByLabelText('Product')).toHaveValue('3')
    expect(screen.getByLabelText('Overdue')).toBeChecked()
    expect(screen.getByRole('link', { name: 'Cora overview' })).toHaveAttribute('href', '/products/cora/overview')
  })

  it('selects the product when the filter uses its slug', () => {
    render(<ItemsIndex {...props({ filters: { product: ['cora'], relevance: 'relevant' } })} />)

    expect(screen.getByLabelText('Product')).toHaveValue('3')
    expect(screen.getByRole('link', { name: 'Cora overview' })).toHaveAttribute('href', '/products/cora/overview')
  })

  it('shows an empty state when nothing matches', () => {
    render(<ItemsIndex {...props({ items: [] })} />)

    expect(screen.getByRole('heading', { name: 'No items match these filters' })).toBeInTheDocument()
  })

  it('shows an error state for an invalid filter', () => {
    render(<ItemsIndex {...props({ items: [], error: 'That filter is not valid (sentiment: bad).' })} />)

    expect(screen.getByRole('alert')).toHaveTextContent('That filter is not valid')
    expect(screen.queryByRole('heading', { name: 'No items match these filters' })).not.toBeInTheDocument()
  })

  it('keeps the filters in pagination links', () => {
    render(
      <ItemsIndex
        {...props({ filters: { sentiment: ['praise'], relevance: 'relevant' }, pagination: { page: 2, prev_page: 1, next_page: 3 } })}
      />,
    )

    expect(screen.getByRole('link', { name: 'Newer' })).toHaveAttribute('href', '/items?sentiment=praise&page=1')
    expect(screen.getByRole('link', { name: 'Older' })).toHaveAttribute('href', '/items?sentiment=praise&page=3')
  })
})

describe('toQuery', () => {
  it('drops empty filters and the default relevance', () => {
    expect(
      toQuery({
        product: '',
        sentiment: 'praise',
        category: '',
        status: '',
        source: '',
        range: '7d',
        relevance: 'relevant',
        needs_review: false,
        overdue: true,
      }),
    ).toEqual({ sentiment: 'praise', range: '7d', overdue: '1' })
  })
})
