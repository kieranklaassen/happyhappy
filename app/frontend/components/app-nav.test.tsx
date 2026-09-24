import { render, screen } from '@testing-library/react'
import { type ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import AppNav, { NAV_ENTRIES, isActive } from './app-nav'

const page = { url: '/items' }

vi.mock('@inertiajs/react', () => ({
  usePage: () => page,
  Link: ({ href, children, ...rest }: { href: string; children: ReactNode }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}))

describe('AppNav', () => {
  beforeEach(() => {
    page.url = '/items'
  })

  it('links to every section', () => {
    render(<AppNav />)

    expect(screen.getByRole('navigation', { name: 'Main' })).toBeInTheDocument()
    for (const { label, href } of NAV_ENTRIES) {
      expect(screen.getByRole('link', { name: label })).toHaveAttribute('href', href)
    }
    expect(NAV_ENTRIES.map((entry) => entry.label)).toEqual([
      'Feed',
      'Products',
      'Categories',
      'Sources',
      'Agents',
      'Webhooks',
      'Settings',
    ])
  })

  it('marks the current section', () => {
    page.url = '/products/3/overview?range=30'
    render(<AppNav />)

    expect(screen.getByRole('link', { name: 'Products' })).toHaveAttribute('aria-current', 'page')
    expect(screen.getByRole('link', { name: 'Feed' })).not.toHaveAttribute('aria-current')
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
})
