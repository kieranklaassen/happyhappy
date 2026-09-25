// Client-side cost per page against the perf fixture, in headless Chrome.
//
//   npm install --no-save playwright-core
//   BASE_URL=http://localhost:3200 TIMELINE_ID=123 node script/perf/browser.mjs
//
// Prints JSON: per page, the median over RUNS fresh loads of LCP, total blocking time, a TTI estimate,
// main-thread time during load, DOM nodes, JS heap, idle main-thread use (animation cost), and scroll
// jank. `burst` opens the weekly dashboard, has another process change 50 items at once, and reports the
// main-thread time above the page's idle rate while it catches up.
// SCREENSHOTS=dir also saves reduced-motion screenshots for visual comparison.
import { spawn } from 'node:child_process'
import { mkdirSync } from 'node:fs'
import { chromium } from 'playwright-core'

const BASE = process.env.BASE_URL ?? 'http://localhost:3200'
const RUNS = Number(process.env.RUNS ?? 3)
const CHROME = process.env.CHROME ?? '/usr/local/bin/google-chrome'
const PAGES = {
  dashboard_today: '/',
  dashboard_week: '/?range=7d',
  feed: '/items',
  timeline: `/items/${process.env.TIMELINE_ID}`,
  overview: '/products/cora/overview',
}

const median = (values) => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)]
const round = (value) => Math.round(value * 10) / 10

async function signIn(context) {
  const page = await context.newPage()
  await page.goto(`${BASE}/session/new`)
  await page.getByRole('button', { name: /continue as/i }).first().click()
  await page.waitForURL(`${BASE}/`)
  await page.close()
}

async function taskMs(cdp) {
  const { metrics } = await cdp.send('Performance.getMetrics')
  const value = (name) => metrics.find((metric) => metric.name === name)?.value ?? 0
  return { task: value('TaskDuration') * 1000, heap: value('JSHeapUsedSize') / 1048576 }
}

async function measurePage(context, path) {
  const page = await context.newPage()
  const errors = []
  page.on('pageerror', (error) => errors.push(String(error)))
  const cdp = await context.newCDPSession(page)
  await cdp.send('Performance.enable')
  await page.goto(BASE + path, { waitUntil: 'load' })
  await page.waitForLoadState('networkidle')
  await page.waitForTimeout(800)

  const load = await taskMs(cdp)
  const timing = await page.evaluate(() => {
    const nav = performance.getEntriesByType('navigation')[0]
    const tasks = window.__perf.longTasks
    const lastTask = tasks.reduce((end, [start, duration]) => Math.max(end, start + duration), 0)
    return {
      ttfb_ms: nav.responseStart,
      lcp_ms: window.__perf.lcp,
      tbt_ms: tasks.reduce((sum, [, duration]) => sum + Math.max(0, duration - 50), 0),
      tti_ms: Math.max(nav.domContentLoadedEventEnd, lastTask),
      dom_nodes: document.getElementsByTagName('*').length,
    }
  })

  const idleStart = await taskMs(cdp)
  await page.waitForTimeout(3000)
  const idleEnd = await taskMs(cdp)

  const scrollStart = await taskMs(cdp)
  const scroll = await page.evaluate(
    () =>
      new Promise((resolve) => {
        const deltas = []
        const distance = document.documentElement.scrollHeight - innerHeight
        const started = performance.now()
        let last = started
        function frame(now) {
          deltas.push(now - last)
          last = now
          const progress = Math.min(1, (now - started) / 3000)
          scrollTo(0, distance * progress)
          if (progress < 1) requestAnimationFrame(frame)
          else {
            deltas.sort((a, b) => a - b)
            resolve({ p95: deltas[Math.floor(deltas.length * 0.95)], jank: deltas.filter((d) => d > 50).length })
          }
        }
        requestAnimationFrame(frame)
      }),
  )
  const scrollEnd = await taskMs(cdp)
  await page.close()

  return {
    ...timing,
    load_main_ms: load.task,
    heap_mb: load.heap,
    idle_main_pct: ((idleEnd.task - idleStart.task) / 3000) * 100,
    scroll_p95_frame_ms: scroll.p95,
    scroll_jank_frames: scroll.jank,
    scroll_main_ms: scrollEnd.task - scrollStart.task,
    errors: errors.length,
  }
}

async function measureBurst(context) {
  const page = await context.newPage()
  const cdp = await context.newCDPSession(page)
  await cdp.send('Performance.enable')
  await page.goto(`${BASE}/?range=7d`)
  await page.waitForLoadState('networkidle')
  await page.getByText('Live').first().waitFor()
  await page.waitForTimeout(1000)

  const idleStart = await taskMs(cdp)
  await page.waitForTimeout(3000)
  const idleRate = ((await taskMs(cdp)).task - idleStart.task) / 3000

  const reloads = []
  page.on('requestfinished', async (request) => {
    if (!request.headers()['x-inertia-partial-data']) return
    const response = await request.response()
    reloads.push({ end: Date.now(), bytes: Number((await response?.headerValue('content-length')) ?? 0) })
  })

  const runner = spawn('bin/rails', ['runner', 'script/perf/burst.rb'], { cwd: process.cwd(), stdio: ['ignore', 'pipe', 'inherit'] })
  const started = await new Promise((resolve) => runner.stdout.on('data', () => resolve(Date.now())))
  const before = await taskMs(cdp)
  await new Promise((resolve) => runner.on('exit', resolve))
  await page.waitForTimeout(6000)
  const after = await taskMs(cdp)
  const window = Date.now() - started
  const longest = await page.evaluate(
    (since) => window.__perf.longTasks.filter(([start]) => start > since).reduce((max, [, d]) => Math.max(max, d), 0),
    await page.evaluate((wall) => performance.now() - (Date.now() - wall), started),
  )
  await page.close()

  return {
    burst_reloads: reloads.length,
    burst_extra_main_ms: Math.max(0, after.task - before.task - idleRate * window),
    burst_longest_task_ms: longest,
    burst_settle_ms: reloads.length ? Math.max(...reloads.map((reload) => reload.end)) - started : 0,
  }
}

async function screenshots(browser, dir) {
  mkdirSync(dir, { recursive: true })
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, reducedMotion: 'reduce' })
  await signIn(context)
  const page = await context.newPage()
  for (const [name, path] of Object.entries(PAGES)) {
    await page.goto(BASE + path)
    await page.waitForLoadState('networkidle')
    await page.waitForTimeout(500)
    await page.screenshot({ path: `${dir}/${name}.png` })
  }
  await context.close()
}

const browser = await chromium.launch({ executablePath: CHROME, args: ['--no-sandbox'] })
if (process.env.SCREENSHOTS) await screenshots(browser, process.env.SCREENSHOTS)

const runs = []
for (let run = 0; run < RUNS; run++) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 } })
  await context.addInitScript(() => {
    window.__perf = { lcp: 0, longTasks: [] }
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) window.__perf.lcp = entry.startTime
    }).observe({ type: 'largest-contentful-paint', buffered: true })
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) window.__perf.longTasks.push([entry.startTime, entry.duration])
    }).observe({ type: 'longtask', buffered: true })
  })
  await signIn(context)
  const result = {}
  for (const [name, path] of Object.entries(PAGES)) result[name] = await measurePage(context, path)
  if (process.env.BURST !== '0') result.burst = await measureBurst(context)
  runs.push(result)
  await context.close()
}
await browser.close()

const summary = {}
for (const section of Object.keys(runs[0])) {
  summary[section] = {}
  for (const metric of Object.keys(runs[0][section])) {
    summary[section][metric] = round(median(runs.map((run) => run[section][metric])))
  }
}
console.log(JSON.stringify(summary, null, 2))
