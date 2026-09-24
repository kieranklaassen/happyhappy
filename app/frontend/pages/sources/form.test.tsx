import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { type ReactNode, useState } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import SourceForm from './form'

const submissions: { method: string; url: string; payload: unknown }[] = []

const routerCalls: { url: string; options: unknown }[] = []

vi.mock('@inertiajs/react', () => ({
  Head: () => null,
  router: {
    patch: (url: string, _data: unknown, options: unknown) => routerCalls.push({ url, options }),
  },
  usePage: () => ({ url: '/sources/new', props: { flash: {} } }),
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

const kinds = ['slack', 'discord', 'intercom', 'email', 'x', 'custom'] as const
const products = [
  { id: 1, name: 'Cora' },
  { id: 2, name: 'Spiral' },
]
const blank = { id: null, kind: null, name: null, selector: null, default_product_id: null, monthly_limit: null }

describe('Source form', () => {
  beforeEach(() => {
    submissions.length = 0
    routerCalls.length = 0
  })

  it('labels the selector for the chosen kind and shows the monthly limit only for X', async () => {
    const user = userEvent.setup()
    render(<SourceForm source={blank} kinds={[...kinds]} products={products} />)

    expect(screen.getByLabelText('Slack channel id')).toBeInTheDocument()
    expect(screen.queryByLabelText('Monthly limit (USD)')).not.toBeInTheDocument()

    await user.selectOptions(screen.getByLabelText('Kind'), 'intercom')
    expect(screen.getByLabelText('Intercom inbox or team id')).toBeInTheDocument()

    await user.selectOptions(screen.getByLabelText('Kind'), 'email')
    expect(screen.getByLabelText('Inbound address')).toBeInTheDocument()

    await user.selectOptions(screen.getByLabelText('Kind'), 'x')
    expect(screen.getByLabelText('X search query')).toBeInTheDocument()
    expect(screen.getByLabelText('Monthly limit (USD)')).toBeInTheDocument()
  })

  it('submits a new X source with no default product', async () => {
    const user = userEvent.setup()
    render(<SourceForm source={blank} kinds={[...kinds]} products={products} />)

    await user.selectOptions(screen.getByLabelText('Kind'), 'x')
    await user.type(screen.getByLabelText('Name'), 'X search')
    await user.type(screen.getByLabelText('X search query'), 'spiral app')
    await user.type(screen.getByLabelText('Monthly limit (USD)'), '25')
    await user.click(screen.getByRole('button', { name: 'Create source' }))

    expect(submissions).toEqual([
      {
        method: 'post',
        url: '/sources',
        payload: {
          source: { kind: 'x', name: 'X search', selector: 'spiral app', default_product_id: '', monthly_limit: '25' },
        },
      },
    ])
  })

  it('locks the kind when editing and leaves it out of the update', async () => {
    const user = userEvent.setup()
    render(
      <SourceForm
        source={{ id: 7, kind: 'discord', name: 'Spiral Discord', selector: '110', default_product_id: 2, monthly_limit: null }}
        kinds={[...kinds]}
        products={products}
      />,
    )

    expect(screen.getByLabelText('Kind')).toBeDisabled()
    expect(screen.getByLabelText('Default product')).toHaveValue('2')

    await user.click(screen.getByRole('button', { name: 'Save source' }))

    expect(submissions).toEqual([
      {
        method: 'patch',
        url: '/sources/7',
        payload: { source: { name: 'Spiral Discord', selector: '110', default_product_id: '2', monthly_limit: '' } },
      },
    ])
  })

  it('hides the selector for a custom webhook and requires a product', async () => {
    const user = userEvent.setup()
    render(<SourceForm source={blank} kinds={[...kinds]} products={products} />)

    await user.selectOptions(screen.getByLabelText('Kind'), 'custom')
    expect(screen.queryByLabelText('Webhook token')).not.toBeInTheDocument()
    expect(screen.getByLabelText('Default product')).toBeRequired()
    expect(screen.queryByRole('region', { name: 'Webhook' })).not.toBeInTheDocument()

    await user.type(screen.getByLabelText('Name'), 'Cora app')
    await user.selectOptions(screen.getByLabelText('Default product'), '1')
    await user.click(screen.getByRole('button', { name: 'Create source' }))

    expect(submissions[0].payload).toEqual({
      source: { kind: 'custom', name: 'Cora app', selector: '', default_product_id: '1', monthly_limit: '' },
    })
  })

  it('shows the webhook URL, reveals the secret, and rotates it after confirmation', async () => {
    const user = userEvent.setup()
    const confirm = vi.spyOn(window, 'confirm').mockReturnValueOnce(false).mockReturnValueOnce(true)
    render(
      <SourceForm
        source={{ id: 9, kind: 'custom', name: 'Cora app', selector: 'tok', default_product_id: 1, monthly_limit: null }}
        kinds={[...kinds]}
        products={products}
        webhook={{ url: 'https://happyhappy.test/webhooks/custom/tok', signing_secret: 'hhsec_abc' }}
      />,
    )

    expect(screen.getByLabelText('Webhook URL')).toHaveValue('https://happyhappy.test/webhooks/custom/tok')
    const secret = screen.getByLabelText('Signing secret')
    expect(secret).toHaveAttribute('type', 'password')
    await user.click(screen.getByRole('button', { name: 'Show' }))
    expect(secret).toHaveAttribute('type', 'text')
    expect(secret).toHaveValue('hhsec_abc')

    await user.click(screen.getByRole('button', { name: 'Rotate secret' }))
    expect(routerCalls).toEqual([])
    await user.click(screen.getByRole('button', { name: 'Rotate secret' }))
    expect(routerCalls.map((call) => call.url)).toEqual(['/sources/9/rotate_secret'])
    confirm.mockRestore()
  })
})
