# Claude Code Workflows

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

Structured development with Claude Code. Think before coding, review before shipping.

## Why

Claude Code is powerful but undisciplined. Left to its defaults, it:
- Jumps straight to writing code before understanding the problem
- Loses context over long sessions — early decisions get forgotten, hallucinations increase
- Doesn't naturally follow think → plan → build → review → ship
- Produces no auditable record of what was decided and why

Inspired by [cc-sessions](https://github.com/chronologos/cc-sessions) (a CLI for listing and resuming Claude Code sessions across projects), this project builds an opinionated workflow enforcement system that goes further. Session management alone wasn't enough — Claude also needed:
- **Guardrails** to prevent coding before planning (hard edit gates)
- **Structure** to guide each phase of development (coaching + skills)
- **Accountability** through decision records and review pipelines

The result makes Claude Code behave like a disciplined senior engineer: think first, plan second, code third, review before shipping.

Four tools that work together:

- **Workflow Manager** — Phase-based workflow enforcement with coaching and edit gates
- **Superpowers** — skills for brainstorming, TDD, planning, debugging, code review
- **claude-mem** — cross-session memory via MCP server
- **Status Line** — context usage, git branch, workflow phase at a glance

## Workflow

Six phases. Code edits are blocked until you discuss and approve a plan.

| Phase | Edits | What happens |
|-------|-------|--------------|
| **OFF** | Allowed | No enforcement |
| **DEFINE** | Blocked | Frame the problem, define outcomes |
| **DISCUSS** | Blocked | Research approaches, write plan |
| **IMPLEMENT** | Allowed | Execute plan with TDD |
| **REVIEW** | Allowed | 5 parallel review agents + verification |
| **COMPLETE** | Blocked | Validate outcomes, docs, handover |

Commands: `/define` `/discuss` `/implement` `/review` `/complete` `/off` `/proposals`

Any command can jump to any phase. `/off` closes the workflow. Soft gates warn when skipping steps.

### Autonomy Levels

Orthogonal to phase, the autonomy level controls how independently Claude operates. Set with `/autonomy off|ask|auto` (default: ask):

- `▶` **Supervised (off)**: All writes blocked regardless of phase. Claude can only read files and research.
- `▶▶` **Semi-Auto (ask)**: Writes follow phase rules (blocked in define/discuss/complete, allowed in implement/review). Stops at phase transitions for user approval.
- `▶▶▶` **Unattended (auto)**: Full autonomy within phase rules. Auto-transitions between phases, auto-commits. Stops only when user input is needed or before git push.

See the [Status Line guide](docs/guides/statusline-guide.md) for symbol display details.

Each cycle produces a **decision record** tracking problem, approaches, rationale, findings, and outcomes.

## Tools

| Tool | What it does | Docs |
|------|-------------|------|
| Workflow Manager | Phase-based enforcement + coaching | [Hooks reference](docs/reference/hooks.md) |
| Superpowers | Auto-activated development skills | [Integration guide](docs/guides/integration-guide.md) |
| claude-mem | Persistent cross-session observations | [Memory guide](docs/guides/claude-mem-guide.md) |
| Status Line | Color-coded status bar | [Setup guide](docs/guides/statusline-guide.md) |

### Optional Tools

Installed separately with `--iterm` or `--yubikey` flags:

| Tool | What it does | Docs |
|------|-------------|------|
| YubiKey signing | FIDO2 commit signing + push auth | [YubiKey setup](tools/yubikey-setup/) |
| iTerm Launcher | Dedicated Claude Code window | [Launcher](tools/iterm-launcher/) |

## Docs

- [Overview](docs/guides/overview.md) — what this is, why it exists, how it works
- [Getting Started](docs/guides/getting-started.md) — installation and first workflow
- [Architecture](docs/reference/architecture.md) — how the pieces fit together
- [Command Reference](docs/quick-reference/commands.md) — all commands
- [Professional Standards](docs/reference/professional-standards.md) — behavioral expectations per phase

## Installation

### As a Claude Code Plugin (recommended)

Add the marketplace and install:
```
/plugin marketplace add azevedo-home-lab/claude-code-workflows
/plugin install workflow-manager
```

The plugin auto-wires hooks, installs the statusline, and initializes project state. No manual configuration needed.


## Sources

- [cc-sessions](https://github.com/chronologos/cc-sessions) — CLI for listing and resuming Claude Code sessions across projects
- [claude-mem](https://github.com/thedotmack/claude-mem) — cross-session memory MCP server
- [Superpowers](https://github.com/obra/superpowers) — agentic skills framework and development methodology for Claude Code
- [everything-claude-code](https://github.com/affaan-m/everything-claude-code) — agent harness performance optimization, skills, instincts, memory
- [Context Engineering for AI Agents](https://docs.claude-mem.ai/context-engineering) — context rot, progressive disclosure, agentic memory
- [Reduce Hallucinations](https://docs.anthropic.com/en/docs/test-and-evaluate/strengthen-guardrails/reduce-hallucinations) — grounding, citations, uncertainty
- [Claude Code Best Practices](https://code.claude.com/docs/en/best-practices) — agentic coding patterns
- [Building Effective Agents](https://www.anthropic.com/research/building-effective-agents) — tool design, evaluation loops
- [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — session state, progress checkpoints

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[GPL v3](LICENSE)
