import { act, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { SearchProps } from '../../types/search'
import FeedSearch, { ENCODING_RELOAD_MS, SEARCH_DEBOUNCE_MS } from './feed-search'

const get = vi.fn()
const post = vi.fn()
const reload = vi.fn()

vi.mock('@inertiajs/react', () => ({
  router: {
    get: (...args: unknown[]) => get(...args),
    post: (...args: unknown[]) => post(...args),
    reload: (...args: unknown[]) => reload(...args),
  },
}))

function search(overrides: Partial<SearchProps> = {}): SearchProps {
  return {
    query: 'angry Cora billing this week',
    chips: [
      { key: 'anger', label: 'anger', kind: 'filter', name: 'Anger' },
      { key: 'product:cora', label: 'product', kind: 'boost', name: 'Product: cora' },
      { key: 'time', label: 'time', kind: 'time', name: 'This week' },
    ],
    relaxed_labels: [],
    relaxed_notice: null,
    removed: [],
    invite_row: null,
    encoding_status: 'cached',
    explicit_action: 'enter',
    run_id: null,
    ...overrides,
  }
}

describe('FeedSearch', () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => {
    vi.useRealTimers()
    vi.resetAllMocks()
  })

  it('searches as you type, once the typing pauses, keeping the feed filters', () => {
    render(<FeedSearch search={null} filterQuery={{ status: 'new' }} />)
    const input = screen.getByRole('searchbox', { name: 'Search the feed' })

    fireEvent.change(input, { target: { value: 'need' } })
    fireEvent.change(input, { target: { value: 'needs action now' } })
    act(() => vi.advanceTimersByTime(SEARCH_DEBOUNCE_MS - 1))
    expect(get).not.toHaveBeenCalled()

    act(() => vi.advanceTimersByTime(1))
    expect(get).toHaveBeenCalledTimes(1)
    expect(get).toHaveBeenCalledWith('/items', { status: 'new', q: 'needs action now' }, expect.objectContaining({ replace: true }))
  })

  it('clearing the box goes back to the plain feed', () => {
    render(<FeedSearch search={search()} filterQuery={{ status: 'new' }} />)

    fireEvent.change(screen.getByRole('searchbox'), { target: { value: '' } })
    act(() => vi.advanceTimersByTime(SEARCH_DEBOUNCE_MS))

    expect(get).toHaveBeenCalledWith('/items', { status: 'new' }, expect.anything())
  })

  it('shows filter and boost chips, and removing one searches again without it', () => {
    render(<FeedSearch search={search({ removed: ['mood:grumpy'] })} filterQuery={{}} />)

    expect(screen.getByText('This week')).toHaveAttribute('title', 'Only items with activity this week')
    expect(screen.getByText('Product: cora')).toHaveAttribute('title', 'Ranks items where product: cora higher')
    fireEvent.click(screen.getByRole('button', { name: 'Remove Anger' }))

    expect(get).toHaveBeenCalledWith(
      '/items',
      { q: 'angry Cora billing this week', removed: ['mood:grumpy', 'anger'] },
      expect.objectContaining({ preserveState: true }),
    )
  })

  it('a relaxed filter shows the notice and a dimmed chip that can still be removed', () => {
    const relaxed = search({
      query: 'cora email',
      chips: [
        { key: 'product:cora', label: 'product', kind: 'filter', name: 'Product: cora' },
        { key: 'source:email', label: 'source', kind: 'filter', name: 'Source: email', relaxed: true },
      ],
      relaxed_labels: ['source:email'],
      relaxed_notice: 'Nothing matched Source: email; showing results without it.',
    })
    render(<FeedSearch search={relaxed} filterQuery={{}} />)

    expect(screen.getByRole('status')).toHaveTextContent('Nothing matched Source: email; showing results without it.')
    const chips = screen.getAllByRole('listitem')
    expect(chips[0]).not.toHaveAttribute('data-relaxed')
    expect(chips[1]).toHaveAttribute('data-relaxed', 'true')
    expect(chips[1]).toHaveTextContent('Source: email (relaxed)')
    expect(screen.getByText(/^Source: email/)).toHaveAttribute('title', 'Nothing matched source: email, so it only ranks items higher')

    fireEvent.click(screen.getByRole('button', { name: 'Remove Source: email (relaxed)' }))
    expect(get).toHaveBeenCalledWith('/items', { q: 'cora email', removed: ['source:email'] }, expect.objectContaining({ preserveState: true }))
  })

  it('no notice without relaxed filters', () => {
    render(<FeedSearch search={search()} filterQuery={{}} />)

    expect(screen.queryByRole('status')).not.toBeInTheDocument()
    expect(screen.queryByText(/relaxed/)).not.toBeInTheDocument()
  })

  it('Enter starts a Smart search with the query, filters, and removed chips', () => {
    render(<FeedSearch search={search({ removed: ['time'] })} filterQuery={{ status: 'new' }} />)

    fireEvent.submit(screen.getByRole('search'))

    expect(post).toHaveBeenCalledWith(
      '/items/search',
      { status: 'new', q: 'angry Cora billing this week', removed: ['time'] },
      expect.anything(),
    )
    act(() => vi.advanceTimersByTime(SEARCH_DEBOUNCE_MS))
    expect(get).not.toHaveBeenCalled()
  })

  it('typing then pressing Enter before the pause starts only the Smart search', () => {
    render(<FeedSearch search={search()} filterQuery={{ status: 'new' }} />)

    fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'needs action now' } })
    act(() => vi.advanceTimersByTime(SEARCH_DEBOUNCE_MS - 50))
    fireEvent.submit(screen.getByRole('search'))
    act(() => vi.advanceTimersByTime(SEARCH_DEBOUNCE_MS * 2))

    expect(post).toHaveBeenCalledTimes(1)
    expect(post).toHaveBeenCalledWith('/items/search', { status: 'new', q: 'needs action now', removed: [] }, expect.anything())
    expect(get).not.toHaveBeenCalled()
  })

  it('Enter cancels a keystroke search still in flight so its response cannot land', () => {
    const cancel = vi.fn()
    get.mockImplementation((_url: string, _data: unknown, options: { onCancelToken?: (token: { cancel: () => void }) => void }) => {
      options.onCancelToken?.({ cancel })
    })
    render(<FeedSearch search={null} filterQuery={{}} />)

    fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'needs action' } })
    act(() => vi.advanceTimersByTime(SEARCH_DEBOUNCE_MS))
    expect(get).toHaveBeenCalledTimes(1)
    fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'needs action now' } })
    fireEvent.submit(screen.getByRole('search'))
    act(() => vi.advanceTimersByTime(SEARCH_DEBOUNCE_MS * 2))

    expect(cancel).toHaveBeenCalledTimes(1)
    expect(get).toHaveBeenCalledTimes(1)
    expect(post).toHaveBeenCalledWith('/items/search', { q: 'needs action now', removed: [] }, expect.anything())
  })

  it('reloads the results while the query is still being read', () => {
    render(<FeedSearch search={search({ chips: [], encoding_status: 'pending' })} filterQuery={{}} />)

    expect(screen.getByRole('status')).toHaveTextContent('Reading your search')
    act(() => vi.advanceTimersByTime(ENCODING_RELOAD_MS))
    expect(reload).toHaveBeenCalledWith({ only: ['items', 'search'] })
  })

  it('invites a Smart search when keyword results are thin', () => {
    render(<FeedSearch search={search({ invite_row: { query: 'angry Cora billing', reason: 'weak' } })} filterQuery={{}} />)

    fireEvent.click(screen.getByRole('button', { name: /Jev read the feed for “angry Cora billing this week”/ }))

    expect(post).toHaveBeenCalledWith('/items/search', expect.objectContaining({ q: 'angry Cora billing this week' }), expect.anything())
  })
})
