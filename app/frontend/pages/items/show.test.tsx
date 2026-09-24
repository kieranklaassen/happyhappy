import { fireEvent, render, screen } from '@testing-library/react'
import { type ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import ItemShow, { type ItemShowProps } from './show'

const patch = vi.fn()
const page = { url: '/items/7', props: { flash: {} as { notice?: string; alert?: string } } }

vi.mock('@inertiajs/react', () => ({
  Head: () => null,
  usePage: () => page,
  router: { patch: (...args: unknown[]) => patch(...args) },
  Link: ({ href, children, ...rest }: { href: string; children: ReactNode }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}))

function props(): ItemShowProps {
  return {
    item: {
      id: 7,
      author: 'dee_posts',
      author_name: null,
      author_email: null,
      permalink: 'https://x.com/dee_posts/status/1',
      source: { id: 2, name: 'X mentions', kind: 'x' },
      status: 'claimed',
      needs_review: true,
      overdue: true,
      claimed_by: 'Cursor',
      claimed_at: '2026-09-24T08:00:00Z',
      last_reported_at: null,
      last_message_at: '2026-09-24T10:00:00Z',
      anger_probability: 0.1,
      labels: {
        product: { value: { id: 5, name: 'Sparkle', slug: 'sparkle', retired: false }, probability: 0.45, human_set: false },
        category: { value: { id: 6, name: 'other', retired: false }, probability: 0.5, human_set: true },
        sentiment: { value: 'neutral', probability: 0.7, human_set: false },
        relevant: { value: true, probability: 0.8, human_set: false },
      },
    },
    messages: [
      { id: 1, body: 'Trying out that new file organizer.', occurred_at: '2026-09-24T10:00:00Z', anger_probability: 0.1, classified: true },
    ],
    events: [
      { id: 1, kind: 'arrived', actor: { type: null, name: 'happyhappy' }, data: {}, created_at: '2026-09-24T10:00:00Z' },
      {
        id: 2,
        kind: 'corrected',
        actor: { type: 'User', name: 'Ana Every' },
        data: { label: 'category', from: 'bug', to: 'other' },
        created_at: '2026-09-24T10:05:00Z',
      },
    ],
    options: {
      products: [
        { id: 3, name: 'Cora', slug: 'cora', retired: false },
        { id: 5, name: 'Sparkle', slug: 'sparkle', retired: false },
      ],
      categories: [{ id: 6, name: 'other', retired: false }],
      sentiments: ['complaint', 'praise', 'question', 'neutral'],
      statuses: ['new', 'handled', 'dismissed'],
    },
    low_confidence_threshold: 0.6,
  }
}

describe('Item page', () => {
  beforeEach(() => {
    patch.mockClear()
    page.props.flash = {}
  })

  it('shows messages, badges, and the timeline in order with actor names', () => {
    render(<ItemShow {...props()} />)

    expect(screen.getByRole('heading', { level: 1, name: 'dee_posts' })).toBeInTheDocument()
    expect(screen.getByText('Trying out that new file organizer.')).toBeInTheDocument()
    expect(screen.getByText('Overdue')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Open original' })).toHaveAttribute('href', 'https://x.com/dee_posts/status/1')
    const entries = screen.getAllByRole('listitem').map((item) => item.textContent)
    const arrived = entries.findIndex((text) => text?.includes('Message arrived'))
    const corrected = entries.findIndex((text) => text?.includes('Ana Every · Changed category from bug to other'))
    expect(arrived).toBeGreaterThanOrEqual(0)
    expect(corrected).toBeGreaterThan(arrived)
  })

  it('flags low-confidence labels and marks human-set ones', () => {
    render(<ItemShow {...props()} />)

    expect(screen.getAllByText('Low confidence')).toHaveLength(1)
    expect(screen.getByText('Confidence 45%')).toBeInTheDocument()
    expect(screen.getByText('Human set')).toBeInTheDocument()
  })

  it('submits a product correction', () => {
    render(<ItemShow {...props()} />)

    const save = screen.getByRole('button', { name: 'Save product' })
    expect(save).toBeDisabled()
    fireEvent.change(screen.getByLabelText('Correct product'), { target: { value: '3' } })
    fireEvent.click(save)

    expect(patch).toHaveBeenCalledWith('/items/7/labels', { label: 'product', value: '3' }, expect.any(Object))
  })

  it('changes status with the offered actions and warns about releasing the claim', () => {
    render(<ItemShow {...props()} />)

    expect(screen.getByText(/releases the agent’s claim/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Mark dismissed' }))

    expect(patch).toHaveBeenCalledWith('/items/7/status', { status: 'dismissed' }, { preserveScroll: true })
    expect(screen.getByRole('button', { name: 'Reopen' })).toBeInTheDocument()
  })

  it('surfaces flash notices and alerts', () => {
    page.props.flash = { notice: 'Product set to Cora.', alert: 'Lex is retired' }
    render(<ItemShow {...props()} />)

    expect(screen.getByRole('status')).toHaveTextContent('Product set to Cora.')
    expect(screen.getByRole('alert')).toHaveTextContent('Lex is retired')
  })
})
