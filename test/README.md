# install-coder skill tests

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
3. Asks Claude to drive the `install-coder` skill.
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
  `latest_build.status = succeeded` and `transition = start`.

## Why Docker compose

The test prompt forbids any host install. Coder workspaces (which
this repo is often developed inside) embed an agent named `coder`,
so a host-level install or any blanket `pkill coder` would terminate
the user's session. The skill itself refuses to do a host install
when `CODER_AGENT_TOKEN` is set; the test asserts that constraint
holds by leaving Docker compose as the only viable path.
