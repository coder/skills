---
name: setup
description: Install and bootstrap a Coder (coder/coder) deployment end-to-end from the CLI without using the web UI. Handles both trial setups (auto-tunnel, no TLS) and production setups (real domain, TLS, optional wildcard URL, optional custom external auth, optional external provisioner). Use when the user wants to "install Coder", "set up Coder", "deploy Coder", "run Coder locally / in Docker / on Kubernetes / on a VM", "stand up Coder for my team", "put Coder behind HTTPS / a real domain", "bootstrap the first admin user from the terminal", "push a starter template", or otherwise get a working Coder deployment with one or more workspaces ready to go. Wraps the canonical install.sh, drives `coder login` for non-interactive first-user setup (or hands off to GitHub sign-in on fresh deployments), pushes a starter template, and (optionally) creates a first workspace.
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

## Workflow

Follow these phases in order. Each has a clear exit criterion. Confirm
before any destructive action (system package install, opening ports,
overwriting kubeconfigs, deleting volumes).

1. **Discover** the target environment, deployment mode, and what the
   user wants.
2. **Install** the Coder binary or Helm chart via `install.sh`.
3. **Start** the Coder server.
4. **Bootstrap** the first admin user with `coder login --first-user-*`.
5. **External services** (production only; optional): register external
   auth, run an external provisioner. Skip in trial mode.
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
(production should pin a recent release; trial is fine on whatever
is there).

**Isolate the trial from an existing login.** If
`~/.config/coderv2/url` exists and points somewhere the user does
NOT want to overwrite (e.g. `https://dev.coder.com`, an internal
team deployment), set isolated config and cache directories for
every `coder` and `coder server` invocation in this session:

```sh
export CODER_CONFIG_DIR="$HOME/.config/coderv2-trial"
export CODER_CACHE_DIRECTORY="$HOME/.cache/coder-trial"
mkdir -p "$CODER_CONFIG_DIR" "$CODER_CACHE_DIRECTORY"
```

Ask the user before touching the existing config; the default is
to isolate. Without isolation the trial's `coder login` overwrites
the stored URL and session, kicking the user out of their real
deployment.

#### Pick the deployment mode

Decide between **trial** and **production** before anything else.
Almost every later choice (access URL, database, TLS, external auth,
provisioner topology) follows from the mode.

| Signal                                                | Mode       |
|-------------------------------------------------------|------------|
| "Try Coder", "kick the tires", "demo", "play with it" | trial      |
| Localhost, single host, single user, throwaway        | trial      |
| Real domain named (`coder.example.com`)               | production |
| HTTPS / TLS / Let's Encrypt / cert-manager mentioned  | production |
| "For my team", "for the company", "staging"           | production |
| Cloud workspaces with shared cloud account            | production |

When the signals conflict, ask. Don't guess.

`references/production.md` is the entry point for the production
path. Read it before continuing into Phase 2 if you've picked
production.

#### Pick the first-user auth method

Fresh deployments auto-enable a default "Continue with GitHub"
button on the dashboard, backed by Coder's own OAuth App. The first
user to sign in (any path, any method) is auto-promoted to Owner.
That means you have two ways to bootstrap:

- **GitHub** (recommended for solo and small-team trials). The user
  opens the access URL once, clicks "Continue with GitHub", and is
  the Owner of the deployment. No password to record. Skill skips
  the `coder login --first-user-*` flow entirely.
- **Username and password.** Fully scripted; no browser involved.
  Skill generates a strong password, writes the credentials to
  `~/.config/coder-install/credentials` (mode 0600) so the user has
  a recovery path, and uses `coder login --first-user-*`.

Ask the user once: "Sign in with GitHub, or generate a username and
password?". Default to GitHub when the access URL will be
browser-reachable (the auto-tunnel and `localhost` from the same
machine both qualify); fall back to username/password if the user
says no, asks for fully scripted setup, or runs in headless
(`claude -p`) mode where there's no human to click the button.

For the username/password path, prefill the email from git config
if present:

```sh
EMAIL_DEFAULT="$(git config --global --get user.email 2>/dev/null || true)"
```

Ask the user to confirm or override.

#### Things to ask, by mode

**Trial mode** (defaults that are usually fine):

- **Install target**: standalone host, Docker compose, or Kubernetes
  via Helm. Default to compose if Docker is available; otherwise
  standalone.
- **Access URL**: do **not** ask. The skill defaults to letting
  `coder server` open its built-in `*.try.coder.app` tunnel
  automatically, which works on any host with internet egress and
  sidesteps host-firewall and docker-bridge issues. Fall back to
  `http://localhost:7080` only if the tunnel can't initialize
  (offline host, blocked egress). See Phase 3 for the detection
  recipe. The trial is publicly reachable on a non-guessable
  subdomain protected by the admin's auth; that's an intentional
  tradeoff in exchange for one-shot reliability.
- **First-user auth**: see above.
- **Starter template**: default to `docker` for compose / standalone
  with Docker; `kubernetes` for Helm.
- **Create a workspace?**: default yes for trial.

**Production mode**: collect every input before mutating anything.
Minimum input set:

- Real HTTPS access URL (`https://coder.example.com`); never the
  tunnel.
- TLS termination point: at the Coder server (PEM files) or at a
  reverse proxy / ingress. Pick one.
- Managed PostgreSQL connection string. Built-in PG is trial-only.
- First-user auth method. The default GitHub provider works in
  production too; only ask for username/password if GitHub login
  doesn't fit the org.
- Starter template matching the deployment's Docker / Kubernetes /
  cloud target. See `references/templates.md`.

Ask **only if relevant** (don't surface these as required):

- **Wildcard URL** (`*.coder.example.com`). Needed for subdomain
  app routing, which is what backs `coder port-forward` and many
  embedded `coder_app` ports. If the user doesn't need
  port-forwarding or hits no apps that break under path-based
  proxying, omit it. Most teams want it; ask once.
- **Custom external auth provider** (GHES, GitLab, a non-default
  GitHub OAuth App). The default github.com provider is on
  automatically; only register a custom one if the user has a
  reason. Ask after the deployment is up, not in Phase 1.
- **External provisioner**. Required only when cloud workspaces
  must run with isolated credentials. Ask if the chosen template
  needs cloud creds; otherwise skip.

Full decision matrix and order of operations:
`references/production.md`. Per-topic detail in `wildcard-tls.md`,
`external-auth-github.md`, and `external-provisioner.md`.

If the user has not expressed a preference, propose a default plan
and ask for a single yes/no confirmation before doing anything that
mutates the system. In production mode, also echo back the planned
DNS records, env vars (without secret values), and ingress hostnames
so the user can spot-check before the server starts.

**Headless mode** (`claude -p`, no interactive shell): the user
cannot answer a yes/no prompt and cannot click a browser button.
Treat the original prompt as the approval. For first-user auth,
default to username/password (browser GitHub flow needs a human).
If the prompt doesn't include the required values for production
(access URL, TLS termination, optional wildcard / OAuth /
provisioner key), refuse with a one-line error listing what's
missing rather than blocking on stdin.

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

#### Trial path

Default: let `coder server` open its built-in tunnel. The tunnel is
the most-reliable trial path because it routes around host-firewall
and docker-bridge issues that bite local-only binds. Don't pass
`--access-url`; the server will pick a `*.try.coder.app` URL and
print it to stderr.

```sh
nohup coder server \
  > "$HOME/.coder-server.log" 2>&1 &
echo $! > "$HOME/.coder-server.pid"
```

Watch the log for either:

- A `https://<id>.try.coder.app` access URL appearing within ~30
  seconds. The tunnel is up; record the URL and continue to Phase 4.
- `create tunnel: ...` errors (no internet egress, blocked DNS,
  `*.try.coder.app` not reachable). Stop the server and retry with
  the localhost fallback below.

```sh
# Wait for either readiness or a hard tunnel error.
for _ in $(seq 1 60); do
  ACCESS_URL="$(grep -oE 'https://[a-z0-9-]+\.try\.coder\.app' \
    "$HOME/.coder-server.log" | head -1)"
  if [ -n "$ACCESS_URL" ] && \
     curl -fsS "$ACCESS_URL/healthz" >/dev/null 2>&1; then
    break
  fi
  if grep -q 'create tunnel' "$HOME/.coder-server.log"; then
    ACCESS_URL=""
    break
  fi
  sleep 1
done
```

**Localhost fallback** (no internet egress, or user explicitly asked
for local-only):

```sh
kill "$(cat "$HOME/.coder-server.pid")" 2>/dev/null || true
ACCESS_URL="http://localhost:7080"
nohup coder server \
  --access-url "$ACCESS_URL" \
  --http-address 0.0.0.0:7080 \
  > "$HOME/.coder-server.log" 2>&1 &
echo $! > "$HOME/.coder-server.pid"
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

### Phase 4: Bootstrap the first admin user

Fresh deployments auto-promote whoever signs in first to Owner. The
two paths produce the same end state; pick the one that matches the
auth method chosen in Phase 1.

#### GitHub path

Fresh deployments auto-enable a default GitHub OAuth app on the
dashboard. The user opens the access URL once, clicks "Continue
with GitHub", lands back in Coder as Owner. No password to record,
no `coder login --first-user-*` invocation.

```text
Open the dashboard:

  $ACCESS_URL

Click "Continue with GitHub", authorize the OAuth app, and return
to Coder. You'll be the Owner of this deployment.
```

While the user does that, link the local CLI to the deployment so
the rest of the skill can run admin commands:

```sh
coder login "$ACCESS_URL"
```

This opens a browser to the same access URL; the user signs in once
and the CLI captures the session token. Verify:

```sh
coder whoami
coder users list
```

`users list` shows exactly one row with `OWNER` in the roles column,
the email or login from GitHub.

#### Username and password path

Use `coder login` with `--first-user-*` flags, **including
`--first-user-trial=false`**: if neither the flag nor
`CODER_FIRST_USER_TRIAL` is set, the CLI prompts on stdin and the
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

The password has no recovery path. Persist it to a mode-0600 file at
`~/.config/coder-install/credentials` immediately after `coder login`
succeeds, so the user has a way back in:

```sh
umask 0077
mkdir -p "$HOME/.config/coder-install"
printf 'url=%s\nusername=%s\nemail=%s\npassword=%s\n' \
  "$ACCESS_URL" "$USERNAME" "$EMAIL" "$PASSWORD" \
  > "$HOME/.config/coder-install/credentials"
echo "saved to $HOME/.config/coder-install/credentials (mode 600)"
```

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

For trial-license setup, persistent tokens, and the full failure
list, read `references/first-user.md`.


### Phase 5: External services (production only)

Skip this phase entirely in trial mode.

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
The usual cause on a single-host Linux setup is the trial-path
binding to `127.0.0.1`, which is unreachable from the workspace
container.
### Phase 8: Summarize

Print one block at the end, clearly delimited. Substitute the
placeholders for the values from this run; don't print fields that
don't apply.

For the **GitHub auth path**:

```text
=== Coder is ready ===
Access URL:      $ACCESS_URL
Wildcard URL:    $WILDCARD_URL    (production, if configured)
Sign in with:    GitHub (open the access URL and click "Continue with GitHub")
Template:        $TEMPLATE_NAME
Workspace:       $WORKSPACE_NAME  (or: not created)
Server log:      <command for the install method, see below>
Stop:            <command for the install method, see below>
```

For the **username/password path**:

```text
=== Coder is ready ===
Access URL:      $ACCESS_URL
Wildcard URL:    $WILDCARD_URL    (production, if configured)
Username:        $USERNAME
Email:           $EMAIL
Password:        $PASSWORD        (saved to ~/.config/coder-install/credentials)
Template:        $TEMPLATE_NAME
Workspace:       $WORKSPACE_NAME  (or: not created)
Server log:      <command for the install method, see below>
Stop:            <command for the install method, see below>
```

`Stop:` command by install method:

- nohup (trial): `kill "$(cat ~/.coder-server.pid)"`
- systemd: `sudo systemctl stop coder`
- Docker compose: `docker compose down` in the deployment directory
  (add `-v` only when the user has explicitly asked to delete the
  database).
- Helm: `helm uninstall coder -n coder`.

`Server log:` command by install method:

- nohup (trial): `tail -f $HOME/.coder-server.log`
- systemd: `journalctl -u coder -f`
- Docker compose: `docker compose logs -f coder`
- Helm: `kubectl logs -n coder deploy/coder -f`

For production deploys with custom integrations, also remind the
user to record (these don't have a "show me again" command; back
them up out of band):

- A custom GitHub OAuth App's client ID and callback URL, if one
  was registered in Phase 5. The default github.com provider needs
  no recording; it's managed by Coder.
- The external provisioner key fingerprint, if one was generated.
- The TLS cert paths and DNS records.



## Anti-patterns

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
- Do not start a trial license unless the user asked. Default to
  `--first-user-trial=false`.
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
