import { act, renderHook } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { MIN_RELOAD_GAP_MS, useMoodStream } from './use-mood-stream'

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

  it('keeps reloads apart while pings keep coming, and still catches the last change', () => {
    renderHook(() => useMoodStream())

    act(() => {
      callbacks.received()
      vi.advanceTimersByTime(700)
    })
    expect(reload).toHaveBeenCalledTimes(1)

    act(() => {
      for (let i = 0; i < 10; i++) {
        callbacks.received()
        vi.advanceTimersByTime(200)
      }
    })
    expect(reload).toHaveBeenCalledTimes(1)

    act(() => vi.advanceTimersByTime(MIN_RELOAD_GAP_MS))
    expect(reload).toHaveBeenCalledTimes(2)
  })

  it('waits for a hidden tab to be shown before reloading', () => {
    renderHook(() => useMoodStream())
    const hidden = vi.spyOn(document, 'hidden', 'get').mockReturnValue(true)

    act(() => {
      callbacks.received()
      vi.advanceTimersByTime(700)
    })
    expect(reload).not.toHaveBeenCalled()

    hidden.mockReturnValue(false)
    act(() => {
      document.dispatchEvent(new Event('visibilitychange'))
      vi.advanceTimersByTime(700)
    })
    expect(reload).toHaveBeenCalledTimes(1)
    hidden.mockRestore()
  })

  it('unsubscribes and disconnects on unmount', () => {
    const { unmount } = renderHook(() => useMoodStream())

    unmount()

    expect(unsubscribe).toHaveBeenCalled()
    expect(disconnect).toHaveBeenCalled()
  })
})
