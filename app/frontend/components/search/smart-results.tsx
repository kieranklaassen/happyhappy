import { SMART_BUCKETS, type SmartBucket, type SmartProps, type SmartStatus } from '../../types/search'
import ItemRow from '../item-row'
import { useTrufflerStream } from './use-truffler-stream'

const BUCKET_LABELS: Record<SmartBucket, string> = {
  strong: 'Strong matches',
  possible: 'Possible matches',
  unlikely: 'Unlikely',
}

function statusText(smart: SmartProps): string {
  const status: SmartStatus = smart.status
  switch (status) {
    case 'pending':
      return 'Starting…'
    case 'running':
      return `Jev is reading the top ${smart.reserved_slots} matches…`
    case 'complete':
      return 'Done'
    case 'paused':
      return 'Paused: the Jev rate limit is spent for now; it resumes on its own'
    case 'cancelled':
    case 'expired':
      return 'This Smart search ended. Press Enter to run it again.'
    default: {
      const unreachable: never = status
      return unreachable
    }
  }
}

function Skeleton() {
  return (
    <ul aria-hidden="true" className="rounded border border-gray-200 bg-white">
      {[0, 1].map((index) => (
        <li key={index} className="flex flex-col gap-2 border-b border-gray-100 px-4 py-3 last:border-b-0">
          <span className="h-3 w-1/3 animate-pulse rounded bg-gray-200" />
          <span className="h-3 w-2/3 animate-pulse rounded bg-gray-100" />
        </li>
      ))}
    </ul>
  )
}

function Bucket({ smart, bucket }: { smart: SmartProps; bucket: SmartBucket }) {
  const rows = smart.buckets[bucket]
  const pending = smart.pending[bucket]
  const list =
    rows.length > 0 ? (
      <ul className="rounded border border-gray-200 bg-white">
        {rows.map((item) => (
          <ItemRow key={item.id} item={item} />
        ))}
      </ul>
    ) : pending ? (
      <Skeleton />
    ) : null

  if (smart.collapsed.includes(bucket)) {
    if (rows.length === 0 && !pending) return null
    return (
      <details className="flex flex-col gap-2">
        <summary className="cursor-pointer text-sm font-medium text-gray-700">
          {BUCKET_LABELS[bucket]} ({rows.length})
        </summary>
        <div className="mt-2">{list}</div>
      </details>
    )
  }

  return (
    <section aria-label={BUCKET_LABELS[bucket]} className="flex flex-col gap-2">
      <h3 className="text-sm font-medium text-gray-700">
        {BUCKET_LABELS[bucket]} {rows.length > 0 && <span className="text-gray-500">({rows.length})</span>}
      </h3>
      {list}
      {bucket === 'strong' && smart.no_strong_matches && (
        <p className="text-sm text-gray-600">No strong matches. The possible matches and keyword results are the closest.</p>
      )}
      {bucket === 'possible' && rows.length === 0 && !pending && <p className="text-sm text-gray-500">None.</p>}
    </section>
  )
}

export default function SmartResults({ smart }: { smart: SmartProps }) {
  const active = smart.status === 'pending' || smart.status === 'running'
  useTrufflerStream(smart.run_id, active)
  const ended = smart.status === 'cancelled' || smart.status === 'expired'

  return (
    <section aria-labelledby="smart-results" className="flex flex-col gap-3 rounded border border-gray-200 bg-gray-50 p-4">
      <header className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 id="smart-results" className="text-base font-semibold text-gray-900">
          Smart search
        </h2>
        <span role="status" className="text-sm text-gray-600">
          {statusText(smart)}
        </span>
      </header>
      {!ended && SMART_BUCKETS.map((bucket) => <Bucket key={bucket} smart={smart} bucket={bucket} />)}
    </section>
  )
}
