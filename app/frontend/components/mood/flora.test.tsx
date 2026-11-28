import { render } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import Flora from './flora'

describe('Flora', () => {
  it('renders 9 sprigs by default and respects custom counts including zero', () => {
    expect(render(<Flora seed="cora" />).container.querySelectorAll('svg')).toHaveLength(9)
    expect(render(<Flora seed="cora" count={4} />).container.querySelectorAll('svg')).toHaveLength(4)
    expect(render(<Flora seed="cora" count={0} />).container.querySelectorAll('svg')).toHaveLength(0)
  })

  it('is deterministic for a given seed and varies across different seeds', () => {
    const first = render(<Flora seed="cora" />).container.innerHTML
    const second = render(<Flora seed="cora" />).container.innerHTML
    const other = render(<Flora seed="thesis" />).container.innerHTML

    expect(first).toBe(second)
    expect(first).not.toBe(other)
  })

  it('positions sprigs in ascending horizontal slots with bounded bottom and square size', () => {
    const { container } = render(<Flora seed="meadow-layout" count={12} />)
    const svgs = Array.from(container.querySelectorAll('svg'))

    let previousLeft = -1
    for (const svg of svgs) {
      expect(svg).toHaveAttribute('viewBox', '0 0 24 22')
      expect(svg).toHaveAttribute('filter', 'url(#hh-pencil)')

      const left = Number.parseFloat(svg.style.left)
      const bottom = Number.parseFloat(svg.style.bottom)
      const width = Number.parseFloat(svg.style.width)
      const height = Number.parseFloat(svg.style.height)

      expect(svg.style.left.endsWith('%')).toBe(true)
      expect(left).toBeGreaterThan(previousLeft)
      expect(left).toBeGreaterThan(0)
      expect(left).toBeLessThan(100)
      previousLeft = left

      expect(bottom).toBeGreaterThanOrEqual(6)
      expect(bottom).toBeLessThan(34)

      expect(width).toBeGreaterThanOrEqual(16)
      expect(width).toBeLessThan(24)
      expect(height).toBe(width)
    }
  })

  it('renders grass, daisy, tulip, and pebble art and remaps off-white tulip petals to pink', () => {
    const { container } = render(<Flora seed="all-sprigs" count={60} />)
    const svgs = Array.from(container.querySelectorAll('svg'))

    const hasGrass = svgs.some((svg) => svg.querySelector('g[stroke="#8DB57A"]') !== null)
    const hasDaisy = svgs.some(
      (svg) => svg.querySelectorAll('ellipse').length === 5 && svg.querySelector('circle[fill="#F2C46B"]') !== null,
    )
    const tulipHeads = svgs
      .map((svg) => svg.querySelector('path[d^="M 8.5 5"]'))
      .filter((el): el is SVGPathElement => el !== null)
    const hasPebble = svgs.some((svg) => svg.querySelector('ellipse[fill="#D9D2C4"]') !== null)

    expect(hasGrass).toBe(true)
    expect(hasDaisy).toBe(true)
    expect(tulipHeads.length).toBeGreaterThan(0)
    expect(hasPebble).toBe(true)

    const tulipFills = tulipHeads.map((head) => head.getAttribute('fill'))
    expect(tulipFills).not.toContain('#FFFDF8')
    expect(tulipFills).toContain('#F4A9B8')
  })
})
