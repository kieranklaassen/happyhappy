// The happyhappy mark. public/icon.svg and public/icon.png draw the same sun;
// change them together.
const RAYS = Array.from({ length: 8 }, (_, i) => (i / 8) * Math.PI * 2 + Math.PI / 8)

export default function SunLogo({ className, title }: { className?: string; title?: string }) {
  return (
    <svg
      viewBox="0 0 64 64"
      className={className}
      role={title ? 'img' : undefined}
      aria-hidden={title ? undefined : true}
      aria-label={title}
      focusable="false"
    >
      <g stroke="#F0AE3C" strokeWidth={5} strokeLinecap="round">
        {RAYS.map((angle) => (
          <line
            key={angle}
            x1={32 + Math.cos(angle) * 25.5}
            y1={32 + Math.sin(angle) * 25.5}
            x2={32 + Math.cos(angle) * 29.5}
            y2={32 + Math.sin(angle) * 29.5}
          />
        ))}
      </g>
      <circle cx={32} cy={32} r={19.5} fill="#F8D774" stroke="#D99A2B" strokeWidth={2} />
      <ellipse cx={21.5} cy={36.5} rx={3.4} ry={2.2} fill="#F29A8E" opacity={0.7} />
      <ellipse cx={42.5} cy={36.5} rx={3.4} ry={2.2} fill="#F29A8E" opacity={0.7} />
      <g fill="none" stroke="#3E3542" strokeWidth={2.8} strokeLinecap="round">
        <path d="M 22 30.5 Q 25.5 26.5 29 30.5" />
        <path d="M 35 30.5 Q 38.5 26.5 42 30.5" />
        <path d="M 26 36.5 Q 32 43 38 36.5" />
      </g>
    </svg>
  )
}
