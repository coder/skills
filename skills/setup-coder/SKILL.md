---
name: setup-coder
description: Install and bootstrap a Coder (coder/coder) deployment end-to-end from the CLI without using the web UI. Handles both trial setups (localhost or Docker, no TLS) and production setups (real domain, wildcard URL, TLS, GitHub external auth, external provisioner). Use when the user wants to "install Coder", "set up Coder", "deploy Coder", "run Coder locally / in Docker / on Kubernetes / on a VM", "stand up Coder for my team", "put Coder behind HTTPS / a real domain", "bootstrap the first admin user from the terminal", "push a starter template", or otherwise get a working Coder deployment with one or more workspaces ready to go. Wraps the canonical install.sh, drives `coder login` for non-interactive first-user setup, optionally registers external auth and an external provisioner, pushes a starter template, and (optionally) creates a first workspace.
---

# setup-coder

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
| GitHub / GitLab / OIDC mentioned                      | production |
| Cloud workspaces with shared cloud account            | production |

When the signals conflict, ask. Don't guess.

`references/production.md` is the entry point for the production
path. Read it before continuing into Phase 2 if you've picked
production.

#### Things to ask, by mode

**Trial mode** (defaults that are usually fine):

- **Install target**: standalone host, Docker compose, or Kubernetes
  via Helm. Default to compose if Docker is available; otherwise
  standalone.
- **Access URL**: pick exactly one. Never proceed without an explicit
  choice.
  1. `http://localhost:<port>` (recommended for trial; workspaces
     reachable only from the host).
  2. The built-in `*.try.coder.app` tunnel (publicly exposed; only if
     the user explicitly asked for a public URL with no DNS work).
- **First-user credentials**: email, username, optional full name, and
  a password. Generate a strong one if the user has no preference;
  see `references/first-user.md#generating-a-password` for a portable
  recipe (`openssl` is not on every host). Print it once at the end
  of Phase 8.
- **Starter template**: default to `docker` for compose / standalone
  with Docker; `kubernetes` for Helm.
- **Create a workspace?**: default yes for trial.

**Production mode**: collect every input before mutating anything.
Minimum input set:

- Real HTTPS access URL (`https://coder.example.com`); never the
  tunnel.
- Wildcard URL (`*.coder.example.com`). Both names must resolve
  before starting.
- TLS termination point: at the Coder server (PEM files) or at a
  reverse proxy / ingress. Pick one.
- Managed PostgreSQL connection string. Built-in PG is trial-only.
- External-auth fields if GitHub / GitLab / etc. is in scope: client
  ID, secret, chosen `CODER_EXTERNAL_AUTH_0_ID`.
- Scoped provisioner key (`coder provisioner keys create`) if cloud
  workspaces are in scope.
- First-user credentials. Don't randomize the password in production;
  let the user pick.
- Starter template matching the cloud (`aws-linux`, `kubernetes`,
  etc.). Helm on Kubernetes is the default install target for
  production; standalone or compose only fits a single-VM deploy.

Full decision matrix and order of operations:
`references/production.md`. Per-topic detail in `wildcard-tls.md`,
`external-auth-github.md`, and `external-provisioner.md`.

If the user has not expressed a preference, propose a default plan
and ask for a single yes/no confirmation before doing anything that
mutates the system. In production mode, also echo back the planned
DNS records, env vars (without secret values), and ingress hostnames
so the user can spot-check before the server starts.

**Headless mode** (`claude -p`, no interactive shell): the user
cannot answer a yes/no prompt. Treat the original prompt as the
approval. If it doesn't include the required values (access URL,
wildcard, TLS termination, OAuth client ID and secret, provisioner
key), refuse with a one-line error listing what's missing rather
than blocking on stdin.

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

```sh
coder server --access-url "$ACCESS_URL" --http-address "$BIND_ADDR"
```

Pick `$BIND_ADDR`:

- `127.0.0.1:7080` if no workspace will be built on this host (e.g.
  user only wants the dashboard up).
- `0.0.0.0:7080` if you plan to push the `docker` starter and create
  a workspace. The workspace agent runs inside a container that
  reaches the server via `host.docker.internal`, which resolves to
  the host's docker bridge IP, not the container's loopback. A
  host-loopback bind is unreachable. See
  `references/troubleshooting.md#workspace-agent-cant-reach-the-server`.

On NixOS specifically, the `nixos-fw` chain drops new connections on
the docker bridge by default; even `0.0.0.0` won't be reachable
until you allow the bridge. If the host is NixOS, prefer Docker
compose (the server runs inside the docker network and skips the
host firewall entirely). See `references/troubleshooting.md#nixos-firewall-blocks-docker-bridge`.

Always pass `--access-url` explicitly, with the value the user picked
in Phase 1. Never omit the flag and rely on the implicit
`*.try.coder.app` tunnel; that tunnel is publicly reachable and the
user must opt into it knowingly.

Run the server in the background and capture logs to a file. Three
options, pick the first that fits:

- **systemd**: the install script can register a `coder` service.
  Use it on production-like Linux hosts.
- **nohup**: minimal, works everywhere.
  ```sh
  nohup coder server --access-url "$ACCESS_URL" \
    > "$HOME/.coder-server.log" 2>&1 &
  echo $! > "$HOME/.coder-server.pid"
  ```
- **tmux**: when the user wants a live log they can attach to.
  ```sh
  tmux new -d -s coder "coder server --access-url '$ACCESS_URL'"
  ```

Wait for readiness by polling `$ACCESS_URL/healthz` until it returns
200. Time out after 60 seconds and surface the server log if it
doesn't become ready.

```sh
for _ in $(seq 1 60); do
  if curl -fsS "$ACCESS_URL/healthz" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
```

#### Production path

The server is configured by env, not flags. Set the access URL,
wildcard URL, TLS, and database connection on the deployment manifest
(Helm values or compose `environment:` block), not as CLI args.

Minimum env for a Helm or compose deploy:

```sh
CODER_ACCESS_URL=https://coder.example.com
CODER_WILDCARD_ACCESS_URL=*.coder.example.com
CODER_PG_CONNECTION_URL=postgres://coder:${PASSWORD}@db.internal:5432/coder?sslmode=require
# TLS at the server (omit if a proxy / ingress terminates):
CODER_TLS_ENABLE=true
CODER_TLS_ADDRESS=0.0.0.0:443
CODER_TLS_CERT_FILE=/etc/coder/tls/fullchain.pem
CODER_TLS_KEY_FILE=/etc/coder/tls/privkey.pem
CODER_REDIRECT_TO_ACCESS_URL=true
```

Roll it out (`helm upgrade`, `docker compose up -d`) and wait for
readiness against the public URL:

```sh
for _ in $(seq 1 120); do
  if curl -fsS https://coder.example.com/healthz >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
```

Verify the wildcard resolves end-to-end:

```sh
curl -fsS https://app-test.coder.example.com/healthz
```

Both must return 200 before continuing. Full env-var matrix and
common failures: `references/wildcard-tls.md`.

### Phase 4: Bootstrap the first admin user

This is the step that makes "no UI" possible. Use `coder login` with
`--first-user-*` flags, **including `--first-user-trial=false`**: if
neither the flag nor `CODER_FIRST_USER_TRIAL` is set, the CLI prompts
on stdin and the headless flow hangs.

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

After this:

- The user exists, has the Owner role, and is in the default
  organization.
- The session token is in the OS keyring on macOS / Windows or in
  `~/.config/coderv2/session` on Linux.
- The server URL is in `~/.config/coderv2/url`.
- Subsequent `coder` commands authenticate automatically.

Verify:

```sh
coder whoami
coder users list
```

`whoami` returns the bootstrapped user. `users list` shows exactly one
row with `OWNER` in the roles column.

For trial-license setup, persistent tokens, and the full failure list,
read `references/first-user.md` before running this phase.

### Phase 5: External services (production only)

Skip this phase entirely in trial mode.

In production, do these in order. Each is independent of the others
but template push (Phase 6) often depends on both.

#### Register external auth (usually GitHub)

Lets templates `coder_external_auth` against GitHub so workspaces
can clone private repos without baked-in PATs. Full walkthrough:
`references/external-auth-github.md`. Summary:

1. Pick a provider ID (`primary-github`).
2. Register a GitHub OAuth App with callback URL
   `https://coder.example.com/external-auth/<id>/callback`.
3. Set on the server:
   ```sh
   CODER_EXTERNAL_AUTH_0_ID=primary-github
   CODER_EXTERNAL_AUTH_0_TYPE=github
   CODER_EXTERNAL_AUTH_0_CLIENT_ID=<id>
   CODER_EXTERNAL_AUTH_0_CLIENT_SECRET=<secret>
   CODER_EXTERNAL_AUTH_GITHUB_DEFAULT_PROVIDER_ENABLE=false
   ```
4. Roll out the deployment.
5. Verify with `GET /api/v2/external-auth`.

#### Run an external provisioner

Keeps cloud credentials off the Coder server and lets you scale
parallel builds. Full walkthrough: `references/external-provisioner.md`.
Summary:

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

If the deployment only ever runs Docker templates against the Coder
host's own Docker socket, skip this; the in-server provisioner is
fine.

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

Print one block at the end, clearly delimited. Pick the `Stop:`
command from the install method below and substitute it before
showing the block to the user, so they don't see a `kill` command
when they ran `helm install`.

```text
=== Coder is ready ===
Access URL:      $ACCESS_URL
Wildcard URL:    $WILDCARD_URL    (production only)
Username:        $USERNAME
Email:           $EMAIL
Password:        $PASSWORD        (record now; no recovery path)
Template:        $TEMPLATE_NAME
Workspace:       $WORKSPACE_NAME  (or: not created)
External auth:   $EXTERNAL_AUTH_ID (or: not configured)
Provisioner:     external @ $PROVISIONER_HOST (or: built-in)
Server log:      $SERVER_LOG_PATH (or: managed by orchestrator)
Stop:            <command for the install method, see below>
```

`Stop:` command by install method:

- nohup (trial): `kill "$(cat ~/.coder-server.pid)"`
- systemd: `sudo systemctl stop coder`
- Docker compose: `docker compose down` in the deployment directory
  (add `-v` only when the user has explicitly asked to delete the
  database).
- Helm: `helm uninstall coder -n coder`.

`Server log:` is `$HOME/.coder-server.log` only for the trial nohup
path. For systemd use `journalctl -u coder`; for compose use
`docker compose logs coder`; for Helm use
`kubectl logs -n coder deploy/coder`. Substitute before showing.

For production deploys, also remind the user to record:

- The GitHub OAuth App's client ID / callback URL (rotating the
  secret later requires both).
- The external provisioner key fingerprint.
- The TLS cert and DNS records.

These don't have a "show me again" command; back them up out of
band.

**Password handling.** Never write the password to a file unless the
user explicitly asks ("save the password", "write it to disk", etc.).
When they do, use a secure mode-0600 write that doesn't race:

```sh
umask 0077
mkdir -p "$HOME/.config/coder-install"
printf 'url=%s\nusername=%s\npassword=%s\n' \
  "$ACCESS_URL" "$USERNAME" "$PASSWORD" \
  > "$HOME/.config/coder-install/credentials"
echo "saved to $HOME/.config/coder-install/credentials (mode 600)"
```

The password has no recovery path now that the UI bootstrap is
closed. Print it once and let the user record it.

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
  `/etc/systemd/system/coder.service.d/override.conf`.
- Do not write the admin password to disk silently. Print it once at
  the end of Phase 8 and only persist it after the user opts in. When
  you do persist it, use the `umask 0077` recipe in Phase 8.
- Do not echo cloud credentials, OAuth client secrets, provisioner
  keys, or the admin password back to the user. Confirm receipt with
  `[set]` or a redacted form.
- Do not start a trial license unless the user asked. Default to
  `--first-user-trial=false`.
- Do not omit `--access-url`. The implicit `*.try.coder.app` tunnel
  exposes the deployment publicly and must be an explicit choice.
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
- Do not run a production server without `CODER_WILDCARD_ACCESS_URL`
  if the user expects `coder_app` ports, embedded VS Code, or web
  terminals to work. The skill's Phase 1 collects the wildcard URL
  for production mode; don't skip it.
- Do not register a custom GitHub external auth provider while
  `CODER_EXTERNAL_AUTH_GITHUB_DEFAULT_PROVIDER_ENABLE` is left at the
  default `true`. The dashboard ends up with two "Continue with
  GitHub" buttons.

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
