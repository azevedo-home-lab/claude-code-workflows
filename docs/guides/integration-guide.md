# DAIC + Superpowers Integration Guide

How cc-sessions and Superpowers work together. For command reference, see [commands.md](../quick-reference/commands.md). For examples, see [examples.md](examples.md).

## cc-sessions: Task Lifecycle

Manages the DAIC loop — Discuss, Align, Implement, Check.

| Command | Phase | What It Does |
|---------|-------|-------------|
| `mek: <task>` | Discuss | Creates task, initializes session log, locks tool writes |
| `start^:` | Align | Gathers codebase context, loads past session summaries |
| `yert` | Implement | Locks approved scope, allows code edits only for approved items |
| `finito` | Check | Runs verification, auto-commits, archives session log |

### Scope Enforcement

After `yert`, cc-sessions blocks changes outside the approved plan:

```
Claude: "While I'm here, let me also add SMS notifications"
cc-sessions: ⚠️ Not in approved plan. Return to Discussion or continue with approved scope?
```

### Session Logs and Summaries

Stored in `sessions/logs/`. Capture requirements, approved plan, implementation actions, key decisions, and verification results. Future sessions can load these for warm starts.

## Superpowers: Development Skills

Provides structured techniques that auto-activate contextually.

### Manual Commands (Workflow-Driven)

| Command | When | Output |
|---------|------|--------|
| `/superpowers:brainstorm` | Discussion phase | Structured Q&A → refined requirements in `docs/vision.md` |
| `/superpowers:write-plan` | Alignment phase | Numbered implementation plan with testing steps |
| `/superpowers:execute-plan` | Implementation phase | Batch execution with review checkpoints |

### Auto-Activated Skills (Context-Driven)

| Skill | Triggers When |
|-------|--------------|
| TDD | Creating new functions/modules |
| Systematic Debugging | Error logs or stack traces present |
| Code Review | Refactoring or improving existing code |
| Error Fix | Errors detected during implementation |
| Verification | Before `finito` completion |
| Worktrees | Working on multiple features in parallel |
| Deploy Production | Deploying to production |

## Combined Workflow

```
mek: Add feature X          # cc-sessions: create task
/superpowers:brainstorm      # Superpowers: clarify requirements
start^:                      # cc-sessions: gather codebase context
/superpowers:write-plan      # Superpowers: generate plan
yert                         # cc-sessions: lock scope
/superpowers:execute-plan    # Superpowers: implement with checkpoints
finito                       # cc-sessions: verify, commit, archive
```

## Best Practices

1. **Always brainstorm** — even if requirements seem clear, it catches edge cases
2. **Review plans before `yert`** — easier to change now than during coding
3. **Trust checkpoints** — review at each pause, catching issues early is cheap
4. **Don't fight scope enforcement** — return to Discussion or create a new task
5. **Read your summary** — it's what future-you will load for context

## Installation

```bash
plugin marketplace add obra/superpowers-marketplace
plugin install superpowers@superpowers-marketplace
mkdir -p sessions/logs .claude/context
```

Verify: `/help` should show Superpowers commands.

## Troubleshooting

- **Commands not showing**: `plugin list` to verify, reinstall if needed
- **Skills not activating**: Mention the pattern explicitly (e.g., "let's use TDD")
- **Context gathering slow**: First run analyzes entire codebase; use `.claudeignore` for large dirs
