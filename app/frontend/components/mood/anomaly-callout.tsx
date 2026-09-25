import { Link } from '@inertiajs/react'
import { anomalyItemsHref, anomalyValue, anomalyWindow, isGoodNews } from '../../lib/anomaly-format'
import type { AnomalyProps } from '../../types/anomalies'

type Weather = 'storm' | 'showers' | 'breezy' | 'sunny'

function weatherFor(anomaly: AnomalyProps): Weather {
  if (isGoodNews(anomaly)) return 'sunny'
  switch (anomaly.severity) {
    case 'high':
      return 'storm'
    case 'medium':
      return 'showers'
    case 'low':
      return 'breezy'
    default: {
      const unhandled: never = anomaly.severity
      return unhandled
    }
  }
}

const HEADLINES: Record<Weather, string> = {
  storm: 'Storm warning',
  showers: 'Showers ahead',
  breezy: 'A little breezy',
  sunny: 'Sunny spell',
}

const CLOUD = 'M 14 40 Q 6 40 8 31 Q 10 22 20 24 Q 24 12 37 15 Q 48 10 52 24 Q 62 24 60 34 Q 60 41 50 41 Z'

function WeatherArt({ weather }: { weather: Weather }) {
  return (
    <svg viewBox="0 0 68 60" className="h-12 w-14 shrink-0" aria-hidden="true" focusable="false">
      {weather === 'sunny' ? (
        <g>
          <circle cx={34} cy={28} r={15} fill="#F8D774" filter="url(#hh-wash-0)" />
          <g stroke="#F2C46B" strokeWidth={3} strokeLinecap="round" filter="url(#hh-wash-1)">
            {Array.from({ length: 8 }, (_, i) => {
              const angle = (i / 8) * Math.PI * 2
              return (
                <line
                  key={i}
                  x1={34 + Math.cos(angle) * 19}
                  y1={28 + Math.sin(angle) * 19}
                  x2={34 + Math.cos(angle) * 25}
                  y2={28 + Math.sin(angle) * 25}
                />
              )
            })}
          </g>
        </g>
      ) : (
        <g>
          <path d={CLOUD} fill={weather === 'storm' ? '#86849A' : weather === 'showers' ? '#B9B6C4' : '#E4E1EA'} filter="url(#hh-wash-1)" />
          {weather === 'storm' && (
            <path d="M 38 38 l -6 10 l 5 0 l -4 10 l 11 -13 l -5 0 l 4 -7 Z" fill="#F7D35A" stroke="#C99A1E" strokeWidth={0.6} />
          )}
          {weather !== 'breezy' && (
            <g stroke="#8CB8F2" strokeWidth={2} strokeLinecap="round">
              {[18, 28, 48].map((x, i) => (
                <path key={x} className="hh-rain" style={{ animationDelay: `${i * 0.25}s` }} d={`M ${x} 45 l -2 6`} />
              ))}
            </g>
          )}
          {weather === 'breezy' && (
            <g fill="none" stroke="#9DB7C9" strokeWidth={2} strokeLinecap="round" filter="url(#hh-pencil)">
              <path d="M 4 50 Q 24 44 40 50 T 64 48" />
              <path d="M 12 56 Q 28 52 44 56" />
            </g>
          )}
        </g>
      )}
    </svg>
  )
}

export default function AnomalyCallout({ anomalies }: { anomalies: readonly AnomalyProps[] | undefined }) {
  const anomaly = anomalies?.[0]
  if (!anomaly) return null
  const weather = weatherFor(anomaly)
  const more = (anomalies?.length ?? 1) - 1

  return (
    <aside
      aria-label={`${HEADLINES[weather]} for ${anomaly.product.name}`}
      className="flex max-w-xs items-start gap-2 rounded-2xl bg-[#FBF7EF]/95 px-3 py-2 text-[#3E3542] shadow-sm ring-1 ring-[#3E3542]/10"
    >
      <WeatherArt weather={weather} />
      <div className="min-w-0">
        <p className="hh-hand text-xl leading-none">{HEADLINES[weather]}</p>
        <p className="mt-1 text-sm leading-snug">
          <strong className="font-semibold">{anomaly.label}</strong>
          {anomaly.source ? ` on ${anomaly.source.name}` : ''}: {anomalyValue(anomaly, anomaly.actual)} {anomalyWindow(anomaly)},{' '}
          usually {anomalyValue(anomaly, anomaly.expected)}.
        </p>
        <p className="mt-1 flex flex-wrap gap-x-3 text-xs">
          <Link href={anomalyItemsHref(anomaly)} className="font-semibold underline decoration-[#F28C8C] decoration-2 underline-offset-4">
            See what happened
          </Link>
          {more > 0 && (
            <Link href={`/items?anomaly=active&product=${anomaly.product.slug}`} className="text-[#3E3542]/70 underline decoration-dotted underline-offset-4">
              +{more} more
            </Link>
          )}
        </p>
      </div>
    </aside>
  )
}
