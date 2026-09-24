import { Head, Link, useForm } from '@inertiajs/react'
import { type FormEvent } from 'react'
import AppNav from '../../components/app-nav'
import { Field, inputClass, primaryButtonClass, secondaryButtonClass } from '../../components/form-field'
import { type WebhookEvent, eventLabel } from '../../lib/webhooks'

interface Option<T> {
  value: T
  label: string
}

interface WebhookEndpointFormProps {
  endpoint: {
    id: number | null
    name: string | null
    url: string | null
    active: boolean
    events: WebhookEvent[]
    product_ids: number[]
    category_ids: number[]
    sentiments: string[]
  }
  events: WebhookEvent[]
  products: { id: number; name: string }[]
  categories: { id: number; name: string }[]
  sentiments: string[]
}

function toggle<T>(values: T[], value: T, checked: boolean): T[] {
  return checked ? [...values, value] : values.filter((existing) => existing !== value)
}

function CheckboxGroup<T extends string | number>({
  legend,
  hint,
  error,
  options,
  selected,
  onChange,
}: {
  legend: string
  hint?: string
  error?: string[]
  options: Option<T>[]
  selected: T[]
  onChange: (values: T[]) => void
}) {
  return (
    <fieldset className="flex flex-col gap-2 text-sm">
      <legend className="font-medium text-gray-900">{legend}</legend>
      {hint && <p className="text-xs text-gray-500">{hint}</p>}
      <div className="flex flex-wrap gap-x-5 gap-y-2">
        {options.length === 0 && <p className="text-xs text-gray-500">None set up yet.</p>}
        {options.map((option) => (
          <label key={String(option.value)} className="flex items-center gap-2 text-gray-800">
            <input
              type="checkbox"
              checked={selected.includes(option.value)}
              onChange={(e) => onChange(toggle(selected, option.value, e.target.checked))}
              className="rounded border-gray-300"
            />
            {option.label}
          </label>
        ))}
      </div>
      {error && error.length > 0 && (
        <p role="alert" className="text-xs text-red-700">
          {legend} {error.join(', ')}
        </p>
      )}
    </fieldset>
  )
}

export default function WebhookEndpointForm({
  endpoint,
  events,
  products,
  categories,
  sentiments,
}: WebhookEndpointFormProps) {
  const editing = endpoint.id !== null
  const form = useForm({
    name: endpoint.name ?? '',
    url: endpoint.url ?? '',
    active: endpoint.active,
    events: endpoint.events,
    product_ids: endpoint.product_ids,
    category_ids: endpoint.category_ids,
    sentiments: endpoint.sentiments,
  })

  function submit(event: FormEvent) {
    event.preventDefault()
    form.transform((data) => ({ webhook_endpoint: data }))
    if (editing) {
      form.patch(`/webhook_endpoints/${endpoint.id}`)
    } else {
      form.post('/webhook_endpoints')
    }
  }

  const title = editing ? `Edit ${endpoint.name}` : 'Add webhook endpoint'

  return (
    <>
      <Head title={title} />
      <AppNav />
      <main className="mx-auto flex max-w-2xl flex-col gap-6 px-6 py-8">
        <h1 className="text-2xl font-bold tracking-tight text-gray-900">{title}</h1>

        <form onSubmit={submit} className="flex flex-col gap-5">
          <Field label="Name" htmlFor="endpoint_name" error={form.errors.name}>
            <input
              id="endpoint_name"
              required
              value={form.data.name}
              onChange={(e) => form.setData('name', e.target.value)}
              className={inputClass}
            />
          </Field>

          <Field
            label="URL"
            htmlFor="endpoint_url"
            error={form.errors.url}
            hint="Must be https. happyhappy POSTs JSON here with an X-Happyhappy-Signature header."
          >
            <input
              id="endpoint_url"
              type="url"
              required
              placeholder="https://example.com/happyhappy"
              value={form.data.url}
              onChange={(e) => form.setData('url', e.target.value)}
              className={inputClass}
            />
          </Field>

          <CheckboxGroup
            legend="Events"
            error={form.errors.events}
            options={events.map((value) => ({ value, label: eventLabel(value) }))}
            selected={form.data.events}
            onChange={(values) => form.setData('events', values)}
          />

          <CheckboxGroup
            legend="Products"
            hint="Leave all unchecked to receive every product."
            options={products.map((product) => ({ value: product.id, label: product.name }))}
            selected={form.data.product_ids}
            onChange={(values) => form.setData('product_ids', values)}
          />

          <CheckboxGroup
            legend="Categories"
            hint="Leave all unchecked to receive every category."
            options={categories.map((category) => ({ value: category.id, label: category.name }))}
            selected={form.data.category_ids}
            onChange={(values) => form.setData('category_ids', values)}
          />

          <CheckboxGroup
            legend="Sentiments"
            hint="Leave all unchecked to receive every sentiment."
            error={form.errors.sentiments}
            options={sentiments.map((value) => ({ value, label: value }))}
            selected={form.data.sentiments}
            onChange={(values) => form.setData('sentiments', values)}
          />

          <label className="flex items-center gap-2 text-sm text-gray-900">
            <input
              type="checkbox"
              checked={form.data.active}
              onChange={(e) => form.setData('active', e.target.checked)}
              className="rounded border-gray-300"
            />
            Active
          </label>

          <div className="flex gap-3">
            <button type="submit" disabled={form.processing} className={primaryButtonClass}>
              {editing ? 'Save endpoint' : 'Create endpoint'}
            </button>
            <Link href={editing ? `/webhook_endpoints/${endpoint.id}` : '/webhook_endpoints'} className={secondaryButtonClass}>
              Cancel
            </Link>
          </div>
        </form>
      </main>
    </>
  )
}
