# Coder Skills

[![skills.sh](https://skills.sh/b/coder/skills)](https://skills.sh/coder/skills)

Skills for Claude Code, Codex, Cursor, and other coding agents to install, configure, and operate Coder.

## Usage

**npx skills**:

```sh
npx skills add coder/skills --global
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

Then open Codex and install `coder-skills` from `/plugins`.

After installing, the skill activates automatically when you ask an agent to install or set up Coder.

## License

[MIT](LICENSE)
