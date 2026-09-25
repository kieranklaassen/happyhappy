import { Link } from '@inertiajs/react'
import { anomalyItemsHref, anomalySummary, anomalyTag } from '../../lib/anomaly-format'
import type { AnomalyProps } from '../../types/anomalies'

type Weather = 'rainbow' | 'sunny' | 'breezy' | 'cloudy' | 'showers' | 'storm'

// Good news is always sunshine; only bad news brings clouds, rain, and storms.
function weatherFor(anomaly: AnomalyProps): Weather {
  switch (anomaly.polarity) {
    case 'positive':
      return anomaly.highlight === 'huge' ? 'rainbow' : 'sunny'
    case 'neutral':
      return 'breezy'
    case 'negative':
      return anomaly.severity === 'high' ? 'storm' : anomaly.severity === 'medium' ? 'showers' : 'cloudy'
    default: {
      const unhandled: never = anomaly.polarity
      return unhandled
    }
  }
}

const HEADLINES: Record<Weather, string> = {
  rainbow: 'Great news',
  sunny: 'Good news',
  breezy: 'Busier than usual',
  cloudy: 'Clouds gathering',
  showers: 'Showers ahead',
  storm: 'Storm warning',
}

const CLOUD = 'M 14 40 Q 6 40 8 31 Q 10 22 20 24 Q 24 12 37 15 Q 48 10 52 24 Q 62 24 60 34 Q 60 41 50 41 Z'
const CLOUD_FILL: Record<'cloudy' | 'showers' | 'storm', string> = { cloudy: '#CFCBD8', showers: '#B9B6C4', storm: '#86849A' }
const RAINBOW = ['#F4A3A3', '#F8C98A', '#F8E08E', '#A8D8A8', '#9CC3EC', '#C3A8E2']

function Sun({ cx, cy, r }: { cx: number; cy: number; r: number }) {
  return (
    <g>
      <circle cx={cx} cy={cy} r={r} fill="#F8D774" filter="url(#hh-wash-0)" />
      <g stroke="#F2C46B" strokeWidth={3} strokeLinecap="round" filter="url(#hh-wash-1)">
        {Array.from({ length: 8 }, (_, i) => {
          const angle = (i / 8) * Math.PI * 2
          return (
            <line
              key={i}
              x1={cx + Math.cos(angle) * (r + 4)}
              y1={cy + Math.sin(angle) * (r + 4)}
              x2={cx + Math.cos(angle) * (r + 9)}
              y2={cy + Math.sin(angle) * (r + 9)}
            />
          )
        })}
      </g>
    </g>
  )
}

function WeatherArt({ weather }: { weather: Weather }) {
  return (
    <svg viewBox="0 0 68 60" className="h-12 w-14 shrink-0" aria-hidden="true" focusable="false" data-weather={weather}>
      {weather === 'sunny' && <Sun cx={34} cy={28} r={15} />}
      {weather === 'rainbow' && (
        <g>
          <g fill="none" strokeWidth={3.2} strokeLinecap="round" filter="url(#hh-wash-1)">
            {RAINBOW.map((color, i) => (
              <path key={color} stroke={color} d={`M ${6 + i * 3} 52 A ${28 - i * 3} ${28 - i * 3} 0 0 1 ${62 - i * 3} 52`} />
            ))}
          </g>
          <Sun cx={54} cy={13} r={6} />
        </g>
      )}
      {weather === 'breezy' && (
        <g>
          <path d={CLOUD} fill="#E4E1EA" filter="url(#hh-wash-1)" />
          <g fill="none" stroke="#9DB7C9" strokeWidth={2} strokeLinecap="round" filter="url(#hh-pencil)">
            <path d="M 4 50 Q 24 44 40 50 T 64 48" />
            <path d="M 12 56 Q 28 52 44 56" />
          </g>
        </g>
      )}
      {(weather === 'cloudy' || weather === 'showers' || weather === 'storm') && (
        <g>
          <path d={CLOUD} fill={CLOUD_FILL[weather]} filter="url(#hh-wash-1)" />
          {weather === 'storm' && (
            <path d="M 38 38 l -6 10 l 5 0 l -4 10 l 11 -13 l -5 0 l 4 -7 Z" fill="#F7D35A" stroke="#C99A1E" strokeWidth={0.6} />
          )}
          {weather !== 'cloudy' && (
            <g stroke="#8CB8F2" strokeWidth={2} strokeLinecap="round">
              {[18, 28, 48].map((x, i) => (
                <path key={x} className="hh-rain" style={{ animationDelay: `${i * 0.25}s` }} d={`M ${x} 45 l -2 6`} />
              ))}
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
  const positive = anomaly.polarity === 'positive'

  return (
    <aside
      aria-label={`${HEADLINES[weather]} for ${anomaly.product.name}`}
      className="flex max-w-xs items-start gap-2 rounded-2xl bg-[#FBF7EF]/95 px-3 py-2 text-[#3E3542] shadow-sm ring-1 ring-[#3E3542]/10"
    >
      <WeatherArt weather={weather} />
      <div className="min-w-0">
        <p className="hh-hand text-xl leading-none">{HEADLINES[weather]}</p>
        <p className="mt-1 text-sm leading-snug">{anomalySummary(anomaly, { withProduct: positive })}</p>
        <p className="mt-1 flex flex-wrap gap-x-3 text-xs">
          {anomaly.polarity === 'negative' && <span className="text-[#3E3542]/70">{anomalyTag(anomaly)}</span>}
          <Link
            href={anomalyItemsHref(anomaly)}
            className={`font-semibold underline decoration-2 underline-offset-4 ${positive ? 'decoration-[#F2C46B]' : 'decoration-[#F28C8C]'}`}
          >
            {positive ? 'See the love' : 'See what happened'}
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
