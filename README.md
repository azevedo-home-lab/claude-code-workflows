# Claude Code Workflows

A guide to structured, accountable development with Claude Code using complementary tools:

- **Workflow Manager** — PreToolUse hooks that block code edits until a plan is discussed and approved
- **Superpowers** — Specialized skills (brainstorming, TDD, planning, debugging, code review)
- **claude-mem** — Cross-session persistent memory via MCP server
- **Status Line** — Minimal, color-coded status bar showing model, context usage, git branch, and worktree info

## Quick Start

1. [Getting Started Guide](docs/guides/getting-started.md) - Installation and first workflow
2. [CLAUDE.md Template](claude.md.template) - Copy into your project and customize
3. [Workflow Cheatsheet](docs/quick-reference/workflow-cheatsheet.md) - Daily-use quick reference

## Workflow Manager

Two-phase hard gate that prevents cowboy coding. Claude **cannot** edit files until a plan is discussed and you approve it.

```
DISCUSS ──(/approve)──> IMPLEMENT ──(/discuss)──> DISCUSS
```

| Phase | Write/Edit | Bash writes | Read/Grep | What to do |
|-------|-----------|-------------|-----------|------------|
| **DISCUSS** | Blocked | Blocked | Allowed | Brainstorm, plan, research |
| **IMPLEMENT** | Allowed | Allowed | Allowed | Execute the approved plan |

**Commands:**
- `/approve` — unlock code edits (plan approved, start implementing)
- `/discuss` — lock code edits (back to discussion for next task)

**Install into any project:**
```bash
curl -fsSL https://raw.githubusercontent.com/azevedo-home-lab/claude-code-workflows/main/install.sh | bash
```

Or clone and install manually:
```bash
git clone https://github.com/azevedo-home-lab/claude-code-workflows.git
./claude-code-workflows/install.sh /path/to/your/project
```

Uninstall: `./uninstall.sh` or manually remove `.claude/hooks/workflow-*.sh` and `.claude/commands/{approve,discuss}.md`.

## Tools

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

### Status Line

A minimal single-line status bar with color-coded context usage and worktree support:

```
Opus │ ▓▓░░░░░░░░ 25% │  main │ ~/Projects/MyApp │ Workflow Manager ✓ [DISCUSS] │ Claude-Mem ✓
```

**Quick install:**
```bash
cp statusline/statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Then add to `~/.claude/settings.json`:
```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 2
  }
}
```

See the [Status Line Guide](docs/guides/statusline-guide.md) for full details, customization, and available session data fields.

## Documentation

### Guides
- [Getting Started](docs/guides/getting-started.md) - Installation and first workflow
- [Integration Guide](docs/guides/integration-guide.md) - How Superpowers skills work together
- [Cross-Session Memory](docs/guides/claude-mem-guide.md) - claude-mem usage and handover patterns
- [Status Line](docs/guides/statusline-guide.md) - Setup, customization, and available data fields

### Reference
- [Command Reference](docs/quick-reference/commands.md) - All commands
- [Hooks Reference](docs/reference/hooks.md) - Workflow Manager hooks
- [Architecture](docs/reference/architecture.md) - System design and file organization

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
