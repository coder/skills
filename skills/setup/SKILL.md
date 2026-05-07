---
name: setup
description: Install and bootstrap a Coder (coder/coder) deployment end-to-end from the CLI without using the web UI. Covers quick-start setups (one machine) and production setups (real domain, TLS, optional wildcard, optional custom OAuth, optional external provisioner). Use when the user wants to "install Coder", "set up Coder", "deploy Coder", "run Coder locally / in Docker / on Kubernetes / on a VM", "stand up Coder for my team", "put Coder behind HTTPS / a real domain", "bootstrap the first admin user from the terminal", or otherwise get a working Coder deployment with at least one workspace ready to go. Wraps the canonical install.sh, drives the GitHub device-code flow on fresh deployments to sign the first admin in without a browser on the install machine, falls back to a generated email and password for fully scripted setups, pushes a starter template, and (optionally) creates a first workspace. Defers per-topic configuration (OIDC, custom OAuth, external provisioners, wildcard URL, TLS strategy, template authoring) to https://coder.com/docs/ instead of duplicating it.
---

# setup

End-to-end install and first-run setup for a Coder deployment without
opening the Coder web UI.

The web UI works fine. This skill exists so the user can run one
scripted, repeatable, CLI-only path: install, start the server,
bootstrap the admin user, push a starter template, optionally
create a workspace, and surface the credentials. It is the right
path for demos, headless boxes, automation, team rollouts, and
anyone who explicitly says they don't want to touch the UI.

## Where to get authoritative information

Anything topic-specific (OIDC, custom GitHub OAuth, GitLab,
external provisioners, wildcard URL, TLS termination, template
authoring, cloud installs, Kubernetes / Helm values, Rancher,
OpenShift, air-gapped, upgrades, backups, telemetry, Premium
features) lives in the upstream docs. Pull from there instead of
guessing or duplicating. The docs publish a machine-readable
index designed for agents:

- <https://coder.com/docs/llms.txt> -- compact index. Every page
  is also available as raw Markdown by appending `.md` to its
  URL or sending `Accept: text/markdown`. Read this once at the
  start of the install to see what's available.
- <https://coder.com/docs/llms-full.txt> -- the full corpus in
  one file when the user asks something the index alone can't
  answer.

This skill only documents the install workflow itself: the order
of phases, the user-facing question wording, the small number of
quirks that aren't on coder.com (the auto-tunnel URL parsing
recipe, the GitHub device-flow callback recipe, the workspace
host guard). For everything else, point the user at the relevant
`coder.com/docs/...md` page and let them or a follow-up agent
configure it. That keeps the skill from drifting out of date.

## When to use this skill

Activate when the user says any of:

- "Install Coder", "set up Coder", "deploy Coder", "get me started
  with Coder", "bootstrap Coder", "stand up Coder for my team".
- "Run Coder on this machine", "run Coder in Docker", "deploy Coder
  on Kubernetes", "Coder on AWS / GCP / Azure / DigitalOcean".
- "Put Coder behind HTTPS", "behind Caddy / nginx / cert-manager",
  "with a wildcard domain", "with TLS / Let's Encrypt".
- "I don't want to touch the UI", "do it from the terminal",
  "headless setup", "non-interactive first-user setup".
- "Create the first admin user from the CLI".
- "Push a starter template", "create my first workspace".

Do **not** activate for upgrading an existing deployment, editing
an existing template, or troubleshooting an already-running
server. Point the user at <https://coder.com/docs/install/upgrade.md>,
the relevant `admin/...` page, or
<https://coder.com/docs/support.md> for those.

## Talking to the user

Assume the user has never used Coder and does not know what a
template, workspace, agent, provisioner, access URL, wildcard
URL, or external auth provider is. They asked you to install
Coder; they did not ask for a tour of its internals. Run the
install for them.

Hard rules for every message you send the user:

- **No flags, env-var names, or config keys in user-facing
  questions.** `--first-user-trial`, `CODER_ACCESS_URL`,
  `CODER_WILDCARD_ACCESS_URL`, and `CODER_EXTERNAL_AUTH_*` are
  internal details. They can appear in commands you run, and in
  the final summary as paths to files you wrote, but not as
  things the user has to understand.
- **Explain the thing before you name it.** If you must use a
  Coder term, say what it does first in one short sentence, then
  use the term. Example: "a starter project that builds workspaces
  (Coder calls this a *template*)".
- **Ask one short choice at a time.** Never present a decision
  matrix.
- **Default aggressively.** Pick the obvious default and ask the
  user to confirm, instead of making them choose from options.
- **Translate errors.** Don't paste raw server logs at the user.
  Read the log yourself, decide what's wrong, and tell them in
  plain English. Show the raw log only if they ask.
- **No "Coder-ese" in the final summary.** The handoff at the end
  is what the user reads first. Use "sign-in page", "the app you
  can open in a browser", "the example project", not "access URL",
  "dashboard", "template".
- **Do not narrate yourself.** The user does not know or care
  that a "skill" exists. Never say "this skill", "the setup
  skill", "I ran the skill", "I used the skill", or similar.
  When you need to refer to what just happened, say "I installed
  Coder", "the install", or "setup". The handoff messages and
  any error explanations follow this rule too.
- **Pick exactly one option in any user-facing template.** When
  the skill text shows alternatives like
  `<one of: tail -f ... | docker compose logs -f ...>`, that
  notation is for you, not the user. Resolve it to the single
  command that matches how Coder is actually running before you
  show anything to the user. Never paste the alternatives
  literally.

A short concept glossary you can pull plain-English phrases from:

- **Coder** -> "a thing that gives you and your team cloud
  development environments you open in the browser or in your
  editor".
- **Access URL** -> "the web address people will open to use
  Coder".
- **Wildcard URL** -> "a DNS setup that lets apps inside your dev
  environment have their own subdomain".
- **Workspace** -> "a single dev environment for one person".
- **Template** -> "a recipe Coder follows when it builds a
  workspace; e.g. 'one Linux container with VS Code'".
- **Agent** / **Provisioner** -> internals; users normally don't
  need to know they exist.
- **External auth** -> "letting workspaces sign in to GitHub /
  GitLab / etc. so they can clone private repos".
- **Owner** -> "the admin account; the first person to sign in
  becomes one automatically".
- **Free vs paid** -> Coder is open source; nothing the skill
  does costs money. The upstream CLI has a `--first-user-trial`
  flag that turns on a 30-day enterprise-feature evaluation; the
  skill always passes `--first-user-trial=false` and does not
  bring it up.

If the user asks for technical detail ("what flag does that map
to?", "show me the env var"), shift to engineer voice for that
one answer; default back to plain English on the next turn.

## Workflow

Each phase has a clear exit criterion. Confirm before any
destructive action (system package install, opening ports,
overwriting kubeconfigs, deleting volumes).

1. **Discover.** Ask the user a small set of questions in plain
   English. Probe the host afterward to fill in defaults.
2. **Install.** Use `install.sh` (or Helm / compose).
3. **Start.** Run the server.
4. **Sign in.** Make the asking user the admin (Owner).
5. **Template.** Push a starter that matches the chosen
   infrastructure.
6. **Workspace** (optional). Build the first dev environment.
7. **Hand off.** Tell the user how to sign in, how to start /
   stop, and where to go next.

External-services configuration (custom OAuth, GitLab / GHES,
external provisioners, wildcard DNS, OIDC) is intentionally not
its own phase here. Fresh deployments work without any of it; if
the user asks for one of those features, follow the matching
page on coder.com/docs and apply it.

### Phase 1: Discover

Lead with the user. Walk away from this phase with the shortest
possible interview answered (mode, infrastructure, sign-in
method) so Phases 2 onward have everything they need. Only after
the user has answered, probe the host quietly to fill in any
remaining defaults.

The order is:

1. Ask the familiarity question (new to Coder, or used it
   before).
2. Ask the deployment-mode question.
3. Ask the infrastructure question.
4. Ask the sign-in question.
5. Ask the small per-mode follow-ups.
6. *Then* probe the host (what package manager, is Docker
   installed, is there an existing Coder login, is this a
   workspace).
7. Show the user one short plan paragraph and get a single
   yes/no.

Hard guards run with the actions they protect, not in this phase:

- The workspace-host guard (don't install a host `coder` if this
  is itself someone's Coder workspace) runs at the start of
  Phase 2.
- The existing-login guard (only isolate `CODER_CONFIG_DIR` when
  the host already has a Coder session pointing somewhere the
  user wouldn't want overwritten) runs at the start of Phase 4.

#### Read the audience

Ask one short question first:

> "Have you used Coder before, or is this your first time?"

This isn't paperwork. It changes how you talk for the rest of
the install. Map the answer:

| What the user said                                              | Mode      |
|-----------------------------------------------------------------|-----------|
| "first time", "new to Coder", "never used it", "just heard of it" | new       |
| "used it", "have a deployment", "familiar", "upgrading", "moving" | familiar  |
| anything ambiguous                                              | new       |

Default to **new** when in doubt. The cost of explaining a term
the user already knows is one extra sentence. The cost of
shipping jargon at someone who's never seen it is that they get
stuck.

What the modes change:

- **new.** Whenever you reach a Coder-specific concept
  (workspace, template, agent, provisioner, access URL, wildcard
  URL, external auth), pause for one sentence in plain English
  before using the word. Example: "Coder builds your dev
  environments from a recipe written in Terraform; we call those
  recipes *templates*. I'll push a starter template now." Don't
  belabor it; one sentence, then move on. When you mention
  Terraform, name it as "the language Terraform uses to describe
  cloud infrastructure" the first time. The glossary in the
  "Talking to the user" section is the source of phrasings.
- **familiar.** Skip the inline explanations. Use the Coder
  terms directly. Don't gloss "template" or "workspace".

Familiarity does not change the install path; it only changes
the narration. Quick-start vs production, Docker vs Kubernetes,
GitHub vs email, and every other technical decision is the same
either way.

If the user later asks "what's a template?" or "what's an
agent?", switch to new-mode for that turn regardless of what
they said earlier.

#### Pick the deployment mode

Decide between **quick-start** and **production** before anything
else. It drives almost every later choice. Ask in plain English:

> "Are you trying Coder out on this machine, or setting it up
> for your team to use long-term?"

Map the answer:

| What the user said                                    | Mode        |
|-------------------------------------------------------|-------------|
| "trying it out", "demo", "play with it", "just me"    | quick-start |
| "on this laptop", "my server", "throwaway"            | quick-start |
| Names a real domain (`coder.example.com`)             | production  |
| "HTTPS", "TLS", "Let's Encrypt", "behind a proxy"     | production  |
| "For my team", "for the company", "staging"           | production  |
| "Cloud workspaces" with a shared cloud account        | production  |

If signals conflict, ask one short follow-up. Don't guess.

If the user picks production, read
<https://coder.com/docs/install.md> and
<https://coder.com/docs/admin/setup.md> before proposing the plan
in step 6 below; the production install layout (managed Postgres,
TLS, Helm values, ingress) is documented there and changes more
often than this skill does.

#### Pick the infrastructure

Always ask. Don't silently default to Docker; the user may have a
strong preference based on what they already run.

> "Where do you want Coder to run? I can set it up:
>
>   1. **Docker** on this machine (easiest if Docker is installed).
>   2. **Kubernetes / Helm** against a cluster you have access to.
>   3. **Directly on this machine** (the binary, with systemd).
>
> Pick a number, or tell me about your setup if it's something
> else (Rancher, OpenShift, AWS / GCP / Azure, air-gapped) and
> I'll point you at the right docs page."

Map the answer:

| User says                            | Install path                                              |
|--------------------------------------|-----------------------------------------------------------|
| "Docker", "compose", "container"     | Docker compose (Phase 2)                                  |
| "Kubernetes", "Helm", "k8s", "kind"  | Helm (Phase 2)                                            |
| "directly", "on the host", "binary"  | Standalone install via `install.sh` (Phase 2)             |
| "Rancher" / "OpenShift"              | Hand off to <https://coder.com/docs/install/rancher.md> or `install/openshift.md` |
| "AWS Marketplace" / "GCP" / "Azure"  | Hand off to <https://coder.com/docs/install/cloud.md>     |
| "Air-gapped", "offline", "no internet" | Hand off to <https://coder.com/docs/install/airgap.md>  |

For the hand-off cases, do not try to drive the install yourself.
Tell the user the exact docs page, copy the salient command, and
stop.

If the user picks one of the three driveable options but doesn't
know which, look at the host (Phase 1 step 5) and recommend:
Docker if installed, else Kubernetes if `kubectl` has a current
context, else direct install. Confirm the recommendation in one
short sentence; don't lecture.

#### Pick how the user will sign in

Fresh deployments come with a built-in "Sign in with GitHub" path
turned on, using a GitHub OAuth App that Coder hosts. Whoever
signs in first becomes the admin (the Owner) automatically. Two
reasonable paths:

- **GitHub.** Drive GitHub's standard device-code flow over
  Coder's API. The skill prints a short URL and an 8-character
  code; the user opens the URL on whatever device is handy
  (their phone is fine), pastes the code, approves access on
  GitHub, and the skill captures the session and finishes setup.
  No browser on the install machine, no password to record.
- **Email and password.** Fully scripted, no GitHub round trip.
  The skill picks a strong password, creates the admin account
  from the terminal, and saves the email and password to a file
  in the install's state directory so the user can find them
  later.

Ask once, in plain English:

> "For sign-in, do you want me to walk you through GitHub (I'll
> show you a short URL and a code to paste; works from any
> phone), or just create an email and password for you?"

Default to GitHub when the user can reach github.com on any
device. Fall back to email-and-password if they say no, ask for a
fully scripted setup, or you're running in headless mode
(`claude -p`) where there's no human to type a code.

The device-code path only works on deployments where the Coder
server has device flow enabled for its GitHub provider. Fresh
deployments do; custom-configured GitHub providers may not.
Phase 4 checks `default_provider_configured` and the
`/users/oauth2/github/device` endpoint before driving the flow,
and falls back to email-and-password if either says no.

For the email-and-password path, prefill the email from git
config if present, instead of asking cold:

```sh
EMAIL_DEFAULT="$(git config --global --get user.email 2>/dev/null || true)"
```

Then confirm with the user. Don't make them type it from scratch
unless git doesn't have one.

#### Per-mode follow-ups

**Quick-start mode.** Just confirm the defaults; don't prompt for
each one.

- **Web address.** The skill defaults to letting Coder open its
  own public URL automatically (a `*.try.coder.app` address).
  Tell the user, don't ask. Fall back to a local-only URL only
  if the auto-tunnel can't initialize (offline host) or the user
  asks. Phase 3 has the detection recipe.
- **Example project.** Default: a Linux container in Docker
  (Coder calls this the `docker` template), or one Linux pod
  via Kubernetes if you went through Helm. Confirm in one
  sentence.
- **Build a first dev environment now?** Default yes.

**Production mode.** You need a few things from the user before
touching anything. Ask in plain English; don't make them recite
a config file.

- **The web address people will open.** Mandatory.
  > "What address should everyone open in their browser to use
  > Coder? Something like `coder.yourcompany.com`."
- **Who handles HTTPS.** Either Coder itself or a proxy /
  ingress in front of it. Lead with the user's existing setup if
  spotted (cert-manager, nginx, Caddy).
- **Database.** Coder needs a Postgres for production.
  > "Do you have a Postgres I can point Coder at? If yes, I'll
  > need its connection string."
- **What kind of dev environments.** Maps to the example project
  you'll add. Linux container in Docker, Kubernetes pod, or a
  cloud VM. The list of starter templates is at
  <https://coder.com/docs/admin/templates.md>.

For configuration topics that don't all production deployments
need (wildcard DNS for in-workspace apps, custom GitHub / GitLab
OAuth, OIDC, external provisioners for cloud isolation), do not
ask in Phase 1. After the deployment is up and the user has
signed in, ask once at the end whether they want to wire any of
those in, and if so, point them at the matching page on
coder.com/docs:

- Wildcard URL: <https://coder.com/docs/admin/networking/wildcard-access-url.md>
- GitHub OAuth (default and custom): <https://coder.com/docs/admin/users/github-auth.md>
- OIDC (Okta, Entra, Google, etc.): <https://coder.com/docs/admin/users/oidc-auth.md>
- External authentication for workspaces (clone private repos):
  <https://coder.com/docs/admin/external-auth.md>
- External provisioners: <https://coder.com/docs/admin/provisioners.md>

Don't try to script those configurations from the skill. The env
vars and OAuth callback URLs change; the docs are kept current.

#### Probe the host (after the questions are answered)

With answers in hand, look at the machine to fill in remaining
defaults. This runs silently; don't make the user watch a
detection ceremony.

```sh
uname -sm
command -v apt-get dnf yum apk brew zypper pacman 2>/dev/null
docker version --format '{{.Server.Version}}' 2>/dev/null
kubectl config current-context 2>/dev/null
helm version --short 2>/dev/null
coder --version 2>/dev/null
systemctl is-active coder 2>/dev/null
test -f "$HOME/.config/coderv2/url" && cat "$HOME/.config/coderv2/url"
env | grep -E '^(CODER_AGENT_TOKEN|CODER_WORKSPACE_NAME)=' || true
```

What to do with each result:

- **`coder --version` succeeds.** Plan to reuse the existing
  binary; skip the install in Phase 2 unless the user asked for
  a fresh install or production needs a newer release.
- **No Docker, no Helm.** If the user picked one of those, walk
  them through installing it first; otherwise the standalone
  install is the only option.
- **`~/.config/coderv2/url` exists** and points somewhere the
  user wouldn't want clobbered. Plan to isolate `CODER_CONFIG_DIR`
  in Phase 4. Mention it in the plan paragraph; don't ask.
- **No existing config dir.** Use the default (`~/.config/coderv2`).
  Do **not** isolate by default. Isolation is only for the
  conflict case.
- **`CODER_AGENT_TOKEN` or `CODER_WORKSPACE_NAME` is set.** This
  is itself someone's Coder workspace. Phase 2 will refuse a host
  install and steer to Docker compose or a separate cluster
  context. Note this in the plan so the user knows why.

Then show the user one plan paragraph (mode, infrastructure,
sign-in, any planned isolation, and any defaults you're applying)
and ask for a single yes/no before mutating anything.

**Headless mode** (`claude -p`, no interactive shell): the user
can't answer prompts and can't click a browser button. Treat the
original request as the approval. For sign-in, default to
email-and-password. If the prompt is missing something required
for production (web address, HTTPS strategy, database), refuse
with a one-line error listing what's missing in plain English,
instead of blocking on stdin.

### Phase 2: Install

**Workspace-host guard.** Before running any installer, check
whether you are inside someone's Coder workspace. If
`CODER_AGENT_TOKEN` or `CODER_WORKSPACE_NAME` is set, the
workspace agent on this host is itself a `coder` binary; running
`pkill coder` or letting `install.sh` overwrite
`/usr/local/bin/coder` will disconnect the user. In that case:

- **Refuse a host install** unless the user explicitly asked
  for nested Coder.
- **Docker compose is fine** when scoped to a sub-directory and
  a non-default port. Workspaces ship Docker; the inner server
  runs in its own container.
- **Kubernetes via Helm is fine** when targeted at a separate
  cluster context, not the workspace's host.

See `references/troubleshooting.md#never-pkill-coder-on-a-coder-workspace`
if this guard fires.

Otherwise, install. Always prefer the canonical install script:
it detects the package manager, falls back to a standalone
tarball, and supports an unprivileged user-local install.

Standalone Linux/macOS, system-wide:

```sh
curl -fsSL https://coder.com/install.sh | sh
```

Standalone Linux/macOS, no sudo:

```sh
curl -fsSL https://coder.com/install.sh \
  | sh -s -- --method standalone --prefix "$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
```

For Docker compose, Helm, or anything else, follow the matching
docs page rather than scripting it from the skill:

- Docker: <https://coder.com/docs/install/docker.md>
- Kubernetes / Helm: <https://coder.com/docs/install/kubernetes.md>
- Standalone CLI: <https://coder.com/docs/install/cli.md>
- Rancher / OpenShift / Cloud / Air-gapped: see the install/
  index page.

Useful `install.sh` flags (`--help` for the full set):

- `--mainline` (default) or `--stable`: pick the release channel.
  Use `--stable` for production unless the user asked for
  mainline.
- `--version X.Y.Z`: pin a specific version.
- `--with-terraform`: install Terraform alongside Coder. Use
  this when the deployment will run Terraform locally (almost
  every template does).
- `--method standalone --prefix DIR`: user-local install with
  no package manager and no sudo.
- `--dry-run`: print the commands without running them.

Verify with `coder --version`. Exit criterion: the binary runs.

### Phase 3: Start the server

Skill outputs that need to survive the chat live in one directory
the skill creates up front and prints back to the user in Phase 7.
Do not scatter dotfiles across `$HOME`. The directory follows
XDG: `$XDG_STATE_HOME/coder-install` if set, otherwise
`$HOME/.local/state/coder-install`.

```sh
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/coder-install"
mkdir -p "$STATE_DIR"
```

#### Quick-start path

Default: let `coder server` open its built-in tunnel. The tunnel
is the most-reliable single-machine path because it routes
around host-firewall and docker-bridge issues that bite
local-only binds. Don't pass `--access-url`; the server picks a
`*.try.coder.app` URL and prints it to stderr.

Under the hood, `coder server` reads (or generates and persists)
a wireguard keypair in the user's config dir at
`${XDG_CONFIG_HOME:-$HOME/.config}/coderv2/devtunnel`, opens a
wireguard connection to `pit-1.try.coder.app`, and serves
traffic that arrives there. The hostname is derived from the
keypair, so it's stable across restarts as long as the keypair
file is intact.

The skill does **not** derive the URL itself. The server prints
a banner that includes:

```text
View the Web UI:
https://<id>.pit-1.try.coder.app
```

Parse the URL from the line right after `View the Web UI:`. The
tunnel handshake usually completes in 2-5 seconds.

For **standalone host install**:

```sh
nohup coder server > "$STATE_DIR/server.log" 2>&1 &
echo $! > "$STATE_DIR/server.pid"
```

For **Docker compose**: don't run `coder server` directly; bring
up the compose stack and let the container hold the log. Skip
the state-dir log/pid (the container is its own supervisor;
logs come from `docker compose logs`). The auto-tunnel still
works inside the container as long as the compose file persists
the wireguard keypair (the upstream `compose.yaml` does).

Wait for readiness:

```sh
coder_log() {
  if [ -f "$STATE_DIR/server.log" ]; then
    cat "$STATE_DIR/server.log"
  elif [ -f docker-compose.yml ] || [ -f compose.yaml ]; then
    docker compose logs coder 2>&1
  else
    return 1
  fi
}

ACCESS_URL=""
for _ in $(seq 1 60); do
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
asked for local-only). Only fall back if the loop above exits
with `ACCESS_URL=""`:

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

Bind to `0.0.0.0:7080`, not `127.0.0.1:7080`. The Docker
workspace agent reaches the server via `host.docker.internal`,
so a host-loopback bind is unreachable from inside the workspace
container. On NixOS the firewall may still drop the SYN; see
`references/troubleshooting.md#nixos-firewall-blocks-docker-bridge`.

#### Production path

Production deployments are configured via env, on the deployment
manifest (Helm values, compose `environment:`, systemd
environment file). The minimal env (access URL, Postgres URL,
TLS, optional wildcard) and the canonical Helm values file are
in the upstream docs. Don't reproduce them here; follow:

- <https://coder.com/docs/install/kubernetes.md> for Helm.
- <https://coder.com/docs/install/docker.md> for compose.
- <https://coder.com/docs/admin/setup.md> for the env-var
  matrix (`CODER_ACCESS_URL`, `CODER_PG_CONNECTION_URL`,
  `CODER_TLS_*`, `CODER_REDIRECT_TO_ACCESS_URL`,
  `CODER_WILDCARD_ACCESS_URL`).

Roll out the deployment, then wait for `/healthz` against the
public URL:

```sh
for _ in $(seq 1 120); do
  curl -fsS "$ACCESS_URL/healthz" >/dev/null 2>&1 && break
  sleep 1
done
```

Verify the wildcard if you set one:

```sh
curl -fsS "https://app-test.${WILDCARD_DOMAIN}/healthz"
```

### Phase 4: Sign in as the admin

Whoever signs in first becomes the admin (Owner) automatically.

**Existing-login guard.** Before running any `coder` command that
writes a session, check whether the host already has one. Only
isolate `CODER_CONFIG_DIR` if the *existing* `~/.config/coderv2/url`
points at a real deployment the user wouldn't want overwritten
(e.g. `https://dev.coder.com`, an internal team URL). The default
is **not** to isolate; most users have no prior config and
`coder login` should write to the standard `~/.config/coderv2`.

```sh
default_dir="${XDG_CONFIG_HOME:-$HOME/.config}/coderv2"
if [ -f "$default_dir/url" ]; then
  existing="$(cat "$default_dir/url")"
  case "$existing" in
    "$ACCESS_URL"|"") : ;;  # No conflict.
    *)
      # Existing login points elsewhere; isolate.
      export CODER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/coderv2-quickstart"
      export CODER_CACHE_DIRECTORY="${XDG_CACHE_HOME:-$HOME/.cache}/coderv2-quickstart"
      mkdir -p "$CODER_CONFIG_DIR" "$CODER_CACHE_DIRECTORY"
      ;;
  esac
fi
```

Without isolation, `coder login` would overwrite the existing
URL and session and kick the user out of their real deployment.

#### GitHub path (device code, no browser on this machine)

Drive the GitHub sign-in over GitHub's standard device flow,
proxied through Coder's API. The user gets a short URL and a
one-time code, types it on whatever device is handy, and the
install completes without opening a browser on the install
machine.

First, confirm the deployment can do device flow:

```sh
DEVICE_OK=true
curl -fsS "$ACCESS_URL/api/v2/users/authmethods" \
  | python3 -c '
import json, sys
d = json.load(sys.stdin)
sys.exit(0 if d["github"].get("default_provider_configured") else 1)
' || DEVICE_OK=false

curl -fsS "$ACCESS_URL/api/v2/users/oauth2/github/device" >/dev/null 2>&1 || DEVICE_OK=false
```

If `DEVICE_OK=false` (custom GitHub provider, or device flow
disabled), fall back to the email-and-password path. Don't reach
for the browser flow unless the user has a working browser on
this machine and asked for it.

When device flow is available, drive it with the two scripts
bundled in this skill:
[`scripts/github-device-fetch.sh`](scripts/github-device-fetch.sh)
and
[`scripts/github-device-poll.sh`](scripts/github-device-poll.sh).
**Run them as three separate tool calls**, with a chat message
to the user between them. The full protocol, with rationale and
failure modes, is in
[`references/first-user-github-device.md`](references/first-user-github-device.md).

1. **Fetch.** One short shell command:

   ```sh
   ACCESS_URL="$ACCESS_URL" \
     bash "$SKILL_DIR/scripts/github-device-fetch.sh"
   ```

   Returns in ~3 seconds. Writes
   `$STATE_DIR/github-device.{jar,env}` and prints
   `USER_CODE` / `VERIFY_URI` / `EXPIRES_IN` on stdout. Do NOT
   include the polling loop in this call; if you do, the command
   sits for up to 15 minutes and the user never sees the code.
2. **Tell the user, in chat (not in a shell command).** Read
   `$VERIFY_URI` and `$USER_CODE` from
   `$STATE_DIR/github-device.env` (or from the fetch script's
   stdout) and send the user a chat message like:

   > To sign in to Coder, open this on any device (your phone
   > is fine):
   >
   >   $VERIFY_URI
   >
   > Enter this code:
   >
   >   $USER_CODE
   >
   > Say "ok" when you're done and I'll finish setting you up
   > as the admin.

   Wait for the user's acknowledgement ("ok", "done", "entered
   it"). If they ask for a different sign-in method instead,
   abandon the device flow and switch to email-and-password.
3. **Poll.** A separate shell command:

   ```sh
   ACCESS_URL="$ACCESS_URL" \
     bash "$SKILL_DIR/scripts/github-device-poll.sh"
   ```

   Loops until the user finishes on github.com, writes the
   session token into `$CODER_CONFIG_DIR/{url,session}`, removes
   the cookie jar / env / response scratch files (success or
   failure), and verifies with `coder whoami` and
   `coder users list`.

`$SKILL_DIR` is the directory this `SKILL.md` is in. When the
skill is installed via the marketplace it is something like
`~/.claude/plugins/coder/skills/setup`; when run via
`--plugin-dir` it is wherever the marketplace was pointed. The
runner exposes the location through whichever variable it uses
for skill paths; resolve it once and reuse the value across both
calls.

The reason for the split is that most agent tool runners buffer
a shell command's stdout and only return it when the command
exits. A combined fetch-and-poll script prints the code at the
start but the runner doesn't surface it until the polling exits,
which means the user sits looking at a hung chat for the full
15-minute device-code window. The recipe document opens with
this warning; respect it.

`users list` should show one row with `OWNER` in the roles
column, with the email and login from the user's GitHub account.
If it doesn't, tell the user in one line that GitHub sign-in
didn't take and offer email-and-password instead; don't paste
raw output.

#### Email and password path (no browser)

Use `coder login` with `--first-user-*` flags, **including
`--first-user-trial=false`**. Without that flag (or
`CODER_FIRST_USER_TRIAL=false` in the env), the CLI prompts on
stdin and the headless flow hangs.

Pass the password through the env, not the command line:

```sh
export CODER_FIRST_USER_PASSWORD="$PASSWORD"
coder login "$ACCESS_URL" \
  --first-user-email     "$EMAIL" \
  --first-user-username  "$USERNAME" \
  --first-user-full-name "$FULL_NAME" \
  --first-user-trial=false
unset CODER_FIRST_USER_PASSWORD
```

The password has no recovery path. Persist it to a mode-0600
file in `$STATE_DIR`:

```sh
umask 0077
printf 'url=%s\nusername=%s\nemail=%s\npassword=%s\n' \
  "$ACCESS_URL" "$USERNAME" "$EMAIL" "$PASSWORD" \
  > "$STATE_DIR/credentials"
chmod 0600 "$STATE_DIR/credentials"
```

Verify with `coder whoami` and `coder users list`.

Anything more advanced about the upstream `coder login` flags
(persistent tokens, JSON output, the `--token` form) is in
<https://coder.com/docs/reference/cli/login.md>.

### Phase 5: Push a starter template

Pick the template that matches the chosen infrastructure. The
starter list and required parameters live in
<https://coder.com/docs/admin/templates.md> (and the
per-template pages under it). Don't hard-code the list here; it
changes.

```sh
TEMPLATE_DIR="$(mktemp -d)/$TEMPLATE_NAME"
coder templates init --id "$TEMPLATE_ID" "$TEMPLATE_DIR"
coder templates push "$TEMPLATE_NAME" -d "$TEMPLATE_DIR" --yes
coder templates list
```

For non-secret template variables, use `--variables-file`:

```sh
cat > "$(mktemp).yaml" <<EOF
namespace: coder
use_kubeconfig: false
EOF
coder templates push "$TEMPLATE_NAME" --variables-file <that-file> --yes
```

Never echo secret values back to the user, never put them in
`terraform.tfvars`, and never pass them as `--variable` (they
leak into every template version and the audit log). For cloud
templates that need provider credentials, see
<https://coder.com/docs/admin/templates.md> for the secret
variable pattern, and <https://coder.com/docs/admin/provisioners.md>
if you need to keep credentials off the server.

### Phase 6: Create a workspace (optional)

If the user wants a workspace right away:

```sh
coder create "$WORKSPACE_NAME" --template "$TEMPLATE_NAME" --yes
```

Pass parameters with repeated `--parameter "name=value"`.
Templates evolve; never assume a starter has no required
parameters. Discover them before calling `coder create`:

```sh
coder templates pull "$TEMPLATE_NAME" "$(mktemp -d)/$TEMPLATE_NAME"
# Read main.tf for `data "coder_parameter"` blocks.
```

`coder create` without `--parameter` for a required parameter
blocks on stdin and hangs the headless flow. List, map, and
object parameters need a JSON value:

```sh
coder create "$WORKSPACE_NAME" \
  --template "$TEMPLATE_NAME" \
  --parameter 'jetbrains_ides=[]' \
  --parameter 'cpu=2' \
  --yes
```

For `kubernetes`, the namespace must already exist.

**Wait for the agent to be ready, not just for the build to
succeed.** A successful build with `latest_build.status=running`
only means the workspace's infrastructure stood up; the *agent*
must finish its startup script before `coder ssh` and `coder
open` work.

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
    ready)                     break ;;
    start_error|start_timeout) echo "agent failed: $STATE" >&2; exit 1 ;;
  esac
  [ "$(date +%s)" -gt "$WS_DEADLINE" ] && { echo "agent did not reach ready in 5min (last=$STATE)" >&2; exit 1; }
  sleep 5
done
```

If the agent stalls in `connecting`, see
`references/troubleshooting.md#workspace-agent-cant-reach-the-server`.

### Phase 7: Hand off

Print one short, plain-English block at the end. This is what
the user reads first; write it like a handoff, not a config
dump. Substitute the actual values; don't print fields that
don't apply.

Before you write the message, decide which Logs and Stop
command pair matches the actual install: host install with
`server.log` / `server.pid`, Docker compose, systemd, or
Kubernetes / Helm. Pick ONE pair. The angle-bracket
`<one of: ...>` notation in the templates below is a hint to
you, not text to copy. Resolve it to the one matching command
before you show anything to the user.

Do not refer to yourself or to "the skill" in any user-facing
text. Speak in the first person about what was installed ("I
installed Coder", "setup wrote ..."); never say "this skill"
or "the setup skill".

GitHub device-code path (already signed in by now). Example
shown for a host install; pick one Logs / Stop pair that
matches your install:

```text
=== Coder is ready ===

You're signed in as the admin.

Coder is running here as a host process. The binary is at
$(command -v coder); its data lives in
${CODER_CONFIG_DIR:-$HOME/.config/coderv2}.

Open Coder in your browser:
  $ACCESS_URL

To start, stop, or check on Coder later:
  - Logs:  tail -f $STATE_DIR/server.log
  - Stop:  kill $(cat $STATE_DIR/server.pid)

What to try next:

  - Open the example dev environment "$WORKSPACE_NAME" in your
    browser (or run `coder ssh $WORKSPACE_NAME`).
  - Build your own dev environments by editing the example
    project, or pick a different starter:
      coder templates list
      coder templates init --id <id> ./mytemplate
      coder templates push mytemplate -d ./mytemplate --yes
    Templates use Terraform; the guide is at
    https://coder.com/docs/admin/templates/creating-templates.md
  - Want to add things like Okta / Entra sign-in, GitLab,
    custom domains, or cloud workspaces? See:
      https://coder.com/docs/admin/users/oidc-auth.md
      https://coder.com/docs/admin/users/github-auth.md
      https://coder.com/docs/admin/networking/wildcard-access-url.md
      https://coder.com/docs/admin/provisioners.md

Working files are in $STATE_DIR. Delete that directory to clean
up what setup wrote here.
```

For Docker compose, swap the "Coder is running" sentence and
the Logs / Stop lines for:

```text
Coder is running in Docker on this machine. The compose file
is at $STATE_DIR/docker-compose.yml.

  - Logs:  docker compose -f $STATE_DIR/docker-compose.yml logs -f coder
  - Stop:  docker compose -f $STATE_DIR/docker-compose.yml down
```

For systemd:

```text
Coder is running as a systemd service named `coder`.

  - Logs:  journalctl -u coder -f
  - Stop:  sudo systemctl stop coder
```

For Kubernetes / Helm:

```text
Coder is running in Kubernetes as the `coder` Helm release in
the `coder` namespace.

  - Logs:  kubectl logs -n coder deploy/coder -f
  - Stop:  helm uninstall coder -n coder
```

Print exactly one "Coder is running" sentence, one Logs line,
and one Stop line. Never paste the alternatives at the user.

For the email-and-password path, replace the "You're signed in"
line with the credentials block:

```text
Sign in at $ACCESS_URL with:

  Email:    $EMAIL
  Password: $PASSWORD

Setup wrote them to $STATE_DIR/credentials (mode 0600). Don't
share that file.
```

For the browser-button GitHub fallback (rare; only used when
device-flow isn't available), replace the "You're signed in"
line with:

```text
Open $ACCESS_URL in your browser and click "Sign in with GitHub".
You'll be the admin once you finish.
```

If the user mentioned (or might benefit from) Premium features
like Workspace Proxies, groups, audit log retention, or template
ACLs, mention they can request a license later. Don't drive
that flow yourself; it collects PII (name, phone, job title,
company, country, dev count) and posts to the licensor:

```text
If you ever want to try Premium features, request a license at
https://coder.com/trial and add it under Settings -> Licenses
(or `coder licenses add -f license.jwt`). You don't have to do
this now, and I won't do it for you.
```

End the handoff with a one-line offer:

> "Anything you want to wire up next? OIDC, GitLab, a wildcard
> domain, your own template? I can point you at the right docs
> page and walk you through it."

## Anti-patterns

- **Do not write to the user like a sysadmin.** If a user-facing
  message contains a flag (`--first-user-trial`), an env var
  (`CODER_ACCESS_URL`), or an internal noun ("OAuth provider",
  "ingress", "terraform"), rewrite it. Decide what they need to
  know in plain English, pick a default, and ask for one short
  answer.
- **Do not duplicate Coder's docs.** If a question is about a
  topic that lives on coder.com/docs (OIDC, custom OAuth,
  templates, provisioners, wildcard URL, TLS, upgrades, etc.),
  point at the docs page and apply what it says. Do not transcribe
  it into the skill; it will go stale.
- **Do not run `pkill coder` (or any blanket `kill` against the
  coder binary) when `CODER_AGENT_TOKEN` is set.** That terminates
  the workspace agent the user is connected through. See
  `references/troubleshooting.md#never-pkill-coder-on-a-coder-workspace`.
- **Do not run destructive cleanup commands without an explicit
  user request.** `docker compose down -v`, `helm uninstall coder`,
  and `kubectl delete namespace coder` permanently destroy the
  database and every workspace built from it.
- **Do not pipe `install.sh` to `sudo sh` unless the user asked
  for a system-wide install.** Default to user-local where
  possible.
- **Do not isolate `CODER_CONFIG_DIR` by default.** Only isolate
  when the host already has a Coder login pointing somewhere the
  user wouldn't want overwritten.
- **Do not assume Docker.** Ask the infrastructure question.
  Don't silently default; even when Docker is installed, the
  user may want Kubernetes or a direct install.
- **Do not echo cloud credentials, OAuth client secrets,
  provisioner keys, or the admin password back to the user.**
  Confirm receipt with `[set]` or a redacted form.
- **Do not opt the user into the upstream enterprise-trial
  license flow unless they explicitly asked.** Always pass
  `--first-user-trial=false` to `coder login` and never set
  `CODER_FIRST_USER_TRIAL=true`. The signup-time path collects
  PII (name, phone, job title, company, country, dev count) and
  POSTs it to Coder's licensor; there is no consent UX in the
  skill for that. If a user later wants Premium features,
  `POST /api/v2/licenses` and `coder licenses add` accept a JWT
  they request themselves.
- **Do not skip the `/healthz` readiness probe.** A successful
  `coder server` exit doesn't mean the API is up.
- **Do not run `coder server` in a foreground that ties up the
  chat.** Background it and tail the log.
- **Do not run the GitHub device-flow scripts back to back in
  one tool call.** Tool runners buffer shell stdout until the
  command exits. A fetch immediately followed by a poll prints
  the `user_code` early, then sits in a 15-minute polling loop,
  so the code stays in the buffer until the loop times out and
  the user never sees it. Run
  `scripts/github-device-fetch.sh`, send the user a chat message
  with the URL and code from `$STATE_DIR/github-device.env`,
  wait for them to acknowledge, then run
  `scripts/github-device-poll.sh` as a separate tool call. See
  `references/first-user-github-device.md`.
- **Do not inline the device-flow shell into the chat.** The
  scripts under `scripts/` are the source of truth. Don't paste
  their contents back into Phase 4 or copy fragments of them
  inline; call them by path. Inlining drifts from the bundled
  version on every change and skips the trap-based cleanup.
- **Do not narrate "the skill" at the user.** They asked you to
  install Coder; they didn't subscribe to the implementation.
  Never say "this skill", "the setup skill", "I ran the skill",
  or "the skill saved ...". Use first person about what was
  installed ("I installed Coder", "setup wrote credentials to
  ...") in every user-facing message and in the final handoff.
- **Do not paste the `<one of: ...>` placeholders at the user.**
  The angle-bracket alternatives in the Phase 7 templates are
  notes to you. Pick the single command pair that matches how
  Coder is actually running (host / Docker compose / systemd /
  Kubernetes) before printing.
- **Do not leave OAuth scratch files lying around.** The GitHub
  device-flow recipe writes a cookie jar and an env file under
  `$STATE_DIR/github-device.*`. Both step 1 and step 3 must
  install `trap` cleanups; step 3 must always remove them on
  exit, success or failure. They contain OAuth state and have
  no value once the session token is captured.
- **Do not disable telemetry on the user's behalf.** It defaults
  to on, and Coder strips PII before sending. The user can opt
  out themselves with `CODER_TELEMETRY_ENABLE=false`; don't ask
  them and don't decide for them.

## References

This skill keeps two reference files and two scripts. Everything
else (OIDC, custom OAuth, GitLab, wildcard URL, TLS termination,
external provisioners, template authoring, install layouts,
upgrades) is on coder.com/docs and should be read from there.

- [`references/first-user-github-device.md`](references/first-user-github-device.md):
  the GitHub device-code flow protocol used in Phase 4 (when to
  use it, the three-tool-call structure, common failures).
  Bespoke, not in upstream docs.
- [`references/troubleshooting.md`](references/troubleshooting.md):
  skill-specific safety notes (never `pkill coder` on a Coder
  workspace, NixOS firewall on the docker bridge, the
  `host.docker.internal` loopback issue).
- [`scripts/github-device-fetch.sh`](scripts/github-device-fetch.sh):
  step 1 of the device flow. Primes the OAuth cookies, fetches
  the device code, writes `$STATE_DIR/github-device.{jar,env}`.
- [`scripts/github-device-poll.sh`](scripts/github-device-poll.sh):
  step 3 of the device flow. Polls the callback, writes the
  session, cleans up scratch files.

For everything else, navigate <https://coder.com/docs/llms.txt>.
