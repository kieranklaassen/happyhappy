import { Head, router, useForm } from '@inertiajs/react'
import { type FormEvent } from 'react'
import AppNav from '../../components/app-nav'
import { Field, FlashNotice, inputClass, primaryButtonClass, secondaryButtonClass } from '../../components/form-field'

interface CategoryRow {
  id: number
  name: string
  description: string | null
  position: number
  retired_at: string | null
  item_count: number
}

interface CategoriesIndexProps {
  categories: CategoryRow[]
  retired_categories: CategoryRow[]
}

function CategoryEditor({ category }: { category: CategoryRow }) {
  const form = useForm({
    name: category.name,
    description: category.description ?? '',
    position: category.position.toString(),
  })
  const prefix = `category_${category.id}`

  function submit(event: FormEvent) {
    event.preventDefault()
    form.transform((data) => ({ category: data }))
    form.patch(`/categories/${category.id}`, { preserveScroll: true, onSuccess: () => form.setDefaults() })
  }

  return (
    <form onSubmit={submit} aria-label={`Edit ${category.name}`} className="grid gap-3 px-4 py-4 sm:grid-cols-[5rem_1fr_2fr_auto] sm:items-start">
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
      <Field label="Name" htmlFor={`${prefix}_name`} error={form.errors.name} hint={`${category.item_count} items`}>
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
  const form = useForm({ name: '', description: '' })

  function submit(event: FormEvent) {
    event.preventDefault()
    form.transform((data) => ({ category: data }))
    form.post('/categories', { preserveScroll: true, onSuccess: () => form.reset() })
  }

  return (
    <form onSubmit={submit} aria-label="Add category" className="grid gap-3 rounded border border-gray-200 bg-white px-4 py-4 sm:grid-cols-[1fr_2fr_auto] sm:items-start">
      <Field label="Name" htmlFor="new_category_name" error={form.errors.name}>
        <input
          id="new_category_name"
          required
          value={form.data.name}
          onChange={(e) => form.setData('name', e.target.value)}
          className={inputClass}
        />
      </Field>
      <Field label="Description" htmlFor="new_category_description" error={form.errors.description}>
        <input
          id="new_category_description"
          value={form.data.description}
          onChange={(e) => form.setData('description', e.target.value)}
          className={inputClass}
        />
      </Field>
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
                    {category.name} <span className="text-xs text-gray-500">({category.item_count} items)</span>
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
