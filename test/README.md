# setup-coder skill tests

This skill is tested with [`claude -p`](https://docs.claude.com/en/docs/claude-code/headless)
in non-interactive mode against a real Coder server provisioned via
Docker compose. The test is one-shot end-to-end: install + bootstrap +
template push + workspace create + verify.

## Run the test

Requirements:

- `claude` CLI (the [Claude Code CLI](https://www.npmjs.com/package/@anthropic-ai/claude-code)).
- Docker daemon reachable from the user (no `sudo`).
- A free TCP port for the server. The script defaults to `17080`.
- Anthropic credentials (`ANTHROPIC_API_KEY`, or AWS Bedrock / GCP
  Vertex environment for `claude`).

Run:

```sh
./test/run.sh
```

The script:

1. Spins a clean test directory under `$TMPDIR` (or `/tmp`).
2. Invokes `claude -p` with `--plugin-dir` pointing at the marketplace
   in this repo.
3. Asks Claude to drive the `setup-coder` skill.
4. Independently verifies the server, admin user, template, and
   workspace via the Coder REST API.
5. Prints `PASS` or `FAIL`.

## What's verified

After Claude finishes:

- `GET /healthz` returns `OK`.
- `GET /api/v2/users` returns exactly one user (`admin`, owner role).
- `GET /api/v2/organizations/default/templates` includes the `docker`
  template.
- `GET /api/v2/workspaces` includes a workspace named `demo` with
  `latest_build.job.status = succeeded`, `latest_build.status =
  running`, and `transition = start`.

## Sandbox

The harness sandboxes `$HOME` and `$XDG_CONFIG_HOME` to a temporary
directory under `$TMPDIR`. Anything the skill writes to `~/...`
lands in the sandbox, not the user's real home, so a misbehaving run
cannot clobber `~/.config/coderv2`, `~/.bash_history`, or other host
state. The Docker daemon is shared with the host (the compose recipe
binds the daemon socket), so containers and images created by the
test persist on the host's docker daemon and are cleaned up by the
harness's `cleanup` trap.

## Why Docker compose

The test prompt forbids any host install. Coder workspaces (which
this repo is often developed inside) embed an agent named `coder`,
so a host-level install or any blanket `pkill coder` would terminate
the user's session. The skill itself refuses to do a host install
when `CODER_AGENT_TOKEN` is set; the test asserts that constraint
holds by leaving Docker compose as the only viable path.

## Production path

`run.sh` covers the trial path only. The production-mode workflow
(real domain, wildcard URL, TLS, GitHub external auth, external
provisioner) needs DNS, an OAuth App, and a TLS issuer that the
harness can't provide on its own without a kind cluster + self-
signed CA + stub OAuth server. That harness is not in the repo
yet; the production path is currently exercised manually.

Manual verification recipe (against a real cluster you control):

1. Run the skill with the production-mode prompt:

   ```sh
   claude --plugin-dir . --permission-mode bypassPermissions \
     "Use setup-coder to deploy Coder on Kubernetes at \
      https://coder.example.com with wildcard *.coder.example.com, \
      TLS via cert-manager, GitHub external auth (OAuth App client \
      ID and secret in $GITHUB_CLIENT_ID / $GITHUB_CLIENT_SECRET), \
      and one external provisioner with tag environment=cloud. \
      Push the aws-linux template tagged environment=cloud and \
      create one workspace."
   ```

2. Verify via REST:

   - `GET https://coder.example.com/healthz` returns 200.
   - `GET https://app-test.coder.example.com/healthz` returns 200
     (proves wildcard DNS + TLS).
   - `GET /api/v2/external-auth` lists the GitHub provider.
   - `GET /api/v2/provisionerdaemons` lists the external daemon as
     online with the expected tags.
   - `GET /api/v2/workspaces` shows the workspace with
     `latest_build.status = running`.
