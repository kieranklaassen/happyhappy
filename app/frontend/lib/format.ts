export function formatHour(hour: number): string {
  return `${String(hour).padStart(2, '0')}:00`
}

export function formatDateTime(iso: string | null): string {
  if (!iso) return 'Never'
  return new Date(iso).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })
}

export function formatUsd(amount: number): string {
  return `$${amount.toFixed(2)}`
}
