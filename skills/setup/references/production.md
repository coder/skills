# Production Deployment

This file is the entry point when the user wants a Coder deployment
that survives a reboot, serves a real domain, and lets multiple users
log in. Use it in addition to the rest of the skill, not as a
replacement for it.

The trial path (localhost / tunnel, no TLS, no external auth) covers
demos and "kick the tires" usage. Switch to this path when any of:

- The user names a real domain (`coder.example.com`, `dev.acme.io`).
- The user mentions HTTPS, Let's Encrypt, ingress, or "TLS".
- The user wants a team to log in via GitHub, GitLab, OIDC.
- The user needs cloud workspaces (AWS / GCP / Azure) with credentials
  the Coder server itself should not see.
- The user says "production", "staging", or "for the team".

The skill's Phase 1 collects the deployment mode. Once the user picks
production, this file's order-of-operations replaces the trial path
through Phases 2 and beyond.

## Order of operations

Do these in order. Each step has a clear exit criterion. Do not start
the next step until the current one is verifiable.

1. **Plan the access URL and the wildcard URL.**
   - `CODER_ACCESS_URL=https://coder.example.com` is the server.
   - `CODER_WILDCARD_ACCESS_URL=*.coder.example.com` is the per-app
     hostname pattern that lets `coder_app` ports work. Without it,
     `coder port-forward` and embedded apps fall back to path-based
     proxying which breaks anything that assumes a root path.
   - The wildcard is a separate DNS record (`*.coder.example.com A ...`)
     and a separate TLS certificate SAN. Provision both before
     starting the server.
   - Details: `wildcard-tls.md`.

2. **Provision DNS and TLS.**
   - One A or AAAA record for the apex (`coder.example.com`).
   - One wildcard A or AAAA record (`*.coder.example.com`) pointing
     to the same address.
   - One TLS certificate covering both. ACME (cert-manager,
     Caddy, traefik) is the simplest path; bring your own PEM works
     too. See `wildcard-tls.md` for the exact env vars and the
     terminator-vs-server tradeoff.

3. **Stand up the server with production env.**
   - Use Helm or Docker compose. Don't run `coder server` directly on a
     production host; the install script does not configure systemd
     hardening, log rotation, or a separate database.
   - Set `CODER_ACCESS_URL`, `CODER_WILDCARD_ACCESS_URL`, and the TLS
     env vars from `wildcard-tls.md`.
   - Use a managed PostgreSQL (RDS, Cloud SQL, managed PG operator).
     The built-in `coder.db` is fine for trials only.

4. **Bootstrap the admin user** (Phase 4 of the skill, unchanged).
   - `coder login --first-user-*` against the public access URL.

5. **Register external auth (optional but usually desired).**
   - GitHub is the most common; details and exact env vars in
     `external-auth-github.md`.
   - This is what makes `coder_external_auth` blocks in templates
     work, so workspaces can clone private repos without committing
     PATs.

6. **Run an external provisioner (recommended for cloud templates).**
   - Keeps cloud credentials off the Coder server.
   - Lets you run the server without a Docker socket / cluster
     credentials mounted.
   - Details: `external-provisioner.md`. Skip this step only if all
     templates run against local Docker on the server itself.

7. **Push the template** (Phase 5 of the skill).
   - When using an external provisioner, tag both the provisioner and
     the template (`environment=cloud` is a common pair) so the
     in-server provisioner doesn't pick the job up.

8. **Create one workspace** (Phase 6 of the skill).
   - Verify it builds and reaches `latest_build.status=running`.

9. **Summarize** (Phase 7 of the skill, extended).
   - Print the access URL, login URL, GitHub OAuth callback URL, and
     the provisioner PSK / scoped-key hash so the user can recover
     each later.

## What this path does *not* cover

Out of scope, by design. Point the user at the canonical docs when
they ask:

- **High availability.** Two or more Coder replicas behind a load
  balancer. <https://coder.com/docs/admin/infrastructure/high-availability>
- **Workspace proxies.** Regional dataplanes for users far from the
  control plane. <https://coder.com/docs/admin/networking/workspace-proxies>
- **OIDC / SAML platform login.** The user logs into Coder itself via
  Okta / Azure AD / Google. This skill only covers external auth (the
  per-workspace, per-template "log in to GitHub" flow).
  <https://coder.com/docs/admin/users/oidc-auth>
- **Backups, restore, disaster recovery.** Use your managed PG
  vendor's snapshot story.
- **Licensing and Premium / Enterprise features.** Workspace proxies,
  groups, audit log retention, and template ACLs need a license.
  Don't enable a trial unless the user asked.
- **AI Bridge, prebuilds, autostop schedules, idle timeouts.** Each is
  documented separately.

## Deployment-mode decision matrix

| Concern                                  | Trial path                       | Production path                                       |
|------------------------------------------|----------------------------------|-------------------------------------------------------|
| Access URL                               | `http://localhost:7080`          | `https://coder.example.com`                           |
| Wildcard URL                             | omitted                          | `*.coder.example.com`                                 |
| TLS                                      | none                             | required, terminate at server or proxy                |
| Database                                 | built-in (dqlite/sqlite)         | managed PostgreSQL                                    |
| Server execution                         | `coder server` foreground/nohup  | Helm or compose with restart policy                   |
| External auth                            | omit                             | usually GitHub via OAuth app                          |
| Cloud creds                              | on the server (small blast)      | on a separate provisioner host                        |
| Templates                                | `docker` starter                 | `aws-linux` / `kubernetes` / customer-authored        |
| Workspace count                          | 1                                | many; expect concurrent builds                        |
| Backup story                             | none                             | managed PG snapshots                                  |

## Confirmation gate

Before starting any production phase that mutates DNS, requests a
real certificate, or rotates secrets:

1. Echo back the planned values (DNS records, env vars, cert path)
   without printing the secret material.
2. Ask for a single yes/no confirmation.
3. Only proceed after the user confirms.

In headless mode (`claude -p`) the user can pre-authorize by passing
the values in the prompt and explicitly saying "go ahead".
