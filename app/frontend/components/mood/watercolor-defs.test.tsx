import { render } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import WatercolorDefs from './watercolor-defs'

describe('WatercolorDefs', () => {
  it('renders a hidden zero-size SVG', () => {
    const { container } = render(<WatercolorDefs />)
    const svg = container.querySelector('svg')

    expect(svg).not.toBeNull()
    expect(svg).toHaveAttribute('aria-hidden', 'true')
    expect(svg).toHaveAttribute('focusable', 'false')
    expect(svg).toHaveAttribute('width', '0')
    expect(svg).toHaveAttribute('height', '0')
    expect(svg).toHaveStyle({ position: 'absolute' })
  })

  it('defines the three wash filters, ground filter, and pencil filter', () => {
    const { container } = render(<WatercolorDefs />)
    const filterIds = Array.from(container.querySelectorAll('defs > filter')).map((el) => el.getAttribute('id'))

    expect(filterIds).toEqual(['hh-wash-0', 'hh-wash-1', 'hh-wash-2', 'hh-ground', 'hh-pencil'])
  })
})
