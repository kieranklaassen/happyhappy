import { render, screen } from '@testing-library/react'
import { type ReactNode } from 'react'
import { describe, expect, it, vi } from 'vitest'
import type { DeliveryRow, EndpointRow } from '../../lib/webhooks'
import WebhookEndpointsIndex from './index'

vi.mock('@inertiajs/react', () => ({
  Head: () => null,
  usePage: () => ({ url: '/webhook_endpoints', props: { flash: { notice: 'Ops hook deleted.' } } }),
  Link: ({ href, children, ...rest }: { href: string; children: ReactNode }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}))

const failed: DeliveryRow = {
  id: 9,
  event: 'item.classified',
  status: 'failed',
  attempts: 8,
  response_code: 500,
  last_error: 'HTTP 500: nope',
  test: false,
  item_event_id: 3,
  item_id: 4,
  created_at: '2026-09-24T10:00:00Z',
  last_attempted_at: '2026-09-24T12:00:00Z',
}

const endpoints: EndpointRow[] = [
  {
    id: 1,
    name: 'Support bot',
    url: 'https://bot.example.com/hook',
    active: true,
    events: ['item.classified', 'agent.reported'],
    product_ids: [1],
    category_ids: [],
    sentiments: ['complaint'],
    last_delivery: failed,
  },
  {
    id: 2,
    name: 'Archive',
    url: 'https://archive.example.com/hook',
    active: false,
    events: ['item.arrived'],
    product_ids: [],
    category_ids: [],
    sentiments: [],
    last_delivery: null,
  },
]

describe('Webhook endpoints page', () => {
  it('lists endpoints with their events, filters, and last delivery', () => {
    render(<WebhookEndpointsIndex endpoints={endpoints} />)

    expect(screen.getByRole('link', { name: 'Support bot' })).toHaveAttribute('href', '/webhook_endpoints/1')
    expect(screen.getByText('https://bot.example.com/hook')).toBeInTheDocument()
    expect(screen.getByText(/Item classified, Agent reported · 2 filters/)).toBeInTheDocument()
    expect(screen.getByText('Failed')).toBeInTheDocument()
    expect(screen.getByText('Inactive')).toBeInTheDocument()
    expect(screen.getByText('No deliveries yet')).toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent('Ops hook deleted.')
  })

  it('links to add an endpoint and explains the empty state', () => {
    render(<WebhookEndpointsIndex endpoints={[]} />)

    expect(screen.getByRole('link', { name: 'Add endpoint' })).toHaveAttribute('href', '/webhook_endpoints/new')
    expect(screen.getByText('No endpoints yet.')).toBeInTheDocument()
  })
})
