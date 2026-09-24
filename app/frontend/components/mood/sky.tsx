import { Face } from './character'
import type { SettledMood } from '../../types/mood'

function cloudPath(x: number, y: number, w: number): string {
  const h = w * 0.5
  return [
    `M ${x - w / 2} ${y + h / 3}`,
    `Q ${x - w / 2 - 8} ${y - h / 6} ${x - w / 3} ${y - h / 4}`,
    `Q ${x - w / 4} ${y - h} ${x + w / 12} ${y - h * 0.62}`,
    `Q ${x + w / 3} ${y - h * 0.95} ${x + w / 2.6} ${y - h / 5}`,
    `Q ${x + w / 2 + 10} ${y - h / 8} ${x + w / 2} ${y + h / 3}`,
    'Z',
  ].join(' ')
}

function Sun({ x, y, r, rays = true }: { x: number; y: number; r: number; rays?: boolean }) {
  return (
    <g>
      {rays && (
        <g className="hh-spin" style={{ transformOrigin: `${x}px ${y}px` }} stroke="#F2C46B" strokeWidth={4} strokeLinecap="round" filter="url(#hh-wash-1)">
          {Array.from({ length: 10 }, (_, i) => {
            const angle = (i / 10) * Math.PI * 2
            return (
              <line
                key={i}
                x1={x + Math.cos(angle) * (r + 6)}
                y1={y + Math.sin(angle) * (r + 6)}
                x2={x + Math.cos(angle) * (r + 14)}
                y2={y + Math.sin(angle) * (r + 14)}
              />
            )
          })}
        </g>
      )}
      <circle cx={x} cy={y} r={r} fill="#F8D774" filter="url(#hh-wash-0)" />
    </g>
  )
}

function Rain({ x, y, color = '#8CB8F2' }: { x: number; y: number; color?: string }) {
  return (
    <g stroke={color} strokeWidth={2} strokeLinecap="round">
      {[-18, -6, 6, 18].map((dx, i) => (
        <path key={dx} className="hh-rain" style={{ animationDelay: `${i * 0.2}s` }} d={`M ${x + dx} ${y} l -3 8`} />
      ))}
    </g>
  )
}

export default function Sky({ mood, className }: { mood: SettledMood | null; className?: string }) {
  let art
  switch (mood) {
    case 'beaming':
      art = (
        <g>
          <g fill="none" strokeWidth={5} opacity={0.75} filter="url(#hh-wash-2)">
            <path d="M 4 100 A 56 56 0 0 1 116 100" stroke="#F4B8C5" />
            <path d="M 11 100 A 49 49 0 0 1 109 100" stroke="#F7E3A1" />
            <path d="M 18 100 A 42 42 0 0 1 102 100" stroke="#BFE3CF" />
            <path d="M 25 100 A 35 35 0 0 1 95 100" stroke="#B9D4EE" />
          </g>
          <Sun x={60} y={56} r={26} />
          <Face mood="beaming" eyeY={52} mouthY={63} gap={10} />
        </g>
      )
      break
    case 'content':
      art = (
        <g>
          <Sun x={60} y={56} r={28} />
          <Face mood="content" eyeY={52} mouthY={64} gap={10} />
        </g>
      )
      break
    case 'meh':
      art = (
        <g>
          <Sun x={42} y={42} r={24} rays={false} />
          <path d={cloudPath(66, 70, 74)} fill="#E4E1EA" filter="url(#hh-wash-1)" />
          <Face mood="meh" eyeY={66} mouthY={77} gap={11} />
        </g>
      )
      break
    case 'grumpy':
      art = (
        <g>
          <path d={cloudPath(60, 62, 84)} fill="#B9B6C4" filter="url(#hh-wash-1)" />
          <Face mood="grumpy" eyeY={58} mouthY={70} gap={12} />
          <Rain x={60} y={86} />
        </g>
      )
      break
    case 'furious':
      art = (
        <g>
          <path d={cloudPath(60, 60, 90)} fill="#86849A" filter="url(#hh-wash-1)" />
          <ellipse cx={60} cy={56} rx={24} ry={14} fill="#E8505A" opacity={0.3} filter="url(#hh-wash-2)" />
          <Face mood="furious" eyeY={54} mouthY={66} gap={12} />
          <path className="hh-bolt" d="M 84 70 l -8 14 l 7 0 l -6 14 l 14 -18 l -7 0 l 6 -10 Z" fill="#F7D35A" stroke="#C99A1E" strokeWidth={0.8} />
          <Rain x={48} y={84} />
        </g>
      )
      break
    case null:
      art = (
        <g>
          <circle cx={60} cy={56} r={26} fill="#EFE6C8" filter="url(#hh-wash-0)" />
          <circle cx={72} cy={48} r={22} fill="#FBF7EF" />
          <text x={78} y={34} fontSize={12} fill="#3E3542" opacity={0.6} fontFamily="Caveat, cursive">z z</text>
        </g>
      )
      break
    default: {
      const unhandled: never = mood
      return unhandled
    }
  }

  return (
    <svg viewBox="0 0 120 110" className={className} aria-hidden="true" focusable="false">
      {art}
    </svg>
  )
}
