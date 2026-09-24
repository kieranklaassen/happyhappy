import { render, screen, within } from '@testing-library/react'
import { type ReactNode } from 'react'
import { describe, expect, it, vi } from 'vitest'
import SourcesIndex, { type SourceRow, sourceHealth } from './index'

vi.mock('@inertiajs/react', () => ({
  Head: () => null,
  usePage: () => ({ url: '/sources', props: { flash: {} } }),
  Link: ({ href, children, ...rest }: { href: string; children: ReactNode }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}))

function row(overrides: Partial<SourceRow>): SourceRow {
  return {
    id: 1,
    kind: 'slack',
    name: 'Every community Slack #cora',
    selector: 'C0COMMUNITY',
    status: 'active',
    default_product_name: 'Cora',
    last_message_at: '2026-09-24T12:00:00Z',
    last_error: null,
    last_error_at: null,
    monthly_limit: null,
    month_spend: null,
    ...overrides,
  }
}

describe('Sources index', () => {
  it('shows health, default product, and the latest error for each source', () => {
    render(
      <SourcesIndex
        sources={[
          row({ id: 1 }),
          row({
            id: 2,
            name: 'Old Lex channel',
            default_product_name: null,
            last_message_at: null,
            last_error: 'Slack: channel_not_found',
          }),
        ]}
      />,
    )

    const healthy = within(screen.getByRole('listitem', { name: 'Every community Slack #cora' }))
    expect(healthy.getByText('Connected')).toBeInTheDocument()
    expect(healthy.getByText(/Default product: Cora/)).toBeInTheDocument()
    expect(healthy.queryByText(/Latest error/)).not.toBeInTheDocument()

    const broken = within(screen.getByRole('listitem', { name: 'Old Lex channel' }))
    expect(broken.getByText('Error')).toBeInTheDocument()
    expect(broken.getByText(/Default product: none · Last message: Never/)).toBeInTheDocument()
    expect(broken.getByText(/Latest error: Slack: channel_not_found/)).toBeInTheDocument()
    expect(broken.getByRole('link', { name: 'Edit' })).toHaveAttribute('href', '/sources/2/edit')
  })

  it('shows X spend against the monthly limit and the paused-for-budget badge', () => {
    render(
      <SourcesIndex
        sources={[
          row({ id: 3, kind: 'x', name: 'X mentions', monthly_limit: 50, month_spend: 12.5 }),
          row({ id: 4, kind: 'x', name: 'X search for Spiral', status: 'paused_for_budget', monthly_limit: 10, month_spend: 10 }),
        ]}
      />,
    )

    const mentions = within(screen.getByRole('listitem', { name: 'X mentions' }))
    expect(mentions.getByText('$12.50 of $50.00 this month')).toBeInTheDocument()
    expect(mentions.getByText('Connected')).toBeInTheDocument()

    const paused = within(screen.getByRole('listitem', { name: 'X search for Spiral' }))
    expect(paused.getByText('Paused for budget')).toBeInTheDocument()
    expect(paused.getByText('$10.00 of $10.00 this month')).toBeInTheDocument()
  })

  it('does not show spend for non-X sources', () => {
    render(<SourcesIndex sources={[row({ id: 5 })]} />)

    expect(screen.queryByText(/this month/)).not.toBeInTheDocument()
  })

  it('invites adding a source when there are none', () => {
    render(<SourcesIndex sources={[]} />)

    expect(screen.getByText(/No sources yet/)).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Add source' })).toHaveAttribute('href', '/sources/new')
  })
})

describe('sourceHealth', () => {
  it('maps every status to a label', () => {
    expect(sourceHealth({ status: 'active', last_error: null }).label).toBe('Connected')
    expect(sourceHealth({ status: 'active', last_error: 'boom' }).label).toBe('Error')
    expect(sourceHealth({ status: 'paused', last_error: null }).label).toBe('Paused')
    expect(sourceHealth({ status: 'paused_for_budget', last_error: null }).label).toBe('Paused for budget')
  })
})
