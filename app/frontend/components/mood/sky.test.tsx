import { render } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import type { SettledMood } from '../../types/mood'
import Sky from './sky'

const SETTLED_MOODS: readonly SettledMood[] = ['beaming', 'content', 'relieved', 'meh', 'grumpy', 'furious']

describe('Sky', () => {
  it('renders distinct artwork for every settled mood and the quiet null state', () => {
    const states: readonly (SettledMood | null)[] = [...SETTLED_MOODS, null]
    const markup = states.map((mood) => {
      const { container } = render(<Sky mood={mood} />)
      const svg = container.querySelector('svg')
      expect(svg).toHaveAttribute('viewBox', '0 0 120 110')
      expect(svg).toHaveAttribute('aria-hidden', 'true')
      expect(svg).toHaveAttribute('focusable', 'false')
      return svg?.innerHTML
    })

    expect(new Set(markup).size).toBe(states.length)
  })

  it('forwards className to the root svg', () => {
    const { container } = render(<Sky mood="content" className="h-24 w-24" />)
    expect(container.querySelector('svg')).toHaveClass('h-24', 'w-24')
  })

  it('draws a rainbow and rayed sun for beaming, and a plain rayed sun for content', () => {
    const beaming = render(<Sky mood="beaming" />).container
    const content = render(<Sky mood="content" />).container

    expect(beaming.querySelectorAll('line')).toHaveLength(10)
    expect(beaming.querySelectorAll('g[opacity="0.75"] > path')).toHaveLength(4)
    expect(beaming.querySelector('circle[fill="#F8D774"]')).not.toBeNull()

    expect(content.querySelectorAll('line')).toHaveLength(10)
    expect(content.querySelector('g[opacity="0.75"]')).toBeNull()
    expect(content.querySelector('circle[fill="#F8D774"]')).not.toBeNull()
  })

  it.each<[SettledMood, string]>([
    ['relieved', '#EEF2F6'],
    ['meh', '#E4E1EA'],
  ])('draws a rayless sun with a cloud for %s', (mood, cloudFill) => {
    const { container } = render(<Sky mood={mood} />)

    expect(container.querySelector('circle[fill="#F8D774"]')).not.toBeNull()
    expect(container.querySelectorAll('line')).toHaveLength(0)
    expect(container.querySelector(`path[fill="${cloudFill}"]`)).not.toBeNull()
    expect(container.querySelector('.hh-rain')).toBeNull()
  })

  it('draws staggered rain without sun for grumpy, adding lightning and a red glow for furious', () => {
    const grumpy = render(<Sky mood="grumpy" />).container
    const furious = render(<Sky mood="furious" />).container

    expect(grumpy.querySelector('circle[fill="#F8D774"]')).toBeNull()
    const grumpyDrops = Array.from(grumpy.querySelectorAll<SVGPathElement>('.hh-rain'))
    expect(grumpyDrops).toHaveLength(4)
    grumpyDrops.forEach((drop, i) => {
      expect(drop.style.animationDelay).toMatch(/s$/)
      expect(Number.parseFloat(drop.style.animationDelay)).toBeCloseTo(i * 0.2, 5)
    })
    expect(grumpy.querySelector('.hh-bolt')).toBeNull()

    expect(furious.querySelector('circle[fill="#F8D774"]')).toBeNull()
    expect(furious.querySelectorAll('.hh-rain')).toHaveLength(4)
    expect(furious.querySelector('.hh-bolt')).not.toBeNull()
    expect(furious.querySelector('ellipse[fill="#E8505A"]')).not.toBeNull()
  })

  it('draws a sleeping crescent moon with z z text when mood is null', () => {
    const { container } = render(<Sky mood={null} />)

    expect(container.querySelector('text')?.textContent).toBe('z z')
    expect(container.querySelectorAll('circle')).toHaveLength(2)
    expect(container.querySelector('[filter="url(#hh-pencil)"]')).toBeNull()
    expect(container.querySelector('.hh-rain')).toBeNull()
  })
})
