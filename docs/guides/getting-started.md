# Getting Started

Get up and running with workflow enforcement + Superpowers + claude-mem.

## Prerequisites

- Claude Code installed
- Git repository for your project

## Setup

### 1. Install Workflow Enforcement Hooks

Copy the hooks and commands into your project:

```bash
mkdir -p .claude/hooks .claude/commands .claude/state
cp <claude-code-workflows>/.claude/hooks/workflow-state.sh .claude/hooks/
cp <claude-code-workflows>/.claude/hooks/workflow-gate.sh .claude/hooks/
cp <claude-code-workflows>/.claude/hooks/bash-write-guard.sh .claude/hooks/
cp <claude-code-workflows>/.claude/commands/approve.md .claude/commands/
cp <claude-code-workflows>/.claude/commands/discuss.md .claude/commands/
chmod +x .claude/hooks/*.sh
```

Add the hook configuration to `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit",
        "hooks": [{
          "type": "command",
          "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/workflow-gate.sh"
        }]
      },
      {
        "matcher": "Bash",
        "hooks": [{
          "type": "command",
          "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/bash-write-guard.sh"
        }]
      }
    ]
  }
}
```

Add `.claude/state/` to your `.gitignore`.

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
