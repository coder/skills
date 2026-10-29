// Draws the Coder workspace status as one line above the prompt.
//
// The facts come from scripts/coder-status json. Outside a Coder workspace it
// prints nothing, and nothing is drawn. Apps and startup script names come
// from the agent's manifest, which needs no token. With a logged-in coder CLI
// it also reads the Coder API: autostop and template updates.
//
// The diamond is the workspace at a glance. Its color is the worst thing
// worth knowing (green fine, yellow look soon, red act now), it's hollow when
// the deployment doesn't answer, and it pulses while Claude works or the
// startup scripts run. Everything else on the line is text or a plain link,
// and most of it shows only when there's something to say.

const CRITICAL_PCT = 95
const SOON_SEC = 60 * 60
const VERY_SOON_SEC = 10 * 60
const PULSE = ['◆', '◈', '◇', '◈']
const SCRIPT_OK = new Set(['ok', 'running', 'unknown'])
// Links are drawn in this color, so they read as links on every surface.
const LINK = 'suggestion'
let info = null
let nowSec = 0
let running = false
let pending = false
let working = false
let frame = 0
let pulse = null

async function refresh($) {
  if (running) {
    pending = true
    return
  }
  running = true
  let changed = false
  try {
    do {
      pending = false
      let next = null
      try {
        const r = await $.process.run(['bash', $.plugin.root + '/scripts/coder-status', 'json', await $.session.id()])
        const out = r.stdout.trim()
        next = out ? JSON.parse(out) : null
      } catch {
        next = info
      }
      nowSec = Math.floor((await $.clock.now()) / 1000)
      // The countdown moves even when nothing else does.
      const key = (s) => s && JSON.stringify({ ...s, now: 0, issues: issues(s).map((i) => i.text) })
      if (key(next) !== key(info)) {
        info = next
        changed = true
      }
    } while (pending)
  } finally {
    running = false
  }
  syncPulse($)
  if (changed) {
    $.ui.invalidate('ui.render')
    await showStatusLine($)
  }
}

// shortDuration(4500) is "1h 15m".
function shortDuration(sec) {
  const m = Math.max(0, Math.round(sec / 60))
  if (m < 60) return m + 'm'
  const h = Math.floor(m / 60)
  return m % 60 ? h + 'h ' + (m % 60) + 'm' : h + 'h'
}

function secondsLeft(s) {
  return s.api && s.api.stopsAt ? s.api.stopsAt - nowSec : null
}

// scriptsOf lists the startup scripts and how each run went: coder-status
// reads the agent's log and names the scripts from the agent's manifest.
function scriptsOf(s) {
  const list = (s.startup && s.startup.list) || []
  return list.map((x) => ({ ...x, name: x.name || 'script ' + String(x.id || '').slice(0, 8) }))
}

// Whether the scripts have names, and only the startup ones are listed.
function scriptsNamed(s) {
  return !!(s.startup && s.startup.named)
}

// The Desktop app draws a Link whose URL holds an @ as plain text. The
// dashboard's router reads %40 as @, so its pages (the workspace, its
// terminal, a command app) take the encoded form there. A path-based app,
// which coderd routes itself, keeps its @.
function appSafe(u) {
  return u ? u.replace('/@', '/%40') : u
}

function starting(s) {
  return (!!s.api && s.api.lifecycle === 'starting') || scriptsOf(s).some((x) => x.status === 'running')
}

function failedScripts(s) {
  return scriptsOf(s).filter((x) => !SCRIPT_OK.has(x.status))
}

// issues lists what's worth knowing about the workspace, worst first. Each
// has a level (error, warning, or dim for a quiet note) and a few words.
function issues(s) {
  const out = []
  const a = s.api
  if (s.online === false) out.push({ level: 'error', text: 'Coder unreachable' })
  if (a && a.healthy === false) out.push({ level: 'error', text: 'unhealthy' })
  for (const x of failedScripts(s)) {
    const why = x.status === 'timed_out' ? 'timed out' : x.exit ? 'exit ' + x.exit : 'failed'
    out.push({ level: 'error', text: '✗ ' + x.name + ' ' + why })
  }
  if (a && !failedScripts(s).length) {
    if (a.lifecycle === 'start_error') out.push({ level: 'error', text: 'startup failed' })
    if (a.lifecycle === 'start_timeout') out.push({ level: 'warning', text: 'startup timed out' })
  }
  if (starting(s)) {
    const all = scriptsOf(s)
    const left = all.filter((x) => x.status === 'running')
    const names = scriptsNamed(s) ? left.slice(0, 2).map((x) => x.name).join(', ') + (left.length > 2 ? '…' : '') : ''
    out.push({
      level: 'warning',
      text: scriptsNamed(s) ? 'starting ' + (all.length - left.length) + '/' + all.length + (names ? ': ' + names : '') : left.length + (left.length === 1 ? ' script running' : ' scripts running'),
    })
  }
  for (const [key, label] of [['mem', 'memory'], ['disk', 'disk']]) {
    const v = s[key]
    if (v === null || v === undefined) continue
    if (v >= CRITICAL_PCT) out.push({ level: 'error', text: label + ' ' + v + '%' })
    else if (v >= s.warnPct) out.push({ level: 'warning', text: label + ' ' + v + '%' })
  }
  const left = secondsLeft(s)
  if (left !== null) {
    const text = 'stops in ' + shortDuration(left)
    out.push({ level: left <= VERY_SOON_SEC ? 'error' : left <= SOON_SEC ? 'warning' : 'dim', text })
  }
  if (a && a.outdated) out.push({ level: 'warning', text: 'template update' })
  const rank = { error: 0, warning: 1, dim: 2 }
  return out.sort((x, y) => rank[x.level] - rank[y.level])
}

function level(s) {
  const all = issues(s)
  if (all.some((i) => i.level === 'error')) return 'error'
  if (all.some((i) => i.level === 'warning')) return 'warning'
  return 'success'
}

// The diamond pulses while Claude works or the startup scripts run.
function syncPulse($) {
  const busy = working || (info && starting(info))
  if (busy && !pulse) {
    frame = 0
    pulse = $.clock.every(300, () => {
      frame = (frame + 1) % PULSE.length
      $.ui.invalidate('ui.render')
    })
  } else if (!busy && pulse) {
    pulse.cancel()
    pulse = null
    $.ui.invalidate('ui.render')
  }
}

// The VS Code panel doesn't draw the band above the prompt; it shows each
// mod's status line there instead.
async function showStatusLine($) {
  const surfaces = await $.session.surfaces()
  if (!surfaces.includes('vscode')) return
  $.ui.status(info ? plainLine(info) : undefined)
}

function repoWords(r) {
  const parts = []
  if (r.changed > 0) parts.push(r.changed + ' uncommitted')
  if (r.unpushed > 0) parts.push('↑' + r.unpushed + ' unpushed')
  return parts
}

// Only ports opened during the session: the ones the workspace started with
// are its apps, and /coder-workspace lists them.
function newPorts(s) {
  return s.ports.filter((p) => p.new)
}

function plainLine(s) {
  const parts = [s.workspace, ...issues(s).map((i) => i.text)]
  for (const r of s.repos) {
    const words = repoWords(r)
    parts.push(r.name + ' ' + r.branch + ' ' + (words.length ? words.join(' ') : '✓'))
  }
  for (const p of newPorts(s)) parts.push(p.url ? ':' + p.port + ' ' + p.url : ':' + p.port)
  return parts.join(' · ')
}

// ---------- /coder-workspace: the full card ----------

const COMMAND = 'coder-workspace'

// units lays out elements in a row that wraps between them, never inside one,
// with a dim separator after each but the last.
function units($, e, groups) {
  const { Box, Text } = $.ui.resolve(e)
  const sep = () => Text({ dimColor: true, children: ['  ·  '] })
  return Box({
    flexDirection: 'row',
    flexWrap: 'wrap',
    flexShrink: 1,
    children: groups.map((g, i) =>
      Box({ flexDirection: 'row', flexShrink: 0, children: i < groups.length - 1 ? [...g, sep()] : g })),
  })
}

function scriptMark(x) {
  if (x.status === 'ok') return { mark: '✓', color: 'success' }
  if (x.status === 'running') return { mark: '…', color: 'warning' }
  if (x.status === 'unknown') return { mark: '?', color: undefined }
  return { mark: '✗' + (x.exit ? ' exit ' + x.exit : ' ' + x.status), color: 'error' }
}

// cardView draws the full card. Labels sit in a column on the left; links are
// real links, and the editor links (vscode://, cursor://) only in the
// terminal, since Desktop opens only https links.
function cardView($, e, s) {
  const { Box, Text, Link } = $.ui.resolve(e)
  const inApp = e.surface !== 'terminal'
  const a = s.api
  const rows = []
  const row = (label, groups) => {
    if (!groups.length) return
    rows.push(Box({
      flexDirection: 'row',
      children: [Box({ width: 11, flexShrink: 0, children: [Text({ dimColor: true, children: [label] })] }), units($, e, groups)],
    }))
  }
  // What the surface opens. Desktop takes https (or http://localhost) links
  // without an @ and draws the rest as plain text, so the card does too.
  const opens = (href) => !!href && (!inApp || (/^(https:\/\/|http:\/\/localhost[:/])/.test(href) && !href.includes('@')))
  const page = (u) => (inApp ? appSafe(u) : u)
  const link = (href, label, opts = {}) => {
    const ok = opens(href)
    const text = Text({ color: opts.color || (ok ? LINK : undefined), dimColor: !!opts.dim, bold: !!opts.bold, children: [label] })
    return ok ? Link({ href, children: [text] }) : text
  }

  rows.push(Box({
    flexDirection: 'row',
    children: [
      Text({ bold: true, color: level(s), children: [(s.online === false ? '◇' : '◆') + ' Coder  '] }),
      link(page(s.dashboard), s.workspace, { bold: true }),
    ],
  }))
  // Autostop has its own row below.
  const found = issues(s).filter((i) => i.level !== 'dim' && !i.text.startsWith('stops in'))
  row('', found.map((i) => [Text({ color: i.level, children: [i.text] })]))

  const open = [[link(page(s.dashboard), 'Dashboard')], [link(page(s.terminal), 'Terminal')]]
  if (!inApp && s.vscode) {
    open.push([link(s.vscode, 'VS Code')])
    open.push([link(s.vscode.replace(/^vscode:/, 'cursor:'), 'Cursor')])
  }
  row('Open', open)

  // An app whose port nothing listens on is dimmed and says so.
  const apps = s.apps || []
  row('Apps', apps.map((x) => {
    const down = x.up === false
    const color = x.health === 'unhealthy' ? 'error' : undefined
    return [
      link(x.kind === 'command' ? page(x.url) : x.url, x.name, { color, dim: down }),
      ...(down ? [Text({ dimColor: true, children: [' down'] })] : []),
    ]
  }))

  const covered = new Set(apps.map((x) => x.port).filter(Boolean))
  const ports = s.ports.filter((p) => !covered.has(p.port)).sort((x, y) => (x.new === y.new ? x.port - y.port : x.new ? -1 : 1))
  row('Ports', ports.map((p) => [link(p.url, ':' + p.port, { dim: !p.new }), ...(p.process ? [Text({ dimColor: true, children: [' ' + p.process] })] : [])]))

  if (scriptsOf(s).length) {
    row(scriptsNamed(s) ? 'Startup' : 'Scripts', scriptsOf(s).map((x) => {
      const m = scriptMark(x)
      return [Text({ children: [x.name + ' '] }), Text({ color: m.color, children: [m.mark] })]
    }))
  }

  const left = secondsLeft(s)
  const sched = []
  if (left !== null) sched.push([Text({ color: left <= SOON_SEC ? 'warning' : undefined, children: ['stops in ' + shortDuration(left)] })])
  else if (a) sched.push([Text({ dimColor: true, children: ['no autostop'] })])
  if (a && a.outdated) sched.push([Text({ color: 'warning', children: ['template update available (restart to apply)'] })])
  row('Schedule', sched)

  row('Repos', s.repos.map((r) => {
    const words = repoWords(r)
    return [
      Text({ children: [r.name + ' '] }),
      Text({ dimColor: true, children: [r.branch] }),
      words.length ? Text({ color: 'warning', children: [' ' + words.join(' ')] }) : Text({ color: 'success', children: [' ✓'] }),
    ]
  }))

  const res = []
  if (s.mem !== null) res.push([Text({ children: ['memory ' + s.mem + '%'] })])
  if (s.disk !== null) res.push([Text({ children: ['disk ' + s.disk + '%'] })])
  row('Resources', res)

  for (const x of failedScripts(s)) if (x.log) rows.push(Text({ dimColor: true, children: ['           ' + x.name + ' log: ' + x.log] }))
  return Box({ flexDirection: 'column', children: rows })
}

export function register(on) {
  on('session.start', async ($, e, next) => {
    const result = await next(e)
    await refresh($)
    // Servers started outside Claude's tools show up within a few seconds.
    $.clock.every(5000, () => refresh($))
    try {
      await $.command.register({
        name: COMMAND,
        description: "Show this Coder workspace's links, apps, ports, and startup scripts",
        immediate: true,
      })
    } catch {
      // Taken by another plugin: the line still draws.
    }
    return result
  })

  // The text is the plain card, for Claude to read and for surfaces that
  // don't draw CommandOutput. Terminal and Desktop draw cardView instead.
  on('command.run', { command: COMMAND }, async ($) => {
    await refresh($)
    const r = await $.process.run(['bash', $.plugin.root + '/scripts/coder-status', 'text', await $.session.id()])
    return { text: r.stdout.trim() || 'This session is not in a Coder workspace.' }
  })

  on('ui.render', { component: 'CommandOutput' }, async ($, e, next) => {
    const name = String((e.props && e.props.command) || '').replace(/^\//, '')
    if (name !== COMMAND || !info) return next(e)
    return cardView($, e, info)
  })

  on('turn.start', async ($, e, next) => {
    working = true
    syncPulse($)
    return next(e)
  })

  // A shell command can start a server, commit, or push: refresh as soon as
  // it returns instead of waiting for the turn to end.
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const result = await next(e)
    refresh($)
    return result
  })

  on('turn.complete', async ($, e, next) => {
    working = false
    syncPulse($)
    refresh($)
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const theirs = await next(e)
    if (!info) return theirs
    const { Box, Text, Link } = $.ui.resolve(e)
    // Links only in the apps. A terminal without hyperlink support prints
    // each link's URL after its text, which turns one line into five, and in
    // a terminal you're already in the workspace.
    const inApp = e.surface !== 'terminal'
    const anchor = (href, label) => Link({ href, children: [Text({ color: LINK, children: [label] })] })
    const link = (href, label) => (inApp && href ? anchor(appSafe(href), label) : Text({ children: [label] }))
    // Each item is one unit, its separator included, so a narrow window
    // moves whole items to the next line instead of breaking them apart.
    const items = []
    const item = (...children) => items.push(children)

    const glyph = pulse ? PULSE[frame] : info.online === false ? '◇' : '◆'
    item(
      Text({ bold: true, color: level(info), children: [glyph] }),
      Text({ bold: true, children: [' Coder  '] }),
      link(info.dashboard, info.workspace),
    )

    for (const i of issues(info)) {
      item(i.level === 'dim' ? Text({ dimColor: true, children: [i.text] }) : Text({ color: i.level, children: [i.text] }))
    }

    for (const r of info.repos) {
      const words = repoWords(r)
      item(
        Text({ children: [r.name + ' '] }),
        Text({ dimColor: true, children: [r.branch] }),
        words.length
          ? Text({ color: 'warning', children: [' ' + words.join(' ')] })
          : Text({ color: 'success', children: [' ✓'] }),
      )
    }

    for (const p of newPorts(info)) {
      // Ports link in the terminal too: where it can't draw hyperlinks, the
      // preview URL printed beside the port is the thing you came for.
      item(p.url ? anchor(p.url, ':' + p.port) : Text({ children: [':' + p.port] }))
    }

    if (inApp && info.terminal) item(link(info.terminal, 'Terminal'))

    // The separator trails each item, so a wrapped line starts clean.
    const sep = () => Text({ dimColor: true, children: ['  ·  '] })
    const units = items.map((children, i) =>
      Box({ flexDirection: 'row', flexShrink: 0, children: i < items.length - 1 ? [...children, sep()] : children }),
    )
    const mine = Box({ flexDirection: 'row', flexWrap: 'wrap', children: units })
    return theirs ? Box({ flexDirection: 'column', children: [mine, theirs] }) : mine
  })
}
