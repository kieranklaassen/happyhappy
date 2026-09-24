import { Link } from '@inertiajs/react'
import {
  SENTIMENT_BADGES,
  formatPercent,
  formatTime,
  sentimentLabel,
  sourceKindLabel,
  statusLabel,
} from '../lib/feed-format'
import type { ItemRowData } from '../types/items'

// Low anger is the common case; the badge only calls out items worth a look.
const ANGER_BADGE_MIN = 0.5
const BADGE = 'inline-flex items-center rounded px-1.5 py-0.5 text-xs font-medium ring-1 ring-inset'

export default function ItemRow({ item }: { item: ItemRowData }) {
  return (
    <li className="border-b border-gray-100 last:border-b-0">
      <Link
        href={`/items/${item.id}`}
        className="flex flex-col gap-2 px-4 py-3 hover:bg-gray-50 focus:bg-gray-50 focus:outline-none"
      >
        <div className="flex flex-wrap items-center gap-2 text-xs text-gray-500">
          <span className="font-medium text-gray-900">{item.author}</span>
          <span aria-hidden="true">·</span>
          <span>
            {sourceKindLabel(item.source.kind)} · {item.source.name}
          </span>
          <span aria-hidden="true">·</span>
          <time dateTime={item.last_message_at}>{formatTime(item.last_message_at)}</time>
        </div>

        <p className="line-clamp-2 text-sm text-gray-800">{item.excerpt || 'No message text.'}</p>

        <div className="flex flex-wrap items-center gap-1.5">
          {item.sentiment && (
            <span className={`${BADGE} ${SENTIMENT_BADGES[item.sentiment]}`}>{sentimentLabel(item.sentiment)}</span>
          )}
          <span className={`${BADGE} bg-white text-gray-700 ring-gray-200`}>
            {item.product ? item.product.name : 'No product'}
            {item.product?.retired && ' (retired)'}
          </span>
          {item.category && (
            <span className={`${BADGE} bg-white text-gray-700 ring-gray-200`}>{item.category.name}</span>
          )}
          <span className={`${BADGE} bg-gray-100 text-gray-800 ring-gray-200`}>{statusLabel(item.status)}</span>
          {item.claimed_by && (
            <span className={`${BADGE} bg-white text-gray-700 ring-gray-200`}>Claimed by {item.claimed_by}</span>
          )}
          {item.overdue && <span className={`${BADGE} bg-amber-50 text-amber-800 ring-amber-300`}>Overdue</span>}
          {item.needs_review && (
            <span className={`${BADGE} bg-violet-50 text-violet-700 ring-violet-200`}>Needs review</span>
          )}
          {!item.relevant && (
            <span className={`${BADGE} bg-gray-50 text-gray-500 ring-gray-200`}>Not relevant</span>
          )}
          {item.anger_probability !== null && item.anger_probability >= ANGER_BADGE_MIN && (
            <span className={`${BADGE} bg-red-50 text-red-700 ring-red-200`}>
              Anger {formatPercent(item.anger_probability)}
            </span>
          )}
        </div>
      </Link>
    </li>
  )
}
