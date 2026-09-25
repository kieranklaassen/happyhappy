import type { WebmcpRequestTool } from '../lib/webmcp'

export interface ModelContextStub extends ModelContext {
  tools: Map<string, ModelContextTool>
  signals: Map<string, AbortSignal | undefined>
}

// jsdom's DOMException is not an Error the way browsers' is, so failures are
// Errors carrying the DOMException name the page code checks.
export function domError(message: string, name: string): Error {
  return Object.assign(new Error(message), { name })
}

// Spec-shaped stand-in for document.modelContext: registerTool with AbortSignal
// unregistration and InvalidStateError on duplicate names, like Chrome.
export function createModelContextStub(): ModelContextStub {
  const target = new EventTarget()
  const tools = new Map<string, ModelContextTool>()
  const signals = new Map<string, AbortSignal | undefined>()
  const stub = Object.assign(target, {
    tools,
    signals,
    ontoolchange: null,
    registerTool(tool: ModelContextTool, options: ModelContextRegisterToolOptions = {}) {
      const { signal } = options
      if (signal?.aborted) return Promise.reject(domError('aborted', 'AbortError'))
      if (tools.has(tool.name)) {
        return Promise.reject(domError(`duplicate tool name: ${tool.name}`, 'InvalidStateError'))
      }
      tools.set(tool.name, tool)
      signals.set(tool.name, signal)
      signal?.addEventListener('abort', () => tools.delete(tool.name))
      return Promise.resolve()
    },
    getTools: () => [...tools.values()],
    executeTool: (name: string, input: Record<string, unknown>) =>
      Promise.resolve(tools.get(name)?.execute(input, { signal: new AbortController().signal })),
  })
  return stub as ModelContextStub
}

export function installModelContext(context: ModelContext | undefined, on: object = document): () => void {
  Object.defineProperty(on, 'modelContext', { value: context, configurable: true })
  return () => {
    delete (on as { modelContext?: ModelContext }).modelContext
  }
}

export function requestTool(overrides: Partial<WebmcpRequestTool> = {}): WebmcpRequestTool {
  return {
    name: 'claim_item',
    description: 'Claim an item.',
    input_schema: {
      type: 'object',
      properties: { item_id: { type: 'integer' } },
      required: ['item_id'],
      additionalProperties: false,
    },
    annotations: { read_only_hint: false, untrusted_content_hint: true },
    kind: 'request',
    request: {
      method: 'POST',
      url: `${location.origin}/webmcp/tools/claim_item`,
      path_params: [],
      body_params: ['item_id'],
      agent_identity: 'omit',
    },
    include_viewer_context: false,
    ...overrides,
  }
}
