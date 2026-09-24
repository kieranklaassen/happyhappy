import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { type ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { DeliveryRow } from '../../lib/webhooks'
import WebhookEndpointShow from './show'

const post = vi.fn()
const patch = vi.fn()
const destroy = vi.fn()

vi.mock('@inertiajs/react', () => ({
  Head: () => null,
  usePage: () => ({
    url: '/webhook_endpoints/1',
    props: { flash: { alert: 'Test event failed: HTTP 404: no such hook' } },
  }),
  router: {
    post: (...args: unknown[]) => post(...args),
    patch: (...args: unknown[]) => patch(...args),
    delete: (...args: unknown[]) => destroy(...args),
  },
  Link: ({ href, children, ...rest }: { href: string; children: ReactNode }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}))

const endpoint = {
  id: 1,
  name: 'Support bot',
  url: 'https://bot.example.com/hook',
  active: true,
  events: ['item.escalated' as const],
  product_ids: [1],
  category_ids: [],
  sentiments: [],
  last_delivery: null,
  secret: 'whsec_topsecret',
}

const deliveries: DeliveryRow[] = [
  {
    id: 2,
    event: 'webhook.test',
    status: 'failed',
    attempts: 1,
    response_code: 404,
    last_error: 'HTTP 404: no such hook',
    test: true,
    item_event_id: null,
    item_id: null,
    created_at: '2026-09-24T11:00:00Z',
    last_attempted_at: '2026-09-24T11:00:00Z',
  },
  {
    id: 1,
    event: 'item.escalated',
    status: 'pending',
    attempts: 2,
    response_code: 500,
    last_error: 'HTTP 500: upstream',
    test: false,
    item_event_id: 7,
    item_id: 42,
    created_at: '2026-09-24T10:00:00Z',
    last_attempted_at: '2026-09-24T10:03:00Z',
  },
]

const filters = { products: ['Cora'], categories: [], sentiments: [] }

describe('Webhook endpoint page', () => {
  beforeEach(() => {
    post.mockClear()
    patch.mockClear()
    destroy.mockClear()
  })

  it('lists recent deliveries with their result and last error', () => {
    render(<WebhookEndpointShow endpoint={endpoint} filters={filters} deliveries={deliveries} />)

    expect(screen.getByText('Test send')).toBeInTheDocument()
    expect(screen.getByText('Retrying')).toBeInTheDocument()
    expect(screen.getByText('HTTP 500')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: '#42' })).toHaveAttribute('href', '/items/42')
    expect(screen.getByText('HTTP 500: upstream')).toBeInTheDocument()
    expect(screen.getByRole('alert')).toHaveTextContent('Test event failed')
    expect(screen.getByText('Cora')).toBeInTheDocument()
  })

  it('hides the secret until revealed', async () => {
    const user = userEvent.setup()
    render(<WebhookEndpointShow endpoint={endpoint} filters={filters} deliveries={[]} />)

    expect(screen.getByTestId('endpoint-secret')).not.toHaveTextContent('whsec_topsecret')
    await user.click(screen.getByRole('button', { name: 'Reveal' }))
    expect(screen.getByTestId('endpoint-secret')).toHaveTextContent('whsec_topsecret')
  })

  it('sends a test event', async () => {
    const user = userEvent.setup()
    render(<WebhookEndpointShow endpoint={endpoint} filters={filters} deliveries={[]} />)

    await user.click(screen.getByRole('button', { name: 'Send test event' }))

    expect(post).toHaveBeenCalledWith('/webhook_endpoints/1/test_send', {}, expect.any(Object))
  })

  it('rotates the secret and deletes only after confirmation', async () => {
    const user = userEvent.setup()
    vi.spyOn(window, 'confirm').mockReturnValue(true)
    render(<WebhookEndpointShow endpoint={endpoint} filters={filters} deliveries={[]} />)

    await user.click(screen.getByRole('button', { name: 'Rotate' }))
    await user.click(screen.getByRole('button', { name: 'Delete' }))

    expect(patch).toHaveBeenCalledWith('/webhook_endpoints/1/rotate_secret')
    expect(destroy).toHaveBeenCalledWith('/webhook_endpoints/1')
  })
})
