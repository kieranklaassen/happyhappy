import { Head, router, usePage } from '@inertiajs/react'
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
      <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center gap-6 px-6">
        <h1 className="text-2xl font-bold tracking-tight text-gray-900">Sign in to happyhappy</h1>
        <p className="text-sm text-gray-600">Use your every.to account.</p>

        {flash.alert && (
          <p role="alert" className="rounded bg-red-50 px-3 py-2 text-sm text-red-700">
            {flash.alert}
          </p>
        )}

        {/* A full page navigation, not an Inertia visit: the OmniAuth
            middleware answers with a redirect to Every. */}
        <a
          href={EVERY_SIGN_IN_PATH}
          className="rounded bg-gray-900 px-3 py-2 text-center text-white hover:bg-gray-800"
        >
          Sign in with Every
        </a>

        {dev_login_people && (
          <section aria-labelledby="dev-login-heading" className="flex flex-col gap-2 border-t border-dashed border-gray-300 pt-4">
            <h2 id="dev-login-heading" className="text-sm font-medium text-gray-900">
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
                      className="w-full rounded border border-gray-300 px-3 py-2 text-left text-sm hover:bg-gray-50"
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
    </>
  )
}
