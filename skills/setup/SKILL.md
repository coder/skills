---
name: setup
description: >
  Install, deploy, or bootstrap a new Coder (coder/coder)
  deployment end-to-end. Use for first-time setup on Docker,
  Kubernetes/Helm, a VM, cloud, HTTPS/domain setup, creating the
  first admin, pushing a starter template, or building the first
  workspace. Do not use for upgrades, debugging an existing
  deployment, editing an existing template, or configuring OAuth/OIDC
  on a running deployment.
---

# Setup

Install Coder and complete first-run setup without making the user
learn the CLI or web UI.

## Source of Truth

Read current upstream docs before using topic-specific details:

- <https://coder.com/docs/llms.txt> for the docs index.
- <https://coder.com/docs/llms-full.txt> only when the index is not
  enough.

Most product details belong upstream, not in this skill. Use the docs
for install methods, Helm values, TLS, wildcard domains, templates,
OIDC, OAuth, external provisioners, upgrades, backups, telemetry, and
Premium features. Apply the docs yourself; do not send the user to
documentation unless they explicitly ask.

This skill keeps only the install flow, user interaction rules, and a
few setup-specific gotchas.

## User Interaction

The user asked for a working Coder deployment, not a Coder lesson.
Keep messages short and plain:

- Ask one decision at a time unless using a structured picker.
- Prefer a sensible default, then ask for confirmation.
- Explain a Coder concept before naming it when the user is new.
- Keep flags, env vars, config keys, raw logs, and docs URLs out of
  user-facing questions and handoffs.
- Do not mention "skill" or "setup skill" to the user.
- Do not hand the user a CLI walkthrough as next steps; offer to do
  follow-up work in plain English.

Useful translations:

- Access URL: the web address people open to use Coder.
- Wildcard URL: DNS that gives apps inside workspaces their own
  subdomains.
- Workspace: one dev environment for one person.
- Template: a recipe Coder uses to build a workspace.
- Owner: the first admin account.
- External auth: letting workspaces sign in to GitHub, GitLab, etc.
  so they can clone private repos.

If the user asks for implementation detail, answer technically for that
turn, then return to plain English.

## Workflow

Each phase has an exit criterion. Confirm before destructive actions
such as installing system packages, opening ports, overwriting
kubeconfigs, deleting volumes, or replacing existing Coder state.

### 1. Discover

Get five answers before probing the host:

1. Have they used Coder before?
2. Is this a quick-start/demo or a long-term/team deployment?
3. Where should Coder run: Docker, Kubernetes/Helm, directly on the
   host, or something else?
4. Should the first admin sign in with GitHub or with email/password?
5. Should setup push a starter dev environment and build the first
   workspace?

Use the runner's structured question tool when available. If it only
supports four questions at once, ask the first four together and the
workspace question second. If no structured tool exists, ask the five
questions in one concise chat message.

After answers arrive, probe quietly:

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

Then show one short plan paragraph and ask for a yes/no before
mutating the system.

Mappings:

- Quick-start/demo: use the built-in `*.try.coder.app` tunnel by
  default.
- Production/team: collect domain, HTTPS strategy, Postgres choice,
  wildcard preference, and service manager. Read current install and
  admin setup docs before proposing the plan.
- Docker, Kubernetes/Helm, and direct host installs are driveable.
- Rancher, OpenShift, cloud marketplace, and air-gapped installs must
  follow their current docs rather than a memorized recipe.
- Direct installs can still push the Docker starter if Docker is
  present; do not pick Kubernetes without a valid kube context.
- In headless mode, treat the original request as approval, default to
  email/password sign-in, and fail fast if production inputs are
  missing.

If prior quick-start state exists and the user is moving to production,
ask whether to stop it. Use its PID, compose, systemd, or Helm handle;
never use a blanket `pkill coder`.

### 2. Install

Before installing, check whether this shell is already inside a Coder
workspace:

```sh
test -n "${CODER_AGENT_TOKEN-}${CODER_WORKSPACE_NAME-}"
```

If so, refuse a host install unless the user explicitly asked for
nested Coder. Docker compose in a scoped directory or Helm against a
separate cluster context is acceptable.

Use the canonical installer for direct installs:

```sh
curl -fsSL https://coder.com/install.sh | sh
```

For user-local installs:

```sh
curl -fsSL https://coder.com/install.sh \
  | sh -s -- --method standalone --prefix "$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
```

For Docker compose and Helm, read the current upstream install page and
apply it. For production, prefer stable releases unless the user asked
otherwise. Verify the phase with `coder --version`.

### 3. Start

Create one state directory for generated files:

```sh
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/coder-install"
mkdir -p "$STATE_DIR"
```

Quick-start direct host launch:

```sh
nohup coder server > "$STATE_DIR/server.log" 2>&1 &
echo $! > "$STATE_DIR/server.pid"
```

Do not pass an access URL for the quick-start tunnel. Parse the server
log line after `View the Web UI:` and wait for `/healthz`. If the
tunnel cannot initialize, restart on `http://localhost:7080` with
`--http-address 0.0.0.0:7080`; workspace containers cannot reach a
host-loopback-only bind.

For Docker compose, systemd, and Helm, let that supervisor own the
process and logs. For production, configure the manifest or service
environment from the current docs, then wait for `/healthz` against the
public URL. Verify wildcard DNS if configured.

### 4. Create the Admin

The first user becomes Owner.

Before login, protect existing CLI sessions. Only set an isolated
`CODER_CONFIG_DIR` when the default config already points at a
different real deployment:

```sh
default_dir="${XDG_CONFIG_HOME:-$HOME/.config}/coderv2"
if [ -f "$default_dir/url" ]; then
  existing="$(cat "$default_dir/url")"
  case "$existing" in
    "$ACCESS_URL"|"") : ;;
    *)
      export CODER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/coderv2-quickstart"
      export CODER_CACHE_DIRECTORY="${XDG_CACHE_HOME:-$HOME/.cache}/coderv2-quickstart"
      mkdir -p "$CODER_CONFIG_DIR" "$CODER_CACHE_DIRECTORY"
      ;;
  esac
fi
```

Prefer GitHub device flow for fresh deployments when available. Check
`/api/v2/users/authmethods` and
`/api/v2/users/oauth2/github/device`; if either says device flow is not
available, fall back to email/password.

Run device flow in three distinct steps:

1. Run `scripts/github-device-fetch.sh`.
2. Send the user the verification URL and code in chat, then wait for
   acknowledgement.
3. Run `scripts/github-device-poll.sh`.

Do not combine fetch and poll in one shell call; tool runners usually
buffer stdout until the poll exits. Read
[`references/first-user-github-device.md`](references/first-user-github-device.md)
only if the flow fails or you need protocol detail.

For email/password, generate a strong password, pass it through the
environment, and always disable the upstream enterprise-trial prompt:

```sh
export CODER_FIRST_USER_PASSWORD="$PASSWORD"
coder login "$ACCESS_URL" \
  --first-user-email "$EMAIL" \
  --first-user-username "$USERNAME" \
  --first-user-full-name "$FULL_NAME" \
  --first-user-trial=false
unset CODER_FIRST_USER_PASSWORD
```

Persist generated credentials mode `0600` under `$STATE_DIR` and verify
with `coder whoami` and `coder users list`.

### 5. Push a Starter Template

Pick the starter that matches the chosen infrastructure. Read the
current template docs before assuming IDs or required variables.

```sh
TEMPLATE_DIR="$(mktemp -d)/$TEMPLATE_NAME"
coder templates init --id "$TEMPLATE_ID" "$TEMPLATE_DIR"
coder templates push "$TEMPLATE_NAME" -d "$TEMPLATE_DIR" --yes
coder templates list
```

Use variables files for non-secret values. Never echo secrets, place
them in `terraform.tfvars`, or pass them as plain `--variable` values;
use Coder's secret-variable pattern or external provisioners when
credentials must stay off the server.

### 6. Build a Workspace

Skip this phase if the user declined the first workspace.

Before `coder create`, pull the template and inspect
`data "coder_parameter"` blocks:

```sh
TEMPLATE_PULL="$(mktemp -d)/$TEMPLATE_NAME"
coder templates pull "$TEMPLATE_NAME" "$TEMPLATE_PULL"
```

Pass every required parameter explicitly. Use `[]` for required list
parameters with an obvious "none" value, the first option for simple
single-select enums, and ask only when no sensible value exists.

```sh
coder create "$WORKSPACE_NAME" \
  --template "$TEMPLATE_NAME" \
  --parameter 'jetbrains_ides=[]' \
  --yes
```

Wait until the workspace agent reaches `ready`; a successful build is
not enough. If the agent remains in `connecting`, read
[`references/troubleshooting.md`](references/troubleshooting.md).

### 7. Hand Off

End with one short plain-English block containing:

- The browser URL.
- The sign-in credentials or confirmation that GitHub sign-in is done.
- Where setup wrote local files.
- Exactly one logs command and one stop command matching the real
  supervisor: host PID/log, Docker compose, systemd, or Helm.
- Whether the starter workspace was created.
- A one-line offer to wire up Coder Agents.

Do not include docs URLs, raw upstream `.md` links, alternative command
placeholders, or a list of CLI commands for the user to try.

If the user accepts the Coder Agents offer, read
[`references/coder-agents.md`](references/coder-agents.md) and follow
that recipe. Do not ask the user to paste LLM API keys into chat; have
them export a key in the shell and read it from the environment.

## Safeguards

- Do not assume Docker. Ask where Coder should run.
- Do not use blanket process kills for `coder`, especially inside a
  Coder workspace.
- Do not run destructive cleanup without explicit approval.
- Do not isolate `CODER_CONFIG_DIR` unless an existing login points
  elsewhere.
- Do not opt the user into trials or Premium signup; pass
  `--first-user-trial=false`.
- Do not disable telemetry on the user's behalf.
- Do not skip `/healthz` readiness checks.
- Do not leave GitHub device-flow cookie jars or env files behind.
- Do not print admin passwords, OAuth secrets, cloud credentials, or
  LLM API keys.

When setup stalls, read
[`references/troubleshooting.md`](references/troubleshooting.md)
before diagnosing from scratch. It covers workspace-host protection,
Docker bridge reachability, NixOS firewall behavior, embedded Postgres
on ARM, Terraform installer signature failures, Docker group refresh,
Caddy redirect loops, and tailnet DNS rebind protection.

## Bundled Resources

Load these only when their trigger fires:

- [`references/first-user-github-device.md`](references/first-user-github-device.md):
  GitHub device-code protocol and failures. Trigger: device sign-in
  fails or needs detail.
- [`references/coder-agents.md`](references/coder-agents.md):
  Coder Agents provider/model setup. Trigger: user accepts the Agents
  offer.
- [`references/troubleshooting.md`](references/troubleshooting.md):
  Setup-specific failures not covered well by upstream docs. Trigger:
  install, server, template, or workspace readiness stalls.
- [`scripts/github-device-fetch.sh`](scripts/github-device-fetch.sh):
  Fetch the GitHub device code and write `$STATE_DIR/github-device.*`.
- [`scripts/github-device-poll.sh`](scripts/github-device-poll.sh):
  Poll GitHub completion, write the Coder session, and clean scratch
  files.
