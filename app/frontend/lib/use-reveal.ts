import { type RefObject, useEffect, useRef, useState } from 'react'

export const REVEAL_STEP = 40

// Renders a long list a slice at a time: the first `step` rows, then `step` more whenever the
// sentinel after the last row comes within 1200 px of the viewport. Without IntersectionObserver
// (tests, old browsers) everything renders.
export function useReveal(total: number, step = REVEAL_STEP): { shown: number; sentinel: RefObject<HTMLLIElement | null> } {
  const supported = typeof IntersectionObserver !== 'undefined'
  const [shown, setShown] = useState(supported ? Math.min(step, total) : total)
  const sentinel = useRef<HTMLLIElement>(null)

  useEffect(() => {
    const element = sentinel.current
    if (!element || !supported) return
    const observer = new IntersectionObserver(
      ([entry]) => entry.isIntersecting && setShown((count) => Math.min(count + step, total)),
      { rootMargin: '1200px' },
    )
    observer.observe(element)
    return () => observer.disconnect()
  }, [shown, total, step, supported])

  return { shown: supported ? shown : total, sentinel }
}
