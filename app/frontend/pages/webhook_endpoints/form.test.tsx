import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { type ReactNode, useState } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { WebhookEvent } from '../../lib/webhooks'
import WebhookEndpointForm from './form'

const submissions: { method: string; url: string; payload: unknown }[] = []

vi.mock('@inertiajs/react', () => ({
  Head: () => null,
  usePage: () => ({ url: '/webhook_endpoints/new', props: { flash: {} } }),
  Link: ({ href, children, ...rest }: { href: string; children: ReactNode }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
  useForm: <T extends Record<string, unknown>>(initial: T) => {
    const [data, setDataState] = useState(initial)
    let transformer = (value: T): unknown => value
    return {
      data,
      errors: {},
      processing: false,
      setData: (key: keyof T, value: unknown) => setDataState((current) => ({ ...current, [key]: value })),
      transform: (fn: (value: T) => unknown) => {
        transformer = fn
      },
      post: (url: string) => submissions.push({ method: 'post', url, payload: transformer(data) }),
      patch: (url: string) => submissions.push({ method: 'patch', url, payload: transformer(data) }),
    }
  },
}))

const events: WebhookEvent[] = ['item.arrived', 'item.classified', 'item.status_changed', 'item.escalated', 'agent.reported']
const options = {
  events,
  products: [
    { id: 1, name: 'Cora' },
    { id: 2, name: 'Spiral' },
  ],
  categories: [{ id: 5, name: 'bug' }],
  sentiments: ['complaint', 'praise', 'question', 'neutral'],
}

describe('Webhook endpoint form', () => {
  beforeEach(() => {
    submissions.length = 0
  })

  it('submits a new endpoint with its events and filters', async () => {
    const user = userEvent.setup()
    render(
      <WebhookEndpointForm
        endpoint={{
          id: null,
          name: null,
          url: null,
          active: true,
          events: ['item.classified'],
          product_ids: [],
          category_ids: [],
          sentiments: [],
        }}
        {...options}
      />,
    )

    await user.type(screen.getByLabelText('Name'), 'Support bot')
    await user.type(screen.getByLabelText('URL'), 'https://bot.example.com/hook')
    await user.click(screen.getByLabelText('Escalated'))
    await user.click(screen.getByLabelText('Item classified'))
    await user.click(screen.getByLabelText('Spiral'))
    await user.click(screen.getByLabelText('complaint'))
    await user.click(screen.getByRole('button', { name: 'Create endpoint' }))

    expect(submissions).toEqual([
      {
        method: 'post',
        url: '/webhook_endpoints',
        payload: {
          webhook_endpoint: {
            name: 'Support bot',
            url: 'https://bot.example.com/hook',
            active: true,
            events: ['item.escalated'],
            product_ids: [2],
            category_ids: [],
            sentiments: ['complaint'],
          },
        },
      },
    ])
  })

  it('says when there are no products or categories to filter by', () => {
    render(
      <WebhookEndpointForm
        endpoint={{
          id: null,
          name: null,
          url: null,
          active: true,
          events: ['item.classified'],
          product_ids: [],
          category_ids: [],
          sentiments: [],
        }}
        {...options}
        products={[]}
        categories={[]}
      />,
    )

    expect(screen.getAllByText('None set up yet.')).toHaveLength(2)
  })

  it('updates an existing endpoint and can deactivate it', async () => {
    const user = userEvent.setup()
    render(
      <WebhookEndpointForm
        endpoint={{
          id: 3,
          name: 'Ops',
          url: 'https://ops.example.com',
          active: true,
          events: ['item.escalated'],
          product_ids: [1],
          category_ids: [],
          sentiments: [],
        }}
        {...options}
      />,
    )

    expect(screen.getByLabelText('Cora')).toBeChecked()
    await user.click(screen.getByLabelText('Active'))
    await user.click(screen.getByRole('button', { name: 'Save endpoint' }))

    expect(submissions[0]).toMatchObject({
      method: 'patch',
      url: '/webhook_endpoints/3',
      payload: { webhook_endpoint: { active: false, product_ids: [1] } },
    })
  })
})
