import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { domError, requestTool } from '../test/model-context-stub'
import { executeManifestTool } from './webmcp_execute'

const fetchMock = vi.fn<typeof fetch>()

function respond(status: number, body: string) {
  fetchMock.mockResolvedValueOnce(new Response(body, { status }))
}

function lastRequest(): { url: string; init: RequestInit; headers: Headers } {
  const [url, init = {}] = fetchMock.mock.lastCall!
  return { url: String(url), init, headers: new Headers(init.headers) }
}

describe('executeManifestTool', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', fetchMock)
    document.head.innerHTML = '<meta name="csrf-token" content="page-token">'
  })

  afterEach(() => {
    fetchMock.mockReset()
    vi.unstubAllGlobals()
    document.head.innerHTML = ''
  })

  it('POSTs the declared arguments with the session and the CSRF token and returns the payload as text', async () => {
    respond(200, '{"item":{"id":7,"status":"claimed"}}')

    const result = await executeManifestTool(requestTool(), { item_id: 7, stray: 'dropped' })

    expect(result).toEqual({ content: [{ type: 'text', text: '{"item":{"id":7,"status":"claimed"}}' }] })
    const { url, init, headers } = lastRequest()
    expect(url).toBe(`${location.origin}/webmcp/tools/claim_item`)
    expect(init.method).toBe('POST')
    expect(init.credentials).toBe('same-origin')
    expect(init.body).toBe('{"item_id":7}')
    expect(headers.get('X-CSRF-Token')).toBe('page-token')
    expect(headers.get('Content-Type')).toBe('application/json')
    expect(headers.get('X-Agent-Name')).toBeNull()
  })

  it('turns a refusal into an error envelope carrying the status and message', async () => {
    respond(422, '{"error":"Item 7 is already claimed by Cursor."}')

    const result = await executeManifestTool(requestTool(), { item_id: 7 })

    expect(result.isError).toBe(true)
    expect(JSON.parse(result.content[0].text)).toEqual({ status: 422, error: 'Item 7 is already claimed by Cursor.' })
  })

  it('wraps a non-JSON failure body as a string', async () => {
    respond(502, '<html>bad gateway</html>')

    const result = await executeManifestTool(requestTool(), { item_id: 7 })

    expect(JSON.parse(result.content[0].text)).toEqual({ status: 502, body: '<html>bad gateway</html>' })
  })

  it.each([
    ['another origin', 'https://evil.example/webmcp/tools/claim_item'],
    ['a page route', '/agents'],
    ['the MCP endpoint', '/mcp'],
  ])('refuses %s without a request', async (_label, url) => {
    const tool = requestTool({ request: { ...requestTool().request, url } })

    const result = await executeManifestTool(tool, { item_id: 7 })

    expect(result.isError).toBe(true)
    expect(result.content[0].text).toContain('refused')
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('enforces maxLength as a UTF-8 byte cap before sending', async () => {
    const tool = requestTool({
      input_schema: {
        type: 'object',
        properties: { summary: { type: 'string', maxLength: 10 } },
        required: ['summary'],
        additionalProperties: false,
      },
      request: { ...requestTool().request, body_params: ['summary'] },
    })

    const result = await executeManifestTool(tool, { summary: 'ééééééé' })

    expect(JSON.parse(result.content[0].text)).toMatchObject({ field: 'summary', max_bytes: 10 })
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('reports an aborted call as cancelled and a network failure as unreachable', async () => {
    fetchMock.mockRejectedValueOnce(domError('aborted', 'AbortError'))
    expect(JSON.parse((await executeManifestTool(requestTool(), { item_id: 7 })).content[0].text)).toEqual({
      error: 'cancelled',
    })

    fetchMock.mockRejectedValueOnce(new TypeError('Failed to fetch'))
    expect(JSON.parse((await executeManifestTool(requestTool(), { item_id: 7 })).content[0].text)).toEqual({
      error: 'unreachable',
      detail: 'Failed to fetch',
    })
  })

  it('passes the signal through to fetch', async () => {
    respond(200, '{}')
    const controller = new AbortController()

    await executeManifestTool(requestTool(), { item_id: 7 }, { signal: controller.signal })

    expect(lastRequest().init.signal).toBe(controller.signal)
  })
})
