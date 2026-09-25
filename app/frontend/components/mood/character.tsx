import { type CSSProperties, memo, type ReactNode, useId } from 'react'
import type { Mood } from './moods'
import { traitsFor, type Traits } from './traits'

const INK = '#3E3542'
const CX = 60

interface Geometry {
  headY: number
  headR: number
  bw: number
  shoulderY: number
  eyeY: number
  mouthY: number
  left: [number, number]
  right: [number, number]
}

function geometryFor(traits: Traits): Geometry {
  const shoulderY = traits.headY + traits.headR * 0.5
  const armY = shoulderY + 16
  return {
    headY: traits.headY,
    headR: traits.headR,
    bw: traits.bodyHalfWidth,
    shoulderY,
    eyeY: traits.headY - 1 + traits.eyeDrop,
    mouthY: traits.headY + traits.headR * 0.42 + traits.eyeDrop * 0.5,
    left: [CX - traits.bodyHalfWidth * 0.8, armY],
    right: [CX + traits.bodyHalfWidth * 0.8, armY],
  }
}

function bodyPath({ bw, shoulderY }: Geometry): string {
  return [
    `M ${CX - bw} 128`,
    `C ${CX - bw} ${shoulderY + 8} ${CX - bw * 0.7} ${shoulderY} ${CX} ${shoulderY}`,
    `C ${CX + bw * 0.7} ${shoulderY} ${CX + bw} ${shoulderY + 8} ${CX + bw} 128`,
    `Q ${CX + bw} 138 ${CX + bw - 8} 138`,
    `L ${CX - bw + 8} 138`,
    `Q ${CX - bw} 138 ${CX - bw} 128 Z`,
  ].join(' ')
}

type ArmSet = { back: string[]; front: string[]; fists: [number, number][] }

function arms(mood: Mood, g: Geometry): ArmSet {
  const [lx, ly] = g.left
  const [rx, ry] = g.right
  const out = g.bw
  switch (mood) {
    case 'beaming':
      return {
        back: [
          `M ${lx} ${ly} Q ${CX - out - 10} ${ly - 12} ${CX - out - 14} ${ly - 36}`,
          `M ${rx} ${ry} Q ${CX + out + 10} ${ry - 12} ${CX + out + 14} ${ry - 36}`,
        ],
        front: [],
        fists: [],
      }
    case 'content':
      return {
        back: [],
        front: [
          `M ${lx} ${ly} Q ${CX - out * 0.6} ${ly + 22} ${CX - 3} ${ly + 16}`,
          `M ${rx} ${ry} Q ${CX + out * 0.6} ${ry + 22} ${CX + 3} ${ry + 16}`,
        ],
        fists: [],
      }
    case 'relieved':
      return {
        back: [`M ${rx} ${ry} Q ${CX + out + 5} ${ry + 14} ${CX + out + 2} ${ry + 33}`],
        front: [`M ${lx} ${ly} Q ${CX - out - 12} ${ly - 16} ${CX - g.headR * 0.55} ${g.eyeY - 9}`],
        fists: [],
      }
    case 'meh':
      return {
        back: [
          `M ${lx} ${ly} Q ${CX - out - 6} ${ly + 14} ${CX - out - 3} ${ly + 34}`,
          `M ${rx} ${ry} Q ${CX + out + 6} ${ry + 14} ${CX + out + 3} ${ry + 34}`,
        ],
        front: [],
        fists: [],
      }
    case 'grumpy':
      return {
        back: [],
        front: [
          `M ${lx} ${ly} Q ${CX - 4} ${ly + 22} ${CX + out * 0.62} ${ly + 12}`,
          `M ${rx} ${ry} Q ${CX + 4} ${ry + 16} ${CX - out * 0.62} ${ry + 8}`,
        ],
        fists: [],
      }
    case 'furious':
      return {
        back: [
          `M ${lx} ${ly} Q ${CX - out - 16} ${ly + 10} ${CX - out - 10} ${ly - 16}`,
          `M ${rx} ${ry} Q ${CX + out + 16} ${ry + 10} ${CX + out + 10} ${ry - 16}`,
        ],
        front: [],
        fists: [
          [CX - out - 10, ly - 18],
          [CX + out + 10, ry - 18],
        ],
      }
    case 'pending':
      return {
        back: [`M ${lx} ${ly} Q ${CX - out - 6} ${ly + 14} ${CX - out - 3} ${ly + 32}`],
        front: [`M ${rx} ${ry} Q ${CX + out * 0.9} ${ry + 16} ${CX + 7} ${g.mouthY + 8}`],
        fists: [],
      }
    default: {
      const unhandled: never = mood
      return unhandled
    }
  }
}

function Eyes({ mood, g, gap }: { mood: Mood; g: Pick<Geometry, 'eyeY'>; gap: number }) {
  const y = g.eyeY
  const xs = [CX - gap, CX + gap]
  switch (mood) {
    case 'beaming':
      return (
        <g fill="none" stroke={INK} strokeWidth={2.2} strokeLinecap="round">
          {xs.map((x) => (
            <path key={x} d={`M ${x - 4.5} ${y + 1.5} Q ${x} ${y - 4.5} ${x + 4.5} ${y + 1.5}`} />
          ))}
        </g>
      )
    case 'content':
      return (
        <g>
          {xs.map((x) => (
            <g key={x}>
              <ellipse cx={x} cy={y} rx={2.7} ry={3.1} fill={INK} />
              <circle cx={x + 0.9} cy={y - 1.1} r={0.8} fill="#fff" />
            </g>
          ))}
        </g>
      )
    case 'relieved':
      return (
        <g fill="none" stroke={INK} strokeWidth={2} strokeLinecap="round">
          {xs.map((x) => (
            <path key={x} d={`M ${x - 4} ${y - 0.5} Q ${x} ${y + 3.5} ${x + 4} ${y - 0.5}`} />
          ))}
        </g>
      )
    case 'meh':
      return (
        <g>
          {xs.map((x) => (
            <g key={x}>
              <path d={`M ${x - 3.6} ${y} Q ${x} ${y + 4.6} ${x + 3.6} ${y} Z`} fill={INK} />
              <path d={`M ${x - 5} ${y - 0.6} L ${x + 5} ${y + 0.2}`} stroke={INK} strokeWidth={1.6} strokeLinecap="round" />
            </g>
          ))}
        </g>
      )
    case 'grumpy':
      return (
        <g>
          {xs.map((x, i) => {
            const toward = i === 0 ? 1 : -1
            return (
              <g key={x}>
                <circle cx={x} cy={y + 0.5} r={2.5} fill={INK} />
                <path
                  d={`M ${x - toward * 6} ${y - 7} L ${x + toward * 4} ${y - 4}`}
                  stroke={INK}
                  strokeWidth={2}
                  strokeLinecap="round"
                />
              </g>
            )
          })}
        </g>
      )
    case 'furious':
      return (
        <g>
          {xs.map((x, i) => {
            const toward = i === 0 ? 1 : -1
            return (
              <g key={x}>
                <path d={`M ${x - 3.8} ${y - 0.5} Q ${x} ${y + 4.5} ${x + 3.8} ${y - 0.5} Z`} fill={INK} />
                <path
                  d={`M ${x - toward * 7} ${y - 8} L ${x + toward * 4.5} ${y - 2.5}`}
                  stroke={INK}
                  strokeWidth={2.8}
                  strokeLinecap="round"
                />
              </g>
            )
          })}
        </g>
      )
    case 'pending':
      return (
        <g>
          {xs.map((x) => (
            <g key={x}>
              <ellipse cx={x + 1.2} cy={y - 1.4} rx={2.5} ry={2.9} fill={INK} />
              <circle cx={x + 1.9} cy={y - 2.4} r={0.7} fill="#fff" />
            </g>
          ))}
        </g>
      )
    default: {
      const unhandled: never = mood
      return unhandled
    }
  }
}

function Mouth({ mood, g }: { mood: Mood; g: Pick<Geometry, 'mouthY'> }) {
  const y = g.mouthY
  switch (mood) {
    case 'beaming':
      return (
        <g>
          <path d={`M ${CX - 9} ${y - 1} Q ${CX} ${y + 14} ${CX + 9} ${y - 1} Z`} fill="#7A3B4A" />
          <ellipse cx={CX} cy={y + 6.5} rx={4.2} ry={2.6} fill="#F2929F" />
        </g>
      )
    case 'content':
      return <path d={`M ${CX - 6} ${y} Q ${CX} ${y + 5.5} ${CX + 6} ${y}`} stroke={INK} strokeWidth={1.9} fill="none" strokeLinecap="round" />
    case 'relieved':
      return (
        <g stroke={INK} strokeWidth={1.9} fill="none" strokeLinecap="round">
          <path d={`M ${CX - 6.5} ${y} Q ${CX} ${y + 6} ${CX + 6.5} ${y}`} />
          <ellipse cx={CX + 9.5} cy={y + 0.5} rx={1.3} ry={1.6} strokeWidth={1.3} />
        </g>
      )
    case 'meh':
      return <path d={`M ${CX - 5.5} ${y + 1.5} Q ${CX - 1} ${y + 0.4} ${CX + 5.5} ${y + 2}`} stroke={INK} strokeWidth={1.9} fill="none" strokeLinecap="round" />
    case 'grumpy':
      return <path d={`M ${CX - 6.5} ${y + 4} Q ${CX} ${y - 2.5} ${CX + 6.5} ${y + 4}`} stroke={INK} strokeWidth={2} fill="none" strokeLinecap="round" />
    case 'furious':
      return (
        <g>
          <path d={`M ${CX - 8.5} ${y + 8} Q ${CX - 9} ${y - 2} ${CX} ${y - 2} Q ${CX + 9} ${y - 2} ${CX + 8.5} ${y + 8} Z`} fill="#6E2F3C" />
          <path d={`M ${CX - 6.5} ${y + 0.6} L ${CX + 6.5} ${y + 0.6} L ${CX + 6} ${y + 2.8} L ${CX - 6} ${y + 2.8} Z`} fill="#fff" />
        </g>
      )
    case 'pending':
      return <ellipse cx={CX + 1} cy={y + 1.5} rx={2.2} ry={2.6} stroke={INK} strokeWidth={1.7} fill="none" />
    default: {
      const unhandled: never = mood
      return unhandled
    }
  }
}

export function Face({ mood, eyeY, mouthY, gap }: { mood: Mood; eyeY: number; mouthY: number; gap: number }) {
  return (
    <g filter="url(#hh-pencil)">
      <Eyes mood={mood} g={{ eyeY }} gap={gap} />
      <Mouth mood={mood} g={{ mouthY }} />
    </g>
  )
}

function Headwear({ traits, g }: { traits: Traits; g: Geometry }) {
  const top = g.headY - g.headR
  const r = g.headR
  switch (traits.headwear) {
    case 'none':
      return null
    case 'sprout':
      return (
        <g>
          <path d={`M ${CX + 2} ${top + 2} Q ${CX} ${top - 6} ${CX + 3} ${top - 12}`} stroke="#6F9A5F" strokeWidth={1.8} fill="none" strokeLinecap="round" />
          <path d={`M ${CX + 3} ${top - 11} Q ${CX + 13} ${top - 18} ${CX + 16} ${top - 9} Q ${CX + 9} ${top - 5} ${CX + 3} ${top - 11} Z`} fill="#A8D596" />
          <path d={`M ${CX + 2} ${top - 7} Q ${CX - 8} ${top - 13} ${CX - 11} ${top - 5} Q ${CX - 4} ${top - 2} ${CX + 2} ${top - 7} Z`} fill="#BFE2AE" />
        </g>
      )
    case 'tuft':
      return (
        <g stroke={traits.hair} strokeWidth={2.2} fill="none" strokeLinecap="round">
          <path d={`M ${CX - 4} ${top + 2} Q ${CX - 9} ${top - 6} ${CX - 3} ${top - 10}`} />
          <path d={`M ${CX} ${top + 1} Q ${CX + 1} ${top - 8} ${CX + 6} ${top - 11}`} />
          <path d={`M ${CX + 4} ${top + 2} Q ${CX + 10} ${top - 3} ${CX + 12} ${top - 7}`} />
        </g>
      )
    case 'beanie':
      return (
        <g>
          <path d={`M ${CX - r * 0.98} ${g.headY - r * 0.28} Q ${CX - r} ${top - 6} ${CX} ${top - 7} Q ${CX + r} ${top - 6} ${CX + r * 0.98} ${g.headY - r * 0.28} Z`} fill={traits.accent} opacity={0.9} />
          <rect x={CX - r - 1.5} y={g.headY - r * 0.42} width={r * 2 + 3} height={7} rx={3.5} fill={traits.accent} />
          <circle cx={CX} cy={top - 9} r={5.5} fill="#FFF6EC" stroke={traits.accent} strokeWidth={1} />
        </g>
      )
    case 'bun':
      return (
        <g>
          <path d={`M ${CX - r * 0.95} ${g.headY - r * 0.2} Q ${CX - r * 0.9} ${top - 2} ${CX} ${top - 2} Q ${CX + r * 0.9} ${top - 2} ${CX + r * 0.95} ${g.headY - r * 0.2} Q ${CX} ${top + r * 0.35} ${CX - r * 0.95} ${g.headY - r * 0.2} Z`} fill={traits.hair} opacity={0.88} />
          <circle cx={CX} cy={top - 7} r={8} fill={traits.hair} />
        </g>
      )
    case 'bob':
      return (
        <path
          d={`M ${CX - r - 2} ${g.headY + r * 0.35} Q ${CX - r - 4} ${top - 3} ${CX} ${top - 3} Q ${CX + r + 4} ${top - 3} ${CX + r + 2} ${g.headY + r * 0.35} L ${CX + r * 0.72} ${g.headY + r * 0.3} Q ${CX + r * 0.6} ${top + r * 0.45} ${CX + 2} ${top + r * 0.42} Q ${CX - r * 0.6} ${top + r * 0.5} ${CX - r * 0.72} ${g.headY + r * 0.3} Z`}
          fill={traits.hair}
          opacity={0.9}
        />
      )
    case 'bow':
      return (
        <g transform={`translate(${CX + r * 0.55} ${top + 5}) rotate(18)`}>
          <path d="M 0 0 L -10 -6 Q -12 0 -10 6 Z" fill={traits.accent} />
          <path d="M 0 0 L 10 -6 Q 12 0 10 6 Z" fill={traits.accent} />
          <circle r={2.8} fill={traits.accent} stroke={INK} strokeOpacity={0.25} />
        </g>
      )
    case 'cap':
      return (
        <g>
          <path d={`M ${CX - r * 0.95} ${g.headY - r * 0.3} Q ${CX - r * 0.9} ${top - 5} ${CX} ${top - 5} Q ${CX + r * 0.9} ${top - 5} ${CX + r * 0.95} ${g.headY - r * 0.3} Z`} fill={traits.accent} />
          <path d={`M ${CX + r * 0.4} ${g.headY - r * 0.36} Q ${CX + r * 1.3} ${g.headY - r * 0.46} ${CX + r * 1.45} ${g.headY - r * 0.22} L ${CX + r * 0.5} ${g.headY - r * 0.22} Z`} fill={traits.accent} />
          <circle cx={CX} cy={top - 5} r={2} fill={INK} opacity={0.35} />
        </g>
      )
    case 'curls':
      return (
        <g fill={traits.hair} opacity={0.92}>
          {[-0.8, -0.45, -0.1, 0.25, 0.6, 0.9].map((t, i) => (
            <circle key={t} cx={CX + t * r} cy={top + 3 + Math.abs(t) * 7 - (i % 2) * 2} r={7} />
          ))}
        </g>
      )
    case 'party':
      return (
        <g transform={`rotate(-12 ${CX} ${top})`}>
          <path d={`M ${CX - 9} ${top + 3} L ${CX} ${top - 20} L ${CX + 9} ${top + 3} Z`} fill={traits.accent} />
          <path d={`M ${CX - 5} ${top - 6} L ${CX + 5} ${top - 4} M ${CX - 7} ${top - 1} L ${CX + 7} ${top + 1}`} stroke="#FFF6EC" strokeWidth={1.6} />
          <circle cx={CX} cy={top - 21} r={3} fill="#F7E3A1" />
        </g>
      )
    default: {
      const unhandled: never = traits.headwear
      return unhandled
    }
  }
}

function Accessory({ traits, g, gap }: { traits: Traits; g: Geometry; gap: number }) {
  switch (traits.accessory) {
    case 'none':
      return null
    case 'glasses':
      return (
        <g fill="none" stroke={INK} strokeWidth={1.3} opacity={0.85}>
          <circle cx={CX - gap} cy={g.eyeY} r={6.2} />
          <circle cx={CX + gap} cy={g.eyeY} r={6.2} />
          <path d={`M ${CX - gap + 6.2} ${g.eyeY} Q ${CX} ${g.eyeY - 3} ${CX + gap - 6.2} ${g.eyeY}`} />
        </g>
      )
    case 'freckles':
      return (
        <g fill={traits.body.ink} opacity={0.7}>
          {[-1, 1].flatMap((side) =>
            [0, 1, 2].map((i) => (
              <circle key={`${side}-${i}`} cx={CX + side * (gap + 1 + i * 2.6)} cy={g.eyeY + 6 + (i % 2) * 1.8} r={0.8} />
            )),
          )}
        </g>
      )
    case 'scarf':
      return (
        <g>
          <path d={`M ${CX - g.bw * 0.78} ${g.shoulderY + 4} Q ${CX} ${g.shoulderY + 12} ${CX + g.bw * 0.78} ${g.shoulderY + 4} L ${CX + g.bw * 0.8} ${g.shoulderY + 10} Q ${CX} ${g.shoulderY + 19} ${CX - g.bw * 0.8} ${g.shoulderY + 10} Z`} fill={traits.accent} opacity={0.92} />
          <path d={`M ${CX + g.bw * 0.4} ${g.shoulderY + 12} L ${CX + g.bw * 0.55} ${g.shoulderY + 30} L ${CX + g.bw * 0.2} ${g.shoulderY + 29} Z`} fill={traits.accent} opacity={0.92} />
        </g>
      )
    case 'mustache':
      return (
        <path
          d={`M ${CX} ${g.mouthY - 3.5} Q ${CX - 5} ${g.mouthY - 7} ${CX - 10} ${g.mouthY - 3} Q ${CX - 6} ${g.mouthY - 2} ${CX} ${g.mouthY - 2.5} Q ${CX + 6} ${g.mouthY - 2} ${CX + 10} ${g.mouthY - 3} Q ${CX + 5} ${g.mouthY - 7} ${CX} ${g.mouthY - 3.5} Z`}
          fill={traits.hair}
        />
      )
    default: {
      const unhandled: never = traits.accessory
      return unhandled
    }
  }
}

function Heart({ x, y, size, className, style }: { x: number; y: number; size: number; className: string; style?: CSSProperties }) {
  const s = size
  return (
    <path
      className={className}
      style={style}
      d={`M ${x} ${y + s * 0.9} C ${x - s * 1.4} ${y} ${x - s * 0.7} ${y - s} ${x} ${y - s * 0.3} C ${x + s * 0.7} ${y - s} ${x + s * 1.4} ${y} ${x} ${y + s * 0.9} Z`}
      fill="#F28CA6"
    />
  )
}

function Cloud({ x, y, w, fill }: { x: number; y: number; w: number; fill: string }) {
  const h = w * 0.42
  return (
    <path
      d={`M ${x - w / 2} ${y + h / 2} Q ${x - w / 2 - 6} ${y} ${x - w / 3} ${y - h / 4} Q ${x - w / 4} ${y - h} ${x} ${y - h * 0.7} Q ${x + w / 4} ${y - h * 1.1} ${x + w / 3} ${y - h / 4} Q ${x + w / 2 + 7} ${y - h / 6} ${x + w / 2} ${y + h / 2} Z`}
      fill={fill}
    />
  )
}

function Extras({ mood, g, traits }: { mood: Mood; g: Geometry; traits: Traits }) {
  const top = g.headY - g.headR
  switch (mood) {
    case 'beaming':
      return (
        <g>
          <Heart x={CX - 22} y={top - 4} size={5} className="hh-rise" style={{ animationDelay: '0s' }} />
          <Heart x={CX + 20} y={top - 10} size={6.5} className="hh-rise" style={{ animationDelay: '0.9s' }} />
          <Heart x={CX + 2} y={top - 16} size={4} className="hh-rise" style={{ animationDelay: '1.7s' }} />
          {[
            [CX - 40, top + 10, '#F2C46B', 20],
            [CX + 38, top + 4, '#8CB8F2', -30],
            [CX - 30, top - 14, '#9ED39A', 45],
            [CX + 30, top - 20, '#C69BE8', 10],
            [CX - 8, top - 22, '#F28C8C', -15],
          ].map(([x, y, color, rot], i) => (
            <g key={i} className="hh-confetti" style={{ animationDelay: `${i * 0.35}s` }}>
              <rect
                x={Number(x)}
                y={Number(y)}
                width={4}
                height={2.4}
                rx={0.8}
                fill={String(color)}
                transform={`rotate(${rot} ${x} ${y})`}
              />
            </g>
          ))}
        </g>
      )
    case 'content':
      return (
        <g className="hh-twinkle" style={{ animationDelay: `${traits.phase}s` }}>
          <path
            d={`M ${CX + 30} ${top + 2} l 1.6 4.4 l 4.4 1.6 l -4.4 1.6 l -1.6 4.4 l -1.6 -4.4 l -4.4 -1.6 l 4.4 -1.6 Z`}
            fill="#F2C46B"
          />
        </g>
      )
    case 'relieved':
      return (
        <g>
          <path
            className="hh-drip"
            d={`M ${CX + g.headR * 0.72} ${g.headY - g.headR * 0.55} q 3.4 5.2 0 7.6 q -3.4 -2.4 0 -7.6 Z`}
            fill="#8CB8F2"
            stroke="#5E8FCF"
            strokeWidth={0.5}
            filter="url(#hh-wash-1)"
          />
          <g className="hh-exhale" stroke={INK} strokeWidth={1.2} fill="none" opacity={0.5} strokeLinecap="round">
            <path d={`M ${CX + 14} ${g.mouthY + 1} q 5 -2 9 1`} />
            <path d={`M ${CX + 15} ${g.mouthY + 5} q 6 0 11 3`} />
          </g>
        </g>
      )
    case 'meh':
      return (
        <g>
          <g className="hh-orbit" style={{ transformOrigin: `${CX + 4}px ${top + 6}px` }}>
            <circle cx={CX + 26} cy={top + 2} r={1.6} fill={INK} />
            <ellipse cx={CX + 24.6} cy={top} rx={2} ry={1.2} fill="#fff" stroke={INK} strokeWidth={0.4} opacity={0.9} />
            <ellipse cx={CX + 27.4} cy={top} rx={2} ry={1.2} fill="#fff" stroke={INK} strokeWidth={0.4} opacity={0.9} />
          </g>
          <path
            className="hh-sigh"
            d={`M ${CX - 30} ${g.mouthY - 2} q -4 -3 0 -6 q 4 -3 0 -6`}
            stroke={INK}
            strokeWidth={1.2}
            fill="none"
            opacity={0.5}
            strokeLinecap="round"
          />
        </g>
      )
    case 'grumpy':
      return (
        <g className="hh-grumble" style={{ transformOrigin: `${CX}px ${top - 10}px` }}>
          <path
            d={`M ${CX - 12} ${top - 8} q 3 -8 7 -2 q 2 -9 8 -2 q 5 -6 7 2 q 6 1 1 6 q -4 4 -9 0 q -4 5 -8 0 q -7 3 -6 -4`}
            stroke={INK}
            strokeWidth={1.3}
            fill="none"
            opacity={0.7}
            strokeLinecap="round"
          />
          <text x={CX - 6} y={top - 18} fontSize={8} fill={INK} opacity={0.65} fontWeight={700}>
            #!
          </text>
        </g>
      )
    case 'furious':
      return (
        <g>
          <g className="hh-storm">
            <g filter="url(#hh-wash-1)">
              <Cloud x={CX} y={top - 12} w={52} fill="#8D8C9B" />
              <Cloud x={CX + 8} y={top - 17} w={30} fill="#A7A6B3" />
            </g>
            <path className="hh-bolt" d={`M ${CX + 2} ${top - 4} l -6 10 l 5 0 l -4 10 l 10 -13 l -5 0 l 4 -7 Z`} fill="#F7D35A" stroke="#C99A1E" strokeWidth={0.6} />
            {[-16, -8, 12, 18].map((dx, i) => (
              <path
                key={dx}
                className="hh-rain"
                style={{ animationDelay: `${i * 0.25}s` }}
                d={`M ${CX + dx} ${top - 2} l -2 6`}
                stroke="#8CB8F2"
                strokeWidth={1.4}
                strokeLinecap="round"
              />
            ))}
          </g>
          <g className="hh-steam" fill="#F4F1F6" stroke="#A7A6B3" strokeWidth={0.8}>
            <circle cx={CX - g.headR - 4} cy={g.headY - 6} r={3.6} />
            <circle cx={CX - g.headR - 9} cy={g.headY - 11} r={2.6} />
            <circle cx={CX + g.headR + 4} cy={g.headY - 6} r={3.6} />
            <circle cx={CX + g.headR + 9} cy={g.headY - 11} r={2.6} />
          </g>
        </g>
      )
    case 'pending':
      return (
        <g>
          <circle cx={CX + 24} cy={top + 2} r={2} fill="#fff" stroke={INK} strokeOpacity={0.4} />
          <circle cx={CX + 30} cy={top - 5} r={3} fill="#fff" stroke={INK} strokeOpacity={0.4} />
          <ellipse cx={CX + 38} cy={top - 17} rx={14} ry={9} fill="#fff" stroke={INK} strokeOpacity={0.4} />
          {[0, 1, 2].map((i) => (
            <circle key={i} className="hh-dot" style={{ animationDelay: `${i * 0.2}s` }} cx={CX + 32 + i * 6} cy={top - 17} r={1.6} fill={INK} />
          ))}
        </g>
      )
    default: {
      const unhandled: never = mood
      return unhandled
    }
  }
}

export interface CharacterProps {
  seed: string
  mood: Mood
  bandage?: boolean
  className?: string
  title?: string
  idle?: boolean
}

function Character({ seed, mood, bandage = false, className, title, idle = false }: CharacterProps) {
  const clipId = `hh-clip-${useId().replace(/:/g, '')}`
  const traits = traitsFor(seed)
  const g = geometryFor(traits)
  const armSet = arms(mood, g)
  const wash = traits.body.wash
  const washFilter = `url(#hh-wash-${traits.filterVariant})`
  const style = {
    '--hh-tempo': `${traits.tempo}s`,
    '--hh-phase': `-${traits.phase}s`,
  } as CSSProperties

  const pose = `rotate(${traits.lean} ${CX} 140) scale(${traits.scale}) translate(${((1 - traits.scale) * CX) / traits.scale} ${((1 - traits.scale) * 140) / traits.scale})`

  let front: ReactNode = null
  if (armSet.front.length > 0) {
    front = (
      <g filter={washFilter} strokeLinecap="round" fill="none">
        {armSet.front.map((d) => (
          <path key={`o-${d}`} d={d} stroke={traits.body.ink} strokeWidth={11} strokeOpacity={0.45} />
        ))}
        {armSet.front.map((d) => (
          <path key={d} d={d} stroke={wash} strokeWidth={8.5} />
        ))}
      </g>
    )
  }

  // The filtered body never animates; extras move in their own layer so the
  // watercolor filters are not re-run every frame. The idle class sits where
  // --hh-tempo and --hh-phase are set, so each character keeps its own rhythm.
  return (
    <span className={`relative block ${idle ? `hh-idle hh-idle--${mood}` : ''} ${className ?? ''}`} style={style}>
      <svg
        viewBox="0 -26 120 172"
        className="block w-full"
        role={title ? 'img' : undefined}
        aria-hidden={title ? undefined : true}
        aria-label={title}
        data-mood={mood}
      >
        <defs>
          <clipPath id={clipId}>
            <path d={bodyPath(g)} />
            <circle cx={CX} cy={g.headY} r={g.headR} />
          </clipPath>
        </defs>
        <ellipse cx={CX} cy={142} rx={g.bw + 8} ry={4} fill="#3E3542" opacity={0.08} />
        <g transform={pose}>
          <g filter={washFilter} opacity={0.94}>
            <g fill={wash} stroke="none">
              <ellipse cx={CX - g.bw * 0.45} cy={138} rx={g.bw * 0.36} ry={6} />
              <ellipse cx={CX + g.bw * 0.45} cy={138} rx={g.bw * 0.36} ry={6} />
              <path d={bodyPath(g)} />
              <circle cx={CX} cy={g.headY} r={g.headR} />
            </g>
            <g clipPath={`url(#${clipId})`}>
              <path d={`M ${CX - g.bw} 116 Q ${CX} 126 ${CX + g.bw} 114 L ${CX + g.bw} 140 L ${CX - g.bw} 140 Z`} fill={traits.body.ink} opacity={0.18} />
              <ellipse cx={CX - g.headR * 0.38} cy={g.headY - g.headR * 0.45} rx={g.headR * 0.34} ry={g.headR * 0.22} fill="#FFFDF8" opacity={0.45} transform={`rotate(-30 ${CX - g.headR * 0.38} ${g.headY - g.headR * 0.45})`} />
            </g>
            <g stroke={wash} strokeWidth={9} strokeLinecap="round" fill="none">
              {armSet.back.map((d) => (
                <path key={d} d={d} />
              ))}
            </g>
            {armSet.fists.map(([x, y]) => (
              <circle key={`${x}-${y}`} cx={x} cy={y} r={6} fill={wash} />
            ))}
          </g>
          <g filter="url(#hh-pencil)" fill="none" stroke={traits.body.ink} strokeWidth={1.2} opacity={0.55} transform="translate(0.9 -0.7)">
            <circle cx={CX} cy={g.headY} r={g.headR} />
            <path d={bodyPath(g)} />
          </g>
          {front}
          <g filter="url(#hh-wash-2)">
            <ellipse cx={CX - traits.eyeGap - 5} cy={g.eyeY + 7} rx={5} ry={3} fill="#F08A9A" opacity={mood === 'furious' ? 0.7 : 0.45} />
            <ellipse cx={CX + traits.eyeGap + 5} cy={g.eyeY + 7} rx={5} ry={3} fill="#F08A9A" opacity={mood === 'furious' ? 0.7 : 0.45} />
            {mood === 'furious' && <ellipse cx={CX} cy={g.headY - 2} rx={g.headR * 0.85} ry={g.headR * 0.6} fill="#E8505A" opacity={0.32} />}
          </g>
          <g filter="url(#hh-wash-1)">
            <Headwear traits={traits} g={g} />
          </g>
          <g filter="url(#hh-pencil)">
            <Eyes mood={mood} g={g} gap={traits.eyeGap} />
            <Mouth mood={mood} g={g} />
            <Accessory traits={traits} g={g} gap={traits.eyeGap} />
            {bandage && (
              <g transform={`translate(${CX + traits.eyeGap + 2} ${g.headY - g.headR * 0.55}) rotate(-28)`}>
                <rect x={-8} y={-3} width={16} height={6} rx={3} fill="#F5D7B8" stroke="#C9A27E" strokeWidth={0.6} />
                <rect x={-2.5} y={-2.2} width={5} height={4.4} rx={1} fill="#EBC49F" />
              </g>
            )}
          </g>
        </g>
      </svg>
      <svg viewBox="0 -26 120 172" className="absolute inset-0 block w-full" aria-hidden="true">
        <g transform={pose}>
          <Extras mood={mood} g={g} traits={traits} />
        </g>
      </svg>
    </span>
  )
}

// Every prop is a primitive, so a live reload skips characters whose seed, mood, and bandage held still.
export default memo(Character)
