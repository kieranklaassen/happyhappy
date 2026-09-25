import { Head, router, usePage } from '@inertiajs/react'
import '@fontsource/caveat/600.css'
import '../../components/mood/mood.css'
import LoginCrowd from '../../components/mood/login-crowd'
import WatercolorDefs from '../../components/mood/watercolor-defs'
import SunLogo from '../../components/sun-logo'
import type { FlashData } from '../../types'

export const EVERY_SIGN_IN_PATH = '/auth/every'

interface DevLoginPerson {
  email: string
  name: string | null
}

interface SignInProps {
  dev_login_people?: DevLoginPerson[]
}

interface SignInPageProps {
  flash: FlashData
  [key: string]: unknown
}

export default function SignIn({ dev_login_people }: SignInProps) {
  const { flash } = usePage<SignInPageProps>().props

  return (
    <>
      <Head title="Sign in" />
      <WatercolorDefs />
      <div className="hh-paper flex min-h-screen flex-col">
        <main className="mx-auto flex w-full max-w-sm flex-1 flex-col justify-center gap-6 px-6 py-12">
          <p className="flex items-center gap-3">
            <SunLogo className="h-14 w-14" />
            <span className="hh-hand text-5xl leading-none text-[#3E3542]">happyhappy</span>
          </p>
          <div>
            <h1 className="text-2xl font-bold tracking-tight text-[#3E3542]">Sign in to happyhappy</h1>
            <p className="mt-1 text-sm text-[#3E3542]/70">See how everyone is feeling today. Use your every.to account.</p>
          </div>

          {flash.alert && (
            <p role="alert" className="rounded bg-red-50 px-3 py-2 text-sm text-red-700">
              {flash.alert}
            </p>
          )}

          {/* A full page navigation, not an Inertia visit: the OmniAuth
              middleware answers with a redirect to Every. */}
          <a
            href={EVERY_SIGN_IN_PATH}
            className="rounded-full bg-[#3E3542] px-5 py-3 text-center font-semibold text-[#FBF7EF] shadow-[0_10px_24px_-12px_rgb(62_53_66/0.7)] transition-colors hover:bg-[#2C2530] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#3E3542]"
          >
            Sign in with Every
          </a>

          {dev_login_people && (
            <section aria-labelledby="dev-login-heading" className="flex flex-col gap-2 border-t border-dashed border-[#3E3542]/20 pt-4">
              <h2 id="dev-login-heading" className="text-sm font-medium text-[#3E3542]">
                Dev login
              </h2>
              {dev_login_people.length === 0 ? (
                <p className="text-sm text-gray-600">
                  No seeded people yet. Run <code>bin/rails db:seed</code>.
                </p>
              ) : (
                <ul className="flex flex-col gap-1">
                  {dev_login_people.map((person) => (
                    <li key={person.email}>
                      <button
                        type="button"
                        onClick={() => router.post('/dev/login', { email_address: person.email })}
                        className="w-full rounded-full bg-white/70 px-4 py-2 text-left text-sm text-[#3E3542] ring-1 ring-[#3E3542]/15 hover:bg-white"
                      >
                        Continue as {person.name ?? person.email}
                      </button>
                    </li>
                  ))}
                </ul>
              )}
            </section>
          )}
        </main>
        <LoginCrowd />
      </div>
    </>
  )
}
