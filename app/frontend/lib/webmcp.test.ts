import { afterEach, describe, expect, it } from 'vitest'
import { createModelContextStub, installModelContext } from '../test/model-context-stub'
import { errorResult, getModelContext, textResult, toolNameValid, toSpecAnnotations } from './webmcp'

describe('getModelContext', () => {
  const cleanups: Array<() => void> = []
  afterEach(() => cleanups.splice(0).forEach((cleanup) => cleanup()))

  it('is null when the browser has no WebMCP', () => {
    expect(getModelContext()).toBeNull()
  })

  it('prefers document.modelContext over the pre-draft navigator.modelContext', () => {
    const current = createModelContextStub()
    cleanups.push(installModelContext(current), installModelContext(createModelContextStub(), navigator))

    expect(getModelContext()).toBe(current)
  })

  it('falls back to navigator.modelContext', () => {
    const legacy = createModelContextStub()
    cleanups.push(installModelContext(legacy, navigator))

    expect(getModelContext()).toBe(legacy)
  })

  it('ignores an object without a callable registerTool', () => {
    cleanups.push(installModelContext({} as ModelContext))

    expect(getModelContext()).toBeNull()
  })
})

describe('manifest helpers', () => {
  it('maps snake_case annotations to the spec names', () => {
    expect(toSpecAnnotations({ read_only_hint: true, untrusted_content_hint: false })).toEqual({
      readOnlyHint: true,
      untrustedContentHint: false,
    })
  })

  it('accepts the names Chrome accepts', () => {
    expect(toolNameValid('list_items')).toBe(true)
    expect(toolNameValid('list items')).toBe(false)
    expect(toolNameValid('')).toBe(false)
  })

  it('wraps values in MCP text envelopes', () => {
    expect(textResult('hi')).toEqual({ content: [{ type: 'text', text: 'hi' }] })
    expect(errorResult({ error: 'no' })).toEqual({ content: [{ type: 'text', text: '{"error":"no"}' }], isError: true })
  })
})
