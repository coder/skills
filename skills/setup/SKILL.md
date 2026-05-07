---
name: setup
description: Install and bootstrap a Coder (coder/coder) deployment end-to-end from the CLI without using the web UI. Handles both quick-start setups (one machine, auto-tunnel, no TLS) and production setups (real domain, TLS, optional wildcard URL, optional custom external auth, optional external provisioner). Use when the user wants to "install Coder", "set up Coder", "deploy Coder", "run Coder locally / in Docker / on Kubernetes / on a VM", "stand up Coder for my team", "put Coder behind HTTPS / a real domain", "bootstrap the first admin user from the terminal", "push a starter template", or otherwise get a working Coder deployment with one or more workspaces ready to go. Wraps the canonical install.sh, drives `coder login` for non-interactive first-user setup (or hands off to GitHub device-code sign-in on fresh deployments), pushes a starter template, and (optionally) creates a first workspace.
---

# setup

End-to-end install and first-run setup for a Coder deployment without
ever opening the Coder web UI.

The web UI works fine for setup. This skill exists so the user can run
one scripted, repeatable, CLI-only path: install, start the server,
bootstrap the admin user, optionally wire up TLS, external auth, and
an external provisioner, push a starter template, optionally create
a workspace, and surface the credentials. It is the right path for
demos, headless boxes, automation, team rollouts, and anyone who
explicitly says they don't want to touch the UI.

## When to use this skill

Activate when the user says any of:

- "Install Coder", "set up Coder", "deploy Coder", "get me started
  with Coder", "bootstrap Coder", "stand up Coder for my team".
- "Run Coder on this machine", "run Coder in Docker", "deploy Coder
  on Kubernetes", "Coder on AWS / GCP / Azure / DigitalOcean".
- "Put Coder behind HTTPS", "behind Caddy / nginx / cert-manager",
  "with a wildcard domain", "with TLS / Let's Encrypt".
- "Wire up GitHub for our templates", "let workspaces clone private
  repos", "external auth".
- "Run an external provisioner", "keep cloud creds off the server".
- "I don't want to touch the UI", "do it from the terminal", "headless
  setup", "non-interactive first-user setup".
- "Create the first admin user from the CLI".
- "Push the Docker / Kubernetes starter template", "create a starter
  workspace".

Do **not** activate for upgrading an existing deployment, editing an
existing template, or troubleshooting an already-running server. Point
the user at <https://coder.com/docs> for those.

## Talking to the user

Assume the user has never used Coder and does not know what a
template, workspace, agent, provisioner, access URL, wildcard URL,
or external auth provider is. They asked you to install Coder; they
did not ask for a tour of its internals. Run the install for them.

Hard rules for every message you send the user:

- **No flags, env-var names, or config keys in user-facing
  questions.** `--first-user-trial`, `CODER_ACCESS_URL`,
  `CODER_WILDCARD_ACCESS_URL`, and `CODER_EXTERNAL_AUTH_*` are
  internal details. The user should never see them in a question.
  They can appear in commands you run, and in the final summary as
  paths to files you wrote, but not as a thing the user has to
  understand.
- **Explain the thing before you name it.** If you must use a Coder
  term, say what it does first in one short sentence, then use the
  term. Example: "a starter project that builds workspaces (Coder
  calls this a *template*)".
- **Ask one yes/no or one short choice at a time.** Never present a
  decision matrix. If you need three answers, ask three questions in
  sequence, each phrased so a non-technical user can answer.
- **Default aggressively.** Pick the obvious default and ask the
  user to confirm, instead of making them choose from options.
  "I'll set this up so it's reachable from a public URL Coder
  generates for you. Sound good?" is better than "Pick an access URL
  strategy."
- **Never blame the user for missing context.** If you need
  something they haven't given you (a domain name, a database
  connection string), explain in one line what it's for and what a
  valid example looks like.
- **Translate errors.** Don't paste raw server logs at the user.
  Read the log yourself, decide what's wrong, and tell them in plain
  English. Show the raw log only if they ask, or as a follow-up
  after the plain-English explanation.
- **No "Coder-ese" in the final summary.** The summary block at the
  end (Phase 8) is what the user reads first. Use "sign-in page",
  "the app you can open in a browser", "the example project", not
  "access URL", "dashboard", "template".

Examples of the same question in DevOps voice vs user voice:

| DevOps voice (don't)                          | User voice (do)                                                                                  |
|-----------------------------------------------|--------------------------------------------------------------------------------------------------|
| "Pick a deployment mode: quick-start or production." | "Are you trying Coder out on this machine, or setting it up for your team to use long-term?" |
| "Provide an access URL."                      | "What address should people open in their browser to use this? (Like `coder.yourcompany.com`.)" |
| "Configure the wildcard access URL."          | "Some apps inside workspaces work better if Coder gets a wildcard DNS record. Want me to set that up, or skip it?" |
| "First-user auth: GitHub or password?"        | "For sign-in, do you want me to walk you through GitHub (I'll print a short URL and a code; works from any phone), or just create an email and password for you?" |
| "Register an external auth provider."         | "Should workspaces be able to clone your private GitHub repos? (yes / no / not sure)"            |
| "Push the docker starter template."           | "I'll set up an example project that builds Linux workspaces in Docker. OK?"                     |
| "Workspace agent reached lifecycle=ready."    | "Your first workspace is up and ready to open."                                                  |

A short concept glossary you can pull plain-English phrases from:

- **Coder** -> "a thing that gives you and your team cloud
  development environments you open in the browser or in your
  editor".
- **Access URL** -> "the web address people will open to use
  Coder".
- **Wildcard URL** -> "a DNS setup that lets apps inside your dev
  environment have their own subdomain (optional, only matters for
  some apps)".
- **Workspace** -> "a single dev environment for one person".
- **Template** -> "a recipe Coder follows when it builds a
  workspace; e.g. 'one Linux container with VS Code'".
- **Agent** -> "the small helper that runs inside a workspace so
  Coder can talk to it". Most users never need to know this exists.
- **Provisioner** -> "the thing that actually builds workspaces
  when someone asks for one". Users never need to know this exists
  unless they explicitly need cloud isolation.
- **External auth** -> "letting workspaces sign in to GitHub /
  GitLab / etc. so they can clone private repos".
- **Owner** -> "the admin account; the first person to sign in
  becomes one automatically".
- **Free vs paid** -> Coder is open source; nothing the skill does
  costs money. The upstream CLI has a `--first-user-trial` flag
  that turns on a 30-day enterprise-feature evaluation; the skill
  always passes `--first-user-trial=false` and does not bring it
  up. Ignore the word "trial" if it shows up in upstream
  documentation; this skill never opts users into anything paid.

If the user asks for technical detail ("what flag does that map
to?", "show me the env var"), you can shift to engineer voice for
that one answer; default back to plain English on the next turn.

## Workflow

Follow these phases in order. Each has a clear exit criterion. Confirm
before any destructive action (system package install, opening ports,
overwriting kubeconfigs, deleting volumes).

1. **Discover** the target environment, deployment mode, and what the
   user wants.
2. **Install** the Coder binary or Helm chart via `install.sh`.
3. **Start** the Coder server.
4. **Bootstrap** the first admin user.
5. **External services** (production only; optional): register external
   auth, run an external provisioner. Skip in quick-start mode.
6. **Template**: push a starter that matches the chosen infrastructure.
7. **Workspace** (optional): create the user's first workspace.
8. **Summarize** with credentials, URLs, and next steps.

### Phase 1: Discover

**Stop first if you are running inside a Coder workspace.** When the
environment has `CODER_AGENT_TOKEN` or `CODER_WORKSPACE_NAME` set, you
are inside someone's workspace. The workspace agent is itself a `coder`
process; running `pkill coder` or installing a server that overwrites
`/usr/local/bin/coder` will disconnect the user.

In that case:

- **Refuse a host install** (running `coder server` directly on the
  workspace, systemd, or `install.sh` to `/usr/local/bin`) unless the
  user explicitly asked for nested Coder.
- **Docker compose is fine** when scoped to a sub-directory and a
  non-default port. Workspaces ship Docker; the inner server runs in
  its own container and the host `coder` agent is unaffected.
- **Kubernetes via Helm is fine** when targeted at a separate cluster
  context, not the workspace's host.

Read `references/troubleshooting.md#never-pkill-coder-on-a-coder-workspace`
before touching anything.

Detect first, then ask only what you can't infer:

```sh
# If either of these is set, refuse a host install.
env | grep -E '^(CODER_AGENT_TOKEN|CODER_WORKSPACE_NAME)=' || true

uname -sm
command -v apt-get dnf yum apk brew zypper pacman 2>/dev/null
docker version --format '{{.Server.Version}}' 2>/dev/null
kubectl config current-context 2>/dev/null
helm version --short 2>/dev/null
coder --version 2>/dev/null
systemctl is-active coder 2>/dev/null
test -f "$HOME/.config/coderv2/url" && cat "$HOME/.config/coderv2/url"
```

**Reuse an existing `coder` binary** if `coder --version` already
works. Skip Phase 2 entirely unless the user asked to reinstall or
the existing version is older than the deployment they want
(production should pin a recent release; the quick-start path runs
on whatever version is already there).

**Isolate this install from an existing login.** If
`~/.config/coderv2/url` exists and points somewhere the user does
NOT want to overwrite (e.g. `https://dev.coder.com`, an internal
team deployment), set isolated config and cache directories for
every `coder` and `coder server` invocation in this session.
Directories go under the standard XDG locations because the Coder
CLI expects `CODER_CONFIG_DIR` to be a real config dir; we just
pick a non-conflicting name.

```sh
export CODER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/coderv2-quickstart"
export CODER_CACHE_DIRECTORY="${XDG_CACHE_HOME:-$HOME/.cache}/coderv2-quickstart"
mkdir -p "$CODER_CONFIG_DIR" "$CODER_CACHE_DIRECTORY"
```

Ask the user before touching the existing config; the default is
to isolate. Without isolation the new install's `coder login`
overwrites the stored URL and session, kicking the user out of
their real deployment.

#### Pick the deployment mode

Decide between **quick-start** and **production** before anything
else. It drives almost every later choice: where the server runs,
whether it needs a real domain, whether it needs a managed
database. Don't show this as a config-style question; ask in
plain English. Internally, the two modes are just labels for the
shape of the install; nothing about either is a paid feature.

Ask like this (pick whichever matches what the user has already
said):

- "Are you trying Coder out on this machine, or setting it up for
  your team to use long-term?"
- "Is this a quick try-it-out, or the real thing for your
  company / team?"

Map the answer:

| What the user said                                    | Mode        |
|-------------------------------------------------------|-------------|
| "trying it out", "demo", "play with it", "just me"    | quick-start |
| "on this laptop", "my server", "throwaway"            | quick-start |
| Names a real domain (`coder.example.com`)             | production |
| "HTTPS", "TLS", "Let's Encrypt", "behind a proxy"     | production |
| "For my team", "for the company", "staging"           | production |
| "Cloud workspaces" with a shared cloud account        | production |

If signals conflict, ask one short follow-up. Don't guess.

`references/production.md` is the entry point for the production
path. Read it before continuing into Phase 2 if you've picked
production.

#### Pick how the user will sign in

Fresh deployments come with a built-in "Sign in with GitHub" path
turned on, using a GitHub OAuth App that Coder hosts. Whoever
signs in first becomes the admin (Coder calls this the Owner)
automatically. So there are two reasonable paths:

- **GitHub.** Drive GitHub's standard device-code flow over
  Coder's API. The skill prints a short URL and an 8-character
  code; the user opens the URL on whatever device is handy
  (their phone is fine), pastes the code, approves access on
  GitHub, and the skill captures the session and finishes setup.
  No browser on the install machine, no password to record.
  Best for solo installs, demos, and small teams whose accounts
  already live on GitHub.
- **Email and password.** Fully scripted, no GitHub round trip.
  The skill picks a strong password, creates the admin account
  from the terminal, and saves the email and password to a
  mode-0600 file in this install's state directory (under
  `$XDG_STATE_HOME/coder-install`, defaulting to
  `~/.local/state/coder-install`) so the user can find them
  later. The exact path is printed in the final summary.

Ask the user once. Phrase it without jargon:

> "For sign-in, do you want me to walk you through GitHub (I'll
> show you a short URL and a code to paste; works from any
> phone), or just create an email and password for you?"

Default to GitHub when the user can reach github.com on any
device. Fall back to email-and-password if they say no, ask for
a fully scripted setup, or you're running in headless mode
(`claude -p`) where there's no human to type a code.

Note that the device-code path only works on deployments where
the Coder server has device flow enabled for its GitHub provider.
Fresh deployments do (Coder's hosted OAuth App ships with
`device_flow=true`); custom-configured GitHub providers may not.
The skill checks `default_provider_configured` and the
`/users/oauth2/github/device` endpoint in Phase 4 before driving
the flow, and falls back to email-and-password if either check
says no.

For the email-and-password path, prefill the email from git config
if present, instead of asking cold:

```sh
EMAIL_DEFAULT="$(git config --global --get user.email 2>/dev/null || true)"
```

Then confirm with the user ("I'll use `$EMAIL_DEFAULT` as the admin
email. OK, or use a different one?"). Don't ask them to type it
from scratch unless git doesn't have one.

#### What to ask up front, by mode

The goal is the smallest possible interview. Ask one thing at a
time, in plain English. Defaults are listed so you can lead with
them.

**Quick-start mode.** You only need one or two things from the
user; everything else has a sane default.

- **Where to run it.** Default: Docker if it's on the machine,
  otherwise install it directly on the machine. Don't lecture about
  options; pick the default and confirm.
  > "I'll run Coder using Docker on this machine. Sound good, or
  > do you want it installed directly instead?"
- **Web address (access URL).** Don't ask. The skill defaults to
  letting Coder open its own public URL automatically (a random
  `*.try.coder.app` address that only people with the link can
  use). It works on any machine with internet, and avoids local
  firewall and Docker networking gotchas. Tell the user what's
  happening, don't ask:
  > "I'll get Coder a public URL automatically so you can open it
  > from anywhere. It's protected by your sign-in, but if you'd
  > rather keep it local-only, say so."
  Fall back to a local-only URL only if the user opts in or the
  automatic one fails. See Phase 3 for the detection recipe.
- **Sign-in method.** See the section above.
- **Example project to start with.** Default: a Linux container
  via Docker (Coder calls this the `docker` template), or one
  Linux pod via Kubernetes if you're going through Helm.
  > "I'll add an example project that builds a Linux dev
  > environment in Docker so you have something to open. OK?"
- **Build a first dev environment now?** Default yes for
  quick-start.
  > "Want me to build your first dev environment now so you can
  > open it as soon as Coder is ready?"

**Production mode.** You need a few things from the user before
touching anything. Ask in plain English; don't make them recite a
config file.

- **The web address people will open.** This is mandatory.
  > "What address should everyone open in their browser to use
  > Coder? Something like `coder.yourcompany.com`. (You can set
  > the DNS for it now or later, but I need to know the address
  > to wire things up.)"
- **Who handles HTTPS.** Either Coder itself, or a proxy /
  load balancer / Kubernetes ingress in front of it. Lead with
  the user's existing setup if you can spot one (cert-manager,
  nginx, Caddy).
  > "Are you using something like cert-manager, nginx, or Caddy
  > to handle HTTPS already, or should Coder handle HTTPS itself
  > using cert files I'll point it at?"
- **Database.** Coder needs a real Postgres for production; the
  built-in one is for the quick-start path only.
  > "Coder needs a Postgres database for production. Do you have
  > one I can point it at? (If yes, I'll need its connection
  > string. If you're not sure, I can show you what one looks
  > like.)"
- **Sign-in method.** Same question as above.
- **What kind of dev environments people want.** Maps to the
  example project (template) you'll add.
  > "What should the first dev environment look like? Linux
  > container in Docker, a Kubernetes pod, or a cloud VM
  > (AWS / GCP / Azure)?"
  Then pick from `references/templates.md` based on the answer.

Ask these **only if relevant** (don't ever surface them as
required):

- **Subdomain routing for in-workspace apps.** Some apps inside
  workspaces (notebooks, web previews) work better when each one
  gets its own subdomain. This needs a wildcard DNS record. If
  the user mentions "port forwarding" or "opening apps in the
  workspace", offer it; otherwise leave it off.
  > "Some apps inside dev environments work better if Coder gets
  > a wildcard DNS record (`*.coder.yourcompany.com`). Want me
  > to set that up, or skip it for now? You can always add it
  > later."
- **Custom GitHub / GitLab login.** The default "Sign in with
  GitHub" button uses GitHub.com out of the box. If the team is
  on GitHub Enterprise, GitLab, or wants to use their own OAuth
  App, you'll set up a custom one in Phase 5. Don't ask in
  Phase 1; the default works.
- **Cloud-isolated builds.** Only matters when workspaces will
  run in a cloud account whose credentials shouldn't sit on the
  Coder server. Ask only if the chosen example project needs
  cloud creds.
  > "This template needs an AWS account to build workspaces. Do
  > you want me to keep the AWS credentials off the Coder server
  > (recommended for production), or is it OK to put them there
  > for now?"

Full decision matrix and order of operations:
`references/production.md`. Per-topic detail in `wildcard-tls.md`,
`external-auth-github.md`, and `external-provisioner.md`.

When the user has not expressed a preference, propose the default
plan in one paragraph and ask for a single yes/no before mutating
the system. In production mode, also list the DNS names you'll
need and the database string in the same paragraph, so the user
can spot-check before the server starts.

**Headless mode** (`claude -p`, no interactive shell): the user
can't answer a yes/no prompt and can't click a browser button.
Treat the original prompt as the approval. For sign-in, default to
email-and-password (browser GitHub flow needs a human). If the
prompt is missing something required for production (web address,
HTTPS strategy, database, optional wildcard / OAuth / provisioner
key), refuse with a one-line error listing what's missing in plain
English, instead of blocking on stdin.

### Phase 2: Install

Always prefer the canonical install script. It already detects the
package manager, falls back to a standalone tarball, and supports an
unprivileged user-local install. Don't reinvent it.

Standalone Linux/macOS, system-wide:

```sh
curl -fsSL https://coder.com/install.sh | sh
```

Standalone Linux/macOS, no sudo (recommended for testing and demos):

```sh
curl -fsSL https://coder.com/install.sh \
  | sh -s -- --method standalone --prefix "$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
```

Useful flags to remember (full set: `bash <(curl -fsSL https://coder.com/install.sh) --help`):

- `--mainline` (default) or `--stable`: pick the release channel.
  Default mainline. Use `--stable` for production unless the user
  explicitly asked for mainline.
- `--version X.Y.Z`: pin a specific version.
- `--with-terraform`: install Terraform alongside Coder. Use this when
  the deployment will run Terraform locally (almost every template
  does).
- `--method standalone --prefix DIR`: user-local install with no
  package manager and no sudo.
- `--dry-run`: print the commands the script would run without running
  them. Use this to show the user what's about to happen on a fresh
  machine.

Windows (no install.sh):

- `winget install Coder.Coder`, or download the MSI from
  <https://github.com/coder/coder/releases>.

Docker compose and Kubernetes (Helm): see `references/install-methods.md`.
Both wrap the same binary, so the rest of this skill applies to all
three.

For production, Helm on Kubernetes or compose with a managed PG is
the recommended layout. `references/wildcard-tls.md` shows the
canonical Helm values file with TLS, ingress, and the wildcard
hostname wired up.

Verify with `coder --version`. Exit criterion: the binary runs.

### Phase 3: Start the server

#### Quick-start path

Default: let `coder server` open its built-in tunnel. The tunnel
is the most-reliable single-machine path because it routes around
host-firewall and docker-bridge issues that bite local-only binds.
Don't pass `--access-url`; the server will pick a
`*.try.coder.app` URL and print it to stderr.

Under the hood, when `coder server` starts without an access URL,
it reads (or generates and persists) a wireguard keypair in the
user's config dir at `${XDG_CONFIG_HOME:-$HOME/.config}/coderv2/devtunnel`,
opens a wireguard connection to `pit-1.try.coder.app` (the
wgtunnel server in `coderd/devtunnel/servers.go`), and serves
traffic that arrives there. The public URL is
`<base32hex(sha256(pubkey)[:8]) lowercased>.pit-1.try.coder.app`,
derived from the same wireguard public key, so it's stable across
restarts as long as the keypair file is intact.

The skill does not derive the URL itself: the server announces
it. As soon as the wireguard handshake succeeds, the server prints
a block to stderr that ends with the line:

```text
View the Web UI:
https://<id>.pit-1.try.coder.app
```

This is the only piece of the URL the skill should depend on;
parse it from there. Tunnel handshake usually completes within
2-5 seconds on a healthy network.

All of the skill's persistent outputs (server log, pid file,
credentials file if email/password is used, install notes) live
in one directory the skill creates up front and prints back to
the user in Phase 8. Do not scatter dotfiles across `$HOME`. The
directory follows XDG: `$XDG_STATE_HOME/coder-install` if set,
otherwise `$HOME/.local/state/coder-install`.

```sh
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/coder-install"
mkdir -p "$STATE_DIR"
```

For **standalone host install** (the `coder` binary on the host):

```sh
nohup coder server \
  > "$STATE_DIR/server.log" 2>&1 &
echo $! > "$STATE_DIR/server.pid"
```

For **Docker compose**: don't run `coder server` directly; bring
up the compose stack and let the container hold the log. Skip
the state-dir log-and-pid setup (the container is its own
supervisor; logs come from `docker compose logs`). The auto-tunnel
still works inside the container as long as the compose file
persists `/home/coder` to a named volume so the wireguard keypair
survives restarts. The upstream `compose.yaml` in the
`coder/coder` repo already does this.

Wait for the server to be ready and the tunnel URL to appear.
The loop is fast on purpose: in Docker compose the server's
HTTP port is up within a second or two, and the tunnel handshake
completes a few seconds later. Don't pad with arbitrary sleeps.

```sh
# How to read the log depends on how it was started.
# Use whichever of these matches the install method.
coder_log() {
  if [ -f "$STATE_DIR/server.log" ]; then
    cat "$STATE_DIR/server.log"
  elif [ -f docker-compose.yml ] || [ -f compose.yaml ]; then
    docker compose logs coder 2>&1
  else
    return 1
  fi
}

# Poll up to 60s. Check the log on every iteration so we can fail
# fast when the tunnel can't come up at all (no egress, blocked
# DNS, *.try.coder.app unreachable).
ACCESS_URL=""
for _ in $(seq 1 60); do
  # The server prints a banner that includes the line
  #   View the Web UI:
  #   https://<id>.pit-1.try.coder.app
  # so look for the announced URL on the line right after the
  # banner. It is the URL we should trust; the wgtunnel hostname
  # is derived from the wireguard public key (base32hex of
  # sha256(pubkey)[:8]), but the skill should not re-derive it.
  ACCESS_URL="$(coder_log 2>/dev/null \
    | awk '/View the Web UI:/{getline; print; exit}' \
    | grep -oE 'https?://[a-zA-Z0-9.-]+(\:[0-9]+)?')"
  if [ -n "$ACCESS_URL" ] && \
     curl -fsS "$ACCESS_URL/healthz" >/dev/null 2>&1; then
    break
  fi
  if coder_log 2>/dev/null | grep -q 'create tunnel'; then
    ACCESS_URL=""
    break
  fi
  sleep 1
done
```

**Local-only fallback** (no internet egress, or user explicitly
asked for local-only). Only fall back to this if the loop above
exits with `ACCESS_URL=""`; the auto-tunnel is the default
because it is more reliable.

```sh
kill "$(cat "$STATE_DIR/server.pid")" 2>/dev/null || true
ACCESS_URL="http://localhost:7080"
nohup coder server \
  --access-url "$ACCESS_URL" \
  --http-address 0.0.0.0:7080 \
  > "$STATE_DIR/server.log" 2>&1 &
echo $! > "$STATE_DIR/server.pid"
for _ in $(seq 1 60); do
  curl -fsS "$ACCESS_URL/healthz" >/dev/null 2>&1 && break
  sleep 1
done
```

Bind to `0.0.0.0:7080`, not `127.0.0.1:7080`. The `docker` workspace
agent reaches the server via `host.docker.internal` (the docker
bridge IP), so a host-loopback bind is unreachable from inside the
workspace container. On NixOS the `nixos-fw` chain may still drop
the SYN; see
`references/troubleshooting.md#nixos-firewall-blocks-docker-bridge`.

Other supervisors instead of `nohup` (pick whichever fits the host):

- **systemd**: `install.sh` registers a `coder` unit if it ran with
  sudo. Drop env into `/etc/coder.d/coder.env` and
  `sudo systemctl restart coder`.
- **tmux**: `tmux new -d -s coder "coder server"` for a live log
  the user can attach to.

In either of those cases the server log is no longer in
`$STATE_DIR/server.log`; record `journalctl -u coder` or
`tmux a -t coder` instead, and skip writing the pid file.

#### Production path

The server is configured by env, not flags. Set the access URL
(plus optional wildcard, TLS, and database) on the deployment
manifest (Helm values, compose `environment:` block, or systemd
environment file), not as CLI args.

Minimum env for a Helm or compose deploy:

```sh
CODER_ACCESS_URL=https://coder.example.com
CODER_PG_CONNECTION_URL=postgres://coder:${PASSWORD}@db.internal:5432/coder?sslmode=require
# TLS at the server (omit if a proxy / ingress terminates):
CODER_TLS_ENABLE=true
CODER_TLS_ADDRESS=0.0.0.0:443
CODER_TLS_CERT_FILE=/etc/coder/tls/fullchain.pem
CODER_TLS_KEY_FILE=/etc/coder/tls/privkey.pem
CODER_REDIRECT_TO_ACCESS_URL=true
```

If Phase 1 collected a wildcard URL, also set:

```sh
CODER_WILDCARD_ACCESS_URL=*.coder.example.com
```

The wildcard is optional; without it Coder serves apps on path-based
routes instead of subdomains. Most apps work either way; some break
under path routing (anything that hardcodes the root path or scopes
cookies to a specific host). See `references/wildcard-tls.md` for
the tradeoff matrix.

Roll it out (`helm upgrade`, `docker compose up -d`,
`sudo systemctl restart coder`) and wait for readiness against the
public URL:

```sh
for _ in $(seq 1 120); do
  if curl -fsS https://coder.example.com/healthz >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
```

If the wildcard is configured, verify it resolves end-to-end:

```sh
curl -fsS https://app-test.coder.example.com/healthz
```

Full env-var matrix and common failures: `references/wildcard-tls.md`.

### Phase 4: Sign in as the admin

Whoever signs in to a fresh Coder first becomes the admin (Owner)
automatically. Pick the path that matches what the user said in
Phase 1.

#### GitHub path (device code, no browser on this machine)

Drive the GitHub sign-in over GitHub's standard device flow,
proxied through Coder's API. The user gets a short URL and a
one-time code, types the code into the GitHub page on whatever
device is handy (their phone is fine), and the install completes
without opening a browser on the install machine and without
asking them for credentials. Don't tell the user to "go to the
dashboard and click Sign in with GitHub"; that's a fallback for
deployments where device flow isn't available.

First, confirm the deployment can do device flow. The default
GitHub provider that ships with fresh deployments has it on; a
custom provider may not.

```sh
curl -fsS "$ACCESS_URL/api/v2/users/authmethods" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["github"].get("default_provider_configured", False))'
curl -fsS "$ACCESS_URL/api/v2/users/oauth2/github/device" >/dev/null
```

If either check fails (`default_provider_configured` is `False`,
or the device endpoint returns `Device flow is not enabled`),
fall back to the email-and-password path below; don't reach for
the browser flow unless the user has a working browser on this
machine and asked for it.

When device flow is available, run the recipe in
[`references/first-user-github-device.md`](references/first-user-github-device.md).
Follow it end-to-end; it handles cookie priming, polling,
`authorization_pending`, and writing the session into
`$CODER_CONFIG_DIR/{url,session}` so subsequent `coder` commands
are authenticated as the admin.

While the device endpoint is responding, print this to the user
(substitute `$VERIFY_URI` and `$USER_CODE` from the device-endpoint
response, not from the recipe; both come straight from GitHub):

```text
To sign in to Coder, open this on any device:

  $VERIFY_URI

Then enter this code:

  $USER_CODE

I'll wait here. As soon as GitHub confirms it, I'll finish setting
you up as the admin.
```

Then poll. The user typically takes 20-60 seconds; the code is
good for 15 minutes.

When the recipe returns success, verify quietly:

```sh
coder whoami
coder users list
```

`users list` should show exactly one row with `OWNER` in the
roles column, with the email and login from the user's GitHub
account. If it doesn't, tell the user in one line that GitHub
sign-in didn't take and offer to try email-and-password instead;
don't paste raw output.

#### GitHub path (browser fallback)

Use this only when the device-flow check above failed AND the
user has a browser on the install machine. The sign-in page has a
"Sign in with GitHub" button; tell them to click it.

```text
Coder is ready. Open this address in your browser:

  $ACCESS_URL

Click "Sign in with GitHub", approve the prompt on GitHub's site,
and you'll come back to Coder signed in as the admin. Nothing for
you to write down.
```

While the user does that, link your terminal to the same
deployment so the rest of the install can run as admin:

```sh
coder login "$ACCESS_URL"
```

This pops a browser to the same address; the user signs in once,
and the terminal grabs a session token. Verify with `coder
whoami` and `coder users list` (one row, `OWNER`).

#### Email and password path (no browser)

This path creates the admin account from the terminal so the user
doesn't have to click through anything. Tell them what's happening,
and make sure the credentials end up in a file they can find later;
if they lose this password there's no recovery.

Under the hood: use `coder login` with `--first-user-*` flags,
**including `--first-user-trial=false`**. Without the flag and
without `CODER_FIRST_USER_TRIAL`, the CLI prompts on stdin and the
headless flow hangs.

Pass the password through the env, not the command line, so it
doesn't land in shell history or process listings:

```sh
export CODER_FIRST_USER_PASSWORD="$PASSWORD"
coder login "$ACCESS_URL" \
  --first-user-email     "$EMAIL" \
  --first-user-username  "$USERNAME" \
  --first-user-full-name "$FULL_NAME" \
  --first-user-trial=false
unset CODER_FIRST_USER_PASSWORD
```

All four of `--first-user-email`, `--first-user-username`,
`--first-user-full-name`, and `--first-user-trial` are also accepted
as `CODER_FIRST_USER_*` env vars; use whichever is more convenient.

The password has no recovery path. Persist it to a mode-0600 file
in the same `$STATE_DIR` Phase 3 created (so everything the skill
produced for this install lives in one place):

```sh
umask 0077
printf 'url=%s\nusername=%s\nemail=%s\npassword=%s\n' \
  "$ACCESS_URL" "$USERNAME" "$EMAIL" "$PASSWORD" \
  > "$STATE_DIR/credentials"
chmod 0600 "$STATE_DIR/credentials"
```

`STATE_DIR` was set in Phase 3 to
`${XDG_STATE_HOME:-$HOME/.local/state}/coder-install`. Don't
create a separate `~/.config/coder-install/` for this; the
credentials are skill-managed runtime state, not user-edited
config.

This differs from the GitHub path: GitHub-bootstrapped deployments
don't need a credentials file because the user owns the recovery
path via GitHub. Username/password deployments do, because the
password exists nowhere else.

Verify:

```sh
coder whoami
coder users list
```

`whoami` returns the bootstrapped user. `users list` shows exactly
one row with `OWNER` in the roles column.

For the upstream CLI's enterprise-trial flow (separate from the
skill's quick-start mode), persistent tokens, and the full failure
list, read `references/first-user.md`.


### Phase 5: External services (production only)

Skip this phase entirely in quick-start mode.

In production, both items below are **optional**. The default
github.com external auth provider is already on for fresh
deployments, and the in-server provisioner runs Docker templates
fine. Touch this phase only when the user names a reason.

#### Custom external auth provider (only if needed)

The default `github.com` provider works out of the box for fresh
deployments and covers the "workspaces clone private GitHub repos"
case without any setup. Register a *custom* provider only when:

- The user runs GitHub Enterprise Server (GHES). The default points
  at github.com only.
- The user wants GitLab, Bitbucket, Gitea, Azure DevOps, or another
  non-GitHub provider.
- The user has a corporate-owned OAuth App they prefer over Coder's
  default (e.g. for audit visibility, restricted scopes).

When one of those applies, follow `references/external-auth-github.md`.
The short version:

1. Pick a provider ID (`primary-github`).
2. Register an OAuth App with callback URL
   `https://coder.example.com/external-auth/<id>/callback`.
3. Set on the server:
   ```sh
   CODER_EXTERNAL_AUTH_0_ID=primary-github
   CODER_EXTERNAL_AUTH_0_TYPE=github
   CODER_EXTERNAL_AUTH_0_CLIENT_ID=<id>
   CODER_EXTERNAL_AUTH_0_CLIENT_SECRET=<secret>
   ```
4. Roll out the deployment.
5. Verify with `GET /api/v2/external-auth`.

When a *custom* GitHub provider is configured, the default github.com
provider auto-suppresses (the server picks the explicit one over its
built-in default; no need to set
`CODER_EXTERNAL_AUTH_GITHUB_DEFAULT_PROVIDER_ENABLE=false`).

#### External provisioner (only if needed)

The in-server provisioner is fine for Docker / Kubernetes templates
that run against the same host or cluster the server runs on.
Register a separate provisioner only when:

- Cloud workspaces (AWS / GCP / Azure) need credentials the Coder
  server should not see.
- Build concurrency is a bottleneck (each daemon = one concurrent
  build).
- Build environments need network isolation from the control plane.

Full walkthrough: `references/external-provisioner.md`. Short
version:

1. Generate a scoped key:
   ```sh
   coder provisioner keys create cloud-provisioner \
     --org default --tag environment=cloud
   ```
2. Run the daemon (separate VM, container, or Helm release) with:
   ```sh
   CODER_URL=https://coder.example.com
   CODER_PROVISIONER_DAEMON_KEY=<key>
   AWS_ACCESS_KEY_ID=...
   AWS_SECRET_ACCESS_KEY=...
   coder provisioner start --tag environment=cloud
   ```
3. Verify with `coder provisioner list` (online, tagged).
4. Tag templates pushed in Phase 6 with the same `environment=cloud`
   so the in-server provisioner doesn't claim cloud builds.


### Phase 6: Push a starter template

Pick the template that matches the install target. The full matrix
with required parameters lives in `references/templates.md`.

```sh
TEMPLATE_DIR="$(mktemp -d)/$TEMPLATE_NAME"
coder templates init --id "$TEMPLATE_ID" "$TEMPLATE_DIR"
coder templates push "$TEMPLATE_NAME" -d "$TEMPLATE_DIR" --yes
coder templates list
```

When an external provisioner is in use (Phase 5), tag the push so
the matching daemon picks the build up:

```sh
coder templates push "$TEMPLATE_NAME" -d "$TEMPLATE_DIR" \
  --provisioner-tag environment=cloud --yes
```

Cloud templates need real provider credentials before `templates push`
will succeed (or before workspaces will build, depending on the
template). With an external provisioner, set them on the **provisioner's**
environment, not the server's. Without one, set them on the server's
environment (and accept that the server now has cloud creds).

For non-secret template variables, use `--variables-file`:

```sh
cat > /tmp/vars.yaml <<EOF
namespace: coder
use_kubeconfig: false
EOF
coder templates push "$TEMPLATE_NAME" --variables-file /tmp/vars.yaml --yes
```

The format is YAML key/value pairs (`codersdk.ParseUserVariableValues`
unmarshals it directly).

Never echo secret values back to the user, never put them in
`terraform.tfvars`, and never pass them as `--variable` (they leak
into every template version and the audit log). See
`references/templates.md#provider-credentials`.

### Phase 7: Create a workspace (optional)

If the user wants a workspace right away:

```sh
coder create "$WORKSPACE_NAME" --template "$TEMPLATE_NAME" --yes
```

Pass parameters with repeated `--parameter "name=value"`. Templates
evolve; never assume a starter has no required parameters. Discover
them before calling `coder create`:

```sh
coder templates pull "$TEMPLATE_NAME" "$(mktemp -d)/$TEMPLATE_NAME"
# Then read main.tf for `data "coder_parameter"` blocks.
```

`coder create` without `--parameter` for a required parameter
blocks on stdin and hangs the headless flow. List, map, and object
parameters need a JSON value:

```sh
coder create "$WORKSPACE_NAME" \
  --template "$TEMPLATE_NAME" \
  --parameter 'jetbrains_ides=[]' \
  --parameter 'cpu=2' \
  --yes
```

For `kubernetes`, the namespace must already exist (the template
assumes the server has RBAC to create pods in it).

**Wait for the agent to be ready, not just for the build to
succeed.** A build with `latest_build.job.status=succeeded` and
`latest_build.status=running` only means the workspace's
infrastructure stood up. The user-facing question is whether the
*agent* is connected and finished its startup script. Without this
check, the skill reports success but `coder ssh` /
`coder open` still fail because the agent is in `connecting`.

Poll the agent lifecycle until it reaches `ready` (or fail loudly
on `start_error` / `start_timeout`):

```sh
WS_DEADLINE=$(( $(date +%s) + 300 ))
while :; do
  STATE=$(coder list -o json 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
for w in d:
  if w["name"] != "'"$WORKSPACE_NAME"'": continue
  for r in (w["latest_build"].get("resources") or []):
    for a in (r.get("agents") or []):
      print(a["lifecycle_state"]); raise SystemExit
print("no-agent")
')
  case "$STATE" in
    ready)                     echo "agent ready"; break ;;
    start_error|start_timeout) echo "agent failed: $STATE" >&2; exit 1 ;;
  esac
  [ "$(date +%s)" -gt "$WS_DEADLINE" ] && { echo "agent did not reach ready in 5min (last=$STATE)" >&2; exit 1; }
  sleep 5
done
```

If the agent stalls in `connecting`, see
`references/troubleshooting.md#workspace-agent-cant-reach-the-server`.
The usual cause on a single-host Linux setup is the local-only
fallback binding to `127.0.0.1`, which is unreachable from the
workspace container.
### Phase 8: Wrap up and tell the user what they got

After everything is up, print one short block, clearly delimited.
It's the first thing the user reads when they get back to the
terminal, so write it like a handoff, not a config dump. Use plain
labels ("Open in your browser", not "Access URL"), and only show
fields that apply this run.

If the user signed in via the **GitHub device-code flow** (already
signed in by the time we reach this phase):

```text
=== Coder is ready ===

You're signed in as the admin.

Open Coder in your browser whenever you want:
  $ACCESS_URL

Your first dev environment:  $WORKSPACE_NAME
  (or: skipped, you can create one from the home page)

If you want to add more dev environments later, you'll use the
example project named "$TEMPLATE_NAME" that's already set up.

When you want to stop or restart Coder, see below.
```

If you instead used the **GitHub browser-button fallback** (the
device-code check failed and the user clicked the button on the
sign-in page), say so plainly:

```text
=== Coder is ready ===

Open in your browser:   $ACCESS_URL
  (If you haven't already, click "Sign in with GitHub" there.)

Your first dev environment:  $WORKSPACE_NAME
  (or: skipped, you can create one once you're signed in)

If you want to add more dev environments later, you'll use the
example project named "$TEMPLATE_NAME" that's already set up.

When you want to stop or restart Coder, see below.
```

If the user got an **email and password** instead:

```text
=== Coder is ready ===

Open in your browser:   $ACCESS_URL

Sign in with:
  Email:    $EMAIL
  Password: $PASSWORD

These are saved to $STATE_DIR/credentials (mode 0600) so you
can find them later. Don't share that file.

Your first dev environment:  $WORKSPACE_NAME
  (or: skipped, you can create one from the dashboard)

If you want to add more dev environments later, you'll use the
example project named "$TEMPLATE_NAME" that's already set up.

When you want to stop or restart Coder, see below.
```

Then append two short lines that match how Coder is actually
running on this machine. Don't dump all four; pick the one that
applies.

To see Coder's logs:

- Quick-start install (skill ran `coder server` in the background):
  `tail -f $STATE_DIR/server.log`
- systemd service:        `journalctl -u coder -f`
- Docker compose:         `docker compose logs -f coder`
- Kubernetes via Helm:    `kubectl logs -n coder deploy/coder -f`

To stop Coder:

- Quick-start install (skill ran `coder server` in the background):
  `kill "$(cat "$STATE_DIR/server.pid")"`
- systemd service:   `sudo systemctl stop coder`
- Docker compose:    `docker compose down` in the install
  directory. Don't add `-v` unless the user explicitly asks to
  wipe everything; it deletes the database and every dev
  environment.
- Kubernetes via Helm: `helm uninstall coder -n coder`.

Also tell the user where the install's state directory is, so
they can find or delete it. Print the actual expanded path, not
the `$STATE_DIR` placeholder:

```text
The skill kept its working files in:
  $STATE_DIR

  - server.log     server output
  - server.pid     pid of the background server (if started here)
  - credentials    admin email + password (mode 0600), if applicable

Deleting that directory cleans up everything the skill wrote
under your home directory. (It does not delete Coder itself or
your dev environments.)
```

If the user mentioned (or might benefit from) Premium features
like Workspace Proxies, groups, audit log retention, or template
ACLs, mention they can add a license later. The skill never opts
them in automatically; getting a license is a separate flow that
asks for some contact info and is run by Coder's licensor service.
A short pointer is enough; don't over-explain:

```text
If you ever want to try Premium features (Workspace Proxies,
groups, audit log retention, template ACLs), you can request a
license at https://coder.com/trial and paste it into Coder under
Settings -> Licenses (or `coder licenses add -f license.jwt`).
You don't have to do this now, and the skill won't do it for you.
```

For production setups with custom integrations, also remind the
user to write down the things you can't show again later:

- A custom GitHub / GitLab OAuth App's client ID and callback URL,
  if you registered one in Phase 5. (The default "Sign in with
  GitHub" button has nothing to record; Coder manages it.)
- The provisioner key fingerprint, if you generated one for
  cloud-isolated builds.
- The TLS cert file paths and the DNS records you set up.



## Anti-patterns

- **Do not write to the user like a sysadmin.** If a user-facing
  message contains a flag (`--first-user-trial`), an env var
  (`CODER_ACCESS_URL`), an internal noun ("OAuth provider",
  "reverse proxy", "ingress", "terraform"), or a config matrix,
  rewrite it. Decide what they need to know in plain English,
  pick a default, and ask for one short answer. The user does
  not need to learn Coder's vocabulary to use this skill.
- **Do not run `pkill coder` (or any blanket `kill` against the coder
  binary) when `CODER_AGENT_TOKEN` is set.** That terminates the
  workspace agent the user is connected through. See
  `references/troubleshooting.md#never-pkill-coder-on-a-coder-workspace`.
  This is the single most common way to disconnect yourself from a
  Coder-on-Coder install attempt.
- **Do not run destructive cleanup commands without an explicit user
  request.** `docker compose down -v`, `helm uninstall coder`, and
  `kubectl delete namespace coder` permanently destroy the database
  and every workspace built from it. Only run them after the user has
  said "delete everything", "start over", or similar. In headless
  mode, also confirm by echoing the destructive intent back before
  the command runs.
- Do not pipe `install.sh` to `sudo sh` unless the user asked for a
  system-wide install. Default to user-local where possible. If the
  user is wary of `curl | sh`, offer
  `curl -fsSL https://coder.com/install.sh -o install.sh` followed by
  `bash install.sh ...` so they can inspect the script first.
- Do not edit `/etc/systemd/system/coder.service` by hand. Use the
  installer's unit and override with a drop-in at
  `/etc/systemd/system/coder.service.d/override.conf`. systemd is
  itself a fine production supervisor; what makes a deployment
  production-ready is managed Postgres, real TLS, and a real access
  URL, not the choice of process manager.
- Do not write the username/password admin credentials to disk
  silently for the GitHub auth path; that path doesn't need a
  credentials file because the user owns recovery via GitHub. Do
  write them when the user picks username/password (Phase 4) so
  they have a recovery path.
- Do not echo cloud credentials, OAuth client secrets, provisioner
  keys, or the admin password back to the user. Confirm receipt with
  `[set]` or a redacted form.
- Do not opt the user into the upstream enterprise-trial license
  flow unless they explicitly asked. Always pass
  `--first-user-trial=false` to `coder login` and never set
  `CODER_FIRST_USER_TRIAL=true`. The flag's signup-time path
  collects PII (first name, last name, phone, job title, company,
  country, developer count) and POSTs it to Coder's licensor;
  there is no consent UX in the skill for that. If a user later
  wants Premium features, the post-signup `POST /api/v2/licenses`
  endpoint and `coder licenses add` accept a JWT they request
  themselves, with no PII collection on the skill's side. Phase 8
  prints a short pointer at that flow. The skill's "quick-start"
  mode label is unrelated to the trial flag and never costs money.
- Do not skip the `/healthz` readiness probe. A successful `coder
  server` exit doesn't mean the API is up.
- Do not run `coder server` in a foreground that ties up the chat.
  Background it and tail the log.
- Do not push a cloud template before either the server or an
  external provisioner has its provider credentials in scope. The
  first workspace build will hang.
- Do not put the production server's cloud credentials in
  `--variable`, `terraform.tfvars`, or any artifact that ends up in
  the audit log. Set them on the server (or the provisioner's)
  environment instead.
- Do not disable telemetry on the user's behalf. It defaults to on,
  and Coder strips PII before sending. The user can opt out with
  `CODER_TELEMETRY_ENABLE=false` if they need to; don't ask them and
  don't decide for them.
- Do not register a custom GitHub external auth provider for a fresh
  deployment unless the user has a reason (GHES, non-default OAuth
  App). The default github.com provider is on automatically and
  covers the common case.

## References

- [`references/install-methods.md`](references/install-methods.md) -
  full per-target install matrix, with verification.
- [`references/templates.md`](references/templates.md) - starter
  template matrix and required variables.
- [`references/first-user.md`](references/first-user.md) - `coder
  login` flags, env vars, and edge cases.
- [`references/first-user-github-device.md`](references/first-user-github-device.md) -
  GitHub device-code flow recipe for signing the first admin in
  without a browser on the install machine.
- [`references/production.md`](references/production.md) - deployment
  mode decision matrix, order of operations, scope boundaries.
- [`references/wildcard-tls.md`](references/wildcard-tls.md) - DNS,
  wildcard subdomain, TLS termination options, Helm values.
- [`references/external-auth-github.md`](references/external-auth-github.md) -
  GitHub OAuth App registration and `CODER_EXTERNAL_AUTH_*` env vars.
- [`references/external-provisioner.md`](references/external-provisioner.md) -
  scoped keys, provisioner tags, AWS / GCP / Azure isolation.
- [`references/troubleshooting.md`](references/troubleshooting.md) -
  readiness probe failures, port conflicts, sudo and SELinux issues,
  Helm rollback, TLS failures, OAuth failures, cleanup.

For background on Coder concepts (templates vs workspaces vs agents),
the canonical docs at <https://coder.com/docs> are authoritative.
This skill does not duplicate that material.
