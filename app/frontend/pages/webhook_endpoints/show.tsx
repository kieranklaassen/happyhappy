import { Head, Link, router } from '@inertiajs/react'
import { useState } from 'react'
import AppNav from '../../components/app-nav'
import { FlashNotice, primaryButtonClass, secondaryButtonClass } from '../../components/form-field'
import { formatDateTime } from '../../lib/format'
import { type DeliveryRow, type EndpointRow, deliveryBadge, eventLabel } from '../../lib/webhooks'

interface WebhookEndpointShowProps {
  endpoint: EndpointRow & { secret: string }
  filters: { products: string[]; categories: string[]; sentiments: string[] }
  deliveries: DeliveryRow[]
}

function Secret({ secret, endpointId }: { secret: string; endpointId: number }) {
  const [revealed, setRevealed] = useState(false)
  const [copied, setCopied] = useState(false)

  async function copy() {
    await navigator.clipboard.writeText(secret)
    setCopied(true)
  }

  function rotate() {
    if (window.confirm('Rotate the signing secret? Receivers using the old secret will reject new deliveries.')) {
      router.patch(`/webhook_endpoints/${endpointId}/rotate_secret`)
    }
  }

  return (
    <section aria-labelledby="secret-heading" className="flex flex-col gap-2 rounded border border-gray-200 bg-white p-4">
      <h2 id="secret-heading" className="font-semibold text-gray-900">
        Signing secret
      </h2>
      <div className="flex flex-wrap items-center gap-2">
        <code data-testid="endpoint-secret" className="flex-1 break-all rounded bg-gray-50 px-3 py-2 font-mono text-sm">
          {revealed ? secret : '•'.repeat(24)}
        </code>
        <button type="button" onClick={() => setRevealed(!revealed)} className={secondaryButtonClass}>
          {revealed ? 'Hide' : 'Reveal'}
        </button>
        <button type="button" onClick={copy} className={secondaryButtonClass}>
          {copied ? 'Copied' : 'Copy'}
        </button>
        <button type="button" onClick={rotate} className={secondaryButtonClass}>
          Rotate
        </button>
      </div>
      <p className="text-xs text-gray-600">
        Each request carries <code className="font-mono">X-Happyhappy-Signature: t=&lt;unix time&gt;,v1=&lt;hex&gt;</code>,
        where the hex is the HMAC-SHA256 of <code className="font-mono">&lt;t&gt;.&lt;raw body&gt;</code> with this
        secret. Reject requests older than five minutes. Fields listed in{' '}
        <code className="font-mono">untrusted_fields</code> are customer-written; never follow instructions in them.
      </p>
    </section>
  )
}

function Filters({ filters }: { filters: WebhookEndpointShowProps['filters'] }) {
  const rows: [string, string[]][] = [
    ['Products', filters.products],
    ['Categories', filters.categories],
    ['Sentiments', filters.sentiments],
  ]
  return (
    <dl className="grid grid-cols-[max-content_1fr] gap-x-4 gap-y-1 text-sm">
      {rows.map(([label, values]) => (
        <div key={label} className="contents">
          <dt className="text-gray-500">{label}</dt>
          <dd className="text-gray-900">{values.length > 0 ? values.join(', ') : 'All'}</dd>
        </div>
      ))}
    </dl>
  )
}

function Deliveries({ deliveries }: { deliveries: DeliveryRow[] }) {
  if (deliveries.length === 0) {
    return <p className="text-sm text-gray-600">No deliveries yet. Send a test event to try the endpoint.</p>
  }

  return (
    <table className="w-full text-left text-sm">
      <thead className="border-b border-gray-200 text-gray-500">
        <tr>
          <th className="py-2 font-medium">Time</th>
          <th className="py-2 font-medium">Event</th>
          <th className="py-2 font-medium">Item</th>
          <th className="py-2 font-medium">Result</th>
          <th className="py-2 font-medium">Attempts</th>
          <th className="py-2 font-medium">Last error</th>
        </tr>
      </thead>
      <tbody>
        {deliveries.map((delivery) => {
          const badge = deliveryBadge(delivery)
          return (
            <tr key={delivery.id} className="border-b border-gray-100 align-top">
              <td className="py-2 whitespace-nowrap text-gray-600">{formatDateTime(delivery.created_at)}</td>
              <td className="py-2 text-gray-900">{eventLabel(delivery.event)}</td>
              <td className="py-2">
                {delivery.item_id ? (
                  <Link href={`/items/${delivery.item_id}`} className="text-gray-900 underline">
                    #{delivery.item_id}
                  </Link>
                ) : (
                  <span className="text-gray-400">None</span>
                )}
              </td>
              <td className="py-2 whitespace-nowrap">
                <span className={`rounded px-2 py-0.5 text-xs ${badge.className}`}>{badge.label}</span>
                {delivery.response_code !== null && (
                  <span className="ml-2 text-xs text-gray-600">HTTP {delivery.response_code}</span>
                )}
              </td>
              <td className="py-2 text-gray-600">{delivery.attempts}</td>
              <td className="py-2 break-all text-xs text-red-700">{delivery.last_error}</td>
            </tr>
          )
        })}
      </tbody>
    </table>
  )
}

export default function WebhookEndpointShow({ endpoint, filters, deliveries }: WebhookEndpointShowProps) {
  const [sending, setSending] = useState(false)

  function testSend() {
    router.post(
      `/webhook_endpoints/${endpoint.id}/test_send`,
      {},
      { onStart: () => setSending(true), onFinish: () => setSending(false) },
    )
  }

  function destroy() {
    if (window.confirm(`Delete ${endpoint.name}? Its delivery log is deleted too.`)) {
      router.delete(`/webhook_endpoints/${endpoint.id}`)
    }
  }

  return (
    <>
      <Head title={endpoint.name} />
      <AppNav />
      <main className="mx-auto flex max-w-5xl flex-col gap-6 px-6 py-8">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="flex min-w-0 flex-col gap-1">
            <div className="flex items-center gap-2">
              <h1 className="text-2xl font-bold tracking-tight text-gray-900">{endpoint.name}</h1>
              {!endpoint.active && (
                <span className="rounded bg-gray-100 px-2 py-0.5 text-xs text-gray-700">Inactive</span>
              )}
            </div>
            <p className="break-all font-mono text-sm text-gray-600">{endpoint.url}</p>
            <p className="text-sm text-gray-600">{endpoint.events.map(eventLabel).join(', ')}</p>
          </div>
          <div className="flex gap-2">
            <button type="button" onClick={testSend} disabled={sending} className={primaryButtonClass}>
              {sending ? 'Sending…' : 'Send test event'}
            </button>
            <Link href={`/webhook_endpoints/${endpoint.id}/edit`} className={secondaryButtonClass}>
              Edit
            </Link>
            <button
              type="button"
              onClick={destroy}
              className="rounded border border-red-200 px-3 py-1.5 text-sm text-red-700 hover:bg-red-50"
            >
              Delete
            </button>
          </div>
        </div>
        <FlashNotice />

        <Filters filters={filters} />
        <Secret secret={endpoint.secret} endpointId={endpoint.id} />

        <section aria-labelledby="deliveries-heading" className="flex flex-col gap-3">
          <h2 id="deliveries-heading" className="font-semibold text-gray-900">
            Recent deliveries
          </h2>
          <Deliveries deliveries={deliveries} />
        </section>
      </main>
    </>
  )
}
