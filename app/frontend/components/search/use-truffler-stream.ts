import { router } from '@inertiajs/react'
import { createConsumer } from '@rails/actioncable'
import { useEffect } from 'react'

interface Ping {
  run_id?: string
  section?: string
}

export const SMART_COALESCE_MS = 100
export const SMART_POLL_MS = 2_000
const SMART_PROPS = ['smart']

// Smart search results stream in as rerank chunks land. TrufflerChannel pings
// carry only the run id, so the page reloads its own `smart` prop; pings for
// an older run are ignored. The poll covers a dropped socket and stops once
// the run is no longer active.
export function useTrufflerStream(runId: string | null, active: boolean) {
  useEffect(() => {
    if (!runId) return
    const consumer = createConsumer()
    let pending: number | undefined
    const reload = () => {
      pending = undefined
      router.reload({ only: SMART_PROPS })
    }
    const schedule = () => {
      if (pending === undefined) pending = window.setTimeout(reload, SMART_COALESCE_MS)
    }
    const subscription = consumer.subscriptions.create('TrufflerChannel', {
      received: (ping?: Ping) => {
        if (ping?.run_id === runId) schedule()
      },
    })
    return () => {
      window.clearTimeout(pending)
      subscription.unsubscribe()
      consumer.disconnect()
    }
  }, [runId])

  useEffect(() => {
    if (!runId || !active) return
    const poll = window.setInterval(() => router.reload({ only: SMART_PROPS }), SMART_POLL_MS)
    return () => window.clearInterval(poll)
  }, [runId, active])
}
