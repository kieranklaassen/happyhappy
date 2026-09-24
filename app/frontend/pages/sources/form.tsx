import { Head, Link, useForm } from '@inertiajs/react'
import { type FormEvent } from 'react'
import AppNav from '../../components/app-nav'
import { Field, inputClass, primaryButtonClass, secondaryButtonClass } from '../../components/form-field'
import { type SourceKind, selectorField } from '../../lib/source-kinds'

interface SourceFormProps {
  source: {
    id: number | null
    kind: SourceKind | null
    name: string | null
    selector: string | null
    default_product_id: number | null
    monthly_limit: number | null
  }
  kinds: SourceKind[]
  products: { id: number; name: string }[]
}

export default function SourceForm({ source, kinds, products }: SourceFormProps) {
  const editing = source.id !== null
  const form = useForm({
    kind: source.kind ?? kinds[0],
    name: source.name ?? '',
    selector: source.selector ?? '',
    default_product_id: source.default_product_id?.toString() ?? '',
    monthly_limit: source.monthly_limit?.toString() ?? '',
  })
  const field = selectorField(form.data.kind)

  function submit(event: FormEvent) {
    event.preventDefault()
    if (editing) {
      form.transform(({ kind: _kind, ...data }) => ({ source: data }))
      form.patch(`/sources/${source.id}`)
    } else {
      form.transform((data) => ({ source: data }))
      form.post('/sources')
    }
  }

  const title = editing ? `Edit ${source.name}` : 'Add source'

  return (
    <>
      <Head title={title} />
      <AppNav />
      <main className="mx-auto flex max-w-2xl flex-col gap-6 px-6 py-8">
        <h1 className="text-2xl font-bold tracking-tight text-gray-900">{title}</h1>

        <form onSubmit={submit} className="flex flex-col gap-5">
          <Field
            label="Kind"
            htmlFor="source_kind"
            error={form.errors.kind}
            hint={editing ? 'The kind cannot change after a source is created.' : undefined}
          >
            <select
              id="source_kind"
              value={form.data.kind}
              disabled={editing}
              onChange={(e) => form.setData('kind', e.target.value as SourceKind)}
              className={inputClass}
            >
              {kinds.map((kind) => (
                <option key={kind} value={kind}>
                  {selectorField(kind).kindLabel}
                </option>
              ))}
            </select>
          </Field>

          <Field label="Name" htmlFor="source_name" error={form.errors.name}>
            <input
              id="source_name"
              required
              value={form.data.name}
              onChange={(e) => form.setData('name', e.target.value)}
              className={inputClass}
            />
          </Field>

          <Field label={field.label} htmlFor="source_selector" error={form.errors.selector} hint={field.hint}>
            <input
              id="source_selector"
              required
              placeholder={field.placeholder}
              value={form.data.selector}
              onChange={(e) => form.setData('selector', e.target.value)}
              className={inputClass}
            />
          </Field>

          {form.data.kind === 'x' && (
            <Field
              label="Monthly limit (USD)"
              htmlFor="source_monthly_limit"
              error={form.errors.monthly_limit}
              hint="Searches pause for the rest of the month once estimated spend would pass this."
            >
              <input
                id="source_monthly_limit"
                type="number"
                min={0}
                step={0.01}
                value={form.data.monthly_limit}
                onChange={(e) => form.setData('monthly_limit', e.target.value)}
                className={inputClass}
              />
            </Field>
          )}

          <Field
            label="Default product"
            htmlFor="source_default_product_id"
            error={form.errors.default_product_id}
            hint="Used when a message does not name a product. Classification can still override it."
          >
            <select
              id="source_default_product_id"
              value={form.data.default_product_id}
              onChange={(e) => form.setData('default_product_id', e.target.value)}
              className={inputClass}
            >
              <option value="">None</option>
              {products.map((product) => (
                <option key={product.id} value={product.id}>
                  {product.name}
                </option>
              ))}
            </select>
          </Field>

          <div className="flex gap-3">
            <button type="submit" disabled={form.processing} className={primaryButtonClass}>
              {editing ? 'Save source' : 'Create source'}
            </button>
            <Link href="/sources" className={secondaryButtonClass}>
              Cancel
            </Link>
          </div>
        </form>
      </main>
    </>
  )
}
