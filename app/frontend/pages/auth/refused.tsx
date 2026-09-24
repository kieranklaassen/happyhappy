import { Head } from '@inertiajs/react'
import { EVERY_SIGN_IN_PATH } from './sign_in'

interface RefusedProps {
  email: string
}

export default function Refused({ email }: RefusedProps) {
  return (
    <>
      <Head title="Not an Every account" />
      <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center gap-6 px-6">
        <h1 className="text-2xl font-bold tracking-tight text-gray-900">
          happyhappy is for the Every team
        </h1>
        <p role="alert" className="text-sm text-gray-700">
          {email ? <>You signed in as <strong>{email}</strong>. </> : null}
          Only verified every.to accounts can use happyhappy.
        </p>
        <p className="text-sm text-gray-600">
          To switch accounts, sign out of every.to first, then sign in again.
        </p>
        <a
          href={EVERY_SIGN_IN_PATH}
          className="rounded border border-gray-300 px-3 py-2 text-center text-sm hover:bg-gray-50"
        >
          Sign in with a different Every account
        </a>
      </main>
    </>
  )
}
