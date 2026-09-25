import { act, renderHook } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { SMART_COALESCE_MS, SMART_POLL_MS, useTrufflerStream } from './use-truffler-stream'

const reload = vi.fn()
const unsubscribe = vi.fn()
const disconnect = vi.fn()
let received: (ping?: { run_id?: string; section?: string }) => void
let channel: string | undefined

vi.mock('@inertiajs/react', () => ({
  router: { reload: (...args: unknown[]) => reload(...args) },
}))

vi.mock('@rails/actioncable', () => ({
  createConsumer: () => ({
    subscriptions: {
      create: (name: string, handlers: { received: typeof received }) => {
        channel = name
        received = handlers.received
        return { unsubscribe }
      },
    },
    disconnect,
  }),
}))

describe('useTrufflerStream', () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => {
    vi.useRealTimers()
    vi.clearAllMocks()
    channel = undefined
  })

  it('reloads only the smart prop once per burst of pings for the current run', () => {
    renderHook(() => useTrufflerStream('run-1', true))

    expect(channel).toBe('TrufflerChannel')
    act(() => {
      received({ run_id: 'run-1', section: 'smart' })
      received({ run_id: 'run-1', section: 'smart' })
      vi.advanceTimersByTime(SMART_COALESCE_MS)
    })

    expect(reload).toHaveBeenCalledTimes(1)
    expect(reload).toHaveBeenCalledWith({ only: ['smart'] })
  })

  it('ignores pings for an older run', () => {
    renderHook(() => useTrufflerStream('run-2', false))

    act(() => {
      received({ run_id: 'run-1', section: 'smart' })
      received()
      vi.advanceTimersByTime(SMART_COALESCE_MS)
    })

    expect(reload).not.toHaveBeenCalled()
  })

  it('polls while the run is active and stops once it is done', () => {
    const { rerender } = renderHook(({ active }) => useTrufflerStream('run-1', active), { initialProps: { active: true } })

    act(() => vi.advanceTimersByTime(SMART_POLL_MS))
    expect(reload).toHaveBeenCalledTimes(1)

    rerender({ active: false })
    act(() => vi.advanceTimersByTime(SMART_POLL_MS * 3))
    expect(reload).toHaveBeenCalledTimes(1)
  })

  it('does nothing without a run, and unsubscribes on unmount', () => {
    renderHook(() => useTrufflerStream(null, true))
    expect(channel).toBeUndefined()

    const { unmount } = renderHook(() => useTrufflerStream('run-1', true))
    unmount()
    expect(unsubscribe).toHaveBeenCalled()
    expect(disconnect).toHaveBeenCalled()
  })
})
