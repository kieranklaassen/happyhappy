import { http, HttpCancelledError, type HttpRequestConfig, type HttpResponse } from '@inertiajs/core'
import { createInertiaApp, router } from '@inertiajs/react'
import { act, fireEvent, render, screen } from '@testing-library/react'
import { expect, it, vi } from 'vitest'
import ItemsIndex from '../../pages/items/index'
import { LIVE_RELOAD_GAP_MS } from '../mood/use-mood-stream'

// The real Inertia client decides what a late reload does to the page, so only the network is fake here.
const { channels } = vi.hoisted(() => ({ channels: {} as Record<string, { received: (ping?: unknown) => void }> }))

vi.mock('@rails/actioncable', () => ({
  createConsumer: () => ({
    subscriptions: {
      create: (name: string, handlers: (typeof channels)[string]) => {
        channels[name] = handlers
        return { unsubscribe: vi.fn() }
      },
    },
    disconnect: vi.fn(),
  }),
}))
vi.mock('../app-nav', () => ({ default: () => null }))

const FEED = '/items?q=billing'

function page(href: string, only?: string[]) {
  const url = new URL(href, window.location.href)
  const runId = url.searchParams.get('run_id')
  const buckets = <T,>(value: () => T) => ({ strong: value(), possible: value(), unlikely: value() })
  const props: Record<string, unknown> = {
    items: [],
    filters: {},
    pagination: { page: 1, prev_page: null, next_page: null },
    options: { products: [], categories: [], sources: [], sentiments: [], statuses: [], ranges: [], actionability: [], sorts: [] },
    anomalies: [],
    search: {
      query: 'billing', chips: [], relaxed_labels: [], relaxed_notice: null, removed: [],
      invite_row: null, encoding_status: 'cached', explicit_action: 'enter', run_id: runId,
    },
    smart: runId && {
      run_id: runId, status: 'running', reserved_slots: 30, paused: false, collapsed: [], no_strong_matches: false,
      pending: buckets(() => true), buckets: buckets(() => []),
    },
    error: null,
  }
  const sent = only ? Object.fromEntries(only.map((key) => [key, props[key]])) : props
  return { component: 'items/index', props: { ...sent, errors: {} }, url: url.pathname + url.search, version: '1', flash: {} }
}

interface Sent {
  method: string
  only?: string[]
  land: (href?: string) => void
}

let sent: Sent[] = []

http.setClient({
  request: (config: HttpRequestConfig) =>
    new Promise<HttpResponse>((resolve, reject) => {
      const only = (config.headers?.['X-Inertia-Partial-Data'] as string | undefined)?.split(',')
      config.signal?.addEventListener('abort', () => reject(new HttpCancelledError('cancelled', config.url)))
      sent.push({
        method: config.method,
        only,
        land: (href = config.url) =>
          resolve({ status: 200, headers: { 'x-inertia': 'true' }, data: JSON.stringify(page(href, only)) }),
      })
    }),
})

const settle = (ms = 50) => act(() => new Promise<void>((resolve) => void setTimeout(resolve, ms)))
const runInUrl = () => new URLSearchParams(window.location.search).get('run_id')
const reloads = (prop: string) => sent.filter(({ only }) => only?.includes(prop))

async function pressEnter() {
  sent = []
  fireEvent.submit(screen.getByRole('search'))
  await settle()
}

async function landPost(runId: string) {
  sent.find(({ method }) => method === 'post')?.land(`${FEED}&run_id=${runId}`)
  await settle()
}

async function moodPing() {
  channels.MoodChannel.received({})
  await settle(LIVE_RELOAD_GAP_MS + 100)
}

it('a background reload sent during the Smart POST cannot take the new run off the page', async () => {
  vi.stubGlobal('scrollTo', vi.fn())
  window.history.replaceState(null, '', FEED)
  const el = document.body.appendChild(document.createElement('div'))
  el.id = 'app'
  await createInertiaApp({
    page: page(FEED) as never,
    resolve: () => ItemsIndex as never,
    progress: false,
    setup: ({ App, props }) => void render(<App {...props} />, { container: el }),
  })
  await settle()

  await pressEnter()
  await moodPing()
  await landPost('r1')
  expect(runInUrl()).toBe('r1')
  reloads('items').forEach((reload) => reload.land())
  await settle()
  expect(runInUrl()).toBe('r1')
  expect(screen.getByText(/reading the top 30 matches/)).toBeInTheDocument()
  expect(reloads('items')).toHaveLength(0)

  // The new page's own reloads still go out, with its run, and so do live ones.
  sent = []
  await act(async () => router.reload({ only: ['smart'] }))
  await moodPing()
  expect(reloads('smart')).not.toHaveLength(0)
  expect(reloads('items')).toHaveLength(1)
  sent.forEach((reload) => reload.land())
  await settle()
  expect(screen.getByText(/reading the top 30 matches/)).toBeInTheDocument()

  // A poll of the previous run, sent during the next POST, does not bring that run back.
  await pressEnter()
  await act(async () => router.reload({ only: ['smart'] }))
  await landPost('r2')
  reloads('smart').forEach((reload) => reload.land())
  await settle()
  expect(runInUrl()).toBe('r2')
})
