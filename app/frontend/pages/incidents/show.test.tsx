import { fireEvent, render, screen } from '@testing-library/react'
import { type ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { anomaly } from '../../test/anomaly-fixture'
import type { IncidentProps } from '../../types/incidents'
import IncidentShow from './show'

const patch = vi.fn()
const setData = vi.fn()
let formData = { note: '', handle_items: false }

vi.mock('@inertiajs/react', () => ({
  Head: () => null,
  usePage: () => ({ url: '/incidents/4', props: { flash: {} } }),
  useForm: () => ({ data: formData, setData, patch, processing: false }),
  Link: ({ href, children, ...rest }: { href: string; children: ReactNode }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}))

function incident(overrides: Partial<IncidentProps> = {}): IncidentProps {
  return {
    id: 4,
    product: { id: 3, slug: 'cora', name: 'Cora' },
    status: 'open',
    opened_at: '2026-09-30T13:00:00Z',
    last_anomaly_at: '2026-09-30T13:30:00Z',
    resolved_at: null,
    resolved_by: null,
    resolution_note: null,
    items_handled: false,
    item_ids: [7, 8],
    sources: [
      { id: 1, kind: 'intercom', name: 'Intercom' },
      { id: 2, kind: 'discord', name: 'Discord' },
    ],
    slack_posted: true,
    url: 'http://localhost:3000/incidents/4',
    anomalies: [anomaly({ incident_id: 4 })],
    ...overrides,
  }
}

describe('IncidentShow', () => {
  beforeEach(() => {
    patch.mockClear()
    setData.mockClear()
    formData = { note: '', handle_items: false }
  })

  it('shows what spiked and the sources, without linking back to itself', () => {
    render(<IncidentShow incident={incident()} />)

    expect(screen.getByRole('heading', { name: 'Cora incident' })).toBeInTheDocument()
    expect(screen.getByText('Open')).toBeInTheDocument()
    expect(screen.getByText(/Intercom, Discord/)).toBeInTheDocument()
    expect(screen.getByText('Bug messages')).toBeInTheDocument()
    expect(screen.queryByRole('link', { name: /Resolve incident|Incident/ })).not.toBeInTheDocument()
  })

  it('resolves with an optional note and an items checkbox that defaults off', () => {
    render(<IncidentShow incident={incident()} />)

    const checkbox = screen.getByRole('checkbox', { name: /mark the driving items/ })
    expect(checkbox).not.toBeChecked()
    fireEvent.click(checkbox)
    expect(setData).toHaveBeenCalledWith('handle_items', true)
    fireEvent.change(screen.getByLabelText('Resolution note'), { target: { value: 'Fixed' } })
    expect(setData).toHaveBeenCalledWith('note', 'Fixed')
    fireEvent.click(screen.getByRole('button', { name: 'Resolve incident' }))
    expect(patch).toHaveBeenCalledWith('/incidents/4/resolve', { preserveScroll: true })
  })

  it('shows who resolved it and hides the form once resolved', () => {
    render(
      <IncidentShow
        incident={incident({ status: 'resolved', resolved_at: '2026-09-30T14:00:00Z', resolved_by: 'Ana Every', resolution_note: 'IMAP sync fixed', items_handled: true })}
      />,
    )

    const resolution = screen.getByRole('region', { name: 'Resolution' })
    expect(resolution).toHaveTextContent('Resolved by Ana Every')
    expect(resolution).toHaveTextContent('driving items marked handled')
    expect(resolution).toHaveTextContent('IMAP sync fixed')
    expect(screen.queryByRole('button', { name: 'Resolve incident' })).not.toBeInTheDocument()
  })
})
