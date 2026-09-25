import { Head, Link } from '@inertiajs/react'
import { useEffect, useMemo, useRef } from 'react'
import '@fontsource/caveat/600.css'
import '../../components/mood/mood.css'
import AppNav from '../../components/app-nav'
import AnomalyCallout from '../../components/mood/anomaly-callout'
import { MOOD_COLORS, plural, timeAgo } from '../../components/mood/format'
import { sourceKindLabel } from '../../lib/feed-format'
import Meadow, { type MoodHistory } from '../../components/mood/meadow'
import { moodLabel, type Mood } from '../../components/mood/moods'
import Sky from '../../components/mood/sky'
import { useMoodStream } from '../../components/mood/use-mood-stream'
import WatercolorDefs from '../../components/mood/watercolor-defs'
import type { MoodDashboardProps, MoodSummary, SettledMood } from '../../types/mood'

const RANGE_LABELS: Record<string, string> = {
  '24h': 'the last 24 hours',
  '7d': 'the last 7 days',
}

const BAR_MOODS: readonly SettledMood[] = ['beaming', 'content', 'relieved', 'meh', 'grumpy', 'furious']

export function headline(mood: SettledMood | null): string {
  switch (mood) {
    case 'beaming':
      return 'Everyone is over the moon.'
    case 'content':
      return 'Mostly sunny out there.'
    case 'relieved':
      return 'The clouds are clearing.'
    case 'meh':
      return 'A bit of a shrug today.'
    case 'grumpy':
      return 'Grumbly out there.'
    case 'furious':
      return 'Stormy. Grab an umbrella.'
    case null:
      return 'Quiet so far.'
    default: {
      const unhandled: never = mood
      return unhandled
    }
  }
}

function query(range: string, product: string | null): string {
  const params = new URLSearchParams()
  if (range !== '24h') params.set('range', range)
  if (product) params.set('product', product)
  const search = params.toString()
  return search ? `/?${search}` : '/'
}

function MoodBar({ today }: { today: MoodSummary }) {
  const total = BAR_MOODS.reduce((sum, mood) => sum + today.counts[mood], 0)
  if (total === 0) return null
  return (
    <div className="mt-4">
      <div className="flex h-4 w-full max-w-md overflow-hidden rounded-full" style={{ filter: 'url(#hh-wash-0)' }} aria-hidden="true">
        {BAR_MOODS.filter((mood) => today.counts[mood] > 0).map((mood) => (
          <span key={mood} style={{ width: `${(today.counts[mood] / total) * 100}%`, background: MOOD_COLORS[mood] }} />
        ))}
      </div>
      <ul className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-sm text-[#3E3542]/75">
        {BAR_MOODS.map((mood) => (
          <li key={mood} className="flex items-center gap-1.5">
            <span className="inline-block h-2.5 w-2.5 rounded-full" style={{ background: MOOD_COLORS[mood] }} aria-hidden="true" />
            {today.counts[mood]} {moodLabel(mood).toLowerCase()}
          </li>
        ))}
      </ul>
    </div>
  )
}

function Chip({ href, active, children }: { href: string; active: boolean; children: string }) {
  return (
    <Link
      href={href}
      preserveScroll
      aria-current={active ? 'page' : undefined}
      className={
        active
          ? 'rounded-full bg-[#3E3542] px-3.5 py-1.5 text-sm font-medium text-[#FBF7EF]'
          : 'rounded-full bg-white/70 px-3.5 py-1.5 text-sm text-[#3E3542]/80 ring-1 ring-[#3E3542]/10 hover:bg-white hover:text-[#3E3542]'
      }
    >
      {children}
    </Link>
  )
}

export default function Home({ scene, today, filters, options, anomalies }: MoodDashboardProps) {
  const status = useMoodStream()
  const history = useRef<Map<string, Mood> | null>(null)
  const previous: MoodHistory = useMemo(() => history.current, [scene])
  useEffect(() => {
    history.current = new Map(scene.flatMap((group) => group.characters.map((character) => [character.key, character.mood])))
  }, [scene])

  const rangeLabel = RANGE_LABELS[today.range] ?? RANGE_LABELS['24h']
  const everyone = scene.flatMap((group) => group.characters.map((character) => ({ character, product: group.product?.name ?? 'Not sure' })))

  return (
    <>
      <Head title="How is everyone feeling?" />
      <WatercolorDefs />
      <div className="hh-paper min-h-screen">
        <AppNav />
        <main className="mx-auto max-w-6xl px-4 pb-16 pt-6 sm:px-6">
          <header className="flex flex-col gap-4 md:flex-row md:items-center md:gap-8">
            <Sky mood={today.mood} className="h-28 w-32 shrink-0 self-center md:h-36 md:w-40" />
            <div className="min-w-0 flex-1">
              <h1 className="hh-hand text-[2.75rem] leading-none text-[#3E3542] lg:text-6xl">How is everyone feeling?</h1>
              <p className="mt-2 text-lg text-[#3E3542]/85">
                <strong className="font-semibold">{headline(today.mood)}</strong>{' '}
                {today.people > 0
                  ? `${today.smiling} smiling${today.relieved > 0 ? ` (${today.relieved} relieved)` : ''}, ${today.counts.meh} meh, and ${today.grumpy} grumpy across ${plural(today.people, 'person', 'people')} in ${rangeLabel}.`
                  : `Nobody has written in ${rangeLabel}.`}
              </p>
              <MoodBar today={today} />
            </div>
            <p className="flex items-center gap-2 self-start rounded-full bg-white/70 px-3 py-1 text-xs text-[#3E3542]/70 ring-1 ring-[#3E3542]/10" aria-live="polite">
              <span className={`inline-block h-2 w-2 rounded-full ${status === 'live' ? 'hh-live bg-[#6FBF8B]' : 'bg-[#C9C2B6]'}`} aria-hidden="true" />
              {status === 'live' ? 'Live' : 'Refreshing every 30 seconds'} · updated {timeAgo(today.updated_at)}
            </p>
          </header>

          <nav aria-label="Dashboard filters" className="mt-8 flex flex-wrap items-center gap-2">
            {options.ranges.map((range) => (
              <Chip key={range} href={query(range, filters.product)} active={filters.range === range}>
                {range === '24h' ? 'Today' : 'This week'}
              </Chip>
            ))}
            <span className="mx-2 h-5 w-px bg-[#3E3542]/15" aria-hidden="true" />
            <Chip href={query(filters.range, null)} active={!filters.product}>
              Everyone
            </Chip>
            {options.products.map((product) => (
              <Chip key={product.slug} href={query(filters.range, product.slug)} active={filters.product === product.slug}>
                {product.name}
              </Chip>
            ))}
          </nav>

          {scene.length === 0 ? (
            <section className="hh-meadow mt-6 flex flex-col items-center rounded-[2rem] px-6 py-12 text-center">
              <Sky mood={null} className="h-28 w-32" />
              <h2 className="hh-hand mt-2 text-3xl text-[#3E3542]">The meadow is empty</h2>
              <p className="mt-1 text-[#3E3542]/75">No customer has written in {rangeLabel}. Enjoy the quiet.</p>
              {filters.range === '24h' && (
                <Link href={query('7d', filters.product)} className="mt-4 text-sm font-semibold underline decoration-[#F28C8C] decoration-2 underline-offset-4">
                  See the last 7 days
                </Link>
              )}
            </section>
          ) : (
            <div className="mt-6 flex flex-wrap gap-6">
              {scene.map((group) => (
                <Meadow
                  key={group.product?.slug ?? 'none'}
                  group={group}
                  history={previous}
                  productHref={query(filters.range, group.product?.slug ?? null)}
                  aside={group.product && anomalies?.[group.product.slug] && <AnomalyCallout anomalies={anomalies[group.product.slug]} />}
                />
              ))}
            </div>
          )}

          {everyone.length > 0 && (
            <details className="mt-10 rounded-2xl bg-white/60 px-5 py-3 ring-1 ring-[#3E3542]/10">
              <summary className="cursor-pointer text-sm font-medium text-[#3E3542]/80">Read the crowd as a list</summary>
              <table className="mt-3 w-full text-left text-sm">
                <thead className="text-xs uppercase tracking-wide text-[#3E3542]/55">
                  <tr>
                    <th scope="col" className="py-2 pr-3 font-medium">Person</th>
                    <th scope="col" className="py-2 pr-3 font-medium">Product</th>
                    <th scope="col" className="py-2 pr-3 font-medium">Mood</th>
                    <th scope="col" className="py-2 pr-3 font-medium">Where</th>
                    <th scope="col" className="py-2 font-medium">What they said</th>
                  </tr>
                </thead>
                <tbody>
                  {everyone.map(({ character, product }) => (
                    <tr key={character.key} className="border-t border-[#3E3542]/10 align-top">
                      <td className="py-2 pr-3">
                        <Link href={`/items/${character.item_id}`} className="underline decoration-dotted underline-offset-4">
                          {character.name}
                        </Link>
                      </td>
                      <td className="py-2 pr-3">{product}</td>
                      <td className="py-2 pr-3">{moodLabel(character.mood)}</td>
                      <td className="py-2 pr-3">
                        {sourceKindLabel(character.source_kind)}, {timeAgo(character.last_message_at)}
                      </td>
                      <td className="py-2 text-[#3E3542]/80">{character.excerpt}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </details>
          )}
        </main>
      </div>
    </>
  )
}
