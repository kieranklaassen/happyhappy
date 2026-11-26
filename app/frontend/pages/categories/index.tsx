import { Head, router, useForm } from '@inertiajs/react'
import { type FormEvent, useEffect, useRef } from 'react'
import AppNav from '../../components/app-nav'
import { Field, FlashNotice, inputClass, primaryButtonClass, secondaryButtonClass } from '../../components/form-field'
import { plural } from '../../components/mood/format'

interface CategoryRow {
  id: number
  name: string
  description: string | null
  search_blurb: string | null
  position: number
  retired_at: string | null
  item_count: number
}

const SEARCH_BLURB_MAX = 40
const SEARCH_BLURB_HINT = 'Words that name it in feed search, 40 characters at most. Blank uses the name.'

interface CategoriesIndexProps {
  categories: CategoryRow[]
  retired_categories: CategoryRow[]
}

type TextField = 'name' | 'description' | 'search_blurb'

interface TextFieldsForm {
  data: Record<TextField, string>
  errors: Partial<Record<TextField, string[]>>
  setData(field: TextField, value: string): void
}

function TextFields({ form, prefix, nameHint }: { form: TextFieldsForm; prefix: string; nameHint?: string }) {
  return (
    <>
      <Field label="Name" htmlFor={`${prefix}_name`} error={form.errors.name} hint={nameHint}>
        <input
          id={`${prefix}_name`}
          required
          value={form.data.name}
          onChange={(e) => form.setData('name', e.target.value)}
          className={inputClass}
        />
      </Field>
      <Field label="Description" htmlFor={`${prefix}_description`} error={form.errors.description}>
        <input
          id={`${prefix}_description`}
          value={form.data.description}
          onChange={(e) => form.setData('description', e.target.value)}
          className={inputClass}
        />
      </Field>
      <Field label="Search words" htmlFor={`${prefix}_search_blurb`} error={form.errors.search_blurb} hint={SEARCH_BLURB_HINT}>
        <input
          id={`${prefix}_search_blurb`}
          maxLength={SEARCH_BLURB_MAX}
          value={form.data.search_blurb}
          onChange={(e) => form.setData('search_blurb', e.target.value)}
          className={inputClass}
        />
      </Field>
    </>
  )
}

const BLANK: Record<TextField, string> = { name: '', description: '', search_blurb: '' }

// Fields still as they were in `from` move to `to`; a field typed in since then keeps its text.
function moveUntyped<T extends Record<string, string>>(data: T, from: T, to: T): T {
  return Object.fromEntries(Object.keys(data).map((key) => [key, data[key] === from[key] ? to[key] : data[key]])) as T
}

function storedValues(category: CategoryRow) {
  return {
    name: category.name,
    description: category.description ?? '',
    search_blurb: category.search_blurb ?? '',
    position: category.position.toString(),
  }
}

function CategoryEditor({ category }: { category: CategoryRow }) {
  const form = useForm(storedValues(category))
  // The form's defaults, which useForm does not expose.
  const defaults = useRef(form.data)
  const prefix = `category_${category.id}`

  function setDefaults(values: typeof form.data) {
    defaults.current = values
    form.setDefaults(values)
  }

  // Waits for a save in flight to finish, because only then is it known whether what it sent was stored.
  useEffect(() => {
    if (form.processing) return
    const stored = storedValues(category)
    const from = defaults.current
    form.setData((data) => moveUntyped(data, from, stored))
    setDefaults(stored)
  }, [category, form.processing])

  function submit(event: FormEvent) {
    event.preventDefault()
    const sent = form.data
    form.transform((data) => ({ category: data }))
    form.patch(`/categories/${category.id}`, { preserveScroll: true, errorBag: prefix, onSuccess: () => setDefaults(sent) })
  }

  return (
    <form onSubmit={submit} aria-label={`Edit ${category.name}`} className="grid gap-3 px-4 py-4 sm:grid-cols-[5rem_1fr_2fr_1fr_auto] sm:items-start">
      <Field label="Order" htmlFor={`${prefix}_position`} error={form.errors.position}>
        <input
          id={`${prefix}_position`}
          type="number"
          step={1}
          value={form.data.position}
          onChange={(e) => form.setData('position', e.target.value)}
          className={inputClass}
        />
      </Field>
      <TextFields form={form} prefix={prefix} nameHint={plural(category.item_count, 'item')} />
      <div className="flex gap-2 sm:pt-6">
        <button type="submit" disabled={form.processing || !form.isDirty} className={secondaryButtonClass}>
          Save
        </button>
        <button
          type="button"
          className={secondaryButtonClass}
          onClick={() => router.patch(`/categories/${category.id}/retire`, {}, { preserveScroll: true })}
        >
          Retire
        </button>
      </div>
    </form>
  )
}

function NewCategoryForm() {
  const form = useForm(BLANK)

  function submit(event: FormEvent) {
    event.preventDefault()
    const sent = form.data
    form.transform((data) => ({ category: data }))
    form.post('/categories', {
      preserveScroll: true,
      errorBag: 'new_category',
      onSuccess: () => form.setData((data) => moveUntyped(data, sent, BLANK)),
    })
  }

  return (
    <form onSubmit={submit} aria-label="Add category" className="grid gap-3 rounded border border-gray-200 bg-white px-4 py-4 sm:grid-cols-[1fr_2fr_1fr_auto] sm:items-start">
      <TextFields form={form} prefix="new_category" />
      <div className="sm:pt-6">
        <button type="submit" disabled={form.processing} className={primaryButtonClass}>
          Add category
        </button>
      </div>
    </form>
  )
}

export default function CategoriesIndex({ categories, retired_categories }: CategoriesIndexProps) {
  return (
    <>
      <Head title="Categories" />
      <AppNav />
      <main className="mx-auto flex max-w-6xl flex-col gap-6 px-6 py-8">
        <div className="flex flex-col gap-1">
          <h1 className="text-2xl font-bold tracking-tight text-gray-900">Categories</h1>
          <p className="text-sm text-gray-600">One list for every product. The classifier picks from the active categories.</p>
        </div>
        <FlashNotice />

        <div className="divide-y divide-gray-200 rounded border border-gray-200 bg-white">
          {categories.map((category) => (
            <CategoryEditor key={category.id} category={category} />
          ))}
        </div>

        <NewCategoryForm />

        {retired_categories.length > 0 && (
          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-gray-700">Retired</h2>
            <p className="text-xs text-gray-500">Retired categories stay on past items but are left out of new classification.</p>
            <ul className="divide-y divide-gray-200 rounded border border-gray-200 bg-gray-50">
              {retired_categories.map((category) => (
                <li key={category.id} className="flex items-center justify-between px-4 py-3 text-sm">
                  <span className="text-gray-600">
                    {category.name} <span className="text-xs text-gray-500">({plural(category.item_count, 'item')})</span>
                  </span>
                  <button
                    type="button"
                    className={secondaryButtonClass}
                    onClick={() => router.patch(`/categories/${category.id}/restore`, {}, { preserveScroll: true })}
                  >
                    Restore
                  </button>
                </li>
              ))}
            </ul>
          </section>
        )}
      </main>
    </>
  )
}
