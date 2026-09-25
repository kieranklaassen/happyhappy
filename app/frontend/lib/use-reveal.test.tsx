import { act, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { useReveal } from './use-reveal'

function List({ total }: { total: number }) {
  const { shown, sentinel } = useReveal(total, 10)
  return (
    <ol>
      {Array.from({ length: shown }, (_, i) => (
        <li key={i}>row {i}</li>
      ))}
      {shown < total && <li ref={sentinel} data-testid="sentinel" />}
    </ol>
  )
}

describe('useReveal', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('renders everything when IntersectionObserver is missing', () => {
    render(<List total={25} />)

    expect(screen.getAllByText(/row/)).toHaveLength(25)
  })

  it('renders a slice at a time as the sentinel nears the viewport', () => {
    let fire: (hit: boolean) => void = () => {}
    vi.stubGlobal(
      'IntersectionObserver',
      class {
        constructor(callback: (entries: { isIntersecting: boolean }[]) => void) {
          fire = (hit) => callback([{ isIntersecting: hit }])
        }
        observe() {}
        disconnect() {}
      },
    )
    render(<List total={25} />)
    expect(screen.getAllByText(/row/)).toHaveLength(10)

    act(() => fire(true))
    expect(screen.getAllByText(/row/)).toHaveLength(20)

    act(() => fire(true))
    expect(screen.getAllByText(/row/)).toHaveLength(25)
    expect(screen.queryByTestId('sentinel')).toBeNull()
  })
})
