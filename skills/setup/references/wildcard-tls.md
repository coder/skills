# Wildcard Access URL and TLS

Two related things you must get right for any production Coder
deployment.

## Why both URLs

Coder has *two* URLs in its config:

- `CODER_ACCESS_URL`: where users browse the dashboard, where the CLI
  authenticates, and where workspace agents dial back. Required.
- `CODER_WILDCARD_ACCESS_URL`: the hostname pattern Coder uses to
  serve `coder_app` resources (port-forwarded apps, web terminals,
  embedded VS Code, etc.) on per-workspace subdomains. Optional;
  enable it when the user wants subdomain app routing.

Without the wildcard, Coder serves apps on path-based routes. Most
apps work that way. The ones that break are anything that hardcodes
a root path, scopes cookies to a specific host, or relies on
`coder port-forward` URLs (which are subdomain-shaped). If the user
needs those, set the wildcard; otherwise leave it off.
The docs at <https://coder.com/docs/admin/networking#wildcard-access-url>
go deeper.

## DNS

If you set a wildcard URL, you need two records, both pointing at
the same address (the load balancer, ingress, reverse proxy, or VM).
If you didn't, just the apex.

```text
coder.example.com.        300  IN  A  203.0.113.10
*.coder.example.com.      300  IN  A  203.0.113.10   # only with wildcard
```

Use AAAA records for IPv6. CNAME is fine for the apex on providers
that support CNAME-at-apex (Cloudflare, Route 53 alias). The wildcard
must be a separate record, even though it lives under the apex zone.

Verify before continuing:

```sh
dig +short coder.example.com
dig +short app.coder.example.com    # arbitrary subdomain to test wildcard
```

Both must resolve to the same address before you start the server,
otherwise the first `coder login` against the apex works but every
embedded-app URL 404s.

## TLS certificate

The certificate must include both names as Subject Alternative Names:

- `coder.example.com`
- `*.coder.example.com`

Standard ACME (Let's Encrypt) supports wildcard certs only via
DNS-01 challenge. HTTP-01 will not issue a wildcard. cert-manager,
Caddy, and traefik all do this; configure your DNS provider as the
ACME01 solver.

## Where TLS terminates

Pick one. Don't mix.

### Option A: Terminate at the Coder server

Use this for a single VM with no reverse proxy. Coder reads PEM files
directly.

Server env:

```sh
export CODER_ACCESS_URL=https://coder.example.com
export CODER_WILDCARD_ACCESS_URL=*.coder.example.com
export CODER_TLS_ENABLE=true
export CODER_TLS_ADDRESS=0.0.0.0:443
export CODER_TLS_CERT_FILE=/etc/coder/tls/fullchain.pem
export CODER_TLS_KEY_FILE=/etc/coder/tls/privkey.pem
export CODER_HTTP_ADDRESS=""   # disable plain HTTP listener
```

`CODER_TLS_CERT_FILE` and `CODER_TLS_KEY_FILE` accept a comma-
separated list of PEMs if you want to serve multiple certs. The first
PEM should be the leaf followed by intermediates concatenated (the
standard `fullchain.pem` layout from certbot / cert-manager).

The private key file must be readable only by the user that runs
`coder server`. Lock it down before starting:

```sh
sudo install -m 0700 -d /etc/coder/tls
sudo install -m 0600 -o coder -g coder /path/to/privkey.pem \
  /etc/coder/tls/privkey.pem
sudo install -m 0644 -o coder -g coder /path/to/fullchain.pem \
  /etc/coder/tls/fullchain.pem
```

Adjust `coder:coder` to the actual user/group running the server
(`root:root` if installed via the system package and started with
systemd as root). World-readable key files are the most common
self-inflicted leak in this path.

To enforce HTTPS, set `CODER_REDIRECT_TO_ACCESS_URL=true` so plain HTTP
hits get a 308 to the HTTPS URL.

### Option B: Terminate at a reverse proxy or ingress

Use this for Kubernetes (the standard pattern), or any cloud LB.
Coder serves plain HTTP internally; the proxy speaks HTTPS to clients.

Server env:

```sh
export CODER_ACCESS_URL=https://coder.example.com
export CODER_WILDCARD_ACCESS_URL=*.coder.example.com
export CODER_HTTP_ADDRESS=0.0.0.0:7080
# Do NOT set CODER_TLS_ENABLE=true; the proxy handles TLS.
```

The proxy must:

- Forward both `coder.example.com` and `*.coder.example.com` to the
  same upstream.
- Preserve the `Host` header (Coder uses it to detect which workspace
  app to serve).
- Allow WebSocket upgrades on every path (workspace agents and the
  web terminal use them).
- Pass `X-Forwarded-Proto: https` and `X-Forwarded-For` so audit logs
  record the right origin.

### Option C: ACME inside Coder

Coder has no built-in ACME client. Don't try to put one there. Use
Caddy (one-line config), traefik, or cert-manager.

## Helm: the canonical production deployment

The `coder-v2` chart wires the env vars and the ingress for you. A
working values file:

```yaml
coder:
  env:
    - name: CODER_ACCESS_URL
      value: "https://coder.example.com"
    - name: CODER_WILDCARD_ACCESS_URL
      value: "*.coder.example.com"
    - name: CODER_PG_CONNECTION_URL
      valueFrom:
        secretKeyRef:
          name: coder-db-url
          key: url
  service:
    type: ClusterIP
  ingress:
    enable: true
    className: nginx
    host: "coder.example.com"
    wildcardHost: "*.coder.example.com"
    tls:
      enable: true
      secretName: coder-tls
      wildcardSecretName: coder-tls-wildcard   # if separate cert
```

Most clusters provision the cert with cert-manager. A minimal
`Certificate`:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: coder-tls
  namespace: coder
spec:
  secretName: coder-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - coder.example.com
    - "*.coder.example.com"
```

Verify:

```sh
kubectl rollout status -n coder deploy/coder --timeout=180s
curl -fsS https://coder.example.com/healthz
curl -fsS https://workspaces-test.coder.example.com/healthz   # arbitrary sub
```

Both `curl`s must return 200.

## Common failures

- **Apps load but their JS calls 404.** Wildcard URL not set, or DNS
  not resolving the wildcard subdomain. Verify with the
  `dig +short app.coder.example.com` check above.
- **`tls: failed to find any PEM data`.** `CODER_TLS_CERT_FILE` is
  pointing at a directory, an empty file, or a PEM with the wrong
  ordering (key must be in `CODER_TLS_KEY_FILE`, not concatenated
  with the cert).
- **Browser warns "subject alternative name" mismatch on subdomain.**
  The cert covers `coder.example.com` but not the wildcard. Reissue
  with both SANs.
- **Workspace agents fail to connect with `tls: bad certificate`.**
  Self-signed cert without a CA the agent trusts. Either issue a real
  cert from a trusted CA, or deploy the CA bundle to every workspace
  template via `CODER_AGENT_CA_CERTS`.
- **Hard-coded `Host` headers.** A reverse proxy in front of Coder
  rewrote `Host` to `coder-svc.coder.svc.cluster.local`. Coder can't
  match that to a workspace app and serves the dashboard. Configure
  the proxy to preserve the original `Host`.

## After provisioning

Set the deployment-config flag to redirect plain HTTP and tighten
HSTS at the proxy:

```sh
export CODER_REDIRECT_TO_ACCESS_URL=true
```

If you exposed `0.0.0.0:7080` on a public NIC, firewall it off; only
the proxy should reach the plaintext listener.
