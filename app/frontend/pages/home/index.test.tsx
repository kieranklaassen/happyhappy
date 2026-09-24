import { render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import Home from './index'

// Head reads an Inertia head-manager from context that does not exist in isolation.
vi.mock('@inertiajs/react', () => ({
  Head: () => null,
}))

describe('Home page', () => {
  it('renders the heading with the name prop', () => {
    render(<Home name="happyhappy" />)

    expect(
      screen.getByRole('heading', { name: /hello, happyhappy/i }),
    ).toBeInTheDocument()
  })
})
