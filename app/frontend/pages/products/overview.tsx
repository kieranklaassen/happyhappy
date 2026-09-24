import { Head, Link } from '@inertiajs/react'
import AppNav from '../../components/app-nav'
import ItemRow from '../../components/item-row'
import SentimentChart, { type DayCounts } from '../../components/sentiment-chart'
import { SENTIMENTS, SENTIMENT_COLORS, sentimentLabel } from '../../lib/feed-format'
import type { ItemRowData, ProductOption } from '../../types/items'

export interface ProductOverviewProps {
  product: ProductOption
  days: DayCounts[]
  totals: Omit<DayCounts, 'date'>
  notable_complaints: ItemRowData[]
  notable_praise: ItemRowData[]
  products: ProductOption[]
}

function Notable({ id, title, items, empty }: { id: string; title: string; items: ItemRowData[]; empty: string }) {
  return (
    <section aria-labelledby={id} className="flex flex-col gap-3">
      <h2 id={id} className="text-lg font-semibold text-gray-900">
        {title}
      </h2>
      {items.length === 0 ? (
        <p className="text-sm text-gray-500">{empty}</p>
      ) : (
        <ul className="rounded border border-gray-200 bg-white">
          {items.map((item) => (
            <ItemRow key={item.id} item={item} />
          ))}
        </ul>
      )}
    </section>
  )
}

export default function ProductOverview({
  product,
  days,
  totals,
  notable_complaints,
  notable_praise,
  products,
}: ProductOverviewProps) {
  return (
    <>
      <Head title={`${product.name} overview`} />
      <AppNav />
      <main className="mx-auto flex max-w-6xl flex-col gap-6 px-6 py-8">
        <header className="flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 className="text-2xl font-bold tracking-tight text-gray-900">
              {product.name} overview
              {product.retired && <span className="ml-2 text-base font-normal text-gray-500">(retired)</span>}
            </h1>
            <p className="mt-1 text-sm text-gray-600">Relevant items from the last 30 days, by day of arrival.</p>
          </div>
          <nav aria-label="Other products" className="flex flex-wrap gap-2 text-sm">
            {products
              .filter((other) => other.id !== product.id && !other.retired)
              .map((other) => (
                <Link
                  key={other.id}
                  href={`/products/${other.slug}/overview`}
                  className="rounded px-2 py-1 text-gray-700 hover:bg-gray-100"
                >
                  {other.name}
                </Link>
              ))}
            <Link href={`/items?product=${product.id}`} className="rounded px-2 py-1 text-blue-700 underline">
              Open in feed
            </Link>
          </nav>
        </header>

        <section aria-labelledby="mix-heading" className="flex flex-col gap-4 rounded border border-gray-200 bg-white p-4">
          <h2 id="mix-heading" className="text-lg font-semibold text-gray-900">
            Volume and mix
          </h2>
          <dl className="grid grid-cols-2 gap-3 sm:grid-cols-5">
            <div>
              <dt className="text-xs text-gray-500">Total</dt>
              <dd className="text-2xl font-semibold text-gray-900">{totals.total}</dd>
            </div>
            {SENTIMENTS.map((sentiment) => (
              <div key={sentiment}>
                <dt className="flex items-center gap-1 text-xs text-gray-500">
                  <span aria-hidden="true" className={`h-2 w-2 rounded-sm ${SENTIMENT_COLORS[sentiment]}`} />
                  {sentimentLabel(sentiment)}
                </dt>
                <dd className="text-2xl font-semibold text-gray-900">{totals[sentiment]}</dd>
              </div>
            ))}
          </dl>
          {totals.total === 0 ? (
            <p className="text-sm text-gray-500">No items about {product.name} in the last 30 days.</p>
          ) : (
            <SentimentChart days={days} />
          )}
        </section>

        <div className="grid gap-6 lg:grid-cols-2">
          <Notable
            id="complaints-heading"
            title="Notable complaints"
            items={notable_complaints}
            empty="No complaints in the last 30 days."
          />
          <Notable
            id="praise-heading"
            title="Notable praise"
            items={notable_praise}
            empty="No praise in the last 30 days."
          />
        </div>
      </main>
    </>
  )
}
