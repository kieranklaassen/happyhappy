import { Head, Link, router, usePage } from '@inertiajs/react'
import { type FormEvent, type ReactNode, useState } from 'react'
import AppNav from '../../components/app-nav'
import Timeline from '../../components/timeline'
import {
  formatPercent,
  formatTime,
  safeLink,
  sentimentLabel,
  sourceKindLabel,
  statusLabel,
} from '../../lib/feed-format'
import type {
  CategoryOption,
  FlashProps,
  ItemDetail,
  ItemStatus,
  Label,
  MessageData,
  ProductOption,
  Sentiment,
  TimelineEvent,
} from '../../types/items'

export interface ItemShowProps {
  item: ItemDetail
  messages: MessageData[]
  events: TimelineEvent[]
  options: {
    products: ProductOption[]
    categories: CategoryOption[]
    sentiments: Sentiment[]
    statuses: ItemStatus[]
  }
  low_confidence_threshold: number
}

type LabelName = 'product' | 'category' | 'sentiment' | 'relevant'

interface LabelFormProps {
  itemId: number
  name: LabelName
  title: string
  label: Label<unknown>
  current: string
  display: ReactNode
  threshold: number
  children: ReactNode
}

function LabelForm({ itemId, name, title, label, current, display, threshold, children }: LabelFormProps) {
  const [value, setValue] = useState(current)
  const [processing, setProcessing] = useState(false)
  const lowConfidence = !label.human_set && label.probability !== null && label.probability < threshold
  const inputId = `label-${name}`

  function submit(event: FormEvent) {
    event.preventDefault()
    router.patch(
      `/items/${itemId}/labels`,
      { label: name, value },
      { preserveScroll: true, onStart: () => setProcessing(true), onFinish: () => setProcessing(false) },
    )
  }

  return (
    <form onSubmit={submit} className="flex flex-col gap-2 border-b border-gray-100 py-3 last:border-b-0">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="text-xs font-medium tracking-wide text-gray-500 uppercase">{title}</span>
        <span className="text-xs text-gray-500">
          {label.human_set ? (
            <span className="rounded bg-blue-50 px-1.5 py-0.5 font-medium text-blue-700">Human set</span>
          ) : (
            <>Confidence {formatPercent(label.probability)}</>
          )}
          {lowConfidence && (
            <span className="ml-1.5 rounded bg-violet-50 px-1.5 py-0.5 font-medium text-violet-700">Low confidence</span>
          )}
        </span>
      </div>
      <p className="text-sm font-medium text-gray-900">{display}</p>
      <div className="flex gap-2">
        <label htmlFor={inputId} className="sr-only">
          Correct {title.toLowerCase()}
        </label>
        <select
          id={inputId}
          value={value}
          onChange={(e) => setValue(e.target.value)}
          className="min-w-0 flex-1 rounded border border-gray-300 bg-white py-1.5 pr-8 pl-2 text-sm"
        >
          {children}
        </select>
        <button
          type="submit"
          disabled={processing || (label.human_set && value === current)}
          className="rounded border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-800 hover:bg-gray-50 disabled:opacity-50"
        >
          Save {title.toLowerCase()}
        </button>
      </div>
    </form>
  )
}

export default function ItemShow({ item, messages, events, options, low_confidence_threshold }: ItemShowProps) {
  const { flash } = usePage<FlashProps>().props
  const { labels } = item
  const permalink = safeLink(item.permalink)

  function changeStatus(status: ItemStatus) {
    router.patch(`/items/${item.id}/status`, { status }, { preserveScroll: true })
  }

  return (
    <>
      <Head title={`Item from ${item.author}`} />
      <AppNav />
      <main className="mx-auto flex max-w-6xl flex-col gap-6 px-6 py-8">
        <div>
          <Link href="/items" className="text-sm text-blue-700 underline">
            Back to feed
          </Link>
        </div>

        {flash.notice && (
          <p role="status" className="rounded bg-emerald-50 px-4 py-2 text-sm text-emerald-800">
            {flash.notice}
          </p>
        )}
        {flash.alert && (
          <p role="alert" className="rounded bg-red-50 px-4 py-2 text-sm text-red-700">
            {flash.alert}
          </p>
        )}

        <header className="flex flex-col gap-2">
          <h1 className="text-2xl font-bold tracking-tight text-gray-900">{item.author}</h1>
          <p className="text-sm text-gray-600">
            {sourceKindLabel(item.source.kind)} · {item.source.name}
            {item.author_email && <> · {item.author_email}</>}
            {permalink && (
              <>
                {' · '}
                <a href={permalink} target="_blank" rel="noreferrer" className="text-blue-700 underline">
                  Open original
                </a>
              </>
            )}
          </p>
          <div className="flex flex-wrap gap-1.5 text-xs">
            <span className="rounded bg-gray-100 px-1.5 py-0.5 font-medium text-gray-800">
              {statusLabel(item.status)}
            </span>
            {item.claimed_by && (
              <span className="rounded bg-white px-1.5 py-0.5 text-gray-700 ring-1 ring-gray-200">
                Claimed by {item.claimed_by}
                {item.claimed_at && <> since {formatTime(item.claimed_at)}</>}
              </span>
            )}
            {item.overdue && (
              <span className="rounded bg-amber-50 px-1.5 py-0.5 font-medium text-amber-800 ring-1 ring-amber-300">
                Overdue
              </span>
            )}
            {item.needs_review && (
              <span className="rounded bg-violet-50 px-1.5 py-0.5 font-medium text-violet-700">Needs review</span>
            )}
            <span className="rounded bg-white px-1.5 py-0.5 text-gray-700 ring-1 ring-gray-200">
              Anger {formatPercent(item.anger_probability)}
            </span>
          </div>
        </header>

        <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_20rem]">
          <div className="flex flex-col gap-6">
            <section aria-labelledby="messages-heading" className="flex flex-col gap-3">
              <h2 id="messages-heading" className="text-lg font-semibold text-gray-900">
                Messages
              </h2>
              {messages.length === 0 ? (
                <p className="text-sm text-gray-500">No messages stored for this item.</p>
              ) : (
                <ol className="flex flex-col gap-3">
                  {messages.map((message) => (
                    <li key={message.id} className="rounded border border-gray-200 bg-white p-4">
                      <p className="text-sm whitespace-pre-wrap text-gray-900">{message.body}</p>
                      <p className="mt-2 text-xs text-gray-500">
                        <time dateTime={message.occurred_at}>{formatTime(message.occurred_at)}</time>
                        {' · '}
                        {message.classified
                          ? `Anger ${formatPercent(message.anger_probability)}`
                          : 'Not classified yet'}
                      </p>
                    </li>
                  ))}
                </ol>
              )}
            </section>

            <section aria-labelledby="timeline-heading" className="flex flex-col gap-3">
              <h2 id="timeline-heading" className="text-lg font-semibold text-gray-900">
                Timeline
              </h2>
              <Timeline events={events} />
            </section>
          </div>

          <aside className="flex flex-col gap-6">
            <section aria-labelledby="labels-heading" className="rounded border border-gray-200 bg-white px-4 py-2">
              <h2 id="labels-heading" className="pt-2 text-lg font-semibold text-gray-900">
                Labels
              </h2>
              <LabelForm
                itemId={item.id}
                name="product"
                title="Product"
                label={labels.product}
                current={labels.product.value ? String(labels.product.value.id) : ''}
                threshold={low_confidence_threshold}
                display={
                  labels.product.value ? (
                    <Link href={`/products/${labels.product.value.slug}/overview`} className="underline">
                      {labels.product.value.name}
                      {labels.product.value.retired && ' (retired)'}
                    </Link>
                  ) : (
                    'No product'
                  )
                }
              >
                <option value="">No product</option>
                {options.products.map((product) => (
                  <option key={product.id} value={String(product.id)}>
                    {product.name}
                    {product.retired ? ' (retired)' : ''}
                  </option>
                ))}
              </LabelForm>
              <LabelForm
                itemId={item.id}
                name="category"
                title="Category"
                label={labels.category}
                current={labels.category.value ? String(labels.category.value.id) : ''}
                threshold={low_confidence_threshold}
                display={labels.category.value?.name ?? 'No category'}
              >
                <option value="">No category</option>
                {options.categories.map((category) => (
                  <option key={category.id} value={String(category.id)}>
                    {category.name}
                    {category.retired ? ' (retired)' : ''}
                  </option>
                ))}
              </LabelForm>
              <LabelForm
                itemId={item.id}
                name="sentiment"
                title="Sentiment"
                label={labels.sentiment}
                current={labels.sentiment.value ?? ''}
                threshold={low_confidence_threshold}
                display={sentimentLabel(labels.sentiment.value)}
              >
                <option value="">Unclassified</option>
                {options.sentiments.map((sentiment) => (
                  <option key={sentiment} value={sentiment}>
                    {sentimentLabel(sentiment)}
                  </option>
                ))}
              </LabelForm>
              <LabelForm
                itemId={item.id}
                name="relevant"
                title="Relevance"
                label={labels.relevant}
                current={String(labels.relevant.value)}
                threshold={low_confidence_threshold}
                display={labels.relevant.value ? 'Relevant' : 'Not relevant'}
              >
                <option value="true">Relevant</option>
                <option value="false">Not relevant</option>
              </LabelForm>
            </section>

            <section aria-labelledby="status-heading" className="rounded border border-gray-200 bg-white p-4">
              <h2 id="status-heading" className="text-lg font-semibold text-gray-900">
                Status
              </h2>
              <p className="mt-1 text-sm text-gray-600">
                Currently {statusLabel(item.status).toLowerCase()}.
                {item.claimed_by && ' Changing it releases the agent’s claim.'}
              </p>
              <div className="mt-3 flex flex-wrap gap-2">
                {options.statuses
                  .filter((status) => status !== item.status)
                  .map((status) => (
                    <button
                      key={status}
                      type="button"
                      onClick={() => changeStatus(status)}
                      className="rounded border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-800 hover:bg-gray-50"
                    >
                      {status === 'new' ? 'Reopen' : `Mark ${statusLabel(status).toLowerCase()}`}
                    </button>
                  ))}
              </div>
            </section>
          </aside>
        </div>
      </main>
    </>
  )
}
