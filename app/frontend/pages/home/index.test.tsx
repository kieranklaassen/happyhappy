import { render, screen } from '@testing-library/react'
import { type ReactNode } from 'react'
import { describe, expect, it, vi } from 'vitest'
import { anomaly } from '../../test/anomaly-fixture'
import Home, { headline } from './index'
import type { MoodDashboardProps } from '../../types/mood'

vi.mock('@inertiajs/react', () => ({
  Head: () => null,
  Link: ({ href, children, preserveScroll: _preserveScroll, ...rest }: { href: string; children: ReactNode; preserveScroll?: boolean }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
  usePage: () => ({ url: '/' }),
  usePoll: vi.fn(),
  router: { reload: vi.fn() },
}))

vi.mock('@rails/actioncable', () => ({
  createConsumer: () => ({
    subscriptions: { create: () => ({ unsubscribe: vi.fn() }) },
    disconnect: vi.fn(),
  }),
}))

const counts = { beaming: 1, content: 0, relieved: 0, meh: 0, grumpy: 0, furious: 1, pending: 0 }

const props: MoodDashboardProps = {
  scene: [
    {
      product: { slug: 'cora', name: 'Cora', retired: false },
      mood: 'meh',
      counts,
      overflow: 0,
      characters: [
        {
          key: 'cora-a',
          seed: 'a1',
          item_id: 3,
          name: 'Ana Customer',
          handle: '@ana',
          mood: 'furious',
          sentiment: 'complaint',
          anger: 0.9,
          source_kind: 'slack',
          status: 'new',
          threads: 1,
          excerpt: 'Cora replied to my boss with a haiku.',
          last_message_at: new Date().toISOString(),
          mended: false,
        },
      ],
    },
  ],
  today: { range: '24h', mood: 'meh', people: 2, counts, smiling: 1, relieved: 0, grumpy: 1, updated_at: new Date().toISOString() },
  filters: { range: '24h', product: null },
  options: { ranges: ['24h', '7d'], products: [{ slug: 'cora', name: 'Cora' }] },
}

describe('Home mood dashboard', () => {
  it('summarizes today in words', () => {
    render(<Home {...props} />)

    expect(screen.getByRole('heading', { level: 1, name: 'How is everyone feeling?' })).toBeInTheDocument()
    expect(screen.getByText(/1 smiling, 0 meh, and 1 grumpy across 2 people in the last 24 hours/)).toBeInTheDocument()
    expect(screen.getByText('A bit of a shrug today.')).toBeInTheDocument()
  })

  it('counts relieved customers among the smiling and in the legend', () => {
    const today = { ...props.today, counts: { ...props.today.counts, relieved: 2 }, smiling: 3, relieved: 2 }
    render(<Home {...props} today={today} />)

    expect(screen.getByText(/3 smiling \(2 relieved\), 0 meh, and 1 grumpy/)).toBeInTheDocument()
    expect(screen.getByText('2 relieved')).toBeInTheDocument()
  })

  it('draws a meadow per product and offers filters', () => {
    render(<Home {...props} />)

    expect(screen.getByRole('heading', { level: 2, name: 'Cora' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Everyone' })).toHaveAttribute('aria-current', 'page')
    expect(screen.getByRole('link', { name: 'Cora' })).toHaveAttribute('href', '/?product=cora')
    expect(screen.getByRole('link', { name: 'This week' })).toHaveAttribute('href', '/?range=7d')
  })

  it('offers the crowd as a readable list', () => {
    render(<Home {...props} />)

    expect(screen.getByText('Read the crowd as a list')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Ana Customer' })).toHaveAttribute('href', '/items/3')
  })

  it('shows an empty meadow with a way to look further back', () => {
    render(<Home {...props} scene={[]} today={{ ...props.today, mood: null, people: 0 }} />)

    expect(screen.getByRole('heading', { name: 'The meadow is empty' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'See the last 7 days' })).toHaveAttribute('href', '/?range=7d')
  })
})

describe('headline', () => {
  it('has a line for every overall mood', () => {
    expect(headline('furious')).toBe('Stormy. Grab an umbrella.')
    expect(headline('relieved')).toBe('The clouds are clearing.')
    expect(headline(null)).toBe('Quiet so far.')
  })

  it('puts an anomaly callout on the affected product meadow', () => {
    render(<Home {...props} anomalies={{ cora: [anomaly()] }} />)

    const meadow = screen.getByRole('region', { name: 'Cora' })
    expect(meadow).toContainElement(screen.getByRole('complementary', { name: 'Storm warning for Cora' }))
  })
})
