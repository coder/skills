---
name: coder-workspaces
description: >
  Use an existing Coder deployment from the command line with the
  `coder` CLI: list, inspect, create, start, stop, and delete
  workspaces; run commands and edit files inside a workspace over
  `coder ssh`; forward ports; and read build and agent logs. Use
  when the user asks to run something "in my workspace", mentions
  their Coder workspaces or deployment, or wants a remote
  environment to work in. Do not use for installing or upgrading
  Coder itself (use the setup skill), authoring a template from
  scratch (use the templates skill), or adding registry modules to a
  template (use the modules skill).
---

# Workspaces

Operate an existing Coder deployment with the `coder` CLI. A
workspace is a remote development environment, and it is where a
coding agent does its work: the agent runs commands, edits files,
and serves ports inside the workspace instead of on the user's
machine. This skill covers getting into one, working in it, and
driving its lifecycle.

## Source of truth

`coder <subcommand> --help` is authoritative for flags and output
columns, and both change between releases. Read it before running a
command you have not run in this session. Anything the CLI does not
cover is at <https://coder.com/docs/llms.txt>.

## Preconditions

Run `coder whoami`. Three outcomes:

- Succeeds: continue.
- `coder` is not on `PATH`: install it with
  `curl -fsSL https://coder.com/install.sh | sh`, or use the setup
  skill if the user has no deployment yet.
- Authentication fails: tell the user to run
  `coder login <deployment-url>` and stop. The flow opens a browser
  for a session token, so they run it, not you.

Then check whether you are already inside a Coder workspace:
`CODER_AGENT_TOKEN` or `CODER_WORKSPACE_NAME` in the environment
means you are. In that case work with local tools directly instead
of `coder ssh`, and never stop or delete the workspace you are
running in.

## Non-interactive use

Every command below has to run without a human at the terminal.

- Pass `-o json` wherever it is offered and parse that. Table output
  is for humans and its columns move.
- Pass `-y` to `coder create`, `start`, `stop`, `restart`, and
  `delete`. Without it they block on a confirmation prompt.
- `coder ssh <workspace> -- <command>` runs one command and exits.
  Bare `coder ssh <workspace>` opens an interactive shell and will
  hang. Never run it.
- Commands that stream (`coder logs -f`, `coder port-forward`,
  `coder ping` without `-n`) run until interrupted. Give them a
  bound or run them in the background.
- Workspaces belonging to someone else are addressed as
  `<owner>/<workspace>`.
- A workspace with more than one agent needs the agent name:
  `coder ssh <workspace>.<agent> -- <command>`. Without it the CLI
  errors and lists the available agents.

## Workflow

1. Find the target. `coder list -o json` lists the user's
   workspaces; `coder list -o json --search <query>` or `--all`
   widens it. `coder show <workspace>` prints resources, agents, and
   apps for one.
2. Make sure it is running. A stopped workspace shows
   `status: stopped` in `coder list`. `coder start <workspace> -y`
   starts it, or let `coder ssh` autostart it.
3. Do the work (tables below).
4. Verify. `coder logs <workspace>` for the last build,
   `coder show <workspace>` for the current state.
5. Report the outcome in one or two sentences, naming the workspace
   and its status.

### Lifecycle

| Task | Command |
| --- | --- |
| List workspaces | `coder list -o json` (add `--all` or `--search`) |
| Inspect one | `coder show <workspace>` |
| Create from a template | `coder create <name> --template <template> -y` (add `--preset <preset>` or `--parameter name=value`) |
| Discover templates and presets | `coder templates list -o json`, `coder templates presets list <template>` |
| Start, stop, restart | `coder start <workspace> -y`, `coder stop <workspace> -y`, `coder restart <workspace> -y` |
| Delete | `coder delete <workspace> -y` |
| Update to the latest template version | `coder update <workspace>` |
| Build logs | `coder logs <workspace>` (`-n -1` for the previous build) |

`coder create` fails on a template with required parameters unless
you supply them. Read them from
`coder templates presets list <template>` or ask the user; do not
guess values.

### Inside a workspace

| Task | Command |
| --- | --- |
| Run a command | `coder ssh <workspace> -- <command>` |
| Run with env vars | `coder ssh <workspace> -e KEY=value -- <command>` |
| Read a file | `coder ssh <workspace> -- cat <path>` |
| Write a file | `coder ssh <workspace> -- tee <path> < local-file` |
| Copy files in or out | `coder config-ssh -y`, then `scp`/`rsync` against the generated host |
| Wait for the startup script | `coder ssh <workspace> --wait yes -- true` |
| Forward a port | `coder port-forward <workspace> --tcp 8080:8080` |
| Check connectivity | `coder ping <workspace> -n 3` |

`coder config-ssh -y` writes host entries into `~/.ssh/config`, which
makes every ssh-aware tool (`scp`, `rsync`, `git`, editors) work
against the workspace. Prefer it over shell heredocs for anything
larger than a one-liner. Run `coder config-ssh --dry-run` first to
see the host names it generates; the pattern depends on the
deployment's hostname suffix.

A workspace's startup script may still be running right after a
start. `--wait yes` blocks until it finishes; without it a command
can land in a half-provisioned environment.

## Rules

- Never delete a workspace without an explicit, separate
  confirmation. `coder delete` is irreversible.
- Prefer `stop` over `delete` when the user says "shut down" or
  "turn off".
- Stopping a workspace discards anything not on a persistent volume.
  Warn once before stopping if the user has been editing files.
- Never stop, delete, or restart the workspace you are running
  inside.
- Do not print session tokens, `Coder-Session-Token` headers, or the
  contents of `~/.config/coderv2`. Do not pass a token on a command
  line.
- `coder delete --orphan` leaves cloud resources behind. Use it only
  when the user asks and a normal delete has already failed.
