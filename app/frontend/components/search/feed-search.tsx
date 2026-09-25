import { router } from '@inertiajs/react'
import { type FormEvent, useEffect, useRef, useState } from 'react'
import type { ChipKind, SearchChip, SearchProps } from '../../types/search'

export const SEARCH_DEBOUNCE_MS = 200
export const ENCODING_RELOAD_MS = 400
// Query encoding is one Jev call; after this many reloads keyword results stay.
const MAX_ENCODING_RELOADS = 10
const MAX_QUERY_LENGTH = 200
const VISIT = { preserveState: true, preserveScroll: true }

const CHIP_STYLES: Record<ChipKind, string> = {
  filter: 'bg-gray-900 text-white',
  boost: 'bg-white text-gray-800 ring-1 ring-inset ring-gray-300',
}

function chipTitle(chip: SearchChip): string {
  switch (chip.kind) {
    case 'filter':
      return `Only items where ${chip.name.toLowerCase()}`
    case 'boost':
      return `Ranks items where ${chip.name.toLowerCase()} higher`
    default: {
      const unreachable: never = chip.kind
      return unreachable
    }
  }
}

interface Props {
  search: SearchProps | null
  filterQuery: Record<string, string>
}

// Keystroke search on the feed: typing reloads the feed with `q` (no network
// call to Jev), Enter starts a Smart search. Chips show how the query was
// read; removing one searches again without it.
export default function FeedSearch({ search, filterQuery }: Props) {
  const [text, setText] = useState(search?.query ?? '')
  const sent = useRef(search?.query ?? '')
  const reloads = useRef(0)
  const filters = JSON.stringify(filterQuery)

  useEffect(() => {
    if (text === sent.current) return
    const timer = window.setTimeout(() => {
      sent.current = text
      const base = JSON.parse(filters) as Record<string, string>
      router.get('/items', text.trim() ? { ...base, q: text } : base, { ...VISIT, replace: true })
    }, SEARCH_DEBOUNCE_MS)
    return () => window.clearTimeout(timer)
  }, [text, filters])

  useEffect(() => {
    reloads.current = 0
  }, [search?.query])

  useEffect(() => {
    if (search?.encoding_status !== 'pending' || reloads.current >= MAX_ENCODING_RELOADS) return
    const timer = window.setTimeout(() => {
      reloads.current += 1
      router.reload({ only: ['items', 'search'] })
    }, ENCODING_RELOAD_MS)
    return () => window.clearTimeout(timer)
  }, [search])

  function startSmart(event?: FormEvent) {
    event?.preventDefault()
    if (!text.trim()) return
    sent.current = text
    const removed = search && search.query === text ? search.removed : []
    router.post('/items/search', { ...filterQuery, q: text, removed }, VISIT)
  }

  function removeChip(chip: SearchChip) {
    if (!search) return
    router.get('/items', { ...filterQuery, q: search.query, removed: [...search.removed, chip.key] }, VISIT)
  }

  const pending = search?.encoding_status === 'pending'
  const invite = search?.invite_row && search.invite_row.reason !== 'encoding_pending' && !search.run_id ? search.invite_row : null

  return (
    <section aria-label="Search the feed" className="flex flex-col gap-2">
      <form role="search" onSubmit={startSmart} className="flex gap-2">
        <label htmlFor="feed-search" className="sr-only">
          Search the feed
        </label>
        <input
          id="feed-search"
          type="search"
          value={text}
          maxLength={MAX_QUERY_LENGTH}
          autoComplete="off"
          onChange={(event) => setText(event.target.value)}
          placeholder='Search: "angry Cora billing this week", "needs action now"'
          className="w-full rounded border border-gray-300 bg-white px-3 py-2 text-sm shadow-sm focus:border-gray-900 focus:outline-none"
        />
        <button type="submit" className="whitespace-nowrap rounded bg-gray-900 px-3 py-2 text-sm font-medium text-white">
          Smart search
        </button>
      </form>

      {search && (search.chips.length > 0 || pending) && (
        <ul aria-label="How your search was read" className="flex flex-wrap items-center gap-2 text-sm">
          {search.chips.map((chip) => (
            <li key={chip.key} className={`inline-flex items-center gap-1 rounded-full py-0.5 pr-1 pl-2.5 ${CHIP_STYLES[chip.kind]}`}>
              <span title={chipTitle(chip)}>{chip.name}</span>
              <button
                type="button"
                onClick={() => removeChip(chip)}
                aria-label={`Remove ${chip.name}`}
                className="rounded-full px-1.5 leading-5 opacity-70 hover:opacity-100"
              >
                ×
              </button>
            </li>
          ))}
          {pending && (
            <li role="status" className="text-gray-500">
              Reading your search…
            </li>
          )}
        </ul>
      )}

      {invite && (
        <button
          type="button"
          onClick={() => startSmart()}
          className="self-start rounded border border-dashed border-gray-300 px-3 py-1.5 text-left text-sm text-gray-700 hover:bg-gray-50"
        >
          {invite.reason === 'empty' ? 'No keyword matches. ' : 'Only a few matches. '}
          Press Enter to have Jev read the feed for “{search?.query}”.
        </button>
      )}
    </section>
  )
}
