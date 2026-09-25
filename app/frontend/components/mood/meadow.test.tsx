import { render, screen, within } from '@testing-library/react'
import { type ReactNode } from 'react'
import { describe, expect, it, vi } from 'vitest'
import Meadow, { loudest } from './meadow'
import type { MoodCharacter, MoodGroup } from '../../types/mood'

vi.mock('@inertiajs/react', () => ({
  Link: ({ href, children, ...rest }: { href: string; children: ReactNode }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}))

function person(overrides: Partial<MoodCharacter>): MoodCharacter {
  return {
    key: 'k',
    seed: 'abc',
    item_id: 1,
    name: 'Ana',
    handle: '@ana',
    mood: 'meh',
    sentiment: 'neutral',
    anger: 0.1,
    source_kind: 'slack',
    status: 'new',
    threads: 1,
    excerpt: 'Hello there',
    last_message_at: new Date().toISOString(),
    mended: false,
    ...overrides,
  }
}

const counts = { beaming: 1, content: 0, relieved: 0, meh: 0, grumpy: 0, furious: 1, pending: 0 }

function group(characters: MoodCharacter[]): MoodGroup {
  return { product: { slug: 'cora', name: 'Cora', retired: false }, mood: 'meh', counts, overflow: 0, characters }
}

describe('loudest', () => {
  it('picks the angriest furious customer, else the first beaming one', () => {
    const calm = person({ key: 'a', mood: 'beaming' })
    const loud = person({ key: 'b', mood: 'furious', anger: 0.99 })
    const louder = person({ key: 'c', mood: 'furious', anger: 0.85 })

    expect(loudest([calm, louder, loud])?.key).toBe('b')
    expect(loudest([person({ key: 'd' }), calm])?.key).toBe('a')
    expect(loudest([person({ key: 'e' })])).toBeNull()
  })
})

describe('Meadow', () => {
  it('names the product and describes each customer for screen readers', () => {
    render(
      <Meadow
        group={group([
          person({ key: 'a', item_id: 7, name: 'Ana', mood: 'furious', anger: 0.9, excerpt: 'Where is my inbox?' }),
          person({ key: 'b', item_id: 8, name: 'Bo', mood: 'beaming', source_kind: 'x' }),
        ])}
        history={null}
        productHref="/?range=7d&product=cora"
      />,
    )

    const meadow = screen.getByRole('region', { name: 'Cora' })
    expect(within(meadow).getByRole('button', { name: /Ana is furious about Cora on Slack.*Where is my inbox/ })).toBeInTheDocument()
    expect(within(meadow).getByRole('button', { name: /Bo is beaming about Cora on X/ })).toBeInTheDocument()
    expect(within(meadow).getAllByRole('link', { name: 'Open in the feed' }).map((link) => link.getAttribute('href'))).toEqual(
      expect.arrayContaining(['/items/7', '/items/8']),
    )
    expect(within(meadow).getByText(/1 smiling · 0 meh · 1 grumpy/)).toBeInTheDocument()
    expect(within(meadow).getByRole('link', { name: 'Just Cora' })).toHaveAttribute('href', '/?range=7d&product=cora')
  })

  it('animates a customer whose mood changed and pops in a newcomer', () => {
    const { container } = render(
      <Meadow
        group={group([person({ key: 'a', mood: 'furious' }), person({ key: 'b', seed: 'zzz', mood: 'content' })])}
        history={new Map([['a', 'content']])}
        productHref="/?product=cora"
      />,
    )

    expect(container.querySelectorAll('.hh-changed')).toHaveLength(1)
    expect(container.querySelectorAll('.hh-splash')).toHaveLength(1)
    expect(container.querySelectorAll('.hh-arrive')).toHaveLength(1)
  })

  it('does not animate anyone on first paint', () => {
    const { container } = render(<Meadow group={group([person({ key: 'a' })])} history={null} productHref="/?product=cora" />)

    expect(container.querySelector('.hh-changed, .hh-arrive')).toBeNull()
  })
})
