import { act, renderHook } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { LIVE_COALESCE_MS, LIVE_RELOAD_GAP_MS, MIN_RELOAD_GAP_MS, useMoodStream } from './use-mood-stream'

const reload = vi.fn()
const usePoll = vi.fn()
const unsubscribe = vi.fn()
const disconnect = vi.fn()
let callbacks: {
  connected: () => void
  disconnected: () => void
  received: (ping?: { changed_at?: string; backfill?: boolean }) => void
}
let channel: string

const live = { changed_at: '2026-09-25T10:00:00Z', backfill: false }
const backfill = { changed_at: '2026-09-25T10:00:00Z', backfill: true }

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

  it('reloads the props it is given', () => {
    renderHook(() => useMoodStream(['items', 'anomalies']))

    act(() => {
      callbacks.received(live)
      vi.advanceTimersByTime(LIVE_COALESCE_MS)
    })

    expect(usePoll).toHaveBeenCalledWith(30_000, { only: ['items', 'anomalies'] })
    expect(reload).toHaveBeenCalledWith({ only: ['items', 'anomalies'] })
  })

  it('coalesces a burst of live pings into one quick partial reload', () => {
    renderHook(() => useMoodStream())

    act(() => {
      callbacks.received(live)
      callbacks.received(live)
      callbacks.received(live)
      vi.advanceTimersByTime(LIVE_COALESCE_MS - 1)
    })
    expect(reload).not.toHaveBeenCalled()

    act(() => vi.advanceTimersByTime(1))
    expect(reload).toHaveBeenCalledTimes(1)
    expect(reload).toHaveBeenCalledWith({ only: ['scene', 'today'] })
  })

  it('shows a live change right after a reload within the live gap', () => {
    renderHook(() => useMoodStream())

    act(() => {
      callbacks.received(live)
      vi.advanceTimersByTime(LIVE_COALESCE_MS)
    })
    expect(reload).toHaveBeenCalledTimes(1)

    act(() => {
      callbacks.received(live)
      vi.advanceTimersByTime(LIVE_RELOAD_GAP_MS - 1)
    })
    expect(reload).toHaveBeenCalledTimes(1)

    act(() => vi.advanceTimersByTime(1))
    expect(reload).toHaveBeenCalledTimes(2)
  })

  it('keeps backfill reloads apart while pings keep coming, and still catches the last change', () => {
    renderHook(() => useMoodStream())

    act(() => {
      callbacks.received(backfill)
      vi.advanceTimersByTime(700)
    })
    expect(reload).toHaveBeenCalledTimes(1)

    act(() => {
      for (let i = 0; i < 10; i++) {
        callbacks.received(backfill)
        vi.advanceTimersByTime(200)
      }
    })
    expect(reload).toHaveBeenCalledTimes(1)

    act(() => vi.advanceTimersByTime(MIN_RELOAD_GAP_MS))
    expect(reload).toHaveBeenCalledTimes(2)
  })

  it('brings a pending backfill reload forward when a live change arrives', () => {
    renderHook(() => useMoodStream())

    act(() => {
      callbacks.received(backfill)
      vi.advanceTimersByTime(700)
      callbacks.received(backfill)
      vi.advanceTimersByTime(100)
      callbacks.received(live)
      vi.advanceTimersByTime(LIVE_RELOAD_GAP_MS)
    })

    expect(reload).toHaveBeenCalledTimes(2)
  })

  it('treats a ping without a payload as live', () => {
    renderHook(() => useMoodStream())

    act(() => {
      callbacks.received()
      vi.advanceTimersByTime(LIVE_COALESCE_MS)
    })

    expect(reload).toHaveBeenCalledTimes(1)
  })

  it('waits for a hidden tab to be shown before reloading', () => {
    renderHook(() => useMoodStream())
    const hidden = vi.spyOn(document, 'hidden', 'get').mockReturnValue(true)

    act(() => {
      callbacks.received(live)
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
