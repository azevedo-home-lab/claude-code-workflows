# Architecture

How Workflow Manager, Superpowers, and claude-mem work together in Claude Code.

## System Overview

```
┌─────────────────────────────────────────────────────────┐
│                        User                             │
│            /define  /approve  /discuss                    │
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
| **Hooks** | PreToolUse deny | Blocks Write/Edit in DEFINE and DISCUSS phases | No |
| **Superpowers** | Prompt instructions | Guides brainstorm → plan → execute → verify | Yes (but less likely with hooks backing it up) |

The hooks enforce the **discuss-before-code boundary**. Superpowers handles the **quality of each phase**.

## Phase Model

```
         ┌──(/define)──> DEFINE ──(/discuss)──┐
OFF ─────┤                                    ├──> DISCUSS ──(/approve)──> IMPLEMENT ──(/review)──> REVIEW ──(/complete)──> OFF
         └──(/discuss)────────────────────────┘         │                      │
                                                        └───── (/discuss) ─────┘

DEFINE:     Write/Edit BLOCKED, Bash writes BLOCKED, Read/Grep ALLOWED (optional phase)
DISCUSS:    Write/Edit BLOCKED, Bash writes BLOCKED, Read/Grep ALLOWED
IMPLEMENT:  Everything ALLOWED
REVIEW:     Everything ALLOWED (fixes from review)
```

## Component Responsibilities

### Workflow Manager — Hard Gates

- `workflow-gate.sh` — blocks Write/Edit/MultiEdit in DEFINE and DISCUSS phases
- `bash-write-guard.sh` — blocks Bash write operations in DEFINE and DISCUSS phases
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
DEFINE PHASE (edits blocked, optional):
  /define → guided problem + outcome definition
  Define problem statement, outcomes, success metrics
  Save to docs/plans/define.json

TRANSITION: /discuss → proceed to discussion

DISCUSS PHASE (edits blocked):
  Describe what you want
  /superpowers:brainstorming → Q&A refinement
  /superpowers:writing-plans → numbered plan
  Review the plan

TRANSITION: /approve → unlock edits

IMPLEMENT PHASE (edits allowed):
  /superpowers:executing-plans → step-by-step with checkpoints
  /superpowers:test-driven-development → tests before code

TRANSITION: /review → enter review

REVIEW PHASE (edits allowed for fixes):
  /superpowers:verification-before-completion → run tests, verify claims
  /superpowers:requesting-code-review → security, best practices, requirements
  Fix any issues found

TRANSITION: /complete → task done, back to discuss
           /discuss → abort, rethink
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
│   │   ├── define.md               # /define command
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
