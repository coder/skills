# Coder Skills

[![skills.sh](https://skills.sh/b/coder/skills)](https://skills.sh/coder/skills)

Skills for Claude Code, Codex, Cursor, and other coding agents to install, configure, and operate Coder.

## Usage

**skills CLI**:

```sh
npx skills add coder/skills --global --skill '*'
```

This installs every skill in this repository for the detected agent.
Start a new agent session after installing. For Codex, verify with:

```sh
codex debug prompt-input 'noop' | rg 'setup:'
```

**Claude Code plugin marketplace**:

```sh
claude plugin marketplace add coder/skills
claude plugin install coder-skills@coder-skills
claude plugin list
```

After installing, the skill activates automatically when you ask an agent to install or set up Coder.

## License

[MIT](LICENSE)
