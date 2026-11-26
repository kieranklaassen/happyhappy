import { router } from '@inertiajs/react'
import { fireEvent, render, screen, within } from '@testing-library/react'
import { type ComponentProps, type ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import ProductsIndex from './index'

const page = vi.hoisted(() => ({ flash: {} as { notice?: string; alert?: string } }))

vi.mock('@inertiajs/react', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@inertiajs/react')>()),
  Head: ({ title }: { title: string }) => <title>{title}</title>,
  usePage: () => ({ url: '/products', props: { flash: page.flash } }),
  Link: ({ href, children, ...rest }: { href: string; children: ReactNode }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}))

type Props = ComponentProps<typeof ProductsIndex>
type Product = Props['products'][number]

const cora: Product = {
  id: 7,
  name: 'Cora',
  slug: 'cora-mail',
  description: 'Email assistant.',
  hint_words: ['brief', 'inbox zero'],
  slack_channel_id: 'C1',
  escalation_threshold: 0.75,
  digest_hour: 17,
  retired_at: null,
}

const spiral: Product = {
  id: 9,
  name: 'Spiral',
  slug: 'spiral',
  description: null,
  hint_words: [],
  slack_channel_id: null,
  escalation_threshold: null,
  digest_hour: 9,
  retired_at: null,
}

const lex: Product = { ...cora, id: 31, name: 'Lex', slug: 'lex', retired_at: '2026-09-01T12:00:00Z' }
const plus: Product = { ...lex, id: 32, name: 'Plus One', slug: 'plus-one' }

const EMPTY = 'No products yet. Add one so classification has something to match.'

const patch = vi.spyOn(router, 'patch').mockImplementation(() => {})
const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false)

beforeEach(() => {
  vi.clearAllMocks()
  page.flash = {}
})

function renderPage(props: Partial<Props> = {}) {
  return render(
    <ProductsIndex
      products={[cora, spiral]}
      retired_products={[lex, plus]}
      default_escalation_threshold={0.8}
      {...props}
    />,
  )
}

function main() {
  return within(screen.getByRole('main'))
}

// The active products, then the retired ones, each in page order.
function rows() {
  return main().getAllByRole('listitem')
}

function lines(row: HTMLElement) {
  return Array.from(row.querySelectorAll('p'), (p) => p.textContent)
}

describe('Products index', () => {
  it('titles the page and links to adding a product', () => {
    renderPage()

    expect(document.title).toBe('Products')
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Products')
    expect(screen.getByRole('link', { name: 'Add product' })).toHaveAttribute('href', '/products/new')
    expect(screen.getByRole('link', { current: 'page' })).toHaveAttribute('href', '/products')
  })

  it('shows what the last change did', () => {
    page.flash = { notice: 'Cora saved.', alert: 'Not allowed.' }
    renderPage()

    expect(screen.getByRole('status')).toHaveTextContent('Cora saved.')
    expect(screen.getByRole('alert')).toHaveTextContent('Not allowed.')
  })

  it('lists products in the order given with everything set on them', () => {
    renderPage({ products: [spiral, cora] })

    expect(lines(rows()[0])[0]).toBe('Spiral /spiral')
    expect(lines(rows()[1])).toEqual([
      'Cora /cora-mail',
      'Email assistant.',
      'Hint words: brief, inbox zero',
      'Slack C1 · Escalates at 0.75 · Digest at 17:00',
    ])
    expect(screen.queryByText(EMPTY)).not.toBeInTheDocument()
  })

  it('says what is not set and falls back to the default threshold', () => {
    renderPage()

    expect(lines(rows()[1])).toEqual([
      'Spiral /spiral',
      'Slack not set · Escalates at 0.8 (default) · Digest at 09:00',
    ])
  })

  it('shows a threshold of zero and a midnight digest as set', () => {
    renderPage({ products: [{ ...spiral, escalation_threshold: 0, digest_hour: 0 }] })

    expect(lines(rows()[0])).toContain('Slack not set · Escalates at 0 · Digest at 00:00')
  })

  it('links each product to its edit page', () => {
    renderPage()

    const links = main().getAllByRole('link', { name: 'Edit' })
    expect(links.map((link) => link.getAttribute('href'))).toEqual(['/products/7/edit', '/products/9/edit'])
  })

  it('invites adding a product when there are none', () => {
    renderPage({ products: [], retired_products: [] })

    expect(screen.getByText(EMPTY)).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Add product' })).toBeInTheDocument()
    expect(main().queryByRole('list')).not.toBeInTheDocument()
  })

  it('keeps the retired list when no active products are left', () => {
    renderPage({ products: [] })

    expect(screen.getByText(EMPTY)).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Retired' })).toBeInTheDocument()
  })

  it('retires the chosen product at once', () => {
    renderPage()

    fireEvent.click(within(rows()[1]).getByRole('button', { name: 'Retire' }))

    expect(patch).toHaveBeenCalledExactlyOnceWith('/products/9/retire')
    expect(confirm).not.toHaveBeenCalled()
  })

  it('lists retired products by name, in the order given', () => {
    renderPage()
    const section = within(screen.getByRole('heading', { level: 2, name: 'Retired' }).parentElement!)

    expect(
      section.getByText('Retired products stay on past items but are left out of new classification.'),
    ).toBeInTheDocument()
    expect(section.getAllByRole('listitem').map((item) => item.textContent)).toEqual([
      'LexRestore',
      'Plus OneRestore',
    ])
    expect(section.queryAllByRole('link')).toEqual([])
  })

  it('leaves the retired list out when nothing is retired', () => {
    renderPage({ retired_products: [] })

    expect(screen.queryByRole('heading', { name: 'Retired' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Restore' })).not.toBeInTheDocument()
  })

  it('restores the chosen product at once', () => {
    renderPage()

    fireEvent.click(within(rows()[3]).getByRole('button', { name: 'Restore' }))

    expect(patch).toHaveBeenCalledExactlyOnceWith('/products/32/restore')
    expect(confirm).not.toHaveBeenCalled()
  })
})
