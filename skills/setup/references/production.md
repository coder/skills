# Production Deployment

This file is the entry point when the user wants a Coder deployment
that survives a reboot, serves a real domain, and lets multiple users
log in. Use it in addition to the rest of the skill, not as a
replacement for it.

The trial path (auto-tunnel or localhost, no TLS, no extra
configuration) covers demos and "kick the tires" usage. Switch to
this path when any of:

- The user names a real domain (`coder.example.com`, `dev.acme.io`).
- The user mentions HTTPS, Let's Encrypt, ingress, or "TLS".
- The user wants a team to log in via a non-default GitHub provider,
  GitLab, GHES, or OIDC.
- The user needs cloud workspaces (AWS / GCP / Azure) with credentials
  the Coder server itself should not see.
- The user says "production", "staging", or "for the team".

The skill's Phase 1 collects the deployment mode. Once the user picks
production, this file's order-of-operations replaces the trial path
through Phases 2 and beyond.

## Order of operations

Do these in order. Each step has a clear exit criterion. Do not start
the next step until the current one is verifiable.

1. **Plan the access URL.**
   - `CODER_ACCESS_URL=https://coder.example.com` is the server.
   - **Wildcard URL is optional**, not required. Set
     `CODER_WILDCARD_ACCESS_URL=*.coder.example.com` only when the
     user wants subdomain app routing (which backs `coder
     port-forward` and the cleanest behavior for embedded `coder_app`
     ports). Without it, Coder serves apps on path-based routes;
     most apps work that way, some break (anything that hardcodes a
     root path or scopes cookies to a specific host). Ask once;
     don't gate the deployment on it.
   - Details: `wildcard-tls.md`.

2. **Provision DNS and TLS.**
   - One A or AAAA record for the apex (`coder.example.com`).
   - If using the wildcard, one wildcard A or AAAA record
     (`*.coder.example.com`) pointing to the same address.
   - One TLS certificate covering the names you provisioned. ACME
     (cert-manager, Caddy, traefik) is the simplest path; bring your
     own PEM works too. See `wildcard-tls.md` for the exact env vars
     and the terminator-vs-server tradeoff.

3. **Stand up the server with production env.**
   - Pick a supervisor that suits the host: Helm on Kubernetes,
     Docker compose, or systemd on a single VM. systemd is fine for
     production; what makes a deployment production-ready is managed
     Postgres, real TLS, and a real access URL, not the choice of
     process manager. The install script registers a systemd unit
     when run on a supported distro; drop env into
     `/etc/coder.d/coder.env` and `sudo systemctl restart coder`.
   - Set `CODER_ACCESS_URL` and the TLS env vars from
     `wildcard-tls.md`. Set `CODER_WILDCARD_ACCESS_URL` only if you
     decided to in step 1.
   - Use a managed PostgreSQL (RDS, Cloud SQL, managed PG operator).
     The built-in PG is fine for trials only.

4. **Bootstrap the admin user** (Phase 4 of the skill).
   - **GitHub path** (default for fresh deployments): the dashboard
     auto-shows "Continue with GitHub". The first user to sign in is
     auto-promoted to Owner.
   - **Username/password path**: `coder login --first-user-*`
     against the public access URL.

5. **Register a custom external auth provider** (optional, only if
   needed).
   - The default github.com provider is on by default for fresh
     deployments and covers the "workspaces clone private GitHub
     repos" case. Skip this step unless the user runs GHES, wants
     GitLab/Bitbucket/etc., or has a corporate-owned OAuth App they
     prefer over Coder's default.
   - Details and exact env vars in `external-auth-github.md`.

6. **Run an external provisioner** (optional, only if needed).
   - Required when cloud workspaces (AWS / GCP / Azure) need
     credentials the Coder server should not see, or when build
     concurrency / network isolation matters.
   - The in-server provisioner is fine for Docker / Kubernetes
     templates that run against the same host or cluster the server
     runs on.
   - Details: `external-provisioner.md`.

7. **Push the template** (Phase 6 of the skill).
   - When using an external provisioner, tag both the provisioner
     and the template (`environment=cloud` is a common pair) so the
     in-server provisioner doesn't pick the job up.

8. **Create one workspace** (Phase 7 of the skill).
   - Verify it builds and the agent reaches `lifecycle_state=ready`.

9. **Summarize** (Phase 8 of the skill).
   - Print the access URL, the auth method (GitHub button vs saved
     credentials), and any custom integrations registered (custom
     OAuth App callback, provisioner key fingerprint, TLS cert
     paths). The user backs these up out of band.

## Telemetry

Coder telemetry is on by default and strips PII before sending. The
skill **does not** disable it on the user's behalf and does not ask
them. If the user explicitly says they need to opt out, they can set
`CODER_TELEMETRY_ENABLE=false` in the deployment env. Do not surface
this option proactively.

## What this path does *not* cover

Out of scope, by design. Point the user at the canonical docs when
they ask:

- **High availability.** Two or more Coder replicas behind a load
  balancer. <https://coder.com/docs/admin/infrastructure/high-availability>
- **Workspace proxies.** Regional dataplanes for users far from the
  control plane. <https://coder.com/docs/admin/networking/workspace-proxies>
- **OIDC / SAML platform login.** The user logs into Coder itself via
  Okta / Azure AD / Google. This skill covers GitHub-via-OAuth (the
  default for fresh deployments) and external auth (the per-template
  "log in to GitHub" flow), not enterprise SSO.
  <https://coder.com/docs/admin/users/oidc-auth>
- **Backups, restore, disaster recovery.** Use your managed PG
  vendor's snapshot story.
- **Licensing and Premium / Enterprise features.** Workspace proxies,
  groups, audit log retention, and template ACLs need a license.
  Don't enable a trial unless the user asked.
- **AI Bridge, prebuilds, autostop schedules, idle timeouts.** Each is
  documented separately.

## Deployment-mode decision matrix

| Concern                                  | Trial path                                  | Production path                                       |
|------------------------------------------|---------------------------------------------|-------------------------------------------------------|
| Access URL                               | auto-tunnel `*.try.coder.app` (default)     | `https://coder.example.com`                           |
| Wildcard URL                             | auto-tunnel suffix                          | optional; set when subdomain app routing is wanted    |
| TLS                                      | tunnel-managed                              | required, terminate at server or proxy                |
| Database                                 | built-in (dqlite/sqlite)                    | managed PostgreSQL                                    |
| Server execution                         | `coder server` nohup or compose             | Helm, compose, or systemd with restart policy         |
| First-user auth                          | GitHub default (no setup) or username/pass  | GitHub default or username/pass; custom OAuth optional|
| Cloud creds                              | on the server (small blast radius)          | on a separate provisioner host (recommended)          |
| Templates                                | `docker` starter                            | `aws-linux` / `kubernetes` / customer-authored        |
| Workspace count                          | 1                                           | many; expect concurrent builds                        |
| Backup story                             | none                                        | managed PG snapshots                                  |

## Confirmation gate

Before starting any production phase that mutates DNS, requests a
real certificate, or rotates secrets:

1. Echo back the planned values (DNS records, env vars, cert path)
   without printing the secret material.
2. Ask for a single yes/no confirmation.
3. Only proceed after the user confirms.

In headless mode (`claude -p`) the user can pre-authorize by passing
the values in the prompt and explicitly saying "go ahead".
