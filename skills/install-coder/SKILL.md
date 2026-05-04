---
name: install-coder
description: Install and bootstrap a Coder (coder/coder) deployment end-to-end from the CLI without using the web UI. Use when the user wants to "install Coder", "set up Coder", "run Coder locally / in Docker / on Kubernetes / on a VM", "bootstrap the first admin user from the terminal", "push a starter template", or otherwise get a working Coder deployment with one or more workspaces ready to go. Wraps the canonical install.sh, drives `coder login` for non-interactive first-user setup, pushes a starter template, and (optionally) creates a first workspace.
---

# install-coder

End-to-end install and first-run setup for a Coder deployment without
ever opening the Coder web UI.

The web UI works fine for setup. This skill exists so the user can run
one scripted, repeatable, CLI-only path: install, start the server,
bootstrap the admin user, push a starter template, optionally create a
workspace, and surface the credentials. It is the right path for
demos, headless boxes, automation, and anyone who explicitly says they
don't want to touch the UI.

## When to use this skill

Activate when the user says any of:

- "Install Coder", "set up Coder", "get me started with Coder",
  "bootstrap Coder".
- "Run Coder on this machine", "run Coder in Docker", "deploy Coder
  on Kubernetes", "Coder on AWS / GCP / Azure / DigitalOcean".
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

1. **Discover** the target environment and what the user wants.
2. **Install** the Coder binary or Helm chart via `install.sh`.
3. **Start** the Coder server.
4. **Bootstrap** the first admin user with `coder login --first-user-*`.
5. **Template**: push a starter that matches the chosen infrastructure.
6. **Workspace** (optional): create the user's first workspace.
7. **Summarize** with credentials, URLs, and next steps.

### Phase 1: Discover

**Stop first if you are running inside a Coder workspace.** When the
environment has `CODER_AGENT_TOKEN`, `CODER_WORKSPACE_NAME`, or
`CODER=true`, you are inside someone's workspace. Killing `coder`
processes here will sever the workspace agent and disconnect the
user. Refuse to install a *server* in this case unless the user
explicitly asked for nested Coder. Containerize the test (Docker
compose in a sub-directory) or pick a different host. Read
`references/troubleshooting.md#never-pkill-coder-on-a-coder-workspace`
before touching anything.

Detect first, then ask only what you can't infer:

```sh
# Refuse to proceed with a host install if these are set.
env | grep -E '^(CODER_AGENT_TOKEN|CODER_WORKSPACE_NAME|CODER)=' || true

uname -sm
command -v apt-get dnf yum apk brew zypper pacman 2>/dev/null
docker version --format '{{.Server.Version}}' 2>/dev/null
kubectl config current-context 2>/dev/null
helm version --short 2>/dev/null
coder --version 2>/dev/null
systemctl is-active coder 2>/dev/null
test -f "$HOME/.config/coderv2/url" && cat "$HOME/.config/coderv2/url"
```

Then ask only what you still need:

- **Install target**: standalone host (recommended for solo or single
  VM), Docker compose, or Kubernetes via Helm.
- **Access URL**: a real domain, `http://localhost:7080` for local-only,
  or the built-in tunnel (default if you pass nothing). Never proceed
  without a clear answer; access-URL drift is the single most common
  cause of confused users.
- **First-user credentials**: email, username, optional full name, and a
  password. Generate a strong password if the user has no preference;
  print it once at the end of Phase 7.
- **Starter template**: choose from the matrix in
  `references/templates.md`. Default to the template that matches the
  infrastructure (Docker -> `docker`, Kubernetes -> `kubernetes`,
  EC2 -> `aws-linux`, etc.).
- **Create a workspace?**: yes/no. Default yes for solo local installs;
  default no for shared, multi-user setups.

If the user has not expressed a preference, propose a default plan and
ask for a single yes/no confirmation before doing anything that mutates
the system.

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

Verify with `coder --version`. Exit criterion: the binary runs.

### Phase 3: Start the server

Standalone:

```sh
coder server --access-url "$ACCESS_URL" --http-address 127.0.0.1:7080
```

If the user wants the built-in tunnel for a quick local demo, omit
`--access-url`. Tell the user up front that the tunnel exposes the
deployment over the internet via `*.try.coder.app` until a real access
URL is set.

Run the server in the background and capture logs to a file. Three
options, pick the first that fits:

- **systemd**: the install script can register a `coder` service. Use
  it on production-like Linux hosts.
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

### Phase 4: Bootstrap the first admin user

This is the step that makes "no UI" possible. Use `coder login` with
`--first-user-*` flags, **including `--first-user-trial=false`**: if
neither the flag nor `CODER_FIRST_USER_TRIAL` is set, the CLI prompts
on stdin and the headless flow hangs.

```sh
coder login "$ACCESS_URL" \
  --first-user-email    "$EMAIL" \
  --first-user-username "$USERNAME" \
  --first-user-full-name "$FULL_NAME" \
  --first-user-password "$PASSWORD" \
  --first-user-trial=false
```

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

### Phase 5: Push a starter template

Pick the template that matches the install target. The full matrix
with required parameters lives in `references/templates.md`.

```sh
TEMPLATE_DIR="$(mktemp -d)/$TEMPLATE_NAME"
coder templates init --id "$TEMPLATE_ID" "$TEMPLATE_DIR"
( cd "$TEMPLATE_DIR" && coder templates push "$TEMPLATE_NAME" --yes )
coder templates list
```

Cloud templates need real provider credentials before `templates push`
will succeed (or before workspaces will build, depending on the
template). Collect them up front and pass them to the **server's**
environment, not the CLI's. Never put cloud secrets in
`terraform.tfvars`; they leak into every template version. See
`references/templates.md#provider-credentials`.

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

### Phase 6: Create a workspace (optional)

If the user wants a workspace right away:

```sh
coder create "$WORKSPACE_NAME" --template "$TEMPLATE_NAME" --yes
```

Pass parameters with repeated `--parameter "name=value"` if the
template has any required ones. Show them with `coder templates show
$TEMPLATE_NAME` before guessing.

For the `docker` starter, no parameters are required. For
`kubernetes`, the namespace must already exist (the template assumes
the server has RBAC to create pods in it).

### Phase 7: Summarize

Print one block at the end with:

- Access URL.
- Username, email, password (if generated).
- Template name and ID.
- Workspace name (if created) and how to connect:
  `coder ssh "$WORKSPACE_NAME"` or `coder open vscode "$WORKSPACE_NAME"`.
- Where logs live (server log file, kubectl namespace, etc.).
- The exact command to stop the deployment cleanly:
  - Standalone (nohup): `kill "$(cat ~/.coder-server.pid)"`.
  - systemd: `sudo systemctl stop coder`.
  - Docker compose: `docker compose down` (`-v` also drops the DB).
  - Helm: `helm uninstall coder -n coder`.

The password has no recovery path now that the UI bootstrap is
closed. Print it once and let the user record it.

## Anti-patterns

- **Do not run `pkill coder` (or any blanket `kill` against the coder
  binary) when `CODER_AGENT_TOKEN` is set.** That terminates the
  workspace agent the user is connected through. See
  `references/troubleshooting.md#never-pkill-coder-on-a-coder-workspace`.
  This is the single most common way to disconnect yourself from a
  Coder-on-Coder install attempt.
- Do not pipe `install.sh` to `sudo sh` unless the user asked for a
  system-wide install. Default to user-local where possible.
- Do not edit `/etc/systemd/system/coder.service` by hand. Use the
  installer's unit and override with drop-ins.
- Do not store the admin password in plaintext on disk in a path the
  user can't easily redact. If you must persist it, use mode 0600
  under `~/.config/coder-install/credentials` and tell the user.
- Do not start a trial license unless the user asked. Default to
  `--first-user-trial=false`.
- Do not skip the `/healthz` readiness probe. A successful `coder
  server` exit doesn't mean the API is up.
- Do not run `coder server` in a foreground that ties up the chat.
  Background it and tail the log.
- Do not push a cloud template before the server has its provider
  credentials in scope. The first workspace build will hang.

## References

- [`references/install-methods.md`](references/install-methods.md) -
  full per-target install matrix, with verification.
- [`references/templates.md`](references/templates.md) - starter
  template matrix and required variables.
- [`references/first-user.md`](references/first-user.md) - `coder
  login` flags, env vars, and edge cases.
- [`references/troubleshooting.md`](references/troubleshooting.md) -
  readiness probe failures, port conflicts, sudo and SELinux issues,
  Helm rollback, cleanup.

For background on Coder concepts (templates vs workspaces vs agents),
the canonical docs at <https://coder.com/docs> are authoritative.
This skill does not duplicate that material.
