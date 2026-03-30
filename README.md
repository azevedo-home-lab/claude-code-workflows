# Claude Code Workflows

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

Structured development with Claude Code. Think before coding, review before shipping.

## Why

Claude Code is powerful but undisciplined. Left to its defaults, it:
- Jumps straight to writing code before researching the problem, discussing a solution, writing a plan.
- Might not review the code, or just review some aspects of it, leaving the codebase inconsistent with security or achitectural gaps. 
- Loses context over long sessions — early decisions get forgotten, hallucinations increase, original goals drift
- Doesn't naturally follow follow a natural development flow: think → plan → build → review → ship → reiterate  
- Produces limited or inconsisten auditable record of what was decided or implemented and why

## Goal
The objective is to make Claude Code behave more like a disciplined senior engineer

Inspired by [cc-sessions](https://github.com/GWUDCAP/cc-sessions) (DAIC workflow enforcement with trigger-phrase automation and sub-agents for Claude Code)
This project builds on top an opinionated workflow enforcement system with:
- **Guardrails** - Enforced workflow phases with gated steps.
- **Guidance Structure** to prompt and guide claude on each phase of development (coaching + skills)
- **Accountability** through plans, specs, review pipelines and traceability (github issues and observations) 

## How

Four tools that work together:

- **Workflow Manager** — Phase-based workflow enforcement with coaching and sequential gates
- **Skills and Agents** — skills for brainstorming, Agents for TDD, planning, debugging, code review
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
| **REVIEW** | Allowed |  Parallel review agents + verification |
| **COMPLETE** | Blocked | Validate outcomes, docs, open issues, handover |

Commands: `/define` `/discuss` `/implement` `/review` `/complete` `/off` `/proposals` `/debug` `/autonomy`

Any command can jump to any phase. `/off` closes the workflow. Soft gates warn when skipping steps.

See [Architecture — Phase Model](docs/reference/architecture.md#phase-model) for the full breakdown: steps, agents, gates, milestones, and coaching per phase.

### Autonomy Levels

Orthogonal to phase, the autonomy level controls how independently Claude operates. Set with `/autonomy off|ask|auto` (default: ask):

- `▶` **Supervised (off)**: Step-by-step pair programming. Claude executes one plan step at a time, presents the change, and waits for your review before proceeding. Writes follow phase rules.
- `▶▶` **Semi-Auto (ask)**: Claude works freely within each phase but stops at phase boundaries for review and guidance before transitioning. No auto-commits.
- `▶▶▶` **Unattended (auto)**: Full autonomy. Claude auto-transitions between phases, auto-fixes review findings, auto-commits. Stops only when user input is genuinely needed or before git push.

Autonomy symbols are shown in the status line alongside the current phase.

Each cycle produces a **plan** (problem, approaches, rationale) and a **spec** (requirements, tasks, acceptance criteria).

## Features

| Tool | What it does | Docs |
|------|-------------|------|
| Workflow Manager | Phase-based enforcement + coaching | [Architecture](docs/reference/architecture.md) |
| Integrated Superpowers | Auto-activated development skills | [Hooks reference](docs/reference/hooks.md) |
| Integrated claude-mem | Persistent cross-session observations | [Hooks reference](docs/reference/hooks.md) |
| Status Line | Informational status bar | [`plugin/statusline/statusline.sh`](plugin/statusline/statusline.sh) |

## Docs

- [Architecture](docs/reference/architecture.md) — phases, enforcement, gates, milestones
- [Hooks Reference](docs/reference/hooks.md) — hook implementation details
- [Command Reference](docs/reference/commands.md) — all commands
- [Professional Standards](plugin/docs/reference/professional-standards.md) — behavioral expectations per phase

## Installation

### As a Claude Code Plugin (recommended)

Add the marketplace and install:
```
/plugin marketplace add azevedo-home-lab/claude-code-workflows
/plugin install workflow-manager
```

The plugin auto-wires hooks, installs the statusline, and initializes project state. No manual configuration needed.

### Optional Tools

Installed separately with `--iterm` or `--yubikey` flags:

| Tool | What it does | Docs |
|------|-------------|------|
| YubiKey signing | FIDO2 commit signing + push auth | [YubiKey setup](tools/yubikey-setup/) |
| iTerm Launcher | Dedicated Claude Code window | [Launcher](tools/iterm-launcher/) |

## Sources

- [cc-sessions](https://github.com/GWUDCAP/cc-sessions) — DAIC workflow enforcement with trigger-phrase automation for Claude Code
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
