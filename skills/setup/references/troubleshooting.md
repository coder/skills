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

## Embedded Postgres won't start (`libcrypto.so.1.1` ELF alignment failure on ARM / glibc 2.39+)

Symptom: `coder server` exits seconds after starting with a
log line like:

```text
error loading shared library libcrypto.so.1.1: ... ELF load
command alignment not page-aligned
```

or a `SIGSEGV` from the bundled `postgres` binary on a Raspberry
Pi or other ARM host. Coder ships an embedded Postgres for
development use; the bundled libcrypto isn't built for newer
ARM glibc page sizes and the dynamic loader refuses it.

Fix: install system Postgres and point Coder at it instead of
the embedded one. Roughly:

```sh
sudo apt-get install -y postgresql
sudo -u postgres createuser --pwprompt coder
sudo -u postgres createdb -O coder coder
# Then in /etc/coder.d/coder.env (or your shell env):
# CODER_PG_CONNECTION_URL=postgres://coder:<password>@127.0.0.1:5432/coder?sslmode=disable
```

This is the right fix for production anyway; embedded Postgres
is explicitly not for production use.

## Bundled Terraform installer fails on expired OpenPGP key

Symptom: `coder server` logs `failed to verify gpg signature`
or `unknown signing key` while resolving Terraform on first
template push, and the in-memory provisioner exits. Coder
downloads Terraform on demand and verifies HashiCorp's
OpenPGP signature; HashiCorp has rotated keys before, and old
Coder releases pin the previous one.

Fix: install Terraform locally and tell Coder to use it,
bypassing the bundled installer.

```sh
TF_VERSION=1.14.9      # match what your Coder server expects;
                       # 1.15+ produces a `may experience bugs`
                       # warning, not a failure, but pick the
                       # supported version when you can.
ARCH=$(uname -m | sed 's/aarch64/arm64/; s/x86_64/amd64/')
curl -fsSL -o /tmp/tf.zip \
  "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_${ARCH}.zip"
sudo unzip -o /tmp/tf.zip -d /usr/local/bin
sudo chmod +x /usr/local/bin/terraform
# Then in /etc/coder.d/coder.env:
# CODER_TERRAFORM_BINARY=/usr/local/bin/terraform
```

The expected Terraform version range is in the server's startup
log ("max_version=..."). Pick the highest version at or below
that ceiling.

## Docker group not effective for the running server

Symptom: provisioner job fails with
`permission denied while trying to connect to the Docker daemon
socket`, even though `docker ps` works for you in a fresh
shell. You installed Docker mid-install (apt-get) and the
running `coder server` process predates your group
membership.

Fix when you're already past the install: stop and restart
`coder server` under `sg docker` so the new GID applies for
that session.

```sh
kill "$(cat "$STATE_DIR/server.pid")"
nohup sg docker -c '. "$HOME/.local/state/coder-install/env"; coder server' \
  > "$STATE_DIR/server.log" 2>&1 &
echo $! > "$STATE_DIR/server.pid"
```

For the systemd path, run the unit as the `coder` system user
and add that user to the `docker` group (`gpasswd -a coder
docker`). The unit picks up the supplementary group on next
start; no `sg` wrapper needed.

**Preempt this entirely.** When the install adds Docker to a
host that didn't previously have it, always start the server
under `sg docker -c '...'` for the rest of the session, even
if the agent already has a working `docker ps`. The server
process's GIDs are fixed at exec time.

## Caddy in front of Coder hits a redirect loop

Symptom: `https://$ACCESS_URL/` returns HTTP 307 to itself,
the browser shows `ERR_TOO_MANY_REDIRECTS`, and `curl -v` shows
the `Location` header equals the request URL. Setting
`CODER_PROXY_TRUSTED_ORIGINS` to Caddy's source CIDR didn't
help.

This comes from Coder's own access-URL canonicalization
(`CODER_REDIRECT_TO_ACCESS_URL=true`) firing on top of Caddy's
HTTP -> HTTPS redirect. With Caddy already enforcing HTTPS at
:80, the second redirect is redundant and self-referential.

Fix: set `CODER_REDIRECT_TO_ACCESS_URL=false` in
`/etc/coder.d/coder.env`. Caddy keeps doing the HTTPS redirect;
Coder stops doing the host one. Verify with:

```sh
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' \
  -H 'X-Forwarded-Proto: https' http://127.0.0.1:3000/
```

200 (no redirect_url) means Coder is trusting the proxy
correctly.

Also make sure `CODER_PROXY_TRUSTED_ORIGINS` lists the source
CIDR Caddy connects from (`127.0.0.1/32` for a same-host
Caddy), and `CODER_PROXY_TRUSTED_HEADERS` includes
`X-Forwarded-For,X-Forwarded-Proto`.

## Home router DNS rebind protection NXDOMAINs the apex

Symptom: production install with a tailnet IP. The wildcard
(`*.tinkerpi.bpmct.net`) resolves on every machine, but the
apex (`tinkerpi.bpmct.net`) returns NXDOMAIN from your home
gateway. `dig @1.1.1.1` succeeds, `dig` against the gateway
fails. Workspace containers can't reach the access URL because
their resolv.conf points at the gateway. Tailscale's MagicDNS
falls through to the OS resolver, so it inherits the failure
on some clients.

This is rebind protection: the gateway refuses to return public
DNS answers that resolve to RFC1918 / CGNAT / tailnet IPs when
the queried name matches a local hostname. AT&T and many other
consumer ISPs do this by default.

The right fix is **Tailscale split-DNS**, not `/etc/hosts`:

1. <https://login.tailscale.com/admin/dns>
2. Nameservers -> Add nameserver -> Custom
3. IP: `1.1.1.1` (and `1.0.0.1`)
4. Restrict to domain: the user's domain (`bpmct.net`)
5. Save

Once that's in place, every tailnet member resolves the apex
through Cloudflare regardless of which OS resolver is asking.
When the install is running over Tailscale and the user picks
a public domain, set this up *before* trying to verify the
deployment from the host or from inside a workspace; doing it
after forces a workspace template patch and a rebuild.

Until split-DNS is configured, the workarounds are:

- On the install host: `/etc/hosts` entry mapping the apex to
  the tailnet IP.
- In each workspace: a `host {}` block in the Docker template's
  `docker_container` resource (or equivalent for Kubernetes).
  Workspaces have their own `resolv.conf` and don't see the
  host's `/etc/hosts`.

Document both as temporary; rip them out once the user adds
the split-DNS rule.

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
