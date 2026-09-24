const WASH_SEEDS = [3, 11, 23] as const

function WashFilter({ id, seed }: { id: string; seed: number }) {
  return (
    <filter id={id} x="-20%" y="-20%" width="140%" height="140%" colorInterpolationFilters="sRGB">
      <feTurbulence type="fractalNoise" baseFrequency="0.028" numOctaves={3} seed={seed} result="warp" />
      <feDisplacementMap in="SourceGraphic" in2="warp" scale={7} xChannelSelector="R" yChannelSelector="G" result="shape" />
      <feMorphology in="shape" operator="erode" radius={2.4} result="inner" />
      <feGaussianBlur in="inner" stdDeviation={2.2} result="innerSoft" />
      <feComposite in="shape" in2="innerSoft" operator="out" result="rim" />
      <feBlend in="rim" in2="shape" mode="multiply" result="edged" />
      <feTurbulence type="fractalNoise" baseFrequency="0.02" numOctaves={2} seed={seed + 5} result="bloomNoise" />
      <feColorMatrix
        in="bloomNoise"
        type="matrix"
        values="0 0 0 0 1  0 0 0 0 0.99  0 0 0 0 0.96  1.2 0 0 0 -0.62"
        result="bloom"
      />
      <feGaussianBlur in="bloom" stdDeviation={1.5} result="bloomSoft" />
      <feComposite in="bloomSoft" in2="inner" operator="in" result="bloomIn" />
      <feTurbulence type="fractalNoise" baseFrequency="0.7" numOctaves={1} seed={seed + 9} result="grainNoise" />
      <feColorMatrix
        in="grainNoise"
        type="matrix"
        values="0 0 0 0 0.35  0 0 0 0 0.28  0 0 0 0 0.3  0.45 0 0 0 -0.24"
        result="grain"
      />
      <feComposite in="grain" in2="shape" operator="in" result="grainIn" />
      <feMerge>
        <feMergeNode in="edged" />
        <feMergeNode in="bloomIn" />
        <feMergeNode in="grainIn" />
      </feMerge>
    </filter>
  )
}

export default function WatercolorDefs() {
  return (
    <svg width="0" height="0" aria-hidden="true" focusable="false" style={{ position: 'absolute' }}>
      <defs>
        {WASH_SEEDS.map((seed, i) => (
          <WashFilter key={seed} id={`hh-wash-${i}`} seed={seed} />
        ))}
        <filter id="hh-ground" x="-5%" y="-30%" width="110%" height="160%" colorInterpolationFilters="sRGB">
          <feTurbulence type="fractalNoise" baseFrequency="0.012 0.05" numOctaves={3} seed={17} result="warp" />
          <feDisplacementMap in="SourceGraphic" in2="warp" scale={14} xChannelSelector="R" yChannelSelector="G" result="shape" />
          <feMorphology in="shape" operator="erode" radius={3} result="inner" />
          <feGaussianBlur in="inner" stdDeviation={5} result="innerSoft" />
          <feComposite in="shape" in2="innerSoft" operator="out" result="rim" />
          <feBlend in="rim" in2="shape" mode="multiply" result="edged" />
          <feTurbulence type="fractalNoise" baseFrequency="0.008 0.03" numOctaves={2} seed={29} result="bloomNoise" />
          <feColorMatrix in="bloomNoise" type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 0.97  1.3 0 0 0 -0.6" result="bloom" />
          <feGaussianBlur in="bloom" stdDeviation={3} result="bloomSoft" />
          <feComposite in="bloomSoft" in2="inner" operator="in" result="bloomIn" />
          <feMerge>
            <feMergeNode in="edged" />
            <feMergeNode in="bloomIn" />
          </feMerge>
        </filter>
        <filter id="hh-pencil" x="-10%" y="-10%" width="120%" height="120%">
          <feTurbulence type="fractalNoise" baseFrequency="0.09" numOctaves={2} seed={4} result="jitter" />
          <feDisplacementMap in="SourceGraphic" in2="jitter" scale={1.8} xChannelSelector="R" yChannelSelector="G" />
        </filter>
      </defs>
    </svg>
  )
}
