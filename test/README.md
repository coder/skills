# setup skill tests

The skill ships with two end-to-end harnesses, one per major coding
agent CLI. Both run the skill headlessly, spin a real Coder server in
Docker, and verify the result via the Coder REST API.

| Harness                | Driver                                                              | What it exercises                                  |
|------------------------|---------------------------------------------------------------------|----------------------------------------------------|
| `./test/run.sh`        | [`claude -p`](https://docs.claude.com/en/docs/claude-code/headless) | Claude Code, plugin marketplace via `--plugin-dir` |
| `./test/run-codex.sh`  | `codex exec`                                                        | Codex CLI, skill discovered under `$CODEX_HOME/skills` |

The skill itself is identical for both. The harnesses differ only in
how the agent is launched and how the skill is exposed.

## Run

Requirements (both harnesses):

- Docker daemon reachable from the user (no `sudo`).
- A free TCP port for the server (`run.sh` defaults to `17080`,
  `run-codex.sh` to `17081`).

Per-harness extras:

- `run.sh`: the [`claude` CLI](https://www.npmjs.com/package/@anthropic-ai/claude-code)
  on `PATH` and Anthropic credentials it can use.
- `run-codex.sh`: the [`codex`
  CLI](https://github.com/openai/codex) on `PATH` and a working
  `~/.codex/config.toml` + `~/.codex/auth.json` (the harness copies
  these into a sandbox so it doesn't touch the real ones).

Run:

```sh
./test/run.sh
./test/run-codex.sh
```

Each script:

1. Spins a clean test directory under `$TMPDIR` (or `/tmp`).
2. Drives the agent against the skill in this repo.
3. Independently verifies the server, admin user, template, and
   workspace via the Coder REST API.
4. Prints `PASS` or `FAIL`.

Override the port or timeout via env vars:

```sh
CODER_TEST_PORT=18080 CODER_TEST_TIMEOUT=1800 ./test/run.sh
```

## What's verified

After the agent finishes:

- `GET /healthz` returns `OK`.
- `GET /api/v2/users` returns exactly one user (`admin`, owner role).
- `GET /api/v2/organizations/default/templates` includes the `docker`
  template.
- `GET /api/v2/workspaces` includes a workspace named `demo` with
  `latest_build.job.status = succeeded`, `latest_build.status =
  running`, `transition = start`, and the agent's `lifecycle_state
  = ready`.

## Sandbox

Both harnesses sandbox `$HOME` and `$XDG_CONFIG_HOME` (and Codex's
`$CODEX_HOME`) under `$TMPDIR`. Anything the skill writes lands in
the sandbox, so a misbehaving run cannot clobber `~/.config/coderv2`,
`~/.bash_history`, or other host state. The Docker daemon is shared
with the host (the compose recipe binds the daemon socket), so
containers and images created by the test persist on the host's
docker daemon and are cleaned up by the `cleanup` trap.

## Why Docker compose

The test prompt forbids any host install. Coder workspaces (which
this repo is often developed inside) embed an agent named `coder`,
so a host-level install or any blanket `pkill coder` would terminate
the user's session. The skill itself refuses to do a host install
when `CODER_AGENT_TOKEN` is set; the test asserts that constraint
holds by leaving Docker compose as the only viable path.

## Production path

The harnesses cover the quick-start path only. The production-mode
workflow (real domain, wildcard URL, TLS, GitHub external auth,
external provisioner) needs DNS, an OAuth App, and a TLS issuer that
the harnesses can't provide on their own without a kind cluster +
self-signed CA + stub OAuth server. That harness is not in the repo
yet; the production path is currently exercised manually.

Manual verification recipe (against a real cluster you control):

1. Run the skill with the production-mode prompt:

   ```sh
   claude --plugin-dir . --permission-mode bypassPermissions \
     "Use setup to deploy Coder on Kubernetes at \
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
