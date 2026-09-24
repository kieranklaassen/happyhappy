import { Link, usePage } from '@inertiajs/react'

export interface NavEntry {
  label: string
  href: string
}

export const NAV_ENTRIES: readonly NavEntry[] = [
  { label: 'Mood', href: '/' },
  { label: 'Feed', href: '/items' },
  { label: 'Products', href: '/products' },
  { label: 'Categories', href: '/categories' },
  { label: 'Sources', href: '/sources' },
  { label: 'Agents', href: '/agents' },
  { label: 'Settings', href: '/settings' },
]

export function isActive(currentPath: string, href: string): boolean {
  const path = currentPath.split(/[?#]/)[0]
  if (href === '/') return path === '/'
  return path === href || path.startsWith(`${href}/`)
}

export default function AppNav() {
  const { url } = usePage()

  return (
    <nav aria-label="Main" className="border-b border-gray-200 bg-white">
      <div className="mx-auto flex max-w-6xl items-center gap-6 px-6 py-3">
        <Link href="/" className="text-lg font-bold tracking-tight text-gray-900">
          happyhappy
        </Link>
        <ul className="-mr-6 flex min-w-0 items-center gap-1 overflow-x-auto pr-6 text-sm whitespace-nowrap">
          {NAV_ENTRIES.map((entry) => {
            const active = isActive(url, entry.href)
            return (
              <li key={entry.href}>
                <Link
                  href={entry.href}
                  aria-current={active ? 'page' : undefined}
                  className={
                    active
                      ? 'rounded px-3 py-1.5 font-medium text-gray-900 bg-gray-100'
                      : 'rounded px-3 py-1.5 text-gray-600 hover:bg-gray-50 hover:text-gray-900'
                  }
                >
                  {entry.label}
                </Link>
              </li>
            )
          })}
        </ul>
      </div>
    </nav>
  )
}
