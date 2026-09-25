import { Link } from '@inertiajs/react'
import { anomalyItemsHref, anomalyTag, anomalyValue } from '../lib/anomaly-format'
import { formatDateTime } from '../lib/format'
import type { AnomalyProps } from '../types/anomalies'

const ACTIVE_CLASS: Record<AnomalyProps['polarity'], string> = {
  positive: 'bg-green-50 text-green-700',
  negative: 'bg-red-50 text-red-700',
  neutral: 'bg-sky-50 text-sky-700',
}

function statusLabel(anomaly: AnomalyProps): { label: string; className: string } {
  if (anomaly.historical) return { label: 'History', className: 'bg-gray-100 text-gray-600' }
  switch (anomaly.status) {
    case 'active':
      return { label: 'Active', className: ACTIVE_CLASS[anomaly.polarity] }
    case 'ended':
      return { label: 'Ended', className: 'bg-gray-100 text-gray-700' }
    default: {
      const unhandled: never = anomaly.status
      return unhandled
    }
  }
}

function dotClass(anomaly: AnomalyProps): string {
  switch (anomaly.polarity) {
    case 'positive':
      return 'bg-green-400'
    case 'neutral':
      return 'bg-sky-300'
    case 'negative':
      return anomaly.severity === 'high' ? 'bg-red-500' : anomaly.severity === 'medium' ? 'bg-orange-400' : 'bg-yellow-300'
    default: {
      const unhandled: never = anomaly.polarity
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
              <span className="text-xs text-gray-500">{anomalyTag(anomaly)}</span>
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
