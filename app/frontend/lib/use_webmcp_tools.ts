import { useEffect, useRef } from 'react'
import {
  errorMessage,
  errorResult,
  getModelContext,
  isAbortError,
  toolNameValid,
  toSpecAnnotations,
  type WebmcpManifestTool,
  type WebmcpResult,
} from './webmcp'

/**
 * Page-supplied executor. Receives the run's abort signal so every fetch it
 * starts is cancelled together with the registration on cleanup.
 */
export type WebmcpExecutor = (
  tool: WebmcpManifestTool,
  args: Record<string, unknown>,
  signal: AbortSignal,
) => Promise<WebmcpResult>

interface UseWebmcpToolsOptions {
  /** Registration identity (AppNav passes `"app"`); the only effect dependency. */
  key: string
  tools: WebmcpManifestTool[]
  execute: WebmcpExecutor
}

/**
 * Registers the manifest's tools on the model context once per identity and
 * unregisters them on cleanup (unmount, which includes signing out: the
 * signed-out pages render no AppNav).
 *
 * `tools` and `execute` are read through refs so the effect depends on `key`
 * alone: a partial Inertia reload re-sends a fresh `tools` array and must not
 * re-register (duplicate names reject with `InvalidStateError`). Each run
 * owns one `AbortController`; its signal goes to every `registerTool` and to
 * every fetch, so aborting on cleanup is the single wrong-document guard.
 * StrictMode's mount→cleanup→mount aborts the first registration
 * synchronously, so the second never sees a duplicate name. A browser
 * without WebMCP returns early and logs nothing.
 */
export function useWebmcpTools({ key, tools, execute }: UseWebmcpToolsOptions): void {
  const toolsRef = useRef(tools)
  toolsRef.current = tools
  const executeRef = useRef(execute)
  executeRef.current = execute

  useEffect(() => {
    const controller = new AbortController()
    const { signal } = controller

    // Results are data, never exceptions: a throw would reach the
    // agent as a bare UnknownError and `undefined` fails serialization.
    // The fetch aborts on either signal: the page-lifetime one (cleanup) or
    // the per-call one the agent passes when it cancels the execution, so a
    // cancelled write never reaches the server.
    const run = async (
      tool: WebmcpManifestTool,
      args: Record<string, unknown>,
      callSignal?: AbortSignal,
    ): Promise<WebmcpResult> => {
      try {
        const combined = callSignal ? AbortSignal.any([signal, callSignal]) : signal
        const result = await executeRef.current(tool, args ?? {}, combined)
        if (result === undefined || result === null) {
          return errorResult({ error: `${tool.name} returned no result` })
        }
        return result
      } catch (error) {
        return errorResult({ error: errorMessage(error) })
      }
    }

    // Development seam for script/webmcp_check.mjs: hand-built manifest
    // entries go through the real interpreter without a WebMCP browser.
    // Installed before the feature gate so the interpreter can be exercised
    // from any dev browser; removed on cleanup so it never outlives its page.
    if (import.meta.env.DEV) {
      window.__happyhappyWebmcp = { execute: (tool, args) => run(tool, args) }
    }

    const context = getModelContext()
    const registered: string[] = []
    const teardown = () => {
      controller.abort()
      unregisterLegacy(context, registered)
      if (import.meta.env.DEV && window.__happyhappyWebmcp?.execute) {
        delete window.__happyhappyWebmcp
      }
    }

    if (!context) return teardown

    for (const tool of toolsRef.current) {
      if (import.meta.env.DEV && !toolNameValid(tool.name)) {
        console.warn(`[webmcp] skipping tool with invalid name: ${JSON.stringify(tool.name)}`)
        continue
      }
      try {
        // `Promise.resolve` covers an implementation that returns void
        // synchronously; the spec's Promise rejects asynchronously.
        Promise.resolve(
          context.registerTool(
            {
              name: tool.name,
              description: tool.description,
              inputSchema: tool.input_schema,
              annotations: toSpecAnnotations(tool.annotations),
              execute: (input, options) => run(tool, input, options?.signal),
            },
            { signal },
          ),
        ).catch((error: unknown) => reportRegistrationError(tool.name, error))
        registered.push(tool.name)
      } catch (error) {
        reportRegistrationError(tool.name, error)
      }
    }

    return teardown
  }, [key])
}

/**
 * Chrome builds that predate signal-based unregistration keep tools after the
 * abort; they still expose `unregisterTool`. Spec implementations have no such
 * method, and a name already gone is not worth reporting.
 */
function unregisterLegacy(context: ModelContext | null, names: string[]): void {
  if (typeof context?.unregisterTool !== 'function') return
  for (const name of names) {
    try {
      Promise.resolve(context.unregisterTool(name)).catch(() => {})
    } catch {
      // Already unregistered by the abort.
    }
  }
}

/**
 * AbortError is the expected outcome of StrictMode's synchronous cleanup and
 * of navigating away mid-registration, so it is silent. InvalidStateError
 * (duplicate name) and anything else are real and worth a line in dev tools.
 */
function reportRegistrationError(name: string, error: unknown): void {
  if (isAbortError(error)) return
  if (error instanceof Error && error.name === 'InvalidStateError') {
    console.warn(`[webmcp] ${name} is already registered; skipping`)
    return
  }
  console.warn(`[webmcp] failed to register ${name}: ${errorMessage(error)}`)
}
