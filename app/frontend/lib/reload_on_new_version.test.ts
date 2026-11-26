import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { reloadOnNewVersion } from './reload_on_new_version'

const location = { href: 'https://happy.test/items?page=2#top', reload: vi.fn() }
let stop: () => void

// What Inertia dispatches when the server answers 409 with X-Inertia-Location.
function locationVisit(url: string, versionChange: boolean): boolean {
  return document.dispatchEvent(
    new CustomEvent('inertia:location', { cancelable: true, detail: { url: new URL(url), versionChange } }),
  )
}

beforeEach(() => {
  location.href = 'https://happy.test/items?page=2#top'
  location.reload.mockClear()
  vi.stubGlobal('window', { location })
  stop = reloadOnNewVersion()
})

afterEach(() => {
  stop()
  vi.unstubAllGlobals()
})

describe('reloadOnNewVersion', () => {
  it('reloads the page when a poll of it meets a new asset version', () => {
    const allowed = locationVisit('https://happy.test/items?page=2', true)

    expect(location.reload).toHaveBeenCalledOnce()
    expect(allowed).toBe(true)
  })

  it('goes to the visited page when that is another one', () => {
    locationVisit('https://happy.test/products', true)

    expect(location.href).toBe('https://happy.test/products')
    expect(location.reload).not.toHaveBeenCalled()
  })

  it('leaves other location visits to Inertia', () => {
    locationVisit('https://happy.test/items?page=2', false)
    locationVisit('https://elsewhere.test/', false)

    expect(location.reload).not.toHaveBeenCalled()
    expect(location.href).toBe('https://happy.test/items?page=2#top')
  })
})
