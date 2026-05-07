# coder/skills

Skills for installing, configuring, and operating
[Coder](https://github.com/coder/coder).

This repository is a [Claude Code plugin
marketplace](https://docs.claude.com/en/docs/claude-code/plugins) that
distributes one or more skills targeted at Coder operators and users.

## Skills

| Skill                                                | What it does                                                                                                                                                                                                                                                          |
|------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`setup`](skills/setup/SKILL.md) (`/coder:setup`) | End-to-end install and first-run setup for a Coder deployment without using the web UI. Handles trial setups (auto-tunnel, no TLS) and production setups (real domain, TLS, optional wildcard, optional custom external auth, optional external provisioner). Wraps `install.sh`, hands off to GitHub sign-in by default on fresh deployments, falls back to `coder login --first-user-*` for fully scripted setups, pushes a starter template, and (optionally) creates a first workspace. |

## Install

In Claude Code, add the marketplace once, then install one or more
plugins from it:

```text
/plugin marketplace add coder/skills
/plugin install coder@coder-skills
```

After installing, the skill activates automatically when you ask
Claude to install or set up Coder. Skills don't expose a slash
command; just say what you want ("set up Coder locally", "deploy
Coder behind HTTPS") and the skill activates from its description.

If the install doesn't take effect immediately, run
`/reload-plugins` and try again.

For local development, point at a checkout instead of the GitHub
slug:

```text
/plugin marketplace add /path/to/skills
```

## Run a skill headlessly

Skills work in `claude -p` (non-interactive mode) the same way they
work in the interactive REPL. For local development, point at a
checkout with `--plugin-dir`:

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
files. Only use it on a sandboxed host. The bundled
[`test/run.sh`](test/run.sh) harness wraps this for you and verifies
the result via the Coder REST API.

```sh
./test/run.sh
```

See [`test/README.md`](test/README.md) for what the harness expects.

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

Anthropic's skill spec lives at
<https://github.com/anthropics/skills/tree/main/spec>. Conventions
this repo follows on top of that:

- Keep `SKILL.md` lean (target 1500 to 2500 words). Push detailed
  matrices, tables, and edge-case lists into `references/*.md`.
- Reference files from `SKILL.md` with relative paths so the skill
  works whether it's installed at the personal, project, or plugin
  level.
- Don't ship secrets, license keys, or auth tokens in any skill
  artifact. Skills are public.
- New skills should ship with a smoke test under `test/` that runs
  via `claude -p` and verifies the externally observable result.

## License

To be set by the publisher. Until then, treat as "all rights reserved".
