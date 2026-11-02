#!/usr/bin/env node
/**
 * 直连 CDP 操作调试 Chrome 里的页面 —— 与 `chrome-debug.sh` 配套：
 * 那边负责起 / 停带独立 profile 的 Chrome，这边负责在它的某个标签页里导航、求值、
 * 截图、抓控制台与请求。替代 agent-browser，解决两个实测问题（2026-09-22）：
 *
 * 1. **抢窗口焦点**：agent-browser 的 `tab new`，以及目标 tab 不是当前活动 tab 时的
 *    `open` / `hover` / `reload`，都会激活该 tab，把 Chrome 提到最前、顶掉用户正在
 *    用的应用。本工具全程按 targetId 直连该页自己的 WebSocket，不调用任何激活类方法。
 * 2. **target 漂移**：agent-browser 的 session 会落到别的标签页（实测漂到过
 *    about:blank / 用户自己的页面），容易误判「页面未就绪」。本工具每条命令都
 *    显式带 targetId。
 *
 * 端口：源 profile 默认 9222；clone 的端口看 `chrome-debug.sh status`。
 * 传法三选一：`--port 9223` 放在命令前、环境变量 `CDP_PORT`、不传用 9222。
 *
 * 用法：
 *   node cdp.mjs [--port N] targets                 列出页面 target（id + url）
 *   node cdp.mjs new <url>                          新建标签页并返回 targetId（不抢焦点）
 *   node cdp.mjs nav <tid> <url>                    导航并等 readyState=complete，回 {url, ready}
 *   node cdp.mjs eval <tid> <js>                    求值（await Promise），返回 JSON
 *   node cdp.mjs wait <tid> <js> [timeoutMs=30000]  轮询到表达式为真，回 {ok, value, waitedMs}
 *   node cdp.mjs text <tid>                         document.body.innerText
 *   node cdp.mjs click <tid> <selector>             DOM click（不走 Input，不需要激活）
 *   node cdp.mjs setfiles <tid> <selector> <file…>  给 input[type=file] 塞本地文件（DOM.setFileInputFiles）
 *   node cdp.mjs shot <tid> <path> [--full]         截图（--full 整页）
 *   node cdp.mjs console <tid> <ms>                 采集这段时间的 console.error / pageerror
 *   node cdp.mjs net <tid> <ms> [urlSubstr]         采集请求（含 body；可选按 URL 子串过滤）
 *   node cdp.mjs close <tid>                        关闭标签页
 *
 * 结论纪律：`nav` / `eval` 的返回里带 `location.href`，下结论前先核它是你要的页；
 * 判「页面坏了 / 未就绪」之前先拿一个已知正常的页跑同一条命令做对照。
 */

const argv = process.argv.slice(2)
let portArg
const pi = argv.indexOf('--port')
if (pi !== -1) { portArg = argv[pi + 1]; argv.splice(pi, 2) }
const PORT = portArg ?? process.env.CDP_PORT ?? '9222'
const BASE = `http://127.0.0.1:${PORT}`

async function listTargets() {
  const res = await fetch(`${BASE}/json/list`)
  const all = await res.json()
  return all.filter((t) => t.type === 'page')
}

/** 每条命令开一条到「该页自己」的 WS：不经 browser endpoint，就不会碰激活类方法。 */
function openSession(targetId) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${PORT}/devtools/page/${targetId}`)
    let id = 0
    const pending = new Map()
    const listeners = []
    ws.onmessage = (ev) => {
      const msg = JSON.parse(ev.data)
      if (msg.id != null && pending.has(msg.id)) {
        const { resolve: r, reject: j } = pending.get(msg.id)
        pending.delete(msg.id)
        msg.error ? j(new Error(JSON.stringify(msg.error))) : r(msg.result)
        return
      }
      for (const fn of listeners) fn(msg)
    }
    ws.onerror = () => reject(new Error(`无法连接 target ${targetId}`))
    ws.onopen = () =>
      resolve({
        send: (method, params = {}) =>
          new Promise((r, j) => {
            const mid = ++id
            pending.set(mid, { resolve: r, reject: j })
            ws.send(JSON.stringify({ id: mid, method, params }))
          }),
        on: (fn) => listeners.push(fn),
        close: () => ws.close(),
      })
  })
}

async function evaluate(s, expression) {
  const { result, exceptionDetails } = await s.send('Runtime.evaluate', {
    expression,
    returnByValue: true,
    awaitPromise: true,
  })
  if (exceptionDetails) {
    throw new Error(exceptionDetails.exception?.description ?? 'eval 抛错')
  }
  return result.value
}

/** 等到 readyState complete —— 不用 Page.loadEventFired，避免错过已经加载完的页面。 */
async function waitReady(s, timeoutMs = 60000) {
  const deadline = Date.now() + timeoutMs
  for (;;) {
    const state = await evaluate(s, 'document.readyState')
    if (state === 'complete') return true
    if (Date.now() > deadline) return false
    await new Promise((r) => setTimeout(r, 500))
  }
}

const [cmd, ...args] = argv

function out(value) {
  process.stdout.write(
    typeof value === 'string' ? value + '\n' : JSON.stringify(value) + '\n',
  )
}

const commands = {
  async targets() {
    for (const t of await listTargets()) out(`${t.id}\t${t.url}`)
  },

  async new([url]) {
    // PUT /json/new 实测不抢焦点，而 agent-browser 的 tab new 会。
    const res = await fetch(`${BASE}/json/new?${url ?? 'about:blank'}`, {
      method: 'PUT',
    })
    const t = await res.json()
    out(t.id)
  },

  async nav([tid, url]) {
    const s = await openSession(tid)
    await s.send('Page.enable')
    await s.send('Page.navigate', { url })
    const ok = await waitReady(s)
    out({ url: await evaluate(s, 'location.href'), ready: ok, title: await evaluate(s, 'document.title') })
    s.close()
  },

  async eval([tid, ...rest]) {
    const s = await openSession(tid)
    out(await evaluate(s, rest.join(' ')))
    s.close()
  },

  async wait([tid, js, timeoutMs = '30000']) {
    const s = await openSession(tid)
    const started = Date.now()
    let value
    for (;;) {
      value = await evaluate(s, js)
      if (value) break
      if (Date.now() - started > Number(timeoutMs)) {
        out({ ok: false, value, waitedMs: Date.now() - started, url: await evaluate(s, 'location.href') })
        s.close()
        process.exit(1)
      }
      await new Promise((r) => setTimeout(r, 300))
    }
    out({ ok: true, value, waitedMs: Date.now() - started, url: await evaluate(s, 'location.href') })
    s.close()
  },

  async setfiles([tid, selector, ...files]) {
    if (!selector || files.length === 0) throw new Error('用法：setfiles <tid> <selector> <file…>')
    const { resolve } = await import('node:path')
    const s = await openSession(tid)
    await s.send('DOM.enable')
    const { root } = await s.send('DOM.getDocument', { depth: 1 })
    const { nodeId } = await s.send('DOM.querySelector', { nodeId: root.nodeId, selector })
    if (!nodeId) throw new Error(`没有匹配 ${selector} 的元素`)
    await s.send('DOM.setFileInputFiles', { nodeId, files: files.map((f) => resolve(f)) })
    out({ set: files.length, selector })
    s.close()
  },

  async text([tid]) {
    const s = await openSession(tid)
    out(await evaluate(s, 'document.body.innerText'))
    s.close()
  },

  async click([tid, selector]) {
    const s = await openSession(tid)
    const hit = await evaluate(
      s,
      `(() => { const el = document.querySelector(${JSON.stringify(selector)});
        if (!el) return false; el.click(); return true })()`,
    )
    out({ clicked: hit })
    s.close()
  },

  async shot([tid, path, flag]) {
    const s = await openSession(tid)
    const { data } = await s.send('Page.captureScreenshot', {
      format: 'png',
      ...(flag === '--full' ? { captureBeyondViewport: true } : {}),
    })
    const { writeFileSync } = await import('node:fs')
    writeFileSync(path, Buffer.from(data, 'base64'))
    out({ saved: path })
    s.close()
  },

  async console([tid, ms = '8000']) {
    const s = await openSession(tid)
    const errors = []
    s.on((m) => {
      if (m.method === 'Runtime.consoleAPICalled' && m.params.type === 'error') {
        errors.push({
          kind: 'console.error',
          text: m.params.args
            .map((a) => a.value ?? a.description ?? a.type)
            .join(' ')
            .slice(0, 300),
        })
      }
      if (m.method === 'Runtime.exceptionThrown') {
        errors.push({
          kind: 'pageerror',
          text: (
            m.params.exceptionDetails.exception?.description ?? ''
          ).slice(0, 300),
        })
      }
    })
    await s.send('Runtime.enable')
    await new Promise((r) => setTimeout(r, Number(ms)))
    out({ windowMs: Number(ms), count: errors.length, errors })
    s.close()
  },

  async net([tid, ms = '10000', filter = '']) {
    const s = await openSession(tid)
    const reqs = []
    s.on((m) => {
      if (m.method !== 'Network.requestWillBeSent') return
      const { url, method, postData } = m.params.request
      if (filter && !url.includes(filter)) return
      reqs.push({ method, url: url.slice(0, 200), postData })
    })
    await s.send('Network.enable')
    await new Promise((r) => setTimeout(r, Number(ms)))
    out({ windowMs: Number(ms), count: reqs.length, requests: reqs })
    s.close()
  },

  async close([tid]) {
    await fetch(`${BASE}/json/close/${tid}`)
    out({ closed: tid })
  },
}

const run = commands[cmd]
if (!run) {
  process.stderr.write(
    `未知命令 ${cmd ?? '(空)'}；可用：${Object.keys(commands).join(' / ')}\n`,
  )
  process.exit(1)
}
run(args).then(
  () => process.exit(0),
  (err) => {
    process.stderr.write(String(err?.message ?? err) + '\n')
    process.exit(1)
  },
)
