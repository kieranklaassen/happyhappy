import { usePage } from '@inertiajs/react'
import { type ReactNode } from 'react'
import type { FlashData } from '../types'

export const inputClass =
  'rounded border border-gray-300 px-3 py-2 text-sm text-gray-900 focus:border-gray-900 focus:ring-gray-900'

export const primaryButtonClass =
  'rounded bg-gray-900 px-4 py-2 text-sm font-medium text-white hover:bg-gray-700 disabled:opacity-50'

export const secondaryButtonClass =
  'rounded border border-gray-300 px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50'

interface FieldProps {
  label: string
  htmlFor: string
  error?: string[]
  hint?: ReactNode
  children: ReactNode
}

export function Field({ label, htmlFor, error, hint, children }: FieldProps) {
  const message = error?.join(', ')
  return (
    <div className="flex flex-col gap-1 text-sm">
      <label htmlFor={htmlFor} className="font-medium text-gray-900">
        {label}
      </label>
      {children}
      {hint && <p className="text-xs text-gray-500">{hint}</p>}
      {message && (
        <p role="alert" className="text-xs text-red-700">
          {label} {message}
        </p>
      )}
    </div>
  )
}

export function FlashNotice() {
  const { flash } = usePage<{ flash: FlashData }>().props
  if (!flash?.notice && !flash?.alert) return null

  return (
    <div className="flex flex-col gap-2">
      {flash.notice && (
        <p role="status" className="rounded bg-green-50 px-3 py-2 text-sm text-green-800">
          {flash.notice}
        </p>
      )}
      {flash.alert && (
        <p role="alert" className="rounded bg-red-50 px-3 py-2 text-sm text-red-700">
          {flash.alert}
        </p>
      )}
    </div>
  )
}
