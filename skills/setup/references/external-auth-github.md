# External Auth: GitHub

Lets workspaces clone private GitHub repositories without committing
PATs into templates, and lets users link their GitHub account to
Coder. This is *not* the same thing as logging into Coder *with*
GitHub; that's OIDC, out of scope for this skill.

The mechanism: Coder owns a GitHub OAuth App. When a template
references the auth provider with `data "coder_external_auth"`, Coder
performs the OAuth dance on the user's behalf and exposes the
resulting token to the workspace's environment.

## Default github.com provider (no setup)

Fresh deployments auto-enable a default github.com external auth
provider, backed by Coder's own OAuth App. It covers the common
case: workspaces cloning private github.com repos via
`data "coder_external_auth" { id = "github" }` (or any matching
`type = "github"`).

Follow this file's setup only when the default doesn't fit:

- **GitHub Enterprise Server (GHES).** The default points at
  github.com only.
- **A non-default OAuth App** the user prefers (corporate-owned,
  for audit visibility, restricted scopes).
- **GitLab, Bitbucket, Gitea, Azure DevOps, JFrog Artifactory.** The
  same indexed env-var pattern works for all of them; per-provider
  fields are documented at
  <https://coder.com/docs/admin/external-auth>.

When a custom GitHub provider is configured, the default github.com
provider auto-suppresses; Coder picks the explicit one.

## Prerequisites

- A working `CODER_ACCESS_URL` (HTTPS) you can reach from GitHub's
  servers. The OAuth callback must be a real HTTPS URL; localhost
  works only for the apex, not for shared deployments.
- An admin account on the GitHub org or user account that will own
  the OAuth App.

## Pick the provider ID first

The ID is part of the callback URL. Pick it before registering the
OAuth App and reuse the same value for the env var. Conventional
choices:

- `primary-github` for a single-org deployment.
- `github-acme` if you have multiple GitHub providers (e.g. one for
  internal, one for partner repos).

The ID flows through to the env var as
`CODER_EXTERNAL_AUTH_0_ID=<id>` and the callback path as
`https://coder.example.com/external-auth/<id>/callback`.

## Register the GitHub OAuth App

OAuth Apps live under user or org settings on github.com. Don't use
GitHub Apps for this; the external-auth provider expects the
classical OAuth App fields.

Register at <https://github.com/settings/developers> (personal) or
`https://github.com/organizations/<org>/settings/applications`.

Fields:

- **Application name**: free-form, e.g. `Coder (acme)`.
- **Homepage URL**: `https://coder.example.com`.
- **Authorization callback URL**:
  `https://coder.example.com/external-auth/<id>/callback`.

Click "Register application", then "Generate a new client secret".
Capture the client ID and the secret immediately; the secret cannot
be retrieved later, only rotated.

## Configure Coder

The `CODER_EXTERNAL_AUTH_<N>_*` env vars are indexed; start at 0.
Multiple providers use 0, 1, 2, etc., in order.

**Capture the client secret without leaking it.** Don't paste the
secret into a shell command directly; that puts it in shell history
and process listings. Read it from stdin into the env var, then
immediately move it into the deployment manifest:

```sh
export CODER_EXTERNAL_AUTH_0_ID=primary-github
export CODER_EXTERNAL_AUTH_0_TYPE=github
export CODER_EXTERNAL_AUTH_0_CLIENT_ID=<the client id>
read -r -s -p 'CODER_EXTERNAL_AUTH_0_CLIENT_SECRET: ' \
  CODER_EXTERNAL_AUTH_0_CLIENT_SECRET; echo
export CODER_EXTERNAL_AUTH_0_CLIENT_SECRET
```

The `read -r -s` pattern matches the one used for
`CODER_FIRST_USER_PASSWORD` in the bootstrap phase. Confirm receipt
with `[set]` rather than echoing the value back.

For Helm, write the secret into a Kubernetes Secret directly
(`kubectl create secret generic coder-external-auth --from-file=
client-secret=/dev/stdin <<<"$CODER_EXTERNAL_AUTH_0_CLIENT_SECRET"`)
and reference it with `valueFrom.secretKeyRef`. Don't put the secret
in a values.yaml file that lands in git.

Optional but useful:

```sh
# Override the display name in the dashboard. Defaults to "GitHub".
export CODER_EXTERNAL_AUTH_0_DISPLAY_NAME="Acme GitHub"

# Limit which scopes Coder requests. Defaults are repo-scoped already.
# export CODER_EXTERNAL_AUTH_0_SCOPES="repo,read:org"
```

For GitHub Enterprise Server (self-hosted GHES), set the explicit
endpoints:

```sh
export CODER_EXTERNAL_AUTH_0_TYPE=github
export CODER_EXTERNAL_AUTH_0_AUTH_URL=https://github.acme.internal/login/oauth/authorize
export CODER_EXTERNAL_AUTH_0_TOKEN_URL=https://github.acme.internal/login/oauth/access_token
export CODER_EXTERNAL_AUTH_0_VALIDATE_URL=https://github.acme.internal/api/v3/user
export CODER_EXTERNAL_AUTH_0_REGEX="github\\.acme\\.internal"
```

Restart the server (Helm `helm upgrade`, compose `docker compose up -d`)
so the env reaches the running process.

## Default vs custom provider

When you register your own `github`-typed provider, the default
github.com provider auto-suppresses on fresh deployments; you don't
need to set `CODER_EXTERNAL_AUTH_GITHUB_DEFAULT_PROVIDER_ENABLE=false`
to avoid duplicate "Continue with GitHub" buttons. Set the env var
to `false` only when you want the default off without registering a
replacement (rare).

## Verify

After restart:

```sh
curl -fsS \
  -H "Coder-Session-Token: $SESSION" \
  https://coder.example.com/api/v2/external-auth
```

The response is a JSON array; your provider should appear with the
`id` and `display_name` you set. Empty array means the env vars
aren't reaching the server (re-check the deployment manifest), or
the indexing skipped a number (`CODER_EXTERNAL_AUTH_1_*` without a 0
will fail).

End-to-end: open `https://coder.example.com/external-auth/<id>` in a
browser. It should redirect to GitHub, ask you to authorize the OAuth
App, and redirect back. Coder shows "Authenticated".

## Use it from a template

```hcl
data "coder_external_auth" "github" {
  id = "primary-github"
}

resource "coder_agent" "main" {
  env = {
    GITHUB_TOKEN = data.coder_external_auth.github.access_token
  }
}
```

Workspaces built from this template get `GITHUB_TOKEN` populated for
the lifetime of the OAuth grant. Coder refreshes the token
automatically when it expires.

## Common failures

- **`redirect URI is not valid`** at GitHub. The callback URL in the
  OAuth App doesn't match `<access-url>/external-auth/<id>/callback`
  exactly. Trailing slashes count.
- **Provider missing from `/api/v2/external-auth`.** The env vars
  aren't reaching the server, or the index has a gap. Check
  `kubectl exec` / `docker exec` and `env | grep EXTERNAL_AUTH` on
  the running container.
- **"403 Bad credentials"** during a workspace clone. The OAuth App's
  client secret was rotated and the running deployment still has the
  old value. Restart the server after updating the env.
- **Two "Continue with GitHub" buttons in the UI.** A custom
  `github`-typed provider was registered on a deployment that's not
  considered "fresh" (the auto-suppress only triggers for new
  deployments). Set
  `CODER_EXTERNAL_AUTH_GITHUB_DEFAULT_PROVIDER_ENABLE=false`
  explicitly to drop the default.
- **`access_token` is empty in templates.** The user hasn't
  authorized the provider yet. Workspace builds prompt the user once;
  re-run the build after authorization.

## Beyond GitHub

The same indexed env-var pattern works for GitLab, Bitbucket, Gitea,
Azure DevOps, JFrog Artifactory, and arbitrary OAuth2 providers. The
canonical reference for the per-provider fields is
<https://coder.com/docs/admin/external-auth>. The skill covers GitHub
because it's the dominant case; redirect to the docs for the rest.
