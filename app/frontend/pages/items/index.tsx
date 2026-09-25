import { Head, Link, router } from '@inertiajs/react'
import { type FormEvent, useState } from 'react'
import AppNav from '../../components/app-nav'
import ItemRow from '../../components/item-row'
import { useMoodStream } from '../../components/mood/use-mood-stream'
import { anomalyValue, anomalyWindow } from '../../lib/anomaly-format'
import { sentimentLabel, sourceKindLabel, statusLabel } from '../../lib/feed-format'
import type { AnomalyProps } from '../../types/anomalies'
import type {
  CategoryOption,
  ItemRowData,
  ItemStatus,
  ProductOption,
  Sentiment,
  SourceOption,
} from '../../types/items'

export interface FeedFilters {
  product?: string[]
  sentiment?: string[]
  category?: string[]
  status?: string[]
  source?: string[]
  source_kind?: string[]
  range?: string
  since?: string
  until?: string
  needs_review?: boolean
  overdue?: boolean
  relevance?: 'relevant' | 'not_relevant' | 'all'
  anomaly?: string
}

export interface FeedProps {
  items: ItemRowData[]
  filters: FeedFilters
  pagination: { page: number; prev_page: number | null; next_page: number | null }
  options: {
    products: ProductOption[]
    categories: CategoryOption[]
    sources: SourceOption[]
    sentiments: Sentiment[]
    statuses: ItemStatus[]
    ranges: string[]
  }
  anomalies: AnomalyProps[]
  error: string | null
}

interface FormState {
  product: string
  sentiment: string
  category: string
  status: string
  source: string
  range: string
  relevance: string
  needs_review: boolean
  overdue: boolean
  anomaly: string
}

const RANGE_LABELS: Record<string, string> = {
  '24h': 'Last 24 hours',
  '7d': 'Last 7 days',
  '30d': 'Last 30 days',
  '90d': 'Last 90 days',
}

function initialState(filters: FeedFilters, products: ProductOption[]): FormState {
  const product = filters.product?.[0] ?? ''
  const bySlug = products.find((candidate) => candidate.slug === product)

  return {
    product: bySlug ? String(bySlug.id) : product,
    sentiment: filters.sentiment?.[0] ?? '',
    category: filters.category?.[0] ?? '',
    status: filters.status?.[0] ?? '',
    source: filters.source?.[0] ?? '',
    range: filters.range ?? '',
    relevance: filters.relevance ?? 'relevant',
    needs_review: Boolean(filters.needs_review),
    overdue: Boolean(filters.overdue),
    anomaly: filters.anomaly ?? '',
  }
}

export function toQuery(state: FormState): Record<string, string> {
  const query: Record<string, string> = {}
  for (const key of ['product', 'sentiment', 'category', 'status', 'source', 'range'] as const) {
    if (state[key]) query[key] = state[key]
  }
  if (state.relevance !== 'relevant') query.relevance = state.relevance
  if (state.needs_review) query.needs_review = '1'
  if (state.overdue) query.overdue = '1'
  if (state.anomaly) query.anomaly = state.anomaly
  return query
}

function describe(anomaly: AnomalyProps): string {
  const where = anomaly.source ? `${anomaly.product.name} on ${anomaly.source.name}` : anomaly.product.name
  return `${anomaly.label} for ${where}: ${anomalyValue(anomaly, anomaly.actual)} ${anomalyWindow(anomaly)}, usually ${anomalyValue(anomaly, anomaly.expected)}`
}

export function AnomalyBanner({ anomalies, filter }: { anomalies: AnomalyProps[]; filter?: string }) {
  const selected = filter && filter !== 'active' ? anomalies.find((anomaly) => String(anomaly.id) === filter) : undefined
  if (filter) {
    return (
      <p role="status" className="flex flex-wrap items-center justify-between gap-2 rounded bg-amber-50 px-4 py-3 text-sm text-amber-900">
        <span>
          {filter === 'active'
            ? 'Showing items behind the active anomalies.'
            : selected
              ? `Showing items behind: ${describe(selected)}.`
              : `Showing items behind anomaly ${filter}.`}
        </span>
        <Link href="/items" className="font-medium underline">
          Show the whole feed
        </Link>
      </p>
    )
  }
  if (anomalies.length === 0) return null

  return (
    <section aria-label="Active anomalies" className="rounded bg-amber-50 px-4 py-3 text-sm text-amber-900">
      <p className="flex flex-wrap items-center justify-between gap-2">
        <strong className="font-semibold">
          {anomalies.length === 1 ? '1 anomaly is active' : `${anomalies.length} anomalies are active`}
        </strong>
        <Link href="/items?anomaly=active" className="font-medium underline">
          Show their items
        </Link>
      </p>
      <ul className="mt-1 list-disc pl-5">
        {anomalies.slice(0, 3).map((anomaly) => (
          <li key={anomaly.id}>
            <Link href={`/items?anomaly=${anomaly.id}`} className="hover:underline">
              {describe(anomaly)}
            </Link>
          </li>
        ))}
      </ul>
    </section>
  )
}

const SELECT = 'rounded border border-gray-300 bg-white py-1.5 pr-8 pl-2 text-sm'

const LIVE_PROPS = ['items', 'anomalies']

export default function ItemsIndex({ items, filters, pagination, options, anomalies, error }: FeedProps) {
  useMoodStream(LIVE_PROPS)
  const [form, setForm] = useState<FormState>(() => initialState(filters, options.products))
  const query = toQuery(initialState(filters, options.products))
  const selectedProduct = options.products.find((product) => String(product.id) === form.product)

  function update<K extends keyof FormState>(key: K, value: FormState[K]) {
    setForm((current) => ({ ...current, [key]: value }))
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    router.get('/items', toQuery(form), { preserveScroll: true })
  }

  function pageHref(page: number) {
    const params = new URLSearchParams({ ...query, page: String(page) })
    return `/items?${params.toString()}`
  }

  return (
    <>
      <Head title="Feed" />
      <AppNav />
      <main className="mx-auto flex max-w-6xl flex-col gap-6 px-6 py-8">
        <header className="flex flex-wrap items-baseline justify-between gap-2">
          <h1 className="text-2xl font-bold tracking-tight text-gray-900">Feed</h1>
          {selectedProduct && (
            <Link href={`/products/${selectedProduct.slug}/overview`} className="text-sm text-blue-700 underline">
              {selectedProduct.name} overview
            </Link>
          )}
        </header>

        <AnomalyBanner anomalies={anomalies} filter={filters.anomaly} />

        <form
          onSubmit={submit}
          aria-label="Filter the feed"
          className="flex flex-wrap items-end gap-3 rounded border border-gray-200 bg-white p-4"
        >
          <label className="flex flex-col gap-1 text-xs font-medium text-gray-700">
            Product
            <select className={SELECT} value={form.product} onChange={(e) => update('product', e.target.value)}>
              <option value="">All products</option>
              <option value="none">No product</option>
              {options.products.map((product) => (
                <option key={product.id} value={String(product.id)}>
                  {product.name}
                  {product.retired ? ' (retired)' : ''}
                </option>
              ))}
            </select>
          </label>

          <label className="flex flex-col gap-1 text-xs font-medium text-gray-700">
            Sentiment
            <select className={SELECT} value={form.sentiment} onChange={(e) => update('sentiment', e.target.value)}>
              <option value="">All sentiments</option>
              {options.sentiments.map((sentiment) => (
                <option key={sentiment} value={sentiment}>
                  {sentimentLabel(sentiment)}
                </option>
              ))}
            </select>
          </label>

          <label className="flex flex-col gap-1 text-xs font-medium text-gray-700">
            Category
            <select className={SELECT} value={form.category} onChange={(e) => update('category', e.target.value)}>
              <option value="">All categories</option>
              {options.categories.map((category) => (
                <option key={category.id} value={String(category.id)}>
                  {category.name}
                  {category.retired ? ' (retired)' : ''}
                </option>
              ))}
            </select>
          </label>

          <label className="flex flex-col gap-1 text-xs font-medium text-gray-700">
            Status
            <select className={SELECT} value={form.status} onChange={(e) => update('status', e.target.value)}>
              <option value="">All statuses</option>
              {options.statuses.map((status) => (
                <option key={status} value={status}>
                  {statusLabel(status)}
                </option>
              ))}
            </select>
          </label>

          <label className="flex flex-col gap-1 text-xs font-medium text-gray-700">
            Source
            <select className={SELECT} value={form.source} onChange={(e) => update('source', e.target.value)}>
              <option value="">All sources</option>
              {options.sources.map((source) => (
                <option key={source.id} value={String(source.id)}>
                  {sourceKindLabel(source.kind)}: {source.name}
                </option>
              ))}
            </select>
          </label>

          <label className="flex flex-col gap-1 text-xs font-medium text-gray-700">
            Time range
            <select className={SELECT} value={form.range} onChange={(e) => update('range', e.target.value)}>
              <option value="">Any time</option>
              {options.ranges.map((range) => (
                <option key={range} value={range}>
                  {RANGE_LABELS[range] ?? range}
                </option>
              ))}
            </select>
          </label>

          <label className="flex flex-col gap-1 text-xs font-medium text-gray-700">
            Relevance
            <select className={SELECT} value={form.relevance} onChange={(e) => update('relevance', e.target.value)}>
              <option value="relevant">Relevant only</option>
              <option value="not_relevant">Not relevant only</option>
              <option value="all">Everything</option>
            </select>
          </label>

          <label className="flex items-center gap-2 py-1.5 text-sm text-gray-700">
            <input
              type="checkbox"
              checked={form.needs_review}
              onChange={(e) => update('needs_review', e.target.checked)}
              className="rounded border-gray-300"
            />
            Needs review
          </label>

          <label className="flex items-center gap-2 py-1.5 text-sm text-gray-700">
            <input
              type="checkbox"
              checked={form.overdue}
              onChange={(e) => update('overdue', e.target.checked)}
              className="rounded border-gray-300"
            />
            Overdue
          </label>

          <label className="flex items-center gap-2 py-1.5 text-sm text-gray-700">
            <input
              type="checkbox"
              checked={form.anomaly !== ''}
              onChange={(e) => update('anomaly', e.target.checked ? 'active' : '')}
              className="rounded border-gray-300"
            />
            In an active anomaly
          </label>

          <div className="flex gap-2">
            <button type="submit" className="rounded bg-gray-900 px-3 py-1.5 text-sm font-medium text-white">
              Apply filters
            </button>
            <Link href="/items" className="rounded px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-100">
              Clear
            </Link>
          </div>
        </form>

        {error ? (
          <p role="alert" className="rounded bg-red-50 px-4 py-3 text-sm text-red-700">
            {error}
          </p>
        ) : items.length === 0 ? (
          <section aria-labelledby="empty-feed" className="rounded border border-dashed border-gray-300 p-8 text-center">
            <h2 id="empty-feed" className="text-base font-semibold text-gray-900">
              No items match these filters
            </h2>
            <p className="mt-1 text-sm text-gray-600">
              Try a wider time range or clear the filters. New messages appear here once a source delivers them.
            </p>
          </section>
        ) : (
          <section aria-labelledby="feed-items">
            <h2 id="feed-items" className="sr-only">
              Items
            </h2>
            <ul className="rounded border border-gray-200 bg-white">
              {items.map((item) => (
                <ItemRow key={item.id} item={item} />
              ))}
            </ul>
          </section>
        )}

        {(pagination.prev_page || pagination.next_page) && (
          <nav aria-label="Pagination" className="flex items-center justify-between text-sm">
            {pagination.prev_page ? (
              <Link href={pageHref(pagination.prev_page)} className="text-blue-700 underline">
                Newer
              </Link>
            ) : (
              <span />
            )}
            <span className="text-gray-500">Page {pagination.page}</span>
            {pagination.next_page ? (
              <Link href={pageHref(pagination.next_page)} className="text-blue-700 underline">
                Older
              </Link>
            ) : (
              <span />
            )}
          </nav>
        )}
      </main>
    </>
  )
}
