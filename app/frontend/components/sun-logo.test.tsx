import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import SunLogo from './sun-logo'

describe('SunLogo', () => {
  it('is decorative next to the wordmark', () => {
    const { container } = render(<SunLogo />)

    expect(container.querySelector('svg')).toHaveAttribute('aria-hidden', 'true')
  })

  it('can stand alone with a name', () => {
    render(<SunLogo title="happyhappy" />)

    expect(screen.getByRole('img', { name: 'happyhappy' })).toBeInTheDocument()
  })
})
