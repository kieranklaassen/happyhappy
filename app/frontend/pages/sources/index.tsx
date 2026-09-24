import { Head, Link } from '@inertiajs/react'
import AppNav from '../../components/app-nav'
import { FlashNotice, primaryButtonClass, secondaryButtonClass } from '../../components/form-field'
import { formatDateTime, formatUsd } from '../../lib/format'
import { type SourceKind, selectorField } from '../../lib/source-kinds'

type SourceStatus = 'active' | 'paused' | 'paused_for_budget'

export interface SourceRow {
  id: number
  kind: SourceKind
  name: string
  selector: string
  status: SourceStatus
  default_product_name: string | null
  last_message_at: string | null
  last_error: string | null
  last_error_at: string | null
  monthly_limit: number | null
  month_spend: number | null
}

interface SourcesIndexProps {
  sources: SourceRow[]
}

interface Health {
  label: string
  className: string
}

export function sourceHealth(source: Pick<SourceRow, 'status' | 'last_error'>): Health {
  switch (source.status) {
    case 'active':
      return source.last_error
        ? { label: 'Error', className: 'bg-red-50 text-red-700' }
        : { label: 'Connected', className: 'bg-green-50 text-green-800' }
    case 'paused':
      return { label: 'Paused', className: 'bg-gray-100 text-gray-700' }
    case 'paused_for_budget':
      return { label: 'Paused for budget', className: 'bg-amber-50 text-amber-800' }
    default: {
      const unhandled: never = source.status
      throw new Error(`Unknown source status: ${String(unhandled)}`)
    }
  }
}

function Spend({ source }: { source: SourceRow }) {
  if (source.kind !== 'x' || source.month_spend === null) return null
  const text =
    source.monthly_limit === null
      ? `${formatUsd(source.month_spend)} spent this month, no limit set`
      : `${formatUsd(source.month_spend)} of ${formatUsd(source.monthly_limit)} this month`
  return <p className="text-xs text-gray-600">{text}</p>
}

export default function SourcesIndex({ sources }: SourcesIndexProps) {
  return (
    <>
      <Head title="Sources" />
      <AppNav />
      <main className="mx-auto flex max-w-6xl flex-col gap-6 px-6 py-8">
        <div className="flex items-center justify-between">
          <h1 className="text-2xl font-bold tracking-tight text-gray-900">Sources</h1>
          <Link href="/sources/new" className={primaryButtonClass}>
            Add source
          </Link>
        </div>
        <FlashNotice />

        {sources.length === 0 ? (
          <p className="text-sm text-gray-600">No sources yet. Connect a channel, inbox, address, or search.</p>
        ) : (
          <ul className="divide-y divide-gray-200 rounded border border-gray-200 bg-white">
            {sources.map((source) => {
              const health = sourceHealth(source)
              return (
                <li
                  key={source.id}
                  aria-label={source.name}
                  className="flex flex-col gap-2 px-4 py-4 sm:flex-row sm:items-start sm:justify-between"
                >
                  <div className="flex min-w-0 flex-col gap-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="text-xs font-medium uppercase tracking-wide text-gray-500">
                        {selectorField(source.kind).kindLabel}
                      </span>
                      <span className="font-medium text-gray-900">{source.name}</span>
                      <span className={`rounded px-2 py-0.5 text-xs font-medium ${health.className}`}>{health.label}</span>
                    </div>
                    <p className="break-all font-mono text-xs text-gray-600">{source.selector}</p>
                    <p className="text-xs text-gray-600">
                      Default product: {source.default_product_name ?? 'none'} · Last message:{' '}
                      {formatDateTime(source.last_message_at)}
                    </p>
                    <Spend source={source} />
                    {source.last_error && (
                      <p className="text-xs text-red-700">
                        Latest error: {source.last_error}
                        {source.last_error_at && ` (${formatDateTime(source.last_error_at)})`}
                      </p>
                    )}
                  </div>
                  <Link href={`/sources/${source.id}/edit`} className={`${secondaryButtonClass} shrink-0 self-start`}>
                    Edit
                  </Link>
                </li>
              )
            })}
          </ul>
        )}
      </main>
    </>
  )
}
