import { formatTime } from '../lib/feed-format'
import type { TimelineEvent } from '../types/items'

function text(value: unknown): string | null {
  if (value === null || value === undefined || value === '') return null
  return String(value).replace(/_/g, ' ')
}

export function describeEvent(event: TimelineEvent): string {
  const { data } = event
  switch (event.kind) {
    case 'arrived':
      return 'Message arrived'
    case 'classified':
      return 'Classified'
    case 'classification_failed':
      return text(data.error) ? `Classification failed: ${text(data.error)}` : 'Classification failed'
    case 'corrected':
      return `Changed ${text(data.label) ?? 'a label'} from ${text(data.from) ?? 'none'} to ${text(data.to) ?? 'none'}`
    case 'claimed':
      return 'Claimed'
    case 'released':
      return 'Released the claim'
    case 'reassigned':
      return 'Reassigned'
    case 'reported':
      return text(data.status) ? `Reported back, status ${text(data.status)}` : 'Reported back'
    case 'status_changed': {
      const change = `Status changed from ${text(data.from) ?? 'none'} to ${text(data.to) ?? 'none'}`
      return text(data.released_agent) ? `${change}, releasing ${text(data.released_agent)}` : change
    }
    case 'overdue':
      return 'Flagged overdue'
    case 'escalated':
      return 'Escalated to Slack'
    default: {
      const unhandled: never = event.kind
      return unhandled
    }
  }
}

function detail(event: TimelineEvent): string | null {
  return text(event.data.summary) ?? text(event.data.reason)
}

function safeLink(value: unknown): string | null {
  return typeof value === 'string' && /^https?:\/\//.test(value) ? value : null
}

export default function Timeline({ events }: { events: TimelineEvent[] }) {
  if (events.length === 0) {
    return <p className="text-sm text-gray-500">Nothing has happened to this item yet.</p>
  }

  return (
    <ol className="relative flex flex-col gap-4 border-l border-gray-200 pl-5">
      {events.map((event) => {
        const note = detail(event)
        const link = safeLink(event.data.link)
        return (
          <li key={event.id} className="relative">
            <span
              aria-hidden="true"
              className="absolute top-1.5 -left-[25px] h-2.5 w-2.5 rounded-full border-2 border-white bg-gray-400"
            />
            <p className="text-sm text-gray-900">
              <span className="font-medium">{event.actor.name}</span>
              {event.actor.type === 'Agent' && <span className="text-gray-500"> (agent)</span>}
              <span className="text-gray-700"> · {describeEvent(event)}</span>
            </p>
            {note && <p className="mt-0.5 text-sm text-gray-600">{note}</p>}
            {link && (
              <a href={link} className="mt-0.5 block text-sm text-blue-700 underline" rel="noreferrer" target="_blank">
                {link}
              </a>
            )}
            <time dateTime={event.created_at} className="text-xs text-gray-500">
              {formatTime(event.created_at)}
            </time>
          </li>
        )
      })}
    </ol>
  )
}
