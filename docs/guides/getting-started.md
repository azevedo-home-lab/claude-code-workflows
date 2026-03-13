# Getting Started

Get up and running with the cc-sessions + Superpowers workflow.

## Prerequisites

- Claude Code installed
- Git repository for your project

## Setup

### 1. Install Superpowers

```bash
plugin marketplace add obra/superpowers-marketplace
plugin install superpowers@superpowers-marketplace
```

### 2. Create Directory Structure

```bash
mkdir -p sessions/logs .claude/context
```

### 3. Configure .gitignore

```
sessions/
.claude/context/
.claude/.chats/
.claude/settings.local.json
token_do_not_commit/
.env
.env.local
```

### 4. Copy CLAUDE.md Template

```bash
cp claude.md.template CLAUDE.md
```

Edit `CLAUDE.md` to fill in project-specific placeholders.

## Your First DAIC Workflow

```
mek: Add user authentication with JWT     # Start task
/superpowers:brainstorm                     # Clarify: OAuth? Password rules? Session timeout?
start^:                                     # Gather codebase context
/superpowers:write-plan                     # Generate implementation plan
yert                                        # Approve plan, lock scope
/superpowers:execute-plan                   # Implement with review checkpoints
finito                                      # Verify, commit, archive summary
```

Each phase builds on the previous. The key insight: requirements are locked before coding starts, preventing scope creep and rework.

## Next Steps

- [Integration Guide](integration-guide.md) — How cc-sessions and Superpowers work together
- [Command Reference](../quick-reference/commands.md) — All commands with descriptions
- [Examples](examples.md) — Real-world scenarios
- [Cross-Session Memory](claude-mem-guide.md) — Persistent memory across sessions
