# Troubleshooting

Short list. The full doc is at <https://coder.com/docs/admin/setup>.
Use this file when something breaks during Phases 2 through 6.

## Never `pkill coder` on a Coder workspace

If the environment has `CODER_AGENT_TOKEN` or `CODER_WORKSPACE_NAME`
set, the host is **inside a Coder workspace**. The workspace agent
is itself a `coder` process. Running `pkill coder`, `pkill -f coder`,
or `killall coder` will kill the agent, sever the user's session,
and stop the chat from being able to run any more shell commands.

Guard every cleanup or troubleshooting command with a check first:

```sh
if [ -n "${CODER_AGENT_TOKEN-}${CODER_WORKSPACE_NAME-}" ]; then
  echo "refusing to pkill coder on a Coder workspace" >&2
  exit 1
fi
```

When the host is a Coder workspace, prefer one of:

- A **separate process group** (Docker compose, Helm release in a
  separate kube context, or a child host).
- A **PID-tracked launch**: write the server PID to
  `~/.coder-server.pid` and only kill that PID, never every process
  named `coder`.
- **Skip cleanup entirely** during testing. The workspace itself is
  ephemeral; recreate it instead of fighting in-place.

The rest of this file assumes you are *not* on a Coder workspace, or
that you have already isolated the new server (e.g. inside Docker).

## Phase 2: install fails

### "command not found: coder" after `install.sh`

The script chose `--method standalone` and put the binary in
`/usr/local/bin/coder`, but the shell hasn't refreshed its hash. Run
`hash -r` (bash) or `rehash` (zsh) and retry. If the binary is in
`~/.local/bin`, ensure that's on `$PATH`.

### "permission denied" running `install.sh`

The user is non-root and the script is trying to install to
`/usr/local/bin`. Re-run with:

```sh
curl -fsSL https://coder.com/install.sh \
  | sh -s -- --method standalone --prefix "$HOME/.local"
```

### Helm timeout / "context deadline exceeded"

The chart is waiting for a `LoadBalancer` IP. Switch to `type:
NodePort` for local clusters, or set the values file to use an
existing ingress.

## Phase 3: server won't start

### Port 7080 already in use

Another process owns it. Pick a different port:

```sh
coder server --http-address 127.0.0.1:7090 ...
```

Update the access URL to match.

### "could not connect to postgres"

Coder defaults to the built-in PostgreSQL. If `--postgres-url` is
set, verify the URL with `psql "$POSTGRES_URL" -c '\l'`. The built-in
PG fails when the data directory is on a Docker volume with the wrong
owner.

### Server starts but `/healthz` never returns 200

Check the server log. The most common cause is a TLS misconfig: the
server logs `tls: failed to find any PEM data` and exits. Re-run with
`--tls-enable=false` for the local-only path.

### Tunnel URL stuck on "creating"

The host has no outbound internet, or `*.try.coder.app` is blocked.
Switch to a real access URL or `http://localhost:7080`.

## Phase 4: first-user bootstrap fails

See `first-user.md` for the canonical failure list.

## Phase 5: template push fails

### "context deadline exceeded" during build

The provisioner can't reach the cloud or the local Docker daemon.

- Docker: run `docker info` from the host running `coder server`. If
  it fails, fix the Docker daemon first.
- Kubernetes: `kubectl auth can-i create pods -n coder`. If no, fix
  RBAC; the workspace pod runs in the namespace named in the template's
  `namespace` variable.
- Cloud: missing or wrong credentials. See
  `templates.md#provider-credentials`.

### "no provisioner daemons available"

The server runs a provisioner by default; this error means it's
disabled or oversubscribed. Restart the server with
`--provisioner-daemons 1` or run a separate provisioner with
`coder provisioner start`.

### Template version stays in `pending`

A provisioner picked it up but the build hasn't finished. Tail
provisioner job logs:

```sh
coder provisioner jobs list
coder templates versions list <name>
```

## Phase 6: workspace creation fails

### "template requires a parameter"

Re-run with `--parameter "name=value"` for each missing param. To
see the full list, run `coder templates show <name>`.

### "build job failed"

```sh
coder show <workspace> --output text
```

The provisioner logs are inline. Read the Terraform error and fix
the template variables.

## Cleanup

> [!WARNING]
> The commands in this section permanently destroy the database, every
> workspace, and every template the user built. Run them only after
> the user has explicitly asked to start over, delete everything, or
> uninstall the deployment. Never run them on initiative. In headless
> mode (under `claude -p --permission-mode bypassPermissions`), echo
> the intent back to the user and require an explicit confirmation
> token like `destroy-coder` before proceeding.

When the user has confirmed they want to start over:

```sh
# Refuse on a live Coder workspace; killing the agent disconnects the user.
if [ -n "${CODER_AGENT_TOKEN-}${CODER_WORKSPACE_NAME-}" ]; then
  echo "refusing to clean up coder on a Coder workspace; tear down the workspace instead" >&2
  exit 1
fi

# Confirmation gate. Skip only if the user already confirmed in chat.
read -r -p 'type "destroy-coder" to delete all Coder data: ' confirm
[ "$confirm" = "destroy-coder" ] || { echo aborted; exit 0; }

# Standalone server started by this skill (PID is in ~/.coder-server.pid)
if [ -f "$HOME/.coder-server.pid" ]; then
  kill "$(cat "$HOME/.coder-server.pid")" 2>/dev/null || true
  rm -f "$HOME/.coder-server.pid"
fi
rm -rf "$HOME/.config/coderv2"

# systemd (skip on a workspace; the early guard already returned)
sudo systemctl stop coder && sudo systemctl disable coder

# Docker compose; -v drops the database volume
docker compose down -v

# Helm
helm uninstall coder -n coder
kubectl delete namespace coder
```

Never use `pkill coder`, `killall coder`, or `pkill -f coder`. On a
Coder host that disconnects the user. Only kill the PID this skill
recorded.
