import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createWebMcpSync, findModelContext, type ModelContextTool, startWebMcp } from './webmcp'

const definitions = [
  {
    name: 'list_items',
    description: 'List items in the happyhappy feed.',
    inputSchema: { type: 'object', properties: { product: { type: 'string' } } },
    annotations: { readOnlyHint: true, untrustedContentHint: true },
  },
  {
    name: 'claim_item',
    description: 'Claim a new item.',
    inputSchema: { type: 'object', properties: { item_id: { type: 'integer' } }, required: ['item_id'] },
    annotations: { readOnlyHint: false, untrustedContentHint: true },
  },
]

const config = { tools_url: '/webmcp/tools' }

// A stub of the WebMCP draft's model context: registrations live until their signal aborts.
function stubContext() {
  const tools = new Map<string, ModelContextTool>()
  const registerTool = vi.fn(async (tool: ModelContextTool, options?: { signal?: AbortSignal }) => {
    if (tools.has(tool.name)) throw new Error(`${tool.name} is already registered`)
    tools.set(tool.name, tool)
    options?.signal?.addEventListener('abort', () => tools.delete(tool.name))
  })
  return { tools, context: { registerTool } }
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
}

describe('WebMCP registration', () => {
  let fetchMock: ReturnType<typeof vi.fn>

  beforeEach(() => {
    document.head.innerHTML = '<meta name="csrf-token" content="csrf-123">'
    fetchMock = vi.fn(async (url: string) =>
      url === '/webmcp/tools'
        ? jsonResponse({ tools: definitions })
        : jsonResponse({ content: [{ type: 'text', text: '{"items":[]}' }], structuredContent: { items: [] } }),
    )
    vi.stubGlobal('fetch', fetchMock)
  })

  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
    delete (document as { modelContext?: unknown }).modelContext
    delete (navigator as { modelContext?: unknown }).modelContext
  })

  it('registers every tool from the server definitions when signed in', async () => {
    const { tools, context } = stubContext()

    await createWebMcpSync(() => context)(config)

    expect([...tools.keys()]).toEqual(['list_items', 'claim_item'])
    expect(tools.get('claim_item')).toMatchObject(definitions[1])
    expect(context.registerTool).toHaveBeenCalledWith(expect.anything(), { signal: expect.any(AbortSignal) })
  })

  it('runs a tool on the server with the session and CSRF token and returns its MCP result', async () => {
    const { tools, context } = stubContext()
    await createWebMcpSync(() => context)(config)

    const result = await tools.get('list_items')!.execute({ product: 'cora' })

    expect(result).toEqual({ content: [{ type: 'text', text: '{"items":[]}' }], structuredContent: { items: [] } })
    expect(fetchMock).toHaveBeenLastCalledWith('/webmcp/tools/list_items', {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'X-CSRF-Token': 'csrf-123' },
      body: '{"product":"cora"}',
    })
  })

  it('turns a refused call into a tool error the agent can read', async () => {
    const { tools, context } = stubContext()
    await createWebMcpSync(() => context)(config)
    fetchMock.mockResolvedValueOnce(jsonResponse({ error: 'Sign in to happyhappy to use its tools.' }, 401))

    const result = await tools.get('claim_item')!.execute({ item_id: 1 })

    expect(result).toEqual({
      content: [{ type: 'text', text: 'Sign in to happyhappy to use its tools.' }],
      isError: true,
    })
  })

  it('registers once across navigations and unregisters on sign-out', async () => {
    const { tools, context } = stubContext()
    const sync = createWebMcpSync(() => context)

    await sync(config)
    await sync(config)
    expect(context.registerTool).toHaveBeenCalledTimes(2)

    await sync(null)
    expect(tools.size).toBe(0)

    await sync(config)
    expect([...tools.keys()]).toEqual(['list_items', 'claim_item'])
  })

  it('also calls unregisterTool on older implementations that have it', async () => {
    const { context } = stubContext()
    const unregisterTool = vi.fn()
    const sync = createWebMcpSync(() => ({ ...context, unregisterTool }))

    await sync(config)
    await sync(undefined)

    expect(unregisterTool.mock.calls).toEqual([['list_items'], ['claim_item']])
  })

  it('does nothing, and fetches nothing, when the browser has no model context', async () => {
    await createWebMcpSync(() => null)(config)

    expect(findModelContext()).toBeNull()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('does nothing when signed out', async () => {
    const { context } = stubContext()

    await createWebMcpSync(() => context)(null)

    expect(context.registerTool).not.toHaveBeenCalled()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('prefers document.modelContext and falls back to navigator.modelContext', () => {
    const legacy = stubContext().context
    Object.defineProperty(navigator, 'modelContext', { value: legacy, configurable: true })
    expect(findModelContext()).toBe(legacy)

    const current = stubContext().context
    Object.defineProperty(document, 'modelContext', { value: current, configurable: true })
    expect(findModelContext()).toBe(current)
  })

  it('follows Inertia navigations and unregisters when stopped', async () => {
    const { tools, context } = stubContext()
    let navigate: ((event: { detail: { page: { props: object } } }) => void) | undefined
    const removeListener = vi.fn()
    const router = {
      on: vi.fn((_event: 'navigate', callback: typeof navigate) => {
        navigate = callback
        return removeListener
      }),
    }

    const stop = startWebMcp(null, router, () => context)
    navigate!({ detail: { page: { props: { webmcp: config } } } })
    await vi.waitFor(() => expect(tools.size).toBe(2))

    navigate!({ detail: { page: { props: { webmcp: null } } } })
    expect(tools.size).toBe(0)

    navigate!({ detail: { page: { props: { webmcp: config } } } })
    await vi.waitFor(() => expect(tools.size).toBe(2))
    stop()
    expect(tools.size).toBe(0)
    expect(removeListener).toHaveBeenCalled()
  })
})
