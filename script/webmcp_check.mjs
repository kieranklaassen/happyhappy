// WebMCP browser-tool regression check using Playwright.
// Usage: BASE_URL=http://localhost:3000 node script/webmcp_check.mjs
// Needs a development server (the dev login signs in) with seeded items.
// WEBMCP_CHECK_SCREENSHOT=path saves the signed-in Agents page once tools are registered.
//
// Playwright's Chromium does not run the WebMCP origin trial, so this check installs a
// spec-shaped `document.modelContext` stub before each page script runs. The stub records
// registrations, honors the AbortSignal (unregister), rejects duplicate names like Chrome
// does, and exposes `__webmcpInvoke` so the check can call a registered tool's `execute`
// exactly as a browser agent would. Interpreter refusal scenarios go through the
// development seam `window.__happyhappyWebmcp.execute` with hand-built manifest entries.
import { chromium } from 'playwright'

const BASE = process.env.BASE_URL ?? 'http://localhost:3000'
const ORIGIN = new URL(BASE).origin
const SCREENSHOT = process.env.WEBMCP_CHECK_SCREENSHOT
const TOOLS = ['list_items', 'get_item', 'claim_item', 'release_item', 'report_item', 'list_anomalies']

const assert = (condition, message, detail = '') => {
  if (!condition) throw new Error(`${message}${detail ? `: ${detail}` : ''}`)
  console.log(`✓ ${message}`)
}
const sameSet = (a, b) => JSON.stringify([...a].sort()) === JSON.stringify([...b].sort())
const parseResult = (result) => {
  assert(result && Array.isArray(result.content) && result.content[0]?.type === 'text', 'result is an MCP text envelope')
  try {
    return { text: result.content[0].text, json: JSON.parse(result.content[0].text), isError: result.isError === true }
  } catch {
    return { text: result.content[0].text, json: null, isError: result.isError === true }
  }
}

// Spec-shaped stub: https://webmachinelearning.github.io/webmcp/ (registerTool
// with AbortSignal unregistration, InvalidStateError on duplicate names,
// `toolchange` on register/unregister, getTools()).
const MODEL_CONTEXT_STUB = `
(() => {
  const tools = new Map()
  class ModelContextStub extends EventTarget {
    registerTool(tool, options = {}) {
      const signal = options.signal
      if (signal?.aborted) return Promise.reject(new DOMException('aborted', 'AbortError'))
      if (tools.has(tool.name)) return Promise.reject(new DOMException('duplicate tool name: ' + tool.name, 'InvalidStateError'))
      tools.set(tool.name, tool)
      window.__webmcpToolchange = (window.__webmcpToolchange ?? 0) + 1
      this.dispatchEvent(new Event('toolchange'))
      signal?.addEventListener('abort', () => {
        tools.delete(tool.name)
        window.__webmcpToolchange = (window.__webmcpToolchange ?? 0) + 1
        this.dispatchEvent(new Event('toolchange'))
      })
      return Promise.resolve()
    }
    getTools() {
      return Promise.resolve([...tools.values()].map((tool) => ({
        name: tool.name, description: tool.description, inputSchema: tool.inputSchema,
        annotations: tool.annotations, origin: location.origin,
      })))
    }
  }
  Object.defineProperty(document, 'modelContext', { value: new ModelContextStub(), configurable: true })
  window.__webmcpInvoke = (name, args, { cancel = false } = {}) => {
    const tool = tools.get(name)
    if (!tool) throw new Error('no registered tool named ' + name)
    // The spec passes a per-execution signal; the cancel option aborts it right after
    // the call starts, the way an agent's stop button would.
    const controller = new AbortController()
    const result = tool.execute(args ?? {}, { signal: controller.signal })
    if (cancel) controller.abort()
    return result
  }
})()
`

const browser = await chromium.launch()
const errors = []
let phase = 'boot'
// Tool calls that are supposed to fail log their HTTP status as a console error.
const NOISE = ['status of 401', 'status of 404', 'status of 422', 'Failed to load resource', 'net::ERR_ABORTED']
const isNoise = (message) => NOISE.some((pattern) => message.includes(pattern))
const watch = (page, label) => {
  page.on('pageerror', (error) => {
    const message = error.stack ?? String(error)
    if (!isNoise(message)) errors.push(`${label} [${phase}]: ${message}`)
  })
  page.on('console', (message) => {
    if (message.type() === 'error' && !isNoise(message.text())) {
      errors.push(`${label} [${phase}]: ${message.text()}`)
    }
  })
}

// Every request under /webmcp/, with ALL headers: Playwright's `request.headers()`
// omits cookie and other security headers, so only `allHeaders()` shows them.
const requests = []
const trackRequests = (page) => {
  page.on('request', (request) => {
    if (!new URL(request.url()).pathname.startsWith('/webmcp/')) return
    requests.push(request.allHeaders().then((headers) => ({ url: request.url(), method: request.method(), headers })))
  })
}
const toolRequestsSince = (mark) => Promise.all(requests.slice(mark))

const signIn = async (page) => {
  await page.goto(`${BASE}/session/new`)
  await page.getByRole('button', { name: /^Continue as / }).first().click()
  await page.waitForURL((url) => url.pathname !== '/session/new')
}

const stubContext = await browser.newContext({ viewport: { width: 1440, height: 1000 } })
await stubContext.addInitScript(MODEL_CONTEXT_STUB)
const page = await stubContext.newPage()
watch(page, 'stub')
trackRequests(page)

const getTools = () => page.evaluate(() => document.modelContext.getTools())
const invoke = (name, args, options) =>
  page.evaluate(([n, a, o]) => window.__webmcpInvoke(n, a, o), [name, args, options])
const seam = (tool, args) => page.evaluate(([t, a]) => window.__happyhappyWebmcp.execute(t, a), [tool, args])
const requestTool = (name, url) => ({
  name,
  description: 'hand-built test tool',
  input_schema: { type: 'object', properties: {}, required: [], additionalProperties: false },
  annotations: { read_only_hint: true, untrusted_content_hint: false },
  kind: 'request',
  include_viewer_context: false,
  request: { method: 'POST', url, path_params: [], body_params: [], agent_identity: 'omit' },
})

try {
  phase = 'signed out'
  await page.goto(`${BASE}/session/new`)
  await page.getByRole('button', { name: /^Continue as / }).first().waitFor()
  assert((await getTools()).length === 0, 'the sign-in page registers no tools')
  assert(await page.evaluate(() => window.__happyhappyWebmcp === undefined), 'no development seam while signed out')

  phase = 'registration'
  await page.getByRole('button', { name: /^Continue as / }).first().click()
  await page.waitForURL((url) => url.pathname !== '/session/new')
  await page.waitForFunction((n) => (window.__webmcpToolchange ?? 0) >= n, TOOLS.length)
  const tools = await getTools()
  assert(sameSet(tools.map((t) => t.name), TOOLS), 'signing in registers exactly the six MCP tools')
  assert(
    tools.every((t) => t.description.length > 0 && t.inputSchema?.type === 'object' && t.inputSchema.additionalProperties === false),
    'tools carry descriptions and closed object schemas',
  )
  const byName = Object.fromEntries(tools.map((t) => [t.name, t]))
  assert(byName.list_items.annotations?.readOnlyHint === true && byName.list_items.annotations?.untrustedContentHint === true,
    'list_items maps read-only and untrusted-content hints to the spec annotations')
  assert(byName.claim_item.annotations?.readOnlyHint === false, 'claim_item is not read-only')
  assert(await page.evaluate(() => typeof window.__happyhappyWebmcp?.execute === 'function'),
    'development seam is installed on signed-in pages')

  phase = 'list_items'
  let mark = requests.length
  const listed = parseResult(await invoke('list_items', { status: 'new', limit: 5 }))
  assert(!listed.isError && Array.isArray(listed.json?.items) && listed.json.items.length > 0,
    'list_items returns items through the session endpoint', listed.text.slice(0, 200))
  const [listRequest] = await toolRequestsSince(mark)
  assert(new URL(listRequest.url).origin === ORIGIN && new URL(listRequest.url).pathname === '/webmcp/tools/list_items',
    'the call is a same-origin POST to /webmcp/tools/list_items')
  assert(typeof listRequest.headers.cookie === 'string' && listRequest.headers.cookie.includes('session_id'),
    'the request carries the session cookie')
  assert(listRequest.headers['x-csrf-token']?.length > 0 && listRequest.headers.authorization === undefined,
    'the request carries the CSRF token and no Authorization header')
  const refused = parseResult(await invoke('list_items', { sentiment: ['furious'] }))
  assert(refused.isError && refused.json?.status === 422 && refused.json?.error.includes('sentiment'),
    'an invalid filter value comes back as the 422 tool refusal', refused.text)

  phase = 'claim and release'
  const itemId = listed.json.items[0].id
  const claimed = parseResult(await invoke('claim_item', { item_id: itemId }))
  assert(!claimed.isError && claimed.json?.item?.claimed_by?.endsWith('(WebMCP)'),
    "claim_item holds the claim with the person's browser agent", claimed.text.slice(0, 200))
  const claimEvent = claimed.json.item.timeline.find((event) => event.kind === 'claimed')
  assert(claimEvent?.actor?.type === 'User', 'the claim is credited to the signed-in person', JSON.stringify(claimEvent))
  const released = parseResult(await invoke('release_item', { item_id: itemId }))
  assert(!released.isError && released.json?.item?.status === 'new', 'release_item gives the claim back')
  const releaseEvent = released.json.item.timeline.findLast((event) => event.kind === 'released')
  assert(releaseEvent?.actor?.type === 'User', 'the release is credited to the signed-in person', JSON.stringify(releaseEvent))

  phase = 'cancellation'
  const cancelled = parseResult(await invoke('claim_item', { item_id: itemId }, { cancel: true }))
  assert(cancelled.isError && cancelled.json?.error === 'cancelled', 'a cancelled call returns the cancelled envelope', cancelled.text)
  const afterCancel = parseResult(await invoke('get_item', { item_id: itemId }))
  assert(afterCancel.json?.item?.status === 'new', 'a cancelled claim never reaches the server')

  phase = 'refusals'
  for (const [label, url] of [
    ['an off-origin URL', 'https://evil.example/webmcp/tools/list_items'],
    ['the MCP endpoint', `${ORIGIN}/mcp`],
    ['a page route', `${ORIGIN}/agents`],
  ]) {
    mark = requests.length
    const result = parseResult(await seam(requestTool('t_refused', url), {}))
    assert(result.isError && result.text.includes('refused'), `seam refuses ${label}`, result.text)
    assert((await toolRequestsSince(mark)).length === 0, `${label} made no request`)
  }

  phase = 'navigation'
  await page.getByRole('link', { name: 'Agents' }).click()
  await page.getByRole('heading', { name: 'WebMCP in your browser' }).waitFor()
  await page.waitForFunction(async (names) => {
    const registered = (await document.modelContext.getTools()).map((t) => t.name)
    return registered.length === names.length
  }, TOOLS)
  assert(sameSet((await getTools()).map((t) => t.name), TOOLS), 'after an Inertia visit the six tools are registered once')
  if (SCREENSHOT) {
    await page.screenshot({ path: SCREENSHOT, fullPage: true })
    console.log(`  saved ${SCREENSHOT}`)
  }

  phase = 'sign out'
  const signedOut = await page.evaluate(async () => {
    const token = document.querySelector('meta[name="csrf-token"]').content
    const response = await fetch('/session', { method: 'DELETE', headers: { 'X-CSRF-Token': token } })
    return response.ok
  })
  assert(signedOut, 'signing out ends the session')
  await page.getByRole('link', { name: 'Feed' }).click()
  await page.waitForURL((url) => url.pathname === '/session/new')
  await page.waitForFunction(async () => (await document.modelContext.getTools()).length === 0)
  assert(true, 'the next visit lands on sign-in and unregisters every tool')
  assert(await page.evaluate(() => window.__happyhappyWebmcp === undefined), 'development seam is removed after signing out')
  const status = await page.evaluate(async () => (await fetch('/webmcp/tools/list_items', { method: 'POST', body: '{}' })).status)
  assert(status === 401, 'the tool endpoint answers 401 once signed out', String(status))

  phase = 'no WebMCP'
  const plainContext = await browser.newContext()
  const plain = await plainContext.newPage()
  const plainErrors = []
  plain.on('pageerror', (error) => plainErrors.push(String(error)))
  plain.on('console', (message) => {
    if (message.type() === 'error') plainErrors.push(message.text())
  })
  await signIn(plain)
  await plain.getByRole('link', { name: 'Agents' }).click()
  await plain.getByRole('heading', { name: 'WebMCP in your browser' }).waitFor()
  assert(plainErrors.length === 0, 'signed-in pages load with no console errors without WebMCP', plainErrors.join(' | '))
  await plainContext.close()

  if (errors.length) {
    throw new Error(`unexpected browser errors:\n${errors.join('\n')}`)
  }
  console.log('webmcp_check: all scenarios passed')
} catch (error) {
  console.error(`✗ [${phase}] ${error.message}`)
  process.exitCode = 1
} finally {
  await browser.close()
}
