import { render, screen, within } from '@testing-library/react'
import { type ReactNode } from 'react'
import { describe, expect, it, vi } from 'vitest'
import type { ItemRowData } from '../../types/items'
import type { SmartProps } from '../../types/search'
import SmartResults from './smart-results'

vi.mock('@inertiajs/react', () => ({
  router: { reload: vi.fn() },
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

function row(id: number, excerpt: string): ItemRowData & { score: number } {
  return {
    id,
    excerpt,
    author: 'bo',
    source: { id: 1, name: 'Intercom', kind: 'intercom' },
    product: null,
    category: null,
    sentiment: 'complaint',
    status: 'new',
    relevant: true,
    needs_review: false,
    overdue: false,
    claimed_by: null,
    anger_probability: 0.9,
    actionability: null,
    actionability_band: null,
    last_message_at: '2026-09-24T10:00:00Z',
    score: 0.9,
  }
}

function smart(overrides: Partial<SmartProps> = {}): SmartProps {
  return {
    run_id: 'run-1',
    status: 'running',
    reserved_slots: 40,
    paused: false,
    pending: { strong: true, possible: true, unlikely: true },
    collapsed: ['unlikely'],
    no_strong_matches: false,
    buckets: { strong: [row(1, 'Charged twice for Cora')], possible: [], unlikely: [row(2, 'Lunch?')] },
    ...overrides,
  }
}

describe('SmartResults', () => {
  it('streams strong matches first, with skeletons for buckets still pending and Unlikely collapsed', () => {
    render(<SmartResults smart={smart()} />)

    expect(screen.getByRole('status')).toHaveTextContent('Jev is reading the top 40 matches')
    expect(within(screen.getByRole('region', { name: 'Strong matches' })).getByText('Charged twice for Cora')).toBeInTheDocument()
    expect(screen.getByText('Unlikely (1)').closest('details')).not.toHaveAttribute('open')
  })

  it('says so when a finished run found no strong matches', () => {
    render(
      <SmartResults
        smart={smart({
          status: 'complete',
          pending: { strong: false, possible: false, unlikely: false },
          no_strong_matches: true,
          buckets: { strong: [], possible: [], unlikely: [] },
        })}
      />,
    )

    expect(screen.getByRole('status')).toHaveTextContent('Done')
    expect(screen.getByText(/No strong matches/)).toBeInTheDocument()
    expect(screen.queryByText(/Unlikely/)).not.toBeInTheDocument()
  })

  it('an ended run shows no buckets and offers to run it again', () => {
    render(<SmartResults smart={smart({ status: 'expired' })} />)

    expect(screen.getByRole('status')).toHaveTextContent('Press Enter to run it again')
    expect(screen.queryByText('Charged twice for Cora')).not.toBeInTheDocument()
  })
})
