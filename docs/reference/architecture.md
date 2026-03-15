# Architecture

How workflow hooks, Superpowers, and claude-mem work together in Claude Code.

## System Overview

```
┌─────────────────────────────────────────────────────────┐
│                        User                             │
│                  /approve  /discuss                      │
└───────────────────┬─────────────────────────────────────┘
                    │
                    ↓
        ┌──────────────────────────┐
        │     Claude Code CLI      │
        └──┬──────────┬────────┬──┘
           │          │        │
     ┌─────┘          │        └──────┐
     ↓                ↓               ↓
┌──────────┐  ┌──────────────┐  ┌───────────┐
│ Workflow │  │ Superpowers  │  │ claude-mem│
│ Hooks    │  │ (Skills &    │  │ (Cross-   │
│ (Hard    │  │  Techniques) │  │  session  │
│  gates)  │  │              │  │  memory)  │
└──────────┘  └──────────────┘  └───────────┘
 Deterministic   Behavioral       Persistence
 enforcement     guidance         & recall
```

## Two-Layer Enforcement

| Layer | Mechanism | What it does | Can Claude bypass? |
|-------|-----------|-------------|-------------------|
| **Hooks** | PreToolUse deny | Blocks Write/Edit in DISCUSS phase | No |
| **Superpowers** | Prompt instructions | Guides brainstorm → plan → execute → verify | Yes (but less likely with hooks backing it up) |

The hooks enforce the **discuss-before-code boundary**. Superpowers handles the **quality of each phase**.

## Phase Model

```
DISCUSS ──(/approve)──> IMPLEMENT ──(/discuss)──> DISCUSS

DISCUSS:    Write/Edit BLOCKED, Bash writes BLOCKED, Read/Grep ALLOWED
IMPLEMENT:  Everything ALLOWED
```

## Component Responsibilities

### Workflow Hooks — Hard Gates

- `workflow-gate.sh` — blocks Write/Edit/MultiEdit in DISCUSS phase
- `bash-write-guard.sh` — blocks Bash write operations in DISCUSS phase
- `workflow-state.sh` — state read/write utility
- State: `.claude/state/phase.json` (gitignored)

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
DISCUSS PHASE (edits blocked):
  Describe what you want
  /superpowers:brainstorm → Q&A refinement
  /superpowers:write-plan → numbered plan
  Review the plan

TRANSITION:
  /approve → unlock edits

IMPLEMENT PHASE (edits allowed):
  /superpowers:execute-plan → step-by-step with checkpoints
  (auto-skills: TDD, debugging, etc.)
  /superpowers:verification-before-completion → verify
  Commit

TRANSITION:
  /discuss → lock edits for next task
```

## File Organization

```
your-project/
├── .claude/
│   ├── hooks/
│   │   ├── workflow-state.sh       # State utility
│   │   ├── workflow-gate.sh        # Write/Edit gate
│   │   └── bash-write-guard.sh     # Bash write gate
│   ├── commands/
│   │   ├── approve.md              # /approve command
│   │   └── discuss.md              # /discuss command
│   ├── state/
│   │   └── phase.json              # Phase state (gitignored)
│   └── settings.json               # Hook configuration
├── docs/
│   └── plans/                      # Implementation plans
├── CLAUDE.md                       # Project rules (committed)
└── src/                            # Your code
```

## Security

- `token_do_not_commit/` in `.gitignore`
- `.claude/state/` in `.gitignore` (session state, not committed)
- YubiKey FIDO2 signing optional (see CLAUDE.md template)
- Never commit credentials; use vault-managed secrets
