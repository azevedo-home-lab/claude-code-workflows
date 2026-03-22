# Claude Code Workflows

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

Structured development with Claude Code. Think before coding, review before shipping.

Four tools that work together:

- **Workflow Manager** — hooks that block code edits until you have a plan
- **Superpowers** — skills for brainstorming, TDD, planning, debugging, code review
- **claude-mem** — cross-session memory via MCP server
- **Status Line** — context usage, git branch, workflow phase at a glance

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/azevedo-home-lab/claude-code-workflows/main/install.sh | bash
```

Or clone and install manually:

```bash
git clone https://github.com/azevedo-home-lab/claude-code-workflows.git
./claude-code-workflows/install.sh /path/to/your/project
```

Uninstall: `./uninstall.sh`

If your project has a `CLAUDE.md`, review [`claude.md.template`](claude.md.template) and merge any relevant sections.

## Workflow

Six phases. Code edits are blocked until you discuss and approve a plan.

| Phase | Edits | What happens |
|-------|-------|--------------|
| **OFF** | Allowed | No enforcement |
| **DEFINE** | Blocked | Frame the problem, define outcomes |
| **DISCUSS** | Blocked | Research approaches, write plan |
| **IMPLEMENT** | Allowed | Execute plan with TDD |
| **REVIEW** | Allowed | 3 parallel review agents + verification |
| **COMPLETE** | Blocked | Validate outcomes, docs, handover |

Commands: `/define` `/discuss` `/implement` `/review` `/complete`

Any command can jump to any phase. Soft gates warn when skipping steps.

Each cycle produces a **decision record** tracking problem, approaches, rationale, findings, and outcomes.

## Tools

| Tool | What it does | Docs |
|------|-------------|------|
| Workflow Manager | Phase-based edit gates + coaching system | [Hooks reference](docs/reference/hooks.md) |
| Superpowers | Auto-activated development skills | [Integration guide](docs/guides/integration-guide.md) |
| claude-mem | Persistent cross-session observations | [Memory guide](docs/guides/claude-mem-guide.md) |
| Status Line | Color-coded status bar | [Setup guide](docs/guides/statusline-guide.md) |
| YubiKey signing | FIDO2 commit signing + push auth | [YubiKey setup](tools/yubikey-setup/) |
| iTerm Launcher | Dedicated Claude Code window | [Launcher](tools/iterm-launcher/) |

## Docs

- [Getting Started](docs/guides/getting-started.md) — installation and first workflow
- [Architecture](docs/reference/architecture.md) — how the pieces fit together
- [Command Reference](docs/quick-reference/commands.md) — all commands
- [Professional Standards](docs/reference/professional-standards.md) — behavioral expectations per phase

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[GPL v3](LICENSE)
