import { router, usePoll } from '@inertiajs/react'
import { createConsumer } from '@rails/actioncable'
import { useEffect, useState } from 'react'

export type StreamStatus = 'live' | 'polling'

const RELOAD = { only: ['scene', 'today'] }
const POLL_MS = 30_000
const COALESCE_MS = 600

// Action Cable only says "something changed"; the page refetches its own props,
// so there is still no JSON API. Polling covers a dropped socket.
export function useMoodStream(): StreamStatus {
  const [status, setStatus] = useState<StreamStatus>('polling')
  usePoll(POLL_MS, RELOAD)

  useEffect(() => {
    const consumer = createConsumer()
    let pending: number | undefined
    const subscription = consumer.subscriptions.create('MoodChannel', {
      connected: () => setStatus('live'),
      disconnected: () => setStatus('polling'),
      received: () => {
        if (pending !== undefined) return
        pending = window.setTimeout(() => {
          pending = undefined
          router.reload(RELOAD)
        }, COALESCE_MS)
      },
    })
    return () => {
      window.clearTimeout(pending)
      subscription.unsubscribe()
      consumer.disconnect()
    }
  }, [])

  return status
}
