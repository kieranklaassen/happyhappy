/**
 * WebMCP: while a person is signed in, register happyhappy's MCP tools with the browser's model context
 * so an agent in the browser can use them with the person's session.
 *
 * Targets the WebMCP draft (https://webmachinelearning.github.io/webmcp/): `document.modelContext
 * .registerTool(tool, { signal })`, unregistered by aborting the signal. `navigator.modelContext` and
 * `unregisterTool(name)` are only fallbacks for older implementations. Without a model context this does
 * nothing, and tool definitions are never fetched.
 *
 * Definitions come from the server (Mcp::ToolRegistry), and every call runs on the server, so names,
 * descriptions, schemas, and results match the MCP server exactly.
 */

export interface WebMcpConfig {
  tools_url: string
}

interface ToolDefinition {
  name: string
  title?: string
  description: string
  inputSchema: object
  annotations?: { readOnlyHint?: boolean; untrustedContentHint?: boolean }
}

interface CallToolResult {
  content: { type: 'text'; text: string }[]
  structuredContent?: unknown
  isError?: boolean
}

export interface ModelContextTool extends ToolDefinition {
  execute: (input: object) => Promise<CallToolResult>
}

export interface ModelContextLike {
  registerTool: (tool: ModelContextTool, options?: { signal?: AbortSignal }) => unknown
  unregisterTool?: (name: string) => unknown
}

interface RouterLike {
  on: (event: 'navigate', callback: (event: { detail: { page: { props: object } } }) => void) => () => void
}

type ContextLookup = () => ModelContextLike | null

export function findModelContext(): ModelContextLike | null {
  const context =
    (document as { modelContext?: ModelContextLike }).modelContext ??
    (navigator as { modelContext?: ModelContextLike }).modelContext
  return context && typeof context.registerTool === 'function' ? context : null
}

function csrfToken(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ''
}

function errorResult(text: string): CallToolResult {
  return { content: [{ type: 'text', text }], isError: true }
}

async function callTool(toolsUrl: string, name: string, input: object): Promise<CallToolResult> {
  try {
    const response = await fetch(`${toolsUrl}/${encodeURIComponent(name)}`, {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'X-CSRF-Token': csrfToken() },
      body: JSON.stringify(input ?? {}),
    })
    const body = (await response.json().catch(() => null)) as (CallToolResult & { error?: string }) | null
    if (response.ok && body) return body
    return errorResult(body?.error ?? `happyhappy answered ${response.status}.`)
  } catch {
    return errorResult('happyhappy could not be reached.')
  }
}

/**
 * Returns `sync(config)`: call it with the `webmcp` shared prop after every page load. A config registers
 * the tools once; a missing config (signed out) unregisters them.
 */
export function createWebMcpSync(lookup: ContextLookup = findModelContext) {
  let active: { controller: AbortController; context: ModelContextLike; names: string[] } | null = null

  function stop() {
    if (!active) return
    const { controller, context, names } = active
    active = null
    controller.abort()
    for (const name of names) {
      try {
        context.unregisterTool?.(name)
      } catch {
        // Already gone: the signal unregistered it.
      }
    }
  }

  async function start(config: WebMcpConfig) {
    const context = lookup()
    if (!context) return

    const controller = new AbortController()
    const registration = { controller, context, names: [] as string[] }
    active = registration

    let tools: ToolDefinition[]
    try {
      const response = await fetch(config.tools_url, {
        credentials: 'same-origin',
        headers: { Accept: 'application/json' },
        signal: controller.signal,
      })
      if (!response.ok) throw new Error(`happyhappy answered ${response.status}`)
      tools = ((await response.json()) as { tools: ToolDefinition[] }).tools
    } catch (error) {
      if (active === registration) active = null
      if (!controller.signal.aborted) console.warn('WebMCP tools could not be loaded', error)
      return
    }
    if (controller.signal.aborted) return

    for (const tool of tools) {
      if (controller.signal.aborted) return
      try {
        await context.registerTool(
          { ...tool, execute: (input) => callTool(config.tools_url, tool.name, input) },
          { signal: controller.signal },
        )
        registration.names.push(tool.name)
      } catch (error) {
        console.warn(`WebMCP could not register ${tool.name}`, error)
      }
    }
  }

  return function sync(config: WebMcpConfig | null | undefined): Promise<void> {
    if (!config) {
      stop()
      return Promise.resolve()
    }
    if (active) return Promise.resolve()
    return start(config)
  }
}

/** Syncs WebMCP with the first page and every Inertia navigation. Returns a function that stops it. */
export function startWebMcp(
  initial: WebMcpConfig | null | undefined,
  router: RouterLike,
  lookup: ContextLookup = findModelContext,
): () => void {
  const sync = createWebMcpSync(lookup)
  void sync(initial)
  const removeListener = router.on('navigate', (event) => {
    void sync((event.detail.page.props as { webmcp?: WebMcpConfig | null }).webmcp)
  })
  return () => {
    removeListener()
    void sync(null)
  }
}
