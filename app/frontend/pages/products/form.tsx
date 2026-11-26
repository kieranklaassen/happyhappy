import { Head, Link, useForm } from '@inertiajs/react'
import { type ChangeEvent, type FormEvent } from 'react'
import AppNav from '../../components/app-nav'
import { Field, inputClass, primaryButtonClass, secondaryButtonClass } from '../../components/form-field'
import { formatHour } from '../../lib/format'

interface ProductFormProps {
  product: {
    id: number | null
    name: string | null
    slug: string | null
    description: string | null
    hint_words: string[]
    search_blurb: string | null
    slack_channel_id: string | null
    alert_channel_id: string | null
    alert_mention_ids: string[]
    escalation_threshold: number | null
    digest_hour: number
  }
  default_escalation_threshold: number
}

const SEARCH_BLURB_MAX = 40
const HOURS = Array.from({ length: 24 }, (_, hour) => hour)

export default function ProductForm({ product, default_escalation_threshold }: ProductFormProps) {
  const editing = product.id !== null
  const form = useForm({
    name: product.name ?? '',
    slug: product.slug ?? '',
    description: product.description ?? '',
    hint_words: product.hint_words.join(', '),
    search_blurb: product.search_blurb ?? '',
    slack_channel_id: product.slack_channel_id ?? '',
    alert_channel_id: product.alert_channel_id ?? '',
    alert_mention_ids: product.alert_mention_ids.join(', '),
    escalation_threshold: product.escalation_threshold?.toString() ?? '',
    digest_hour: product.digest_hour.toString(),
  })

  function submit(event: FormEvent) {
    event.preventDefault()
    form.transform((data) => ({ product: data }))
    if (editing) {
      form.patch(`/products/${product.id}`)
    } else {
      form.post('/products')
    }
  }

  function fieldProps(name: keyof typeof form.data) {
    return { htmlFor: `product_${name}`, error: form.errors[name] }
  }

  function controlProps(name: keyof typeof form.data) {
    return {
      id: `product_${name}`,
      value: form.data[name],
      onChange: (e: ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) =>
        form.setData(name, e.target.value),
      className: inputClass,
    }
  }

  const title = editing ? `Edit ${product.name}` : 'Add product'

  return (
    <>
      <Head title={title} />
      <AppNav />
      <main className="mx-auto flex max-w-2xl flex-col gap-6 px-6 py-8">
        <h1 className="text-2xl font-bold tracking-tight text-gray-900">{title}</h1>

        <form onSubmit={submit} className="flex flex-col gap-5">
          <Field label="Name" {...fieldProps('name')}>
            <input {...controlProps('name')} required />
          </Field>

          <Field label="Slug" {...fieldProps('slug')} hint="Leave blank to derive it from the name.">
            <input {...controlProps('slug')} />
          </Field>

          <Field
            label="Description"
            {...fieldProps('description')}
            hint="One or two sentences. The classifier reads this to decide whether a message is about the product."
          >
            <textarea {...controlProps('description')} rows={3} />
          </Field>

          <Field
            label="Hint words"
            {...fieldProps('hint_words')}
            hint="Aliases and feature names, separated by commas or new lines."
          >
            <textarea {...controlProps('hint_words')} rows={2} />
          </Field>

          <Field
            label="Search words"
            {...fieldProps('search_blurb')}
            hint="What people call it, 40 characters at most, for example Cora assistant. Feed search reads these words as naming the product. Leave out words people search for, such as email or inbox. Blank uses the name."
          >
            <input {...controlProps('search_blurb')} maxLength={SEARCH_BLURB_MAX} />
          </Field>

          <Field
            label="Slack support channel id"
            {...fieldProps('slack_channel_id')}
            hint="Escalations and the daily digest post here, for example C0123456789."
          >
            <input {...controlProps('slack_channel_id')} />
          </Field>

          <Field
            label="Incident alert channel id"
            {...fieldProps('alert_channel_id')}
            hint="Bad-news spikes open an incident and ping this channel once, for example C0AGCDCD6KG. Leave empty for no incident pings."
          >
            <input {...controlProps('alert_channel_id')} />
          </Field>

          <Field
            label="On-call Slack IDs"
            {...fieldProps('alert_mention_ids')}
            hint="Mentioned in each incident ping. User IDs start with U (Copy member ID in Slack), user group IDs with S. Separate with commas."
          >
            <input {...controlProps('alert_mention_ids')} />
          </Field>

          <div className="grid gap-5 sm:grid-cols-2">
            <Field
              label="Escalation threshold"
              {...fieldProps('escalation_threshold')}
              hint={`Anger probability from 0 to 1. Blank uses the default, ${default_escalation_threshold}.`}
            >
              <input {...controlProps('escalation_threshold')} type="number" min={0} max={1} step={0.01} />
            </Field>

            <Field label="Digest time" {...fieldProps('digest_hour')} hint="Daily, in the app time zone.">
              <select {...controlProps('digest_hour')}>
                {HOURS.map((hour) => (
                  <option key={hour} value={hour}>
                    {formatHour(hour)}
                  </option>
                ))}
              </select>
            </Field>
          </div>

          <div className="flex gap-3">
            <button type="submit" disabled={form.processing} className={primaryButtonClass}>
              {editing ? 'Save product' : 'Create product'}
            </button>
            <Link href="/products" className={secondaryButtonClass}>
              Cancel
            </Link>
          </div>
        </form>
      </main>
    </>
  )
}
