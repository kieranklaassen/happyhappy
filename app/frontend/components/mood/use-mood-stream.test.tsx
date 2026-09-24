import { act, renderHook } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { useMoodStream } from './use-mood-stream'

const reload = vi.fn()
const usePoll = vi.fn()
const unsubscribe = vi.fn()
const disconnect = vi.fn()
let callbacks: { connected: () => void; disconnected: () => void; received: () => void }
let channel: string

vi.mock('@inertiajs/react', () => ({
  router: { reload: (...args: unknown[]) => reload(...args) },
  usePoll: (...args: unknown[]) => usePoll(...args),
}))

vi.mock('@rails/actioncable', () => ({
  createConsumer: () => ({
    subscriptions: {
      create: (name: string, handlers: typeof callbacks) => {
        channel = name
        callbacks = handlers
        return { unsubscribe }
      },
    },
    disconnect,
  }),
}))

describe('useMoodStream', () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => {
    vi.useRealTimers()
    vi.clearAllMocks()
  })

  it('polls as a fallback and reports live once the socket connects', () => {
    const { result } = renderHook(() => useMoodStream())

    expect(channel).toBe('MoodChannel')
    expect(usePoll).toHaveBeenCalledWith(30_000, { only: ['scene', 'today'] })
    expect(result.current).toBe('polling')

    act(() => callbacks.connected())
    expect(result.current).toBe('live')

    act(() => callbacks.disconnected())
    expect(result.current).toBe('polling')
  })

  it('coalesces a burst of pings into one partial reload', () => {
    renderHook(() => useMoodStream())

    act(() => {
      callbacks.received()
      callbacks.received()
      callbacks.received()
      vi.advanceTimersByTime(700)
    })

    expect(reload).toHaveBeenCalledTimes(1)
    expect(reload).toHaveBeenCalledWith({ only: ['scene', 'today'] })
  })

  it('unsubscribes and disconnects on unmount', () => {
    const { unmount } = renderHook(() => useMoodStream())

    unmount()

    expect(unsubscribe).toHaveBeenCalled()
    expect(disconnect).toHaveBeenCalled()
  })
})
