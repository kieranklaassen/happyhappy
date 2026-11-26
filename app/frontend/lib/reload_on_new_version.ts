import { router } from '@inertiajs/react'

/**
 * Reloads the page when the server reports a new asset version, polls and
 * `router.reload` included. Inertia reloads by itself only for ordinary visits
 * once the server sends X-Inertia-Version (inertia_rails 3.23): background
 * requests just stop updating, which would leave an open dashboard frozen after
 * a deploy. Returning false keeps Inertia from navigating a second time, which
 * could use up a flash message.
 */
export function reloadOnNewVersion(): () => void {
  return router.on('location', ({ detail: { url, versionChange } }) => {
    if (!versionChange) return

    if (withoutHash(url.href) === withoutHash(window.location.href)) {
      window.location.reload()
    } else {
      window.location.href = url.href
    }

    return false
  })
}

function withoutHash(href: string): string {
  return href.split('#')[0]
}
