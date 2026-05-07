# Troubleshooting (skill-specific)

This file is short on purpose. The full operational and admin
guidance lives in <https://coder.com/docs/llms.txt>; pull from
there for anything that's not skill-specific. The notes below
are gotchas that the docs don't cover (because they relate to
how the *skill* drives the install, not Coder itself).

## Never `pkill coder` on a Coder workspace

If the environment has `CODER_AGENT_TOKEN` or
`CODER_WORKSPACE_NAME` set, the host is inside a Coder workspace.
The workspace agent is itself a `coder` process; `pkill coder`,
`pkill -f coder`, or `killall coder` will kill the agent, sever
the user's session, and stop the chat from running shell commands.

Guard every cleanup or troubleshooting command:

```sh
if [ -n "${CODER_AGENT_TOKEN-}${CODER_WORKSPACE_NAME-}" ]; then
  echo "refusing to pkill coder on a Coder workspace" >&2
  exit 1
fi
```

When the host is a Coder workspace, prefer one of:

- A **separate process group** (Docker compose, a Helm release
  in a separate kube context, or a child host).
- A **PID-tracked launch**: write the server PID to
  `$STATE_DIR/server.pid` and kill only that PID.
- **Skip cleanup entirely** during testing. The workspace itself
  is ephemeral; recreate it instead.

## Workspace agent can't reach the server

Symptom: `coder list` shows the workspace as `running` but the
agent stays in `lifecycle=created status=connecting`. The
container started, the agent's init script is curling
`http://host.docker.internal:7080/bin/coder-linux-amd64`, and
the request is timing out.

The `docker` starter template resolves the server via
`host.docker.internal`, which points at the docker bridge gateway
(typically `172.17.0.1`), not the container's loopback. A `coder
server --http-address 127.0.0.1:7080` bind is unreachable from
the container.

Check what the container sees:

```sh
docker exec coder-${USERNAME}-${WORKSPACE_NAME} sh -c \
  'getent hosts host.docker.internal; \
   curl -v --max-time 3 http://host.docker.internal:7080/healthz 2>&1 | tail -10'
```

Fix one of:

1. **Rebind the server to all interfaces.** Stop the server
   (`kill "$(cat "$STATE_DIR/server.pid")"`) and restart with
   `--http-address 0.0.0.0:7080`. The access URL stays
   `http://localhost:7080`.
2. **Switch to Docker compose.** The compose recipe puts the
   server inside the same docker network as the workspace;
   `host.docker.internal` isn't involved and host firewalls
   don't apply.

## NixOS firewall blocks docker bridge

Symptom: server bound to `0.0.0.0:7080`, `ss -tlnp` shows the
listener, but the `curl` from inside the workspace container
still times out. NixOS's stateful `nixos-fw` chain drops new
connections on interfaces that aren't in
`networking.firewall.trustedInterfaces`, including the docker
bridge.

Fastest fix (reversible, lasts until reboot):

```sh
sudo iptables -I nixos-fw -i docker0 -p tcp --dport 7080 -j ACCEPT
# Reverse with:
# sudo iptables -D nixos-fw -i docker0 -p tcp --dport 7080 -j ACCEPT
```

Durable fix: add `docker0` to
`networking.firewall.trustedInterfaces` in the NixOS config. Or
better: switch the install to Docker compose so the server isn't
on the host at all.

## Where to look for everything else

- Server won't start, port conflicts, Postgres connection issues:
  <https://coder.com/docs/install.md> (install method) and
  <https://coder.com/docs/admin/setup.md>.
- TLS certificate, wildcard DNS, ingress:
  <https://coder.com/docs/admin/networking/wildcard-access-url.md>.
- OAuth / OIDC errors:
  <https://coder.com/docs/admin/users/github-auth.md> and
  <https://coder.com/docs/admin/users/oidc-auth.md>.
- Provisioner registration / job failures:
  <https://coder.com/docs/admin/provisioners.md>.
- Template build failures, parameters, `terraform plan`:
  <https://coder.com/docs/admin/templates.md>.
- Upgrades and rollbacks:
  <https://coder.com/docs/install/upgrade.md>.
- Anything else: <https://coder.com/docs/llms.txt>.
