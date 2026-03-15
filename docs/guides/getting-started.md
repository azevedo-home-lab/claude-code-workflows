# Getting Started

Get up and running with workflow enforcement + Superpowers + claude-mem.

## Prerequisites

- Claude Code installed
- Git repository for your project

## Setup

### 1. Install Workflow Enforcement Hooks

**One-liner (from your project root):**
```bash
curl -fsSL https://raw.githubusercontent.com/azevedo-home-lab/claude-code-workflows/main/install.sh | bash
```

**Or clone and install:**
```bash
git clone https://github.com/azevedo-home-lab/claude-code-workflows.git /tmp/ccw
/tmp/ccw/install.sh
rm -rf /tmp/ccw
```

The installer copies hooks, commands, creates `.claude/settings.json` (or warns if one exists), and adds `.claude/state/` to `.gitignore`.

Restart Claude Code after installing.

### 2. Install Superpowers

```bash
plugin marketplace add obra/superpowers-marketplace
plugin install superpowers@superpowers-marketplace
```

### 3. Install claude-mem (optional)

Follow the claude-mem installation guide for your platform. See [claude-mem guide](claude-mem-guide.md).

### 4. Copy CLAUDE.md Template

```bash
cp claude.md.template CLAUDE.md
```

Edit `CLAUDE.md` to fill in project-specific placeholders.

## Your First Workflow

```
"Add user authentication with JWT"       # Describe what you want
/superpowers:brainstorm                   # Clarify requirements (edits BLOCKED)
/superpowers:write-plan                   # Generate plan (edits still BLOCKED)
# Review the plan
/approve                                  # Unlock code edits
/superpowers:execute-plan                 # Implement with review checkpoints
/superpowers:verification-before-completion  # Verify before claiming done
/discuss                                  # Lock edits again for next task
```

The hooks enforce the boundary: Claude cannot write code until you approve. Superpowers guides the quality of each phase.

## Next Steps

- [Integration Guide](integration-guide.md) — How Superpowers skills work together
- [Hooks Reference](../reference/hooks.md) — How the enforcement hooks work
- [Command Reference](../quick-reference/commands.md) — All commands with descriptions
- [Cross-Session Memory](claude-mem-guide.md) — Persistent memory across sessions
