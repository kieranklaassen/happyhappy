import { beforeEach, describe, expect, it, vi } from 'vitest'

type Resolve = (name: string) => unknown
type SsrRender = (page: object) => unknown

const captured = vi.hoisted(() => ({
  resolve: undefined as Resolve | undefined,
  ssrRender: undefined as SsrRender | undefined,
}))

vi.mock('@inertiajs/react', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  createInertiaApp: (options: { resolve?: Resolve }) => {
    captured.resolve = options.resolve
    return Promise.resolve()
  },
}))

vi.mock('@inertiajs/react/server', () => ({
  default: (render: SsrRender) => {
    captured.ssrRender = render
  },
}))

const files = Object.keys(import.meta.glob('../pages/**/*.tsx')).map((path) =>
  path.replace('../pages/', '').replace('.tsx', ''),
)
const isTest = (name: string) => /\.(test|spec)$/.test(name)
const pages = files.filter((name) => !isTest(name))
const tests = files.filter(isTest)

beforeEach(() => {
  captured.resolve = undefined
})

// Whatever an entrypoint can resolve, its build ships.
describe('page resolution', () => {
  it('has pages and page tests to tell apart', () => {
    expect(pages).not.toEqual([])
    expect(tests).not.toEqual([])
  })

  it('resolves every page and no page test in the browser', async () => {
    await import('../entrypoints/inertia')
    const resolve = captured.resolve as Resolve

    for (const name of pages) expect(await resolve(name), name).toBeTypeOf('function')
    for (const name of tests) await expect(resolve(name), name).rejects.toThrow(`Page not found: ${name}`)
  })

  it('resolves every page and no page test on the server', async () => {
    await import('../ssr/ssr')
    captured.ssrRender?.({})
    const resolve = captured.resolve as Resolve

    for (const name of pages) expect(await resolve(name), name).toHaveProperty('default')
    for (const name of tests) expect(await resolve(name), name).toBeUndefined()
  })
})
