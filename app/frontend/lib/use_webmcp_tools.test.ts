import { renderHook } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { createModelContextStub, installModelContext, requestTool } from '../test/model-context-stub'
import { useWebmcpTools, type WebmcpExecutor } from './use_webmcp_tools'
import { textResult, type WebmcpManifestTool } from './webmcp'

const TOOLS: WebmcpManifestTool[] = [
  requestTool({ name: 'list_items', annotations: { read_only_hint: true, untrusted_content_hint: true } }),
  requestTool(),
]

function mount(tools = TOOLS, execute: WebmcpExecutor = async () => textResult('{}')) {
  return renderHook(
    (props: { tools: WebmcpManifestTool[] }) => useWebmcpTools({ key: 'app', tools: props.tools, execute }),
    { initialProps: { tools } },
  )
}

describe('useWebmcpTools', () => {
  let uninstall = () => {}
  afterEach(() => {
    uninstall()
    vi.restoreAllMocks()
  })

  it('does nothing when the browser has no WebMCP', () => {
    const warn = vi.spyOn(console, 'warn')

    const { unmount } = mount()
    unmount()

    expect(warn).not.toHaveBeenCalled()
  })

  it('registers every manifest tool with spec annotations and one shared signal', () => {
    const context = createModelContextStub()
    uninstall = installModelContext(context)

    mount()

    expect([...context.tools.keys()]).toEqual(['list_items', 'claim_item'])
    const listItems = context.tools.get('list_items')!
    expect(listItems.annotations).toEqual({ readOnlyHint: true, untrustedContentHint: true })
    expect(listItems.inputSchema).toEqual(TOOLS[0].input_schema)
    expect(context.signals.get('list_items')).toBe(context.signals.get('claim_item'))
  })

  it('unregisters on unmount, including through the legacy unregisterTool', () => {
    const context = createModelContextStub()
    const unregisterTool = vi.fn()
    uninstall = installModelContext(Object.assign(context, { unregisterTool }), navigator)

    const { unmount } = mount()
    unmount()

    expect(context.tools.size).toBe(0)
    expect(context.signals.get('claim_item')?.aborted).toBe(true)
    expect(unregisterTool.mock.calls).toEqual([['list_items'], ['claim_item']])
  })

  it('does not re-register when a partial reload sends a fresh tools array', () => {
    const context = createModelContextStub()
    const registerTool = vi.spyOn(context, 'registerTool')
    uninstall = installModelContext(context)

    const { rerender } = mount()
    rerender({ tools: [...TOOLS] })

    expect(registerTool).toHaveBeenCalledTimes(2)
  })

  it('runs calls through the executor with a signal and turns throws into error envelopes', async () => {
    const context = createModelContextStub()
    uninstall = installModelContext(context)
    const execute = vi
      .fn<WebmcpExecutor>()
      .mockResolvedValueOnce(textResult('{"items":[]}'))
      .mockRejectedValueOnce(new Error('boom'))
    mount(TOOLS, execute)
    const listItems = context.tools.get('list_items')!

    const signal = new AbortController().signal
    expect(await listItems.execute({ product: 'cora' }, { signal })).toEqual(textResult('{"items":[]}'))
    expect(execute.mock.calls[0][1]).toEqual({ product: 'cora' })
    expect(execute.mock.calls[0][2]).toBeInstanceOf(AbortSignal)
    expect(await listItems.execute({}, { signal })).toEqual({
      content: [{ type: 'text', text: '{"error":"boom"}' }],
      isError: true,
    })
  })

  it('warns about a duplicate name instead of throwing', async () => {
    const context = createModelContextStub()
    uninstall = installModelContext(context)
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})

    mount([TOOLS[0], TOOLS[0]])
    await Promise.resolve()
    await Promise.resolve()

    expect(warn).toHaveBeenCalledWith('[webmcp] list_items is already registered; skipping')
  })
})
