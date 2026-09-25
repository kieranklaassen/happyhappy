import { render } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import Character from './character'
import { MOODS } from './moods'
import { traitsFor } from './traits'

describe('Character', () => {
  it('draws every mood with its own face and extras', () => {
    const markup = MOODS.map((mood) => {
      const { container } = render(<Character seed="ana" mood={mood} />)
      const svg = container.querySelector('svg')
      expect(svg).toHaveAttribute('data-mood', mood)
      return svg?.innerHTML
    })

    expect(new Set(markup).size).toBe(MOODS.length)
  })

  it('gives a furious customer a storm cloud and a beaming one hearts', () => {
    const furious = render(<Character seed="ana" mood="furious" />).container
    const beaming = render(<Character seed="ana" mood="beaming" />).container

    expect(furious.querySelector('.hh-bolt')).not.toBeNull()
    expect(beaming.querySelectorAll('.hh-rise')).toHaveLength(3)
  })

  it('gives a relieved customer a sweat drop and an exhale', () => {
    const relieved = render(<Character seed="ana" mood="relieved" idle />).container

    expect(relieved.querySelector('.hh-drip')).not.toBeNull()
    expect(relieved.querySelector('.hh-exhale')).not.toBeNull()
    expect(relieved.querySelector('.hh-idle')).toHaveClass('hh-idle--relieved')
  })

  it('is decorative unless given a title', () => {
    const { container, rerender } = render(<Character seed="ana" mood="meh" />)
    expect(container.querySelector('svg')).toHaveAttribute('aria-hidden', 'true')

    rerender(<Character seed="ana" mood="meh" title="Ana is meh" />)
    expect(container.querySelector('svg')).toHaveAttribute('role', 'img')
    expect(container.querySelector('svg')).toHaveAttribute('aria-label', 'Ana is meh')
  })

  it('idles on the element that carries its own tempo and phase', () => {
    const { container } = render(<Character seed="ana" mood="beaming" idle />)
    const idler = container.querySelector('.hh-idle')

    expect(idler).toHaveClass('hh-idle--beaming')
    expect((idler as HTMLElement).style.getPropertyValue('--hh-tempo')).toMatch(/s$/)
    expect(render(<Character seed="ana" mood="beaming" />).container.querySelector('.hh-idle')).toBeNull()
  })

  it('draws a bandage on a mended customer', () => {
    const plain = render(<Character seed="ana" mood="grumpy" />).container.innerHTML
    const mended = render(<Character seed="ana" mood="grumpy" bandage />).container.innerHTML

    expect(mended.length).toBeGreaterThan(plain.length)
  })
})

describe('traitsFor', () => {
  it('is stable for one seed and varies across seeds', () => {
    expect(traitsFor('seed-1')).toEqual(traitsFor('seed-1'))

    const looks = new Set(
      Array.from({ length: 40 }, (_, i) => {
        const traits = traitsFor(`person-${i}`)
        return `${traits.body.wash}|${traits.headwear}|${traits.accessory}`
      }),
    )
    expect(looks.size).toBeGreaterThan(30)
  })
})
