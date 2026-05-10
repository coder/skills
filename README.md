# Coder Skills

[![skills.sh](https://skills.sh/b/coder/skills)](https://skills.sh/coder/skills)

Skills for Claude Code, Codex, Cursor, and other coding agents to install, configure, and operate Coder.

## Usage

**npx skills**:

```sh
npx skills add coder/skills
```

**Claude Code**:

```sh
/plugin marketplace add coder/skills
/plugin install coder@coder-skills
/reload-plugins
```

**Codex**:

```sh
codex plugin marketplace add coder/skills
codex plugin install coder@coder-skills
```


### `npx skills` (recommended)

# user-global: drops it in ~/.claude/skills, ~/.codex/skills, ~/.cursor/skills, ...
npx skills add coder/skills@setup --global

# install only for a specific agent
npx skills add coder/skills@setup --agent codex
npx skills add coder/skills@setup --agent claude-code
npx skills add coder/skills@setup --agent cursor
```

Once installed, the skill activates automatically when you ask the
agent to install or set up Coder. There is no slash command; just
say what you want ("set up Coder locally", "deploy Coder behind
HTTPS", "stand up Coder on Kubernetes") and the agent picks the
skill from its description.

### Claude Code (native plugin marketplace)

Claude Code can also load this repo as a [plugin
marketplace](https://docs.claude.com/en/docs/claude-code/plugins)
directly:

```text
/plugin marketplace add coder/skills
/plugin install coder@coder-skills
```

If the install doesn't take effect immediately, run
`/reload-plugins` and try again.

For local development, point the marketplace at a checkout:

```text
/plugin marketplace add /path/to/skills
```

In headless mode (`claude -p`), use `--plugin-dir` instead:

```sh
claude -p \
  --plugin-dir /path/to/skills \
  --permission-mode bypassPermissions \
  "Use the setup skill to install Coder via Docker compose, \
   bootstrap an admin user, push the docker starter template, and \
   create one workspace named demo."
```

`--permission-mode bypassPermissions` is required because the skill
runs `curl | sh`, starts background processes, and writes config
files. Only use it on a sandboxed host.

### Codex (native plugin marketplace)

The Codex CLI has its own plugin marketplace command. Same source:

```sh
codex plugin marketplace add coder/skills
```

Codex auto-discovers any skill placed under `$CODEX_HOME/skills`
(default `~/.codex/skills`), so the `npx skills add coder/skills
--agent codex` path above works without any extra step.

## Run a skill headlessly

Two test harnesses ship with the repo, one per CLI. Both spin a
real Coder server in Docker, drive the skill end-to-end, and verify
the result via the Coder REST API.

```sh
./test/run.sh           # Claude Code (claude -p)
./test/run-codex.sh     # Codex (codex exec)
```

See [`test/README.md`](test/README.md) for what each harness
expects and how to point them at a different port or template.

## Develop a new skill

Each skill is a directory under `skills/<name>/` containing a
`SKILL.md` with YAML frontmatter, plus optional `references/`,
`scripts/`, and `assets/` subdirectories. The frontmatter requires:

```yaml
---
name: kebab-case-skill-name
description: One sentence on what it does and exactly when to use it.
---
```

Anthropic's skill spec is at
<https://github.com/anthropics/skills/tree/main/spec>. Conventions
this repo follows on top of that:

- **Keep `description` under 1024 characters.** Codex truncates the
  description at that limit and drops the skill if the truncated
  YAML is invalid. Claude tolerates longer descriptions but does
  not benefit from them. Push activation triggers and exclusions
  into a tight 1000-char block.
- **Keep `SKILL.md` lean** (target 1500 to 2500 words). Push
  detailed matrices, tables, and edge-case lists into
  `references/*.md` and lazy-load them by trigger.
- **Reference files from `SKILL.md` with relative paths** so the
  skill works at the personal, project, or plugin level and across
  agents.
- **Don't ship secrets, license keys, or auth tokens** in any skill
  artifact. Skills are public.
- **Add a smoke test under `test/`** that runs the skill headlessly
  and verifies the externally observable result. The two existing
  harnesses (`test/run.sh`, `test/run-codex.sh`) are good
  templates.

## Lint and format

```sh
make lint   # shellcheck, shfmt --diff, markdownlint, jq, claude plugin validate, no-emdash, SKILL.md description-length
make fmt    # shfmt -w, markdownlint --fix, jq pretty-print
```

`make lint` is what runs in CI (`.github/workflows/lint.yml`).
Lint configuration lives at the repo root: `.editorconfig`,
`.markdownlint-cli2.jsonc`, `.shellcheckrc`. The shfmt flags
(`-i 2 -ci`) are encoded in `scripts/lint.sh` and `scripts/fmt.sh`
rather than a config file because shfmt has no native config
format.

The SKILL.md description-length check exists because Codex
truncates the YAML `description` field at 1024 characters and
silently drops the skill if truncation breaks the YAML. The
lint catches that before it ships.

## License

To be set by the publisher. Until then, treat as "all rights reserved".
