import { Link } from '@inertiajs/react'
import { type CSSProperties, useEffect, useLayoutEffect, useRef, useState } from 'react'
import Character from './character'
import Flora from './flora'
import { MOOD_COLORS, plural, timeAgo } from './format'
import { sourceKindLabel } from '../../lib/feed-format'
import { moodBlurb, moodLabel, type Mood } from './moods'
import { hashSeed } from './seed'
import Sky from './sky'
import type { MoodCharacter, MoodGroup } from '../../types/mood'

const GROUND_WASHES = ['#CFE6C0', '#E9E3B0', '#D5E8D2', '#C6E1DA', '#E5DDC0'] as const

export type MoodHistory = ReadonlyMap<string, Mood> | null

function describe(character: MoodCharacter, productName: string): string {
  const about = productName ? ` about ${productName}` : ''
  const said = character.excerpt ? `: “${character.excerpt}”` : ''
  return `${character.name} is ${moodLabel(character.mood).toLowerCase()}${about} on ${sourceKindLabel(character.source_kind)}, ${timeAgo(character.last_message_at)}${said}`
}

function statusNote(character: MoodCharacter): string | null {
  switch (character.status) {
    case 'new':
      return null
    case 'claimed':
      return 'An agent has claimed this'
    case 'in_progress':
      return 'An agent is working on it'
    case 'handled':
      return 'Handled'
    case 'dismissed':
      return 'Dismissed'
    default: {
      const unhandled: never = character.status
      return unhandled
    }
  }
}

const SHOUT_LENGTH = 56

// The one line worth reading from across the room: the angriest person, else the happiest.
export function loudest(characters: readonly MoodCharacter[]): MoodCharacter | null {
  const byAnger = (a: MoodCharacter, b: MoodCharacter) => (b.anger ?? 0) - (a.anger ?? 0)
  const furious = characters.filter((character) => character.mood === 'furious' && character.excerpt).sort(byAnger)
  if (furious.length > 0) return furious[0]
  return characters.find((character) => character.mood === 'beaming' && character.excerpt) ?? null
}

const BUBBLE_MARGIN = 8

// Nudges a bubble sideways so it never spills out of its meadow.
function useKeepInside<T extends HTMLElement>(active: boolean) {
  const ref = useRef<T>(null)
  useLayoutEffect(() => {
    const bubble = ref.current
    const meadow = bubble?.closest('section')
    if (!active || !bubble || !meadow) return
    const place = () => {
      bubble.style.setProperty('--hh-nudge', '0px')
      const box = bubble.getBoundingClientRect()
      const bounds = meadow.getBoundingClientRect()
      const left = bounds.left + BUBBLE_MARGIN - box.left
      const right = bounds.right - BUBBLE_MARGIN - box.right
      bubble.style.setProperty('--hh-nudge', `${left > 0 ? left : right < 0 ? right : 0}px`)
    }
    place()
    window.addEventListener('resize', place)
    return () => window.removeEventListener('resize', place)
  }, [active])
  return ref
}

function shorten(text: string): string {
  return text.length > SHOUT_LENGTH ? `${text.slice(0, SHOUT_LENGTH).trimEnd()}…` : text
}

function Person({ character, productName, history, shout }: { character: MoodCharacter; productName: string; history: MoodHistory; shout: boolean }) {
  const previous = history?.get(character.key)
  const arrived = history !== null && previous === undefined
  const changed = previous !== undefined && previous !== character.mood
  const event = arrived ? 'hh-arrive' : changed ? 'hh-changed' : ''
  const offset = (hashSeed(character.seed) % 5) * 5
  const note = statusNote(character)
  const bubbleRef = useKeepInside<HTMLSpanElement>(shout)

  return (
    <li className="hh-person group relative" style={{ marginTop: offset + (shout ? 64 : 0) } as CSSProperties}>
      <button
        type="button"
        className="relative block w-[76px] rounded-2xl text-left outline-none focus-visible:ring-2 focus-visible:ring-[#3E3542]/60 sm:w-[104px]"
        aria-label={describe(character, productName)}
      >
        {shout && (
          <span ref={bubbleRef} className={`hh-bubble hh-hand hh-bubble--${character.mood}`} aria-hidden="true">
            {shorten(character.excerpt)}
          </span>
        )}
        <span key={`${character.key}:${character.mood}`} className={`relative block ${event}`}>
          {changed && <span className="hh-splash" style={{ background: MOOD_COLORS[character.mood] }} aria-hidden="true" />}
          <span className={`hh-idle hh-idle--${character.mood}`}>
            <Character seed={character.seed} mood={character.mood} bandage={character.mended} />
          </span>
        </span>
        <span className="hh-hand -mt-1 block truncate text-center text-[15px] leading-tight text-[#3E3542]/80" aria-hidden="true">
          {character.name}
        </span>
      </button>
      <div className="hh-card">
        <p className="hh-hand text-xl leading-none text-[#3E3542]">
          {character.name}
          <span className="ml-2 text-base text-[#3E3542]/60">is {moodBlurb(character.mood)}</span>
        </p>
        <p className="mt-1 text-xs text-[#3E3542]/60">
          {character.handle ? `${character.handle} · ` : ''}
          {sourceKindLabel(character.source_kind)} · {timeAgo(character.last_message_at)}
          {character.threads > 1 ? ` · ${plural(character.threads, 'thread')}` : ''}
        </p>
        {character.excerpt && <blockquote className="mt-2 text-sm leading-snug text-[#3E3542]">“{character.excerpt}”</blockquote>}
        {note && <p className="mt-2 text-xs font-medium text-[#6E9F86]">{note}</p>}
        <Link href={`/items/${character.item_id}`} className="mt-3 inline-block text-sm font-semibold text-[#3E3542] underline decoration-[#F28C8C] decoration-2 underline-offset-4">
          Open in the feed
        </Link>
      </div>
    </li>
  )
}

export const WIDE_CROWD = 5
const ROW_TOLERANCE = 6

// A wrapped crowd needs a hill under every row, so measure where rows end.
function useRowBottoms(count: number) {
  const listRef = useRef<HTMLUListElement>(null)
  const [bottoms, setBottoms] = useState<number[]>([])

  useLayoutEffect(() => {
    const list = listRef.current
    if (!list || typeof ResizeObserver === 'undefined') return
    const measure = () => {
      const ends = Array.from(list.children as HTMLCollectionOf<HTMLElement>)
        .map((child) => child.offsetTop + child.offsetHeight)
        .sort((a, b) => a - b)
      const rows = ends.reduce<number[]>((acc, end) => {
        const last = acc[acc.length - 1]
        if (last !== undefined && end - last <= ROW_TOLERANCE) acc[acc.length - 1] = end
        else acc.push(end)
        return acc
      }, [])
      setBottoms((current) => (current.join() === rows.join() ? current : rows))
    }
    measure()
    const observer = new ResizeObserver(measure)
    observer.observe(list)
    return () => observer.disconnect()
  }, [count])

  return { listRef, bottoms }
}

// Off-screen meadows pause their animations; SVG animation repaints on the main thread.
function useOnScreen<T extends HTMLElement>() {
  const ref = useRef<T>(null)
  const [onScreen, setOnScreen] = useState(true)

  useEffect(() => {
    const element = ref.current
    if (!element || typeof IntersectionObserver === 'undefined') return
    const observer = new IntersectionObserver(([entry]) => setOnScreen(entry.isIntersecting), { rootMargin: '120px' })
    observer.observe(element)
    return () => observer.disconnect()
  }, [])

  return { ref, onScreen }
}

function Hill({ wash, seed, rowBottom }: { wash: string; seed: string; rowBottom?: number }) {
  const style = rowBottom === undefined ? { bottom: 0 } : { top: `calc(${rowBottom}px - var(--hh-hill))` }
  return (
    <div className="hh-hill pointer-events-none absolute inset-x-0" style={style} aria-hidden="true">
      <svg className="absolute inset-0 h-full w-full" viewBox="0 0 400 60" preserveAspectRatio="none">
        <path d="M 6 58 Q 2 26 40 20 Q 110 4 200 14 Q 300 2 362 16 Q 398 24 394 58 Z" fill={wash} filter="url(#hh-ground)" />
      </svg>
      <Flora seed={seed} />
    </div>
  )
}

export default function Meadow({ group, history }: { group: MoodGroup; history: MoodHistory }) {
  const name = group.product?.name ?? ''
  const title = group.product ? group.product.name : 'Not sure which product'
  const wash = GROUND_WASHES[hashSeed(group.product?.slug ?? 'none') % GROUND_WASHES.length]
  const characters = [...group.characters].sort((a, b) => hashSeed(a.seed) - hashSeed(b.seed))
  const shouter = loudest(group.characters)
  const { listRef, bottoms } = useRowBottoms(characters.length)
  const { ref: meadowRef, onScreen } = useOnScreen<HTMLElement>()
  const headingId = `meadow-${group.product?.slug ?? 'none'}`
  const smiling = group.counts.beaming + group.counts.content
  const grumpy = group.counts.grumpy + group.counts.furious

  return (
    <section
      ref={meadowRef}
      aria-labelledby={headingId}
      className={`hh-meadow ${onScreen ? '' : 'hh-offscreen'} relative min-w-0 grow basis-full rounded-[2rem] px-4 pb-5 pt-4 sm:px-6 ${group.characters.length >= WIDE_CROWD ? '' : 'lg:basis-[calc(50%-0.75rem)]'}`}
    >
      <header className="relative flex flex-wrap items-center gap-x-4 gap-y-1">
        <Sky mood={group.mood} className="h-12 w-14 shrink-0" />
        <h2 id={headingId} className="hh-hand text-3xl leading-none text-[#3E3542]">
          {title}
          {group.product?.retired && <span className="ml-2 text-lg text-[#3E3542]/50">(retired)</span>}
        </h2>
        <p className="text-sm text-[#3E3542]/70">
          {group.mood ? `${moodLabel(group.mood)} overall · ` : ''}
          {smiling} smiling · {group.counts.meh} meh · {grumpy} grumpy
          {group.counts.pending > 0 ? ` · ${group.counts.pending} still reading` : ''}
        </p>
        {group.product && (
          <Link href={`/?product=${group.product.slug}`} className="ml-auto text-sm text-[#3E3542]/70 underline decoration-dotted underline-offset-4 hover:text-[#3E3542]">
            Just {group.product.name}
          </Link>
        )}
      </header>
      <div className="relative mt-1">
        {bottoms.length === 0 ? (
          <Hill wash={wash} seed={group.product?.slug ?? 'none'} />
        ) : (
          bottoms.map((bottom, row) => <Hill key={bottom} wash={wash} seed={`${group.product?.slug ?? 'none'}-${row}`} rowBottom={bottom} />)
        )}
        <ul ref={listRef} className="relative flex flex-wrap items-end justify-center gap-x-1 gap-y-3 pb-1 sm:gap-x-3">
          {characters.map((character) => (
            <Person key={character.key} character={character} productName={name} history={history} shout={character.key === shouter?.key} />
          ))}
        </ul>
      </div>
      {group.overflow > 0 && (
        <p className="hh-hand relative mt-2 text-center text-lg text-[#3E3542]/70">
          …and {plural(group.overflow, 'more person', 'more people')} out of frame
        </p>
      )}
    </section>
  )
}
