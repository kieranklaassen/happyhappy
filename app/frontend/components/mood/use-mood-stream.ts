import { router, usePoll } from '@inertiajs/react'
import { createConsumer } from '@rails/actioncable'
import { useEffect, useState } from 'react'

export type StreamStatus = 'live' | 'polling'

const RELOAD = { only: ['scene', 'today'] }
const POLL_MS = 30_000
const COALESCE_MS = 600
export const MIN_RELOAD_GAP_MS = 3_000

// Action Cable only says "something changed"; the page refetches its own props,
// so there is still no JSON API. Polling covers a dropped socket. During a backfill
// pings never stop, so reloads are at least MIN_RELOAD_GAP_MS apart with a trailing
// reload for the final state, and a hidden tab catches up when it is shown again.
export function useMoodStream(): StreamStatus {
  const [status, setStatus] = useState<StreamStatus>('polling')
  usePoll(POLL_MS, RELOAD)

  useEffect(() => {
    const consumer = createConsumer()
    let pending: number | undefined
    let lastReload = -Infinity
    let staleWhileHidden = false

    const reload = () => {
      pending = undefined
      if (document.hidden) {
        staleWhileHidden = true
        return
      }
      lastReload = Date.now()
      router.reload(RELOAD)
    }
    const schedule = () => {
      if (pending !== undefined) return
      pending = window.setTimeout(reload, Math.max(COALESCE_MS, lastReload + MIN_RELOAD_GAP_MS - Date.now()))
    }
    const onVisible = () => {
      if (document.hidden || !staleWhileHidden) return
      staleWhileHidden = false
      schedule()
    }

    const subscription = consumer.subscriptions.create('MoodChannel', {
      connected: () => setStatus('live'),
      disconnected: () => setStatus('polling'),
      received: schedule,
    })
    document.addEventListener('visibilitychange', onVisible)
    return () => {
      window.clearTimeout(pending)
      document.removeEventListener('visibilitychange', onVisible)
      subscription.unsubscribe()
      consumer.disconnect()
    }
  }, [])

  return status
}
