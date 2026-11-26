import { fireEvent, render, screen, within } from '@testing-library/react'
import { type ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { anomaly, goodNews } from '../../test/anomaly-fixture'
import type { ItemRowData } from '../../types/items'
import ItemsIndex, { type FeedProps, toQuery } from './index'

const get = vi.fn()
const usePoll = vi.fn()

vi.mock('@inertiajs/react', () => ({
  Head: () => null,
  usePage: () => ({ url: '/items' }),
  usePoll: (...args: unknown[]) => usePoll(...args),
  router: { get: (...args: unknown[]) => get(...args), reload: vi.fn() },
  Link: ({ href, children, ...rest }: { href: string; children: ReactNode }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}))

vi.mock('@rails/actioncable', () => ({
  createConsumer: () => ({
    subscriptions: { create: () => ({ unsubscribe: vi.fn() }) },
    disconnect: vi.fn(),
  }),
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
  actionability: 0.91,
  actionability_band: 'act_now',
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
      actionability: ['act_now', 'should_reply', 'fyi', 'noise'],
      sorts: ['recent', 'actionability'],
    },
    anomalies: [],
    search: null,
    smart: null,
    error: null,
    ...overrides,
  }
}

describe('Feed page', () => {
  it('shows each item\'s actionability and offers the band filter and sort', () => {
    render(<ItemsIndex {...props()} />)

    expect(screen.getByText('Act now 91%')).toBeInTheDocument()
    expect(screen.getByRole('option', { name: 'Any (noise hidden)' })).toBeInTheDocument()
    expect(screen.getByRole('option', { name: 'Most actionable first' })).toBeInTheDocument()
  })

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

  it('reloads its items and anomalies when the mood stream pings', () => {
    render(<ItemsIndex {...props()} />)

    expect(usePoll).toHaveBeenCalledWith(30_000, { only: ['items', 'anomalies'] })
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

  it('shows a banner for active anomalies that links to their items', () => {
    render(<ItemsIndex {...props({ anomalies: [anomaly()] })} />)

    const banner = screen.getByRole('region', { name: 'Active anomalies' })
    expect(banner).toHaveTextContent('1 anomaly is active')
    expect(within(banner).getByRole('link', { name: 'Show their items' })).toHaveAttribute('href', '/items?anomaly=active')
    expect(within(banner).getByRole('link', { name: /High severity: Bug messages for Cora: 9 in the last hour, usually under 1/ })).toHaveAttribute(
      'href',
      '/items?anomaly=12',
    )
  })

  it('reads good news in the banner as good news', () => {
    render(<ItemsIndex {...props({ anomalies: [goodNews()] })} />)

    const banner = screen.getByRole('region', { name: 'Active anomalies' })
    expect(banner).toHaveTextContent('Good news: Way more praise messages for Thesis: 12 in a day, usually 2.')
    expect(banner).not.toHaveTextContent(/severity|storm|warning/i)
    expect(banner).toHaveClass('bg-green-50')
  })

  it('filters to items in an active anomaly and explains the filter', () => {
    const { unmount } = render(<ItemsIndex {...props({ anomalies: [anomaly()] })} />)
    fireEvent.click(screen.getByLabelText('In an active anomaly'))
    fireEvent.click(screen.getByRole('button', { name: 'Apply filters' }))
    expect(get).toHaveBeenCalledWith('/items', { anomaly: 'active' }, { preserveScroll: true })
    unmount()

    render(<ItemsIndex {...props({ anomalies: [anomaly()], filters: { anomaly: '12', relevance: 'relevant' } })} />)
    expect(screen.getByRole('status')).toHaveTextContent('Showing items behind: High severity: Bug messages for Cora')
    expect(screen.getByLabelText('In an active anomaly')).toBeChecked()
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

  it('a search shows its chips and best matches, and applying filters keeps the query', () => {
    const search = {
      query: 'angry Cora',
      chips: [{ key: 'anger', label: 'anger', kind: 'filter' as const, name: 'Anger' }],
      removed: [],
      relaxed_labels: [],
      relaxed_notice: null,
      invite_row: null,
      encoding_status: 'cached' as const,
      explicit_action: 'enter',
      run_id: null,
    }
    render(<ItemsIndex {...props({ search })} />)

    expect(screen.getByRole('searchbox', { name: 'Search the feed' })).toHaveValue('angry Cora')
    expect(screen.getByText('Anger')).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Best matches' })).toBeInTheDocument()

    fireEvent.submit(screen.getByRole('form', { name: 'Filter the feed' }))
    expect(get).toHaveBeenCalledWith('/items', { q: 'angry Cora' }, { preserveScroll: true })
  })

  it('applying filters during a search keeps the chips the user removed', () => {
    const search = {
      query: 'angry Cora',
      chips: [{ key: 'product:cora', label: 'product', kind: 'filter' as const, name: 'Product: cora' }],
      removed: ['anger', 'time'],
      relaxed_labels: [],
      relaxed_notice: null,
      invite_row: null,
      encoding_status: 'cached' as const,
      explicit_action: 'enter',
      run_id: null,
    }
    render(<ItemsIndex {...props({ search })} />)

    fireEvent.submit(screen.getByRole('form', { name: 'Filter the feed' }))
    expect(get).toHaveBeenCalledWith('/items', { q: 'angry Cora', removed: ['anger', 'time'] }, { preserveScroll: true })
  })

  it('applying a changed filter during a search submits the filter and the search', () => {
    const search = {
      query: 'angry Cora',
      chips: [],
      removed: ['anger'],
      relaxed_labels: [],
      relaxed_notice: null,
      invite_row: null,
      encoding_status: 'cached' as const,
      explicit_action: 'enter',
      run_id: null,
    }
    render(<ItemsIndex {...props({ search })} />)

    fireEvent.change(screen.getByRole('combobox', { name: 'Sentiment' }), { target: { value: 'praise' } })
    fireEvent.click(screen.getByRole('button', { name: 'Apply filters' }))

    expect(get).toHaveBeenCalledWith(
      '/items',
      { sentiment: 'praise', q: 'angry Cora', removed: ['anger'] },
      { preserveScroll: true },
    )
  })

  it('a search with no matches suggests Smart search', () => {
    const search = {
      query: 'praise for Thesis',
      chips: [],
      removed: [],
      relaxed_labels: [],
      relaxed_notice: null,
      invite_row: { query: 'praise for Thesis', reason: 'empty' as const },
      encoding_status: 'cached' as const,
      explicit_action: 'enter',
      run_id: null,
    }
    render(<ItemsIndex {...props({ items: [], search })} />)

    expect(screen.getByRole('heading', { name: 'Nothing in the feed matches “praise for Thesis”' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /No keyword matches/ })).toBeInTheDocument()
  })

  it.each([
    [
      'Product',
      [
        ['', 'All products'],
        ['none', 'No product'],
        ['3', 'Cora'],
        ['9', 'Lex (retired)'],
      ],
    ],
    [
      'Sentiment',
      [
        ['', 'All sentiments'],
        ['complaint', 'Complaint'],
        ['praise', 'Praise'],
        ['question', 'Question'],
        ['neutral', 'Neutral'],
      ],
    ],
    [
      'Category',
      [
        ['', 'All categories'],
        ['4', 'bug'],
        ['5', 'old (retired)'],
      ],
    ],
    [
      'Status',
      [
        ['', 'All statuses'],
        ['new', 'New'],
        ['claimed', 'Claimed'],
        ['in_progress', 'In progress'],
        ['handled', 'Handled'],
        ['dismissed', 'Dismissed'],
      ],
    ],
    [
      'Source',
      [
        ['', 'All sources'],
        ['1', 'Slack: Community Slack'],
      ],
    ],
    [
      'Time range',
      [
        ['', 'Any time'],
        ['24h', 'Last 24 hours'],
        ['7d', 'Last 7 days'],
        ['30d', 'Last 30 days'],
        ['90d', 'Last 90 days'],
        ['1y', '1y'],
      ],
    ],
    [
      'Actionability',
      [
        ['', 'Any (noise hidden)'],
        ['act_now', 'Act now'],
        ['should_reply', 'Should reply'],
        ['fyi', 'FYI'],
        ['noise', 'Noise'],
      ],
    ],
    [
      'Sort',
      [
        ['recent', 'Most recent first'],
        ['actionability', 'Most actionable first'],
      ],
    ],
    [
      'Relevance',
      [
        ['relevant', 'Relevant only'],
        ['not_relevant', 'Not relevant only'],
        ['all', 'Everything'],
      ],
    ],
  ])('offers the %s options in order', (name, expected) => {
    const base = props()
    const options = {
      ...base.options,
      categories: [...base.options.categories, { id: 5, name: 'old', retired: true }],
      ranges: [...base.options.ranges, '1y'],
    }
    render(<ItemsIndex {...base} options={options} />)

    const select = screen.getByRole('combobox', { name })
    expect(within(select).getAllByRole<HTMLOptionElement>('option').map((option) => [option.value, option.textContent])).toEqual(expected)
  })

  it.each([
    ['Product', 'none', { product: 'none' }],
    ['Sentiment', 'praise', { sentiment: 'praise' }],
    ['Category', '4', { category: '4' }],
    ['Status', 'handled', { status: 'handled' }],
    ['Source', '1', { source: '1' }],
    ['Time range', '7d', { range: '7d' }],
    ['Actionability', 'fyi', { actionability: 'fyi' }],
    ['Sort', 'actionability', { sort: 'actionability' }],
    ['Relevance', 'not_relevant', { relevance: 'not_relevant' }],
  ])('submits only the changed %s select', (name, value, query) => {
    render(<ItemsIndex {...props()} />)

    fireEvent.change(screen.getByRole('combobox', { name }), { target: { value } })
    fireEvent.click(screen.getByRole('button', { name: 'Apply filters' }))

    expect(get).toHaveBeenCalledWith('/items', query, { preserveScroll: true })
  })

  it.each([
    ['Needs review', { needs_review: true }, { needs_review: '1' }],
    ['Overdue', { overdue: true }, { overdue: '1' }],
    ['In an active anomaly', { anomaly: 'active' }, { anomaly: 'active' }],
  ])('turns the %s checkbox on and off', (name, filters, query) => {
    const { unmount } = render(<ItemsIndex {...props()} />)
    expect(screen.getByRole('checkbox', { name })).not.toBeChecked()
    fireEvent.click(screen.getByRole('checkbox', { name }))
    fireEvent.click(screen.getByRole('button', { name: 'Apply filters' }))
    expect(get).toHaveBeenLastCalledWith('/items', query, { preserveScroll: true })
    unmount()

    render(<ItemsIndex {...props({ filters })} />)
    expect(screen.getByRole('checkbox', { name })).toBeChecked()
    fireEvent.click(screen.getByRole('checkbox', { name }))
    fireEvent.click(screen.getByRole('button', { name: 'Apply filters' }))
    expect(get).toHaveBeenLastCalledWith('/items', {}, { preserveScroll: true })
  })

  it('fills every select from the current filters', () => {
    render(
      <ItemsIndex
        {...props({
          filters: {
            product: ['none'],
            sentiment: ['praise'],
            category: ['4'],
            status: ['handled'],
            source: ['1'],
            range: '7d',
            actionability: ['fyi'],
            sort: 'actionability',
            relevance: 'all',
          },
        })}
      />,
    )

    const values = screen.getAllByRole<HTMLSelectElement>('combobox').map((select) => select.value)
    expect(values).toEqual(['none', 'praise', '4', 'handled', '1', '7d', 'fyi', 'actionability', 'all'])
  })

  it('keeps unsubmitted choices out of the pagination links', () => {
    render(<ItemsIndex {...props({ pagination: { page: 1, prev_page: null, next_page: 2 } })} />)

    fireEvent.change(screen.getByRole('combobox', { name: 'Sentiment' }), { target: { value: 'praise' } })

    expect(screen.getByRole('link', { name: 'Older' })).toHaveAttribute('href', '/items?page=2')
  })

  it('keeps unsubmitted choices when new props arrive, while links follow the props', () => {
    const { rerender } = render(<ItemsIndex {...props()} />)
    fireEvent.change(screen.getByRole('combobox', { name: 'Sentiment' }), { target: { value: 'praise' } })

    rerender(
      <ItemsIndex {...props({ filters: { status: ['handled'] }, pagination: { page: 1, prev_page: null, next_page: 2 } })} />,
    )

    expect(screen.getByRole('combobox', { name: 'Sentiment' })).toHaveValue('praise')
    expect(screen.getByRole('combobox', { name: 'Status' })).toHaveValue('')
    expect(screen.getByRole('link', { name: 'Older' })).toHaveAttribute('href', '/items?status=handled&page=2')
  })

  it.each<[string, FeedProps['filters'], [string, string][]]>([
    ['every value of a list', { status: ['new', 'claimed'] }, [['status[]', 'new'], ['status[]', 'claimed']]],
    ['since', { since: '2026-09-01T00:00:00.000Z' }, [['since', '2026-09-01T00:00:00.000Z']]],
    ['until', { until: '2026-09-02T00:00:00.000Z' }, [['until', '2026-09-02T00:00:00.000Z']]],
    ['source_kind', { source_kind: ['slack'] }, [['source_kind', 'slack']]],
    ['min_actionability', { min_actionability: 0 }, [['min_actionability', '0']]],
    ['needs_review', { needs_review: true }, [['needs_review', '1']]],
    ['overdue', { overdue: true }, [['overdue', '1']]],
    ['anomaly', { anomaly: '12' }, [['anomaly', '12']]],
    ['sort', { sort: 'actionability' }, [['sort', 'actionability']]],
    ['relevance', { relevance: 'all' }, [['relevance', 'all']]],
    [
      'relevant when asking for noise would widen it',
      { actionability: ['noise'], relevance: 'relevant' },
      [['actionability', 'noise'], ['relevance', 'relevant']],
    ],
  ])('keeps %s in the Older and Newer links', (_name, filters, expected) => {
    render(<ItemsIndex {...props({ filters, pagination: { page: 2, prev_page: 1, next_page: 3 } })} />)

    for (const [name, page] of [['Newer', '1'], ['Older', '3']]) {
      const href = screen.getByRole('link', { name }).getAttribute('href') ?? ''
      expect([...new URL(href, 'http://localhost').searchParams]).toEqual([...expected, ['page', page]])
    }
  })

  it('keeps every applied filter when removing a search chip', () => {
    const search = {
      query: 'angry Cora',
      chips: [{ key: 'anger', label: 'anger', kind: 'filter' as const, name: 'Anger' }],
      removed: [],
      relaxed_labels: [],
      relaxed_notice: null,
      invite_row: null,
      encoding_status: 'cached' as const,
      explicit_action: 'enter',
      run_id: null,
    }
    const filters = { status: ['new', 'claimed'], since: '2026-09-01T00:00:00.000Z' }
    render(<ItemsIndex {...props({ search, filters })} />)

    fireEvent.click(screen.getByRole('button', { name: 'Remove Anger' }))

    expect(get).toHaveBeenCalledWith(
      '/items',
      { ...filters, q: 'angry Cora', removed: ['anger'] },
      { preserveState: true, preserveScroll: true },
    )
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
        anomaly: '',
        actionability: '',
        sort: 'recent',
      }),
    ).toEqual({ sentiment: 'praise', range: '7d', overdue: '1' })
  })

  it('keeps an actionability band and a non-default sort', () => {
    expect(
      toQuery({
        product: '',
        sentiment: '',
        category: '',
        status: '',
        source: '',
        range: '',
        relevance: 'relevant',
        needs_review: false,
        overdue: false,
        anomaly: '',
        actionability: 'act_now',
        sort: 'actionability',
      }),
    ).toEqual({ actionability: 'act_now', sort: 'actionability' })
  })
})
