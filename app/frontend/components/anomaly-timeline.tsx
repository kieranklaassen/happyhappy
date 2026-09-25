import { Link } from '@inertiajs/react'
import { anomalyItemsHref, anomalyValue, isGoodNews } from '../lib/anomaly-format'
import { formatDateTime } from '../lib/format'
import type { AnomalyProps } from '../types/anomalies'

function statusLabel(anomaly: AnomalyProps): { label: string; className: string } {
  if (anomaly.historical) return { label: 'History', className: 'bg-gray-100 text-gray-600' }
  switch (anomaly.status) {
    case 'active':
      return { label: 'Active', className: 'bg-red-50 text-red-700' }
    case 'ended':
      return { label: 'Ended', className: 'bg-gray-100 text-gray-700' }
    default: {
      const unhandled: never = anomaly.status
      return unhandled
    }
  }
}

function dotClass(anomaly: AnomalyProps): string {
  if (isGoodNews(anomaly)) return 'bg-amber-300'
  switch (anomaly.severity) {
    case 'high':
      return 'bg-red-500'
    case 'medium':
      return 'bg-orange-400'
    case 'low':
      return 'bg-yellow-300'
    default: {
      const unhandled: never = anomaly.severity
      return unhandled
    }
  }
}

export default function AnomalyTimeline({ anomalies }: { anomalies: AnomalyProps[] }) {
  if (anomalies.length === 0) {
    return <p className="text-sm text-gray-500">Nothing unusual in the last 30 days.</p>
  }

  return (
    <ol className="relative flex flex-col gap-4 border-l border-gray-200 pl-5">
      {anomalies.map((anomaly) => {
        const status = statusLabel(anomaly)
        return (
          <li key={anomaly.id} className="relative">
            <span aria-hidden="true" className={`absolute top-1.5 -left-[26px] h-2.5 w-2.5 rounded-full ring-4 ring-white ${dotClass(anomaly)}`} />
            <p className="flex flex-wrap items-center gap-2 text-sm">
              <span className="font-medium text-gray-900">{anomaly.label}</span>
              {anomaly.source && <span className="text-gray-500">on {anomaly.source.name}</span>}
              <span className={`rounded px-1.5 py-0.5 text-xs font-medium ${status.className}`}>{status.label}</span>
              <span className="text-xs text-gray-500">{anomaly.severity} severity</span>
            </p>
            <p className="mt-0.5 text-sm text-gray-700">
              {anomalyValue(anomaly, anomaly.actual)} against an expected {anomalyValue(anomaly, anomaly.expected)} per{' '}
              {anomaly.granularity}, <time dateTime={anomaly.window_start}>{formatDateTime(anomaly.window_start)}</time> to{' '}
              <time dateTime={anomaly.window_end}>{formatDateTime(anomaly.window_end)}</time>
            </p>
            {anomaly.item_ids.length > 0 && (
              <Link href={anomalyItemsHref(anomaly)} className="text-sm text-blue-700 underline">
                {anomaly.item_ids.length === 1 ? '1 item' : `${anomaly.item_ids.length} items`}
              </Link>
            )}
          </li>
        )
      })}
    </ol>
  )
}
