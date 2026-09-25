import { render, screen } from '@testing-library/react'
import { type ReactNode } from 'react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { WebmcpManifest } from '../lib/webmcp'
import { createModelContextStub, installModelContext, requestTool } from '../test/model-context-stub'
import AppNav, { NAV_ENTRIES, isActive } from './app-nav'

const page = { url: '/items', props: {} as { webmcp?: WebmcpManifest | null } }

vi.mock('@inertiajs/react', () => ({
  usePage: () => page,
  Link: ({ href, children, ...rest }: { href: string; children: ReactNode }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}))

describe('AppNav', () => {
  let uninstall = () => {}
  beforeEach(() => {
    page.url = '/items'
    page.props = {}
  })
  afterEach(() => uninstall())

  it('links to every section', () => {
    render(<AppNav />)

    expect(screen.getByRole('navigation', { name: 'Main' })).toBeInTheDocument()
    for (const { label, href } of NAV_ENTRIES) {
      expect(screen.getByRole('link', { name: label })).toHaveAttribute('href', href)
    }
    expect(NAV_ENTRIES.map((entry) => entry.label)).toEqual([
      'Mood',
      'Feed',
      'Products',
      'Categories',
      'Sources',
      'Agents',
      'Webhooks',
      'Settings',
    ])
  })

  it('puts the sun mark next to the wordmark', () => {
    render(<AppNav />)

    const brand = screen.getByRole('link', { name: 'happyhappy' })
    expect(brand).toHaveAttribute('href', '/')
    expect(brand.querySelector('svg')).toHaveAttribute('aria-hidden', 'true')
  })

  it('marks the current section', () => {
    page.url = '/products/3/overview?range=30'
    render(<AppNav />)

    expect(screen.getByRole('link', { name: 'Products' })).toHaveAttribute('aria-current', 'page')
    expect(screen.getByRole('link', { name: 'Feed' })).not.toHaveAttribute('aria-current')
  })

  it('registers the WebMCP manifest from the shared prop and drops it on unmount', () => {
    const context = createModelContextStub()
    uninstall = installModelContext(context)
    page.props = { webmcp: { tools: [requestTool()] } }

    const { unmount } = render(<AppNav />)
    expect([...context.tools.keys()]).toEqual(['claim_item'])

    unmount()
    expect(context.tools.size).toBe(0)
  })

  it('registers nothing without a manifest', () => {
    const context = createModelContextStub()
    uninstall = installModelContext(context)

    render(<AppNav />)

    expect(context.tools.size).toBe(0)
  })
})

describe('isActive', () => {
  it('matches the section path, nested paths, and query strings but not prefixes', () => {
    expect(isActive('/items', '/items')).toBe(true)
    expect(isActive('/items?status=new', '/items')).toBe(true)
    expect(isActive('/items/42', '/items')).toBe(true)
    expect(isActive('/itemsx', '/items')).toBe(false)
    expect(isActive('/settings', '/items')).toBe(false)
  })

  it('treats the mood dashboard at / as active only on the home page', () => {
    expect(isActive('/', '/')).toBe(true)
    expect(isActive('/?product=cora', '/')).toBe(true)
    expect(isActive('/items', '/')).toBe(false)
  })
})
