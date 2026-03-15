# Getting Started

Get up and running with the Superpowers + claude-mem workflow.

## Prerequisites

- Claude Code installed
- Git repository for your project

## Setup

### 1. Install Superpowers

```bash
plugin marketplace add obra/superpowers-marketplace
plugin install superpowers@superpowers-marketplace
```

### 2. Install claude-mem (optional)

Follow the claude-mem installation guide for your platform. See [claude-mem guide](claude-mem-guide.md).

### 3. Copy CLAUDE.md Template

```bash
cp claude.md.template CLAUDE.md
```

Edit `CLAUDE.md` to fill in project-specific placeholders.

## Your First Workflow

```
"Add user authentication with JWT"       # Describe what you want
/superpowers:brainstorm                   # Clarify: OAuth? Password rules? Session timeout?
/superpowers:write-plan                   # Generate implementation plan
# Review and approve the plan
/superpowers:execute-plan                 # Implement with review checkpoints
/superpowers:verification-before-completion  # Verify before claiming done
```

Each phase builds on the previous. The key insight: requirements are clarified and a plan is approved before coding starts, preventing scope creep and rework.

## Next Steps

- [Integration Guide](integration-guide.md) — How Superpowers skills work together
- [Command Reference](../quick-reference/commands.md) — All commands with descriptions
- [Cross-Session Memory](claude-mem-guide.md) — Persistent memory across sessions
