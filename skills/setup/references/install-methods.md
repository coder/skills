# Install Methods

Pick the simplest method that satisfies the user's requirements. When
in doubt, ask. The detection logic below mirrors what `install.sh`
does internally, plus the extra targets (Docker compose, Helm) that
the script doesn't handle.

## Decision tree

1. The user wants a single-host server on their laptop or one VM.
   - Linux/macOS: standalone install via `install.sh`.
   - Windows: download the MSI from
     <https://github.com/coder/coder/releases> or
     `winget install Coder.Coder`.
2. The user wants Docker.
   - Use the compose recipe below. Use the official
     `ghcr.io/coder/coder` image. Pin to a version digest in
     production; `latest` is fine for demos.
3. The user has a Kubernetes cluster.
   - Use Helm with the `coder-v2` chart. See the values file template
     below.
4. The user is on a cloud VM and wants Terraform.
   - Use the standalone install on the VM. Don't recreate the compose
     recipe inside Terraform; use a `remote-exec` provisioner or
     cloud-init that calls `install.sh`.

## Standalone (Linux/macOS) via `install.sh`

The canonical entry point. Use it unless you have a reason not to.

```sh
curl -fsSL https://coder.com/install.sh | sh
```

Useful flags (full set: `bash <(curl -fsSL https://coder.com/install.sh) --help`):

| Flag                            | Effect                                                   |
|---------------------------------|----------------------------------------------------------|
| `--mainline` (default)          | Latest mainline release.                                 |
| `--stable`                      | Latest stable release. Prefer for production.            |
| `--version X.Y.Z`               | Pin a specific version.                                  |
| `--method detect` (default)     | Use the system package manager when available.           |
| `--method standalone`           | Skip the package manager. Drops a tarball.               |
| `--prefix DIR`                  | Standalone install prefix. Pair with `$HOME/.local`.     |
| `--binary-name NAME`            | Rename the binary (e.g. `coder2`).                       |
| `--with-terraform`              | Install Terraform alongside Coder.                       |
| `--rsh CMD`                     | Remote shell to use for `user@host` mode.                |
| `--dry-run`                     | Print the commands without running them.                 |

Detection rules the script applies, in order:

- Debian, Ubuntu, Raspbian: `.deb` from GitHub releases.
- Fedora, CentOS, RHEL, openSUSE: `.rpm` from GitHub releases.
- Alpine: `.apk` from GitHub releases.
- macOS with `brew`: the `coder/coder` Homebrew tap.
- Otherwise: standalone tarball into `--prefix` (default `/usr/local`).

When the script can't find a matching release for the OS or arch it
falls back to the standalone path automatically.

Verify:

```sh
coder --version
```

If the binary landed in `$HOME/.local/bin`, remind the user to put
that on `$PATH`. Don't silently edit shell rc files.

### Standalone, no sudo, ephemeral

For demos, CI, the test harness for this skill, and any environment
without `sudo`:

```sh
mkdir -p "$HOME/.local"
curl -fsSL https://coder.com/install.sh \
  | sh -s -- --method standalone --prefix "$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
coder --version
```

This installs `coder` into `$HOME/.local/bin/coder` with no system
changes.

### Remote install over SSH

`install.sh` accepts a final `user@host` argument. It reuses your SSH
config and runs the same script on the remote host.

```sh
curl -fsSL https://coder.com/install.sh \
  | sh -s -- --stable --with-terraform user@host
```

## Docker compose

Generate this file; do not edit a `compose.yaml` already in the user's
working tree.

> [!WARNING]
> The credentials below are placeholders for a local demo. Before
> using this compose file for anything that survives a reboot:
>
> - Replace `POSTGRES_PASSWORD` with a strong random value (e.g.
>   `export POSTGRES_PASSWORD="$(openssl rand -base64 32)"`).
> - Use `sslmode=require` in `CODER_PG_CONNECTION_URL` and provide
>   real TLS for the database.
> - Move the database off the same host (managed PG, RDS, Cloud
>   SQL).
> - Set `CODER_ACCESS_URL` to a real domain and front the `coder`
>   service with TLS.
>
> Do not commit a populated `compose.yaml` with secrets to git.

```yaml
services:
  database:
    image: "postgres:16"
    environment:
      POSTGRES_USER: coder
      POSTGRES_PASSWORD: "${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD before docker compose up}"
      POSTGRES_DB: coder
    volumes:
      - coder_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U coder"]
      interval: 5s
      timeout: 5s
      retries: 5

  coder:
    image: ghcr.io/coder/coder:latest
    environment:
      CODER_PG_CONNECTION_URL: "postgres://coder:${POSTGRES_PASSWORD}@database/coder?sslmode=disable"
      CODER_HTTP_ADDRESS: "0.0.0.0:7080"
      CODER_ACCESS_URL: "${CODER_ACCESS_URL:-http://localhost:7080}"
    group_add:
      - "${DOCKER_GROUP_ID:-999}"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    depends_on:
      database:
        condition: service_healthy
    ports:
      - "7080:7080"

volumes:
  coder_data:
```

Boot:

```sh
export POSTGRES_PASSWORD="$(openssl rand -base64 32)"
export DOCKER_GROUP_ID="$(getent group docker | cut -d: -f3)"
docker compose up -d
```

Wait for readiness:

```sh
until curl -fsS http://localhost:7080/healthz >/dev/null; do
  sleep 1
done
```

`DOCKER_GROUP_ID` should be set to the host's `docker` GID so the
provisioner inside the Coder container can talk to the host's
Docker daemon. Find it with `getent group docker | cut -d: -f3`.

## Kubernetes (Helm)

```sh
helm repo add coder-v2 https://helm.coder.com/v2
helm repo update
kubectl create namespace coder
helm install coder coder-v2/coder \
  --namespace coder \
  --values values.yaml
```

Minimum `values.yaml`:

```yaml
coder:
  env:
    - name: CODER_ACCESS_URL
      value: "https://coder.example.com"
    - name: CODER_WILDCARD_ACCESS_URL
      value: "*.coder.example.com"
  service:
    type: LoadBalancer
```

For local clusters (kind, minikube, k3d), use `type: NodePort` with
an access URL of `http://localhost:<nodeport>`.

Wait for readiness:

```sh
kubectl rollout status -n coder deploy/coder --timeout=120s
```

## Picking the access URL

Three valid choices, in order of preference:

1. **A real domain you own.** Best for everything except local
   hacking. Set `CODER_ACCESS_URL` and `CODER_WILDCARD_ACCESS_URL` in
   the server's environment.
2. **`http://localhost:7080`.** Local-only. Workspaces will not be
   reachable from outside the host. Fine for solo demos.
3. **The built-in tunnel.** If `coder server` starts with no
   `--access-url`, the server prints a `*.try.coder.app` URL. Tell
   the user it is a public tunnel intended for trial use only.

Whatever you pick, set it once and reuse the same value for `coder
login` in Phase 4. Mismatches between server access URL and login URL
are the single most common source of "it just hangs" reports.
