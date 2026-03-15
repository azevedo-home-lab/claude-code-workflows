# Architecture

How Superpowers and claude-mem work together in Claude Code.

## System Overview

```
┌─────────────────────────────────────────────────────────┐
│                        User                             │
└───────────────────┬─────────────────────────────────────┘
                    │
                    ↓
        ┌──────────────────────────┐
        │     Claude Code CLI      │
        └──────────┬────────┬──────┘
                   │        │
        ┌──────────┘        └──────────┐
        ↓                              ↓
┌──────────────────┐          ┌─────────────────┐
│  Superpowers     │          │  claude-mem     │
│  (Skills &       │          │  (Cross-session │
│   Techniques)    │          │   memory)       │
└──────────────────┘          └─────────────────┘
```

## Component Responsibilities

### Superpowers — Development Techniques

- `/superpowers:brainstorm` — requirements refinement
- `/superpowers:write-plan` — plan generation
- `/superpowers:execute-plan` — batch execution with checkpoints
- Auto-activated skills: TDD, debugging, code review, verification, worktrees

Skills load on-demand when contextually relevant, not preloaded.

### claude-mem — Cross-Session Memory

- Persists observations (decisions, discoveries, preferences) across sessions
- `mem-search` for loading prior context at session start
- `make-plan` / `do` for plan creation and execution

## Workflow

```
REQUIREMENTS:
  Describe what you want
  /superpowers:brainstorm → Q&A refinement

PLANNING:
  /superpowers:write-plan → numbered plan
  Review and approve

IMPLEMENTATION:
  /superpowers:execute-plan → step-by-step with checkpoints
  (auto-skills: TDD, debugging, etc.)

VERIFICATION:
  /superpowers:verification-before-completion → verify
  Commit
```

## File Organization

```
your-project/
├── .claude/
│   ├── skills/            # Custom skills (optional)
│   └── settings.json      # Claude Code config
├── docs/
│   └── plans/             # Implementation plans
├── CLAUDE.md              # Project rules (committed)
└── src/                   # Your code
```

## Security

- `token_do_not_commit/` in `.gitignore`
- YubiKey FIDO2 signing optional (see CLAUDE.md template)
- Never commit credentials; use vault-managed secrets
