import { render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import Refused from './refused'

vi.mock('@inertiajs/react', () => ({ Head: () => null }))

describe('Refused page', () => {
  it('names the refused address and explains the every.to rule', () => {
    render(<Refused email="someone@gmail.com" />)

    expect(screen.getByRole('alert')).toHaveTextContent('someone@gmail.com')
    expect(screen.getByRole('alert')).toHaveTextContent(/every\.to accounts/)
    expect(screen.getByRole('link', { name: /different every account/i })).toHaveAttribute(
      'href',
      '/auth/every',
    )
  })
})
