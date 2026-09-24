import { Head, Link, router } from '@inertiajs/react'
import AppNav from '../../components/app-nav'
import { FlashNotice, primaryButtonClass, secondaryButtonClass } from '../../components/form-field'
import { formatHour } from '../../lib/format'

interface ProductRow {
  id: number
  name: string
  slug: string
  description: string | null
  hint_words: string[]
  slack_channel_id: string | null
  escalation_threshold: number | null
  digest_hour: number
  retired_at: string | null
}

interface ProductsIndexProps {
  products: ProductRow[]
  retired_products: ProductRow[]
  default_escalation_threshold: number
}

export default function ProductsIndex({
  products,
  retired_products,
  default_escalation_threshold,
}: ProductsIndexProps) {
  return (
    <>
      <Head title="Products" />
      <AppNav />
      <main className="mx-auto flex max-w-6xl flex-col gap-6 px-6 py-8">
        <div className="flex items-center justify-between">
          <h1 className="text-2xl font-bold tracking-tight text-gray-900">Products</h1>
          <Link href="/products/new" className={primaryButtonClass}>
            Add product
          </Link>
        </div>
        <FlashNotice />

        {products.length === 0 ? (
          <p className="text-sm text-gray-600">No products yet. Add one so classification has something to match.</p>
        ) : (
          <ul className="divide-y divide-gray-200 rounded border border-gray-200 bg-white">
            {products.map((product) => (
              <li key={product.id} className="flex flex-col gap-2 px-4 py-4 sm:flex-row sm:items-start sm:justify-between">
                <div className="flex flex-col gap-1">
                  <p className="font-medium text-gray-900">
                    {product.name} <span className="text-sm font-normal text-gray-500">/{product.slug}</span>
                  </p>
                  {product.description && <p className="text-sm text-gray-600">{product.description}</p>}
                  {product.hint_words.length > 0 && (
                    <p className="text-xs text-gray-500">Hint words: {product.hint_words.join(', ')}</p>
                  )}
                  <p className="text-xs text-gray-500">
                    Slack {product.slack_channel_id || 'not set'} · Escalates at{' '}
                    {product.escalation_threshold ?? `${default_escalation_threshold} (default)`} · Digest at{' '}
                    {formatHour(product.digest_hour)}
                  </p>
                </div>
                <div className="flex shrink-0 gap-2">
                  <Link href={`/products/${product.id}/edit`} className={secondaryButtonClass}>
                    Edit
                  </Link>
                  <button
                    type="button"
                    className={secondaryButtonClass}
                    onClick={() => router.patch(`/products/${product.id}/retire`)}
                  >
                    Retire
                  </button>
                </div>
              </li>
            ))}
          </ul>
        )}

        {retired_products.length > 0 && (
          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-gray-700">Retired</h2>
            <p className="text-xs text-gray-500">Retired products stay on past items but are left out of new classification.</p>
            <ul className="divide-y divide-gray-200 rounded border border-gray-200 bg-gray-50">
              {retired_products.map((product) => (
                <li key={product.id} className="flex items-center justify-between px-4 py-3 text-sm">
                  <span className="text-gray-600">{product.name}</span>
                  <button
                    type="button"
                    className={secondaryButtonClass}
                    onClick={() => router.patch(`/products/${product.id}/restore`)}
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
