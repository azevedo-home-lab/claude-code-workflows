# Architecture

How the three tools work together in Claude Code.

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
┌──────────────┐              ┌─────────────────┐
│  cc-sessions │              │  Superpowers    │
│  (Lifecycle) │◄────────────►│  (Techniques)   │
└──────┬───────┘              └────────┬────────┘
       │                               │
       └───────────┬───────────────────┘
                   │
                   ↓
        ┌──────────────────────┐
        │  claude-mem (MCP)    │
        │  (Cross-session      │
        │   memory)            │
        └──────────────────────┘
```

## Component Responsibilities

### cc-sessions — Task Lifecycle

- Task creation and tracking (`mek:`)
- Git branch automation
- Context gathering at `start^:` (codebase analysis + past summaries)
- Scope enforcement after `yert` (blocks edits outside approved plan)
- Session logging and summaries in `sessions/logs/`
- Commit workflow at `finito`

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
- Supplements session logs with conversational context

## Integration Flow

```
DISCUSSION:
  mek: Add feature → cc-sessions creates task, locks tools
  /superpowers:brainstorm → Q&A refinement → docs/vision.md

ALIGNMENT:
  start^: → cc-sessions gathers context + claude-mem search
  /superpowers:write-plan → numbered plan

IMPLEMENTATION:
  yert → cc-sessions locks scope
  /superpowers:execute-plan → step-by-step with checkpoints
  (auto-skills: TDD, debugging, etc.)

CHECK:
  finito → verification → commit → summary → archive
```

## File Organization

```
your-project/
├── .claude/
│   ├── commands/          # Custom slash commands
│   └── settings.json      # Claude Code config
├── sessions/
│   └── logs/              # Session summaries (gitignored)
├── docs/
│   ├── vision.md          # Requirements (from brainstorm)
│   └── plans/             # Implementation plans
├── CLAUDE.md              # Project rules (committed)
└── src/                   # Your code
```

**Committed**: `CLAUDE.md`, `.claude/commands/`, `docs/plans/`, `docs/vision.md`
**Gitignored**: `sessions/`, `.claude/context/`, `.claude/.chats/`, `.claude/settings.local.json`

## Security

- Session logs gitignored (may contain code snippets)
- `token_do_not_commit/` in `.gitignore`
- `finito` scans for secret patterns before commit
- YubiKey FIDO2 signing optional (see CLAUDE.md template)
