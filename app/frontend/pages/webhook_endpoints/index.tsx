import { Head, Link } from '@inertiajs/react'
import AppNav from '../../components/app-nav'
import { FlashNotice, primaryButtonClass } from '../../components/form-field'
import { formatDateTime } from '../../lib/format'
import { type EndpointRow, deliveryBadge, eventLabel } from '../../lib/webhooks'

interface WebhookEndpointsIndexProps {
  endpoints: EndpointRow[]
}

function filterCount(endpoint: EndpointRow): number {
  return endpoint.product_ids.length + endpoint.category_ids.length + endpoint.sentiments.length
}

export default function WebhookEndpointsIndex({ endpoints }: WebhookEndpointsIndexProps) {
  return (
    <>
      <Head title="Webhooks" />
      <AppNav />
      <main className="mx-auto flex max-w-6xl flex-col gap-6 px-6 py-8">
        <div className="flex items-center justify-between">
          <div className="flex flex-col gap-1">
            <h1 className="text-2xl font-bold tracking-tight text-gray-900">Webhooks</h1>
            <p className="text-sm text-gray-600">
              Signed POSTs to your endpoints when items arrive, get classified, change status, escalate, or get an
              agent report.
            </p>
          </div>
          <Link href="/webhook_endpoints/new" className={primaryButtonClass}>
            Add endpoint
          </Link>
        </div>
        <FlashNotice />

        {endpoints.length === 0 ? (
          <p className="text-sm text-gray-600">No endpoints yet.</p>
        ) : (
          <ul className="divide-y divide-gray-200 rounded border border-gray-200 bg-white">
            {endpoints.map((endpoint) => {
              const filters = filterCount(endpoint)
              const badge = endpoint.last_delivery && deliveryBadge(endpoint.last_delivery)
              return (
                <li key={endpoint.id} className="flex flex-wrap items-start justify-between gap-4 px-4 py-3">
                  <div className="flex min-w-0 flex-col gap-1">
                    <div className="flex items-center gap-2">
                      <Link
                        href={`/webhook_endpoints/${endpoint.id}`}
                        className="font-medium text-gray-900 hover:underline"
                      >
                        {endpoint.name}
                      </Link>
                      {!endpoint.active && (
                        <span className="rounded bg-gray-100 px-2 py-0.5 text-xs text-gray-700">Inactive</span>
                      )}
                    </div>
                    <p className="truncate font-mono text-xs text-gray-600">{endpoint.url}</p>
                    <p className="text-xs text-gray-600">
                      {endpoint.events.map(eventLabel).join(', ')}
                      {filters > 0 && ` · ${filters} ${filters === 1 ? 'filter' : 'filters'}`}
                    </p>
                  </div>
                  <div className="text-right text-xs text-gray-600">
                    {endpoint.last_delivery && badge ? (
                      <>
                        <span className={`rounded px-2 py-0.5 ${badge.className}`}>{badge.label}</span>
                        <p className="mt-1">{formatDateTime(endpoint.last_delivery.created_at)}</p>
                      </>
                    ) : (
                      <span>No deliveries yet</span>
                    )}
                  </div>
                </li>
              )
            })}
          </ul>
        )}
      </main>
    </>
  )
}
