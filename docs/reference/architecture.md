# Architecture

How Workflow Manager, Superpowers, and claude-mem work together in Claude Code.

## System Overview

```
┌─────────────────────────────────────────────────────────┐
│                        User                             │
│            /define  /implement  /discuss                   │
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
| **Hooks** | PreToolUse deny | Blocks Write/Edit in DEFINE, DISCUSS, and COMPLETE phases | No |
| **Superpowers** | Prompt instructions | Guides brainstorm → plan → execute → verify | Yes (but less likely with hooks backing it up) |

The hooks enforce the **discuss-before-code boundary**. Superpowers handles the **quality of each phase**.

## Phase Model

```
         ┌──(/define)──> DEFINE ──(/discuss)──┐
OFF ─────┤                                    ├──> DISCUSS ──(/implement)──> IMPLEMENT ──(/review)──> REVIEW ──(/complete)──> COMPLETE ──> OFF
         └──(/discuss)────────────────────────┘

Any /phase command can jump directly to any phase. Soft gates warn when skipping recommended steps.

DEFINE:     Write/Edit BLOCKED (except specs/plans), Bash writes BLOCKED (except specs/plans)
DISCUSS:    Write/Edit BLOCKED (except specs/plans), Bash writes BLOCKED (except specs/plans)
IMPLEMENT:  Everything ALLOWED
REVIEW:     Everything ALLOWED (fixes from review)
COMPLETE:   Write/Edit BLOCKED (except docs), Bash writes BLOCKED (except docs)
```

## Component Responsibilities

### Workflow Manager — Hard Gates

- `workflow-gate.sh` — blocks Write/Edit/MultiEdit in DEFINE, DISCUSS, and COMPLETE phases (with different whitelist tiers)
- `bash-write-guard.sh` — blocks Bash write operations in DEFINE, DISCUSS, and COMPLETE phases
- `workflow-state.sh` — state read/write utility
- State: `.claude/state/workflow.json` (gitignored)

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
DEFINE PHASE (Diamond 1 — Problem Space, edits blocked, optional):
  /define → brainstorming with problem-discovery context
  Diverge: domain research, context gathering, assumption challenging agents
  Converge: outcome structurer, scope boundary checker agents
  Output: decision record with Problem section

TRANSITION: /discuss → proceed to solution design

DISCUSS PHASE (Diamond 2 — Solution Space, edits blocked):
  /discuss → brainstorming with solution-design context
  Diverge: solution researchers, prior art scanner agents
  Converge: codebase analyst, risk assessor agents
  Output: decision record enriched with Approaches + Decision sections
  /superpowers:writing-plans → implementation plan

TRANSITION: /implement → unlock edits (soft gate: warns if no plan)

IMPLEMENT PHASE (edits allowed):
  /superpowers:executing-plans → step-by-step with checkpoints
  /superpowers:test-driven-development → tests before code

TRANSITION: /review → enter review (soft gate: warns if no changes)

REVIEW PHASE (edits allowed for fixes):
  3 parallel review agents: code quality, security, architecture
  Verification agent filters false positives
  Findings persisted to decision record
  Fix issues or acknowledge

TRANSITION: /complete → enter completion (soft gate: warns if no review)

COMPLETE PHASE (code blocked, docs allowed):
  Plan validation → verify deliverables with behavioral evidence
  Outcome validation → check decision record outcomes and metrics
  Smart docs detection → recommend doc/README updates
  Commit and push
  Tech debt audit → review accepted trade-offs
  Handover → claude-mem observation with commit hash and decisions

TRANSITION: completes → back to OFF

Note: Any /phase command can jump directly to any phase.
Soft gates warn when skipping recommended steps but never block.
```

## File Organization

```
your-project/
├── .claude/
│   ├── hooks/
│   │   ├── workflow-state.sh       # State utility
│   │   ├── workflow-gate.sh        # Write/Edit gate
│   │   ├── bash-write-guard.sh     # Bash write gate
│   │   └── post-tool-navigator.sh  # Phase guidance messages
│   ├── commands/
│   │   ├── define.md               # /define command
│   │   ├── discuss.md              # /discuss command
│   │   ├── implement.md            # /implement command
│   │   ├── review.md               # /review command
│   │   └── complete.md             # /complete command
│   ├── state/
│   │   └── workflow.json           # Consolidated workflow state (gitignored)
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
