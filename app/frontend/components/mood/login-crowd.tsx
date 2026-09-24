import Character from './character'
import Flora from './flora'
import type { Mood } from './moods'

type Visibility = 'always' | 'sm' | 'lg'

interface Extra {
  seed: string
  mood: Mood
  visible: Visibility
  says?: string
}

// Made-up people for a public page: never real customers. Mostly happy, one
// grumpy, one under a storm cloud. Phones show the middle five.
export const LOGIN_CROWD: readonly Extra[] = [
  { seed: 'login-pip', mood: 'content', visible: 'lg' },
  { seed: 'login-marlo', mood: 'beaming', visible: 'sm' },
  { seed: 'login-wren', mood: 'meh', visible: 'lg' },
  { seed: 'login-bo', mood: 'content', visible: 'always' },
  { seed: 'login-sunny', mood: 'beaming', visible: 'always', says: 'Welcome back!' },
  { seed: 'login-bruno', mood: 'furious', visible: 'always' },
  { seed: 'login-noor', mood: 'beaming', visible: 'always' },
  { seed: 'login-greta', mood: 'grumpy', visible: 'always' },
  { seed: 'login-elm', mood: 'content', visible: 'sm' },
  { seed: 'login-yara', mood: 'beaming', visible: 'lg' },
  { seed: 'login-rue', mood: 'content', visible: 'lg' },
]

const VISIBILITY: Record<Visibility, string> = {
  always: 'block',
  sm: 'hidden sm:block',
  lg: 'hidden lg:block',
}

export default function LoginCrowd() {
  return (
    <div className="pointer-events-none relative w-full select-none" aria-hidden="true" data-testid="login-crowd">
      <div className="absolute inset-x-0 bottom-0 h-16 sm:h-20">
        <svg className="absolute inset-0 h-full w-full" viewBox="0 0 400 60" preserveAspectRatio="none">
          <path d="M -10 60 Q -6 24 40 20 Q 120 2 210 14 Q 310 0 372 16 Q 412 24 410 60 Z" fill="#CFE6C0" filter="url(#hh-ground)" />
        </svg>
        <Flora seed="login" count={12} />
      </div>
      <ul className="relative mx-auto flex max-w-6xl items-end justify-center gap-x-1 px-2 pt-12 pb-3 sm:gap-x-3">
        {LOGIN_CROWD.map((extra, index) => (
          <li key={extra.seed} className={`relative ${VISIBILITY[extra.visible]}`} style={{ marginBottom: (index % 3) * 4 }}>
            {extra.says && <span className="hh-bubble hh-hand">{extra.says}</span>}
            <Character seed={extra.seed} mood={extra.mood} idle className="w-[68px] sm:w-[88px] lg:w-[104px]" />
          </li>
        ))}
      </ul>
    </div>
  )
}
