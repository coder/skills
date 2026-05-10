# Coder Skills

[![skills.sh](https://skills.sh/b/coder/skills)](https://skills.sh/coder/skills)

Skills for Claude Code, Codex, Cursor, and other coding agents to install, configure, and operate Coder.

## Usage

**Codex with npx skills**:

```sh
npx skills add coder/skills --global --agent codex --skill setup --yes --copy
```

Start a new Codex session after installing. To verify:

```sh
codex debug prompt-input 'noop' | rg 'setup:'
```

**Claude Code**:

```sh
/plugin marketplace add coder/skills
/plugin install coder-skills@coder-skills
/reload-plugins
```

**Codex**:

```sh
codex plugin marketplace add coder/skills
```

This registers the marketplace, but Codex CLI 0.130.0 does not provide
a command-line plugin install or enable command. Use `npx skills` for a
fully command-line Codex install, or open Codex and install from
`/plugins` if using the marketplace UI.

After installing, the skill activates automatically when you ask an agent to install or set up Coder.

## License

[MIT](LICENSE)
