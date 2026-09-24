import { SENTIMENT_COLORS, sentimentLabel } from '../lib/feed-format'
import type { Sentiment } from '../types/items'

export interface DayCounts {
  date: string
  complaint: number
  praise: number
  question: number
  neutral: number
  total: number
}

const SENTIMENTS: Sentiment[] = ['complaint', 'praise', 'question', 'neutral']

function dayLabel(day: DayCounts): string {
  const parts = SENTIMENTS.filter((sentiment) => day[sentiment] > 0).map(
    (sentiment) => `${day[sentiment]} ${sentiment}`,
  )
  const unclassified = day.total - SENTIMENTS.reduce((sum, sentiment) => sum + day[sentiment], 0)
  if (unclassified > 0) parts.push(`${unclassified} unclassified`)
  return `${day.date}: ${day.total} ${day.total === 1 ? 'item' : 'items'}${parts.length ? ` (${parts.join(', ')})` : ''}`
}

export default function SentimentChart({ days }: { days: DayCounts[] }) {
  const max = Math.max(1, ...days.map((day) => day.total))

  return (
    <figure className="flex flex-col gap-3">
      <div role="list" aria-label="Items per day by sentiment" className="flex h-40 items-end gap-1">
        {days.map((day) => (
          <div
            key={day.date}
            role="listitem"
            aria-label={dayLabel(day)}
            title={dayLabel(day)}
            className="flex h-full flex-1 flex-col justify-end"
          >
            <div
              className="flex flex-col-reverse overflow-hidden rounded-sm bg-gray-200"
              style={{ height: `${(day.total / max) * 100}%` }}
            >
              {SENTIMENTS.map((sentiment) =>
                day[sentiment] > 0 ? (
                  <div
                    key={sentiment}
                    className={SENTIMENT_COLORS[sentiment]}
                    style={{ height: `${(day[sentiment] / day.total) * 100}%` }}
                  />
                ) : null,
              )}
            </div>
          </div>
        ))}
      </div>
      <figcaption className="flex flex-wrap gap-3 text-xs text-gray-600">
        {SENTIMENTS.map((sentiment) => (
          <span key={sentiment} className="inline-flex items-center gap-1">
            <span aria-hidden="true" className={`h-2.5 w-2.5 rounded-sm ${SENTIMENT_COLORS[sentiment]}`} />
            {sentimentLabel(sentiment)}
          </span>
        ))}
        <span className="inline-flex items-center gap-1">
          <span aria-hidden="true" className="h-2.5 w-2.5 rounded-sm bg-gray-200" />
          Unclassified
        </span>
      </figcaption>
    </figure>
  )
}
