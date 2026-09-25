import { Head, Link, useForm } from '@inertiajs/react'
import { type FormEvent } from 'react'
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

  const title = editing ? `Edit ${product.name}` : 'Add product'

  return (
    <>
      <Head title={title} />
      <AppNav />
      <main className="mx-auto flex max-w-2xl flex-col gap-6 px-6 py-8">
        <h1 className="text-2xl font-bold tracking-tight text-gray-900">{title}</h1>

        <form onSubmit={submit} className="flex flex-col gap-5">
          <Field label="Name" htmlFor="product_name" error={form.errors.name}>
            <input
              id="product_name"
              required
              value={form.data.name}
              onChange={(e) => form.setData('name', e.target.value)}
              className={inputClass}
            />
          </Field>

          <Field label="Slug" htmlFor="product_slug" error={form.errors.slug} hint="Leave blank to derive it from the name.">
            <input
              id="product_slug"
              value={form.data.slug}
              onChange={(e) => form.setData('slug', e.target.value)}
              className={inputClass}
            />
          </Field>

          <Field
            label="Description"
            htmlFor="product_description"
            error={form.errors.description}
            hint="One or two sentences. The classifier reads this to decide whether a message is about the product."
          >
            <textarea
              id="product_description"
              rows={3}
              value={form.data.description}
              onChange={(e) => form.setData('description', e.target.value)}
              className={inputClass}
            />
          </Field>

          <Field
            label="Hint words"
            htmlFor="product_hint_words"
            error={form.errors.hint_words}
            hint="Aliases and feature names, separated by commas or new lines."
          >
            <textarea
              id="product_hint_words"
              rows={2}
              value={form.data.hint_words}
              onChange={(e) => form.setData('hint_words', e.target.value)}
              className={inputClass}
            />
          </Field>

          <Field
            label="Search words"
            htmlFor="product_search_blurb"
            error={form.errors.search_blurb}
            hint="What people call it, 40 characters at most, for example Cora assistant. Feed search reads these words as naming the product. Leave out words people search for, such as email or inbox. Blank uses the name."
          >
            <input
              id="product_search_blurb"
              maxLength={SEARCH_BLURB_MAX}
              value={form.data.search_blurb}
              onChange={(e) => form.setData('search_blurb', e.target.value)}
              className={inputClass}
            />
          </Field>

          <Field
            label="Slack support channel id"
            htmlFor="product_slack_channel_id"
            error={form.errors.slack_channel_id}
            hint="Escalations and the daily digest post here, for example C0123456789."
          >
            <input
              id="product_slack_channel_id"
              value={form.data.slack_channel_id}
              onChange={(e) => form.setData('slack_channel_id', e.target.value)}
              className={inputClass}
            />
          </Field>

          <div className="grid gap-5 sm:grid-cols-2">
            <Field
              label="Escalation threshold"
              htmlFor="product_escalation_threshold"
              error={form.errors.escalation_threshold}
              hint={`Anger probability from 0 to 1. Blank uses the default, ${default_escalation_threshold}.`}
            >
              <input
                id="product_escalation_threshold"
                type="number"
                min={0}
                max={1}
                step={0.01}
                value={form.data.escalation_threshold}
                onChange={(e) => form.setData('escalation_threshold', e.target.value)}
                className={inputClass}
              />
            </Field>

            <Field label="Digest time" htmlFor="product_digest_hour" error={form.errors.digest_hour} hint="Daily, in the app time zone.">
              <select
                id="product_digest_hour"
                value={form.data.digest_hour}
                onChange={(e) => form.setData('digest_hour', e.target.value)}
                className={inputClass}
              >
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
