import { router, usePoll } from '@inertiajs/react'
import { createConsumer } from '@rails/actioncable'
import { useEffect, useState } from 'react'

export type StreamStatus = 'live' | 'polling'

interface Ping {
  backfill?: boolean
}

const DASHBOARD_PROPS = ['scene', 'today']
const POLL_MS = 30_000
const COALESCE_MS = 600
export const MIN_RELOAD_GAP_MS = 3_000
export const LIVE_COALESCE_MS = 150
export const LIVE_RELOAD_GAP_MS = 500

// Action Cable only says "something changed"; the page refetches its own props,
// so there is still no JSON API. Polling covers a dropped socket. A live change
// reloads within LIVE_COALESCE_MS, at most every LIVE_RELOAD_GAP_MS. During a
// backfill or rerun pings never stop, so those reloads are at least
// MIN_RELOAD_GAP_MS apart with a trailing reload for the final state. A hidden
// tab catches up when it is shown again.
export function useMoodStream(only: string[] = DASHBOARD_PROPS): StreamStatus {
  const [status, setStatus] = useState<StreamStatus>('polling')
  const props = only.join(',')
  usePoll(POLL_MS, { only })

  useEffect(() => {
    const reloadOptions = { only: props.split(',') }
    const consumer = createConsumer()
    let pending: number | undefined
    let pendingAt = Infinity
    let lastReload = -Infinity
    let staleWhileHidden = false

    const reload = () => {
      pending = undefined
      pendingAt = Infinity
      if (document.hidden) {
        staleWhileHidden = true
        return
      }
      lastReload = Date.now()
      router.reload(reloadOptions)
    }
    const schedule = (live: boolean) => {
      const now = Date.now()
      const at = live
        ? Math.max(now + LIVE_COALESCE_MS, lastReload + LIVE_RELOAD_GAP_MS)
        : Math.max(now + COALESCE_MS, lastReload + MIN_RELOAD_GAP_MS)
      if (at >= pendingAt) return
      window.clearTimeout(pending)
      pendingAt = at
      pending = window.setTimeout(reload, at - now)
    }
    const onVisible = () => {
      if (document.hidden || !staleWhileHidden) return
      staleWhileHidden = false
      schedule(true)
    }

    const subscription = consumer.subscriptions.create('MoodChannel', {
      connected: () => setStatus('live'),
      disconnected: () => setStatus('polling'),
      received: (ping?: Ping) => schedule(!ping?.backfill),
    })
    document.addEventListener('visibilitychange', onVisible)
    return () => {
      window.clearTimeout(pending)
      document.removeEventListener('visibilitychange', onVisible)
      subscription.unsubscribe()
      consumer.disconnect()
    }
  }, [props])

  return status
}
