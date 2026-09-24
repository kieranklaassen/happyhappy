import { between, pick, seededRandom } from './seed'

type Sprig = 'grass' | 'daisy' | 'tulip' | 'pebble'

const SPRIGS: readonly Sprig[] = ['grass', 'grass', 'grass', 'daisy', 'tulip', 'pebble']
const PETALS = ['#FFFDF8', '#F7D6E0', '#F7E3A1', '#D9CCF0'] as const

function SprigArt({ kind, petal }: { kind: Sprig; petal: string }) {
  switch (kind) {
    case 'grass':
      return (
        <g stroke="#8DB57A" strokeWidth={1.6} fill="none" strokeLinecap="round">
          <path d="M 10 20 Q 8 12 4 7" />
          <path d="M 11 20 Q 11 10 12 4" />
          <path d="M 12 20 Q 15 13 19 9" />
        </g>
      )
    case 'daisy':
      return (
        <g>
          <path d="M 12 20 Q 11 14 12 9" stroke="#8DB57A" strokeWidth={1.4} fill="none" />
          {[0, 72, 144, 216, 288].map((angle) => (
            <ellipse key={angle} cx={12} cy={5.5} rx={1.8} ry={3.2} fill={petal} stroke="#D8CFC0" strokeWidth={0.4} transform={`rotate(${angle} 12 8)`} />
          ))}
          <circle cx={12} cy={8} r={1.8} fill="#F2C46B" />
        </g>
      )
    case 'tulip':
      return (
        <g>
          <path d="M 12 20 Q 12 14 12 10" stroke="#8DB57A" strokeWidth={1.4} fill="none" />
          <path d="M 12 16 Q 16 13 17 10" stroke="#8DB57A" strokeWidth={1.2} fill="none" />
          <path d="M 8.5 5 L 10 8 L 12 4.5 L 14 8 L 15.5 5 Q 16 11 12 11.5 Q 8 11 8.5 5 Z" fill={petal === '#FFFDF8' ? '#F4A9B8' : petal} />
        </g>
      )
    case 'pebble':
      return <ellipse cx={12} cy={18} rx={5} ry={2.6} fill="#D9D2C4" />
    default: {
      const unhandled: never = kind
      return unhandled
    }
  }
}

export default function Flora({ seed, count = 9 }: { seed: string; count?: number }) {
  const random = seededRandom(`flora:${seed}`)
  const sprigs = Array.from({ length: count }, (_, i) => ({
    kind: pick(random, SPRIGS),
    petal: pick(random, PETALS),
    left: ((i + between(random, 0.1, 0.9)) / count) * 100,
    bottom: between(random, 6, 34),
    size: between(random, 16, 24),
  }))

  return (
    <div className="absolute inset-x-4 inset-y-0">
      {sprigs.map((sprig, i) => (
        <svg
          key={i}
          viewBox="0 0 24 22"
          className="absolute"
          style={{ left: `${sprig.left}%`, bottom: sprig.bottom, width: sprig.size, height: sprig.size }}
          filter="url(#hh-pencil)"
        >
          <SprigArt kind={sprig.kind} petal={sprig.petal} />
        </svg>
      ))}
    </div>
  )
}
