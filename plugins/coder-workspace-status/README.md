# coder-workspace-status

**For Claude Code only** (2.1.287 or later). It uses Claude Code's plugin
and mod APIs, so other agents can't install or run it.

This plugin shows the state of the Coder workspace Claude Code runs in,
right above the prompt:

```text
◆ Coder  alice/my-ws  ·  stops in 3h 10m  ·  api main ↑1 unpushed
```

Outside a Coder workspace it does nothing.

## What it shows

- **The diamond** is the workspace at a glance. Green: all fine. Yellow:
  look soon (memory or disk at 90% or more, autostop within the hour, a
  template update, startup scripts still running). Red: act now (a startup
  script failed, memory or disk at 95% or more, autostop within 10 minutes,
  the deployment doesn't answer). It's hollow when the deployment is
  unreachable, and it pulses while Claude works or the startup scripts run.
- **The workspace name** links to its dashboard page in Claude Desktop.
- **Problems show only when they happen:** startup scripts still running
  (`starting 3/5: Git Clone, Dev server`), a failed script
  (`✗ Dev server exit 1`), high memory or disk, a template update.
- **Autostop** shows dim when it's hours away, yellow within the hour, red
  within 10 minutes.
- **Repositories** show the branch and uncommitted or unpushed work. A git
  worktree, like the ones Claude Code creates, shows its repository's name.
- **Ports** opened during the session link to their preview URLs.

The line refreshes after every shell command, at the end of every turn, and
every 5 seconds. In a narrow window, whole items move to the next line.

### `/coder-workspace-status`

Draws the full card at once, without a model turn:

```text
◆ Coder  alice/my-ws
Open       Dashboard  ·  Terminal  ·  VS Code  ·  Cursor
Apps       code-server  ·  Preview (5173)  ·  Docs
Ports      :9229 node
Startup    Git Clone ✓  ·  Install deps ✓  ·  Dev server ✓
Schedule   stops in 3h 10m
Repos      api main ↑1 unpushed
Resources  memory 31%  ·  disk 42%
```

Apps are dimmed and marked `down` when nothing listens on their port.
Claude reads the same card, so it can hand you any of these links.

### What Claude learns

At session start, Claude learns the workspace's name, the URL pattern for
port previews (so it gives you a working link when it starts a dev server),
and the links to open the workspace in VS Code or a browser terminal.

## Requirements

- Claude Code 2.1.287 or later, running inside the Coder workspace
- `bash`, `jq`, and `curl` in the workspace (without `jq`, the card has no
  apps or script names)
- `git` for repository state, and `ss` or `/proc` for ports

## Install

In the workspace:

```sh
claude plugin marketplace add coder/skills
claude plugin install coder-workspace-status@coder-skills
```

To install it in every workspace from a template, run the same two
commands from a `coder_script` that starts after Claude Code is installed.

## What needs a token

Nothing, for almost everything. The plugin reads the workspace itself:

- The agent's manifest, from the agent's local debug server
  (`http://127.0.0.1:2113/debug/manifest`, or `CODER_AGENT_DEBUG_ADDRESS`):
  apps with their links, and startup script names
- The agent's log, for how each startup script ran
- Listening ports, git, memory, and disk

Autostop and template updates come from the Coder API, which the agent's
own token can't read. When the `coder` CLI in the workspace is logged in
(for example with the
[`coder-login`](https://registry.coder.com/modules/coder/coder-login)
module), the plugin uses it, and apps also get Coder's health check. API
answers are cached for a minute.

The only network requests the plugin makes are to the Coder deployment:
`/healthz`, and the API through the `coder` CLI when it's logged in.

## Configuration

| Variable | Default | Effect |
| --- | --- | --- |
| `CODER_STATUS_IGNORE_PORTS` | `22 2112 2113 3286 6060` | Ports never reported |
| `CODER_STATUS_WARN_PCT` | `90` | Memory or disk percentage that turns the diamond yellow |

## Where it draws

| Where Claude Code runs | What you see |
| --- | --- |
| `claude` in a terminal in the workspace | The line above the prompt; links where the terminal supports them |
| Claude Desktop over SSH | The line above the prompt, with links to the dashboard, a browser terminal, and new ports |
| VS Code extension 2.1.299 or later | A one-line status in the chat panel |
| Cloud sessions, including Coder Agent Relay | Nothing: the status isn't drawn there |

In a terminal without hyperlink support, Claude Code prints a link's URL
after its text, so the line keeps links to new ports only.

### Links in Claude Desktop

Desktop opens only `https:` links without an `@`, so the plugin writes the
dashboard's `/@owner/workspace` pages as `/%40owner/workspace`, which the
dashboard reads the same way. Editor links (`vscode://`, `cursor://`) show
only in the terminal. A path-based app, on a deployment without a wildcard
app hostname, keeps its `@`, so Desktop shows it as plain text.

## License

MIT
