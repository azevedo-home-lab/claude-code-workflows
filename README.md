# Claude Code Workflows

A comprehensive guide to using three complementary tools for structured, accountable development with Claude Code:

- **cc-sessions** — Task lifecycle management (DAIC workflow: Discuss → Approve → Implement → Complete)
- **Superpowers** — Specialized skills (brainstorming, TDD, planning, debugging, code review)
- **claude-mem** — Cross-session persistent memory via MCP server

## Quick Start

New to this workflow? Start here:
1. [Getting Started Guide](docs/guides/getting-started.md) - Installation and first workflow
2. [CLAUDE.md Template](claude.md.template) - Copy into your project and customize
3. [Workflow Cheatsheet](docs/quick-reference/workflow-cheatsheet.md) - Daily-use quick reference

## The Three Tools

### cc-sessions (Task Lifecycle)

Enforces the DAIC loop: structured task creation, context gathering, implementation with scope control, and clean completion with archival.

```
mek: <task>    → Discussion phase (define requirements)
start^:        → Load context, create plan
yert           → Approve plan, begin implementation
finito         → Verify, commit, archive
```

### Superpowers (Skills)

Auto-activated skills that enforce discipline at each phase:

| Skill | When |
|-------|------|
| `brainstorming` | Before any creative/feature work |
| `writing-plans` | When you have requirements, before code |
| `executing-plans` | Running a plan with review checkpoints |
| `test-driven-development` | Before writing implementation code |
| `systematic-debugging` | When encountering bugs or failures |
| `verification-before-completion` | Before claiming work is done |

### claude-mem (Cross-Session Memory)

MCP server that persists observations across sessions. Replaces manual handover docs.

| Command | Purpose |
|---------|---------|
| `mem-search` | Find work from previous sessions |
| `make-plan` | Create implementation plans with context |
| `do` | Execute plans using subagents |

**Session pattern:**
- **Start**: Search claude-mem for prior context before reading handover files
- **During**: Observations saved automatically as you work
- **End**: Key decisions and findings persisted for next session

## Documentation

### Guides
- [Getting Started](docs/guides/getting-started.md) - Installation and first workflow
- [Superpowers Guide](docs/guides/superpowers-guide.md) - Deep dive into skills
- [cc-sessions Guide](docs/guides/cc-sessions-guide.md) - DAIC workflow details
- [Cross-Session Memory](docs/guides/claude-mem-guide.md) - claude-mem usage and handover patterns
- [Examples](docs/guides/examples.md) - Real-world usage scenarios

### Quick Reference
- [Command Reference](docs/quick-reference/commands.md) - All commands with descriptions
- [Workflow Cheatsheet](docs/quick-reference/workflow-cheatsheet.md) - Daily quick reference

### Reference
- [Architecture](docs/reference/architecture.md) - How the pieces fit together
- [Benefits Analysis](docs/reference/benefits-analysis.md) - Measured benefits

## Templates

- [CLAUDE.md Template](claude.md.template) - Project-specific rules including:
  - Context window management (forbidden topic rule)
  - YubiKey FIDO2 git signing setup
  - Secret protection protocols
  - claude-mem integration
  - Behavioral rules for Claude Code

## Security

The template includes security rules for:
- **Secret protection**: Never display token/key values in output
- **YubiKey signing**: Optional FIDO2 commit signing and push auth
- **Token directories**: Protected paths excluded from git
- **Ownership**: All work attributed to user, never to AI

## Contributing

This workflow is designed for reuse. Copy and customize for your projects.
