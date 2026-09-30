import { Head, Link, useForm } from '@inertiajs/react'
import { type FormEvent } from 'react'
import AnomalyTimeline from '../../components/anomaly-timeline'
import AppNav from '../../components/app-nav'
import { Field, FlashNotice, inputClass, primaryButtonClass } from '../../components/form-field'
import { formatDateTime } from '../../lib/format'
import type { IncidentProps, IncidentStatus } from '../../types/incidents'

function statusBadge(status: IncidentStatus): { label: string; className: string } {
  switch (status) {
    case 'open':
      return { label: 'Open', className: 'bg-red-50 text-red-700' }
    case 'resolved':
      return { label: 'Resolved', className: 'bg-green-50 text-green-700' }
    default: {
      const unhandled: never = status
      return unhandled
    }
  }
}

function ResolveForm({ incident }: { incident: IncidentProps }) {
  const form = useForm({ note: '', handle_items: false })
  const items = incident.item_ids.length

  function submit(event: FormEvent) {
    event.preventDefault()
    form.patch(`/incidents/${incident.id}/resolve`, { preserveScroll: true })
  }

  return (
    <form onSubmit={submit} className="flex flex-col gap-4">
      <Field
        label="Resolution note"
        htmlFor="incident_note"
        hint="Optional. Shown on the incident, threaded under the Slack ping, and sent with the incident.resolved webhook."
      >
        <textarea
          id="incident_note"
          rows={3}
          value={form.data.note}
          onChange={(e) => form.setData('note', e.target.value)}
          className={inputClass}
        />
      </Field>
      {items > 0 && (
        <label className="flex items-start gap-2 text-sm text-gray-700">
          <input
            type="checkbox"
            className="mt-0.5"
            checked={form.data.handle_items}
            onChange={(e) => form.setData('handle_items', e.target.checked)}
          />
          <span>
            Also mark the driving items that still need attention handled ({items === 1 ? '1 item' : `${items} items`} behind this
            incident), with the note as the reason
          </span>
        </label>
      )}
      <div>
        <button type="submit" disabled={form.processing} className={primaryButtonClass}>
          Resolve incident
        </button>
      </div>
    </form>
  )
}

export default function IncidentShow({ incident }: { incident: IncidentProps }) {
  const badge = statusBadge(incident.status)
  const title = `${incident.product.name} incident`

  return (
    <>
      <Head title={title} />
      <AppNav />
      <main className="mx-auto flex max-w-3xl flex-col gap-6 px-6 py-8">
        <header className="flex flex-col gap-2">
          <div className="flex items-center gap-3">
            <h1 className="text-2xl font-bold tracking-tight text-gray-900">{title}</h1>
            <span className={`rounded px-2 py-0.5 text-xs font-medium ${badge.className}`}>{badge.label}</span>
          </div>
          <p className="text-sm text-gray-600">
            Opened <time dateTime={incident.opened_at}>{formatDateTime(incident.opened_at)}</time>
            {incident.sources.length > 0 && <> · {incident.sources.map((source) => source.name).join(', ')}</>}
            {incident.slack_posted && <> · pinged in Slack</>}
          </p>
          <nav className="flex gap-3 text-sm">
            <Link href={`/products/${incident.product.slug}/overview`} className="text-blue-700 underline">
              {incident.product.name} overview
            </Link>
          </nav>
        </header>
        <FlashNotice />

        {incident.status === 'resolved' && (
          <section aria-label="Resolution" className="rounded bg-green-50 px-4 py-3 text-sm text-green-900">
            <p>
              Resolved by <strong>{incident.resolved_by ?? 'someone'}</strong>
              {incident.resolved_at && (
                <>
                  {' '}
                  on <time dateTime={incident.resolved_at}>{formatDateTime(incident.resolved_at)}</time>
                </>
              )}
              {incident.items_handled && ', driving items marked handled'}
            </p>
            {incident.resolution_note && <p className="mt-1 whitespace-pre-line">{incident.resolution_note}</p>}
          </section>
        )}

        <section aria-labelledby="spikes-heading" className="flex flex-col gap-4 rounded border border-gray-200 bg-white p-4">
          <h2 id="spikes-heading" className="text-lg font-semibold text-gray-900">
            What spiked
          </h2>
          <AnomalyTimeline anomalies={incident.anomalies} showIncident={false} />
        </section>

        {incident.status === 'open' && (
          <section id="resolve" aria-labelledby="resolve-heading" className="flex flex-col gap-4 rounded border border-gray-200 bg-white p-4">
            <h2 id="resolve-heading" className="text-lg font-semibold text-gray-900">
              Resolve
            </h2>
            <p className="text-sm text-gray-600">
              Resolving ends these anomalies, stops alerts about the same spikes until they calm down, and takes them off the
              dashboard, the feed banner, and the daily overview.
            </p>
            <ResolveForm incident={incident} />
          </section>
        )}
      </main>
    </>
  )
}
