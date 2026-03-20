# Workflow Manager Hooks Reference

## Overview

Two PreToolUse hooks and a PostToolUse coaching system enforce a plan-before-code workflow by blocking Write/Edit tool calls until the user explicitly approves a plan. This complements superpowers' prompt-based discipline with deterministic enforcement that Claude cannot rationalize away.

## Architecture

```
Layer 1: PreToolUse Hooks (Deterministic)       Layer 2: Superpowers Skills (Behavioral)
┌──────────────────────────────────────┐        ┌──────────────────────────────────┐
│ workflow-gate.sh                     │        │ /superpowers:brainstorm          │
│   Blocks Write/Edit in DEFINE,       │        │ /superpowers:write-plan          │
│   DISCUSS, and COMPLETE              │
│                                      │        │ /superpowers:execute-plan        │
│ bash-write-guard.sh                  │        │ /superpowers:tdd                 │
│   Blocks Bash write ops in DEFINE,   │        │ /superpowers:verify              │
│   DISCUSS, and COMPLETE              │        │ /superpowers:code-review         │
│ State: .claude/state/workflow.json   │        │                                  │
└──────────────────────────────────────┘        └──────────────────────────────────┘
```

Hooks read state but never write it. Phase transitions are driven by user commands (`/implement`, `/discuss`, etc.).

## Phase Model

```
OFF ──(/define)──> DEFINE ──(/discuss)──> DISCUSS ──(/implement)──> IMPLEMENT ──(/review)──> REVIEW ──(/complete)──> COMPLETE ──> OFF

Any /phase command can jump directly to any phase. Soft gates warn when skipping recommended steps.
```

| Phase | Write/Edit/MultiEdit | Bash writes | Read/Grep/Glob/Agent | Git |
|-------|---------------------|-------------|---------------------|-----|
| OFF | Allowed | Allowed | Allowed | Allowed |
| DEFINE | **BLOCKED** (except specs/plans) | **BLOCKED** (except specs/plans) | Allowed | Allowed |
| DISCUSS | **BLOCKED** (except specs/plans) | **BLOCKED** (except specs/plans) | Allowed | Allowed |
| IMPLEMENT | Allowed | Allowed | Allowed | Allowed |
| REVIEW | Allowed | Allowed | Allowed | Allowed |
| COMPLETE | **BLOCKED** (except docs) | **BLOCKED** (except docs) | Allowed | Allowed |

New sessions default to OFF if no state file exists.

## Files

```
.claude/
├── hooks/
│   ├── workflow-state.sh       # State read/write utility (sourced by other scripts)
│   ├── workflow-gate.sh        # PreToolUse: blocks Write/Edit in DISCUSS
│   └── bash-write-guard.sh     # PreToolUse: blocks Bash writes in DISCUSS
├── commands/
│   ├── define.md               # /define → OFF to DEFINE
│   ├── discuss.md              # /discuss → any phase to DISCUSS
│   ├── implement.md            # /implement → DISCUSS to IMPLEMENT
│   ├── review.md               # /review → IMPLEMENT to REVIEW
│   └── complete.md             # /complete → REVIEW to COMPLETE
├── state/
│   └── workflow.json           # Consolidated workflow state (gitignored)
└── settings.json               # Hook configuration
```

## Hook Details

### workflow-gate.sh

- **Matcher**: `Write|Edit|MultiEdit|NotebookEdit`
- **Logic**: Read phase from state file. If `define`, `discuss`, or `complete` → deny with message (with phase-specific whitelist tiers). If `implement` or `review` → allow.
- **Whitelist tiers**: DEFINE/DISCUSS allow specs/plans paths. COMPLETE allows docs paths.
- **No state file**: Allow (no enforcement on first run before setup).

### bash-write-guard.sh

- **Matcher**: `Bash`
- **Logic**: Read phase. If `implement` or `review` → allow all. If `define`, `discuss`, or `complete` → extract command, pattern-match for write operations, deny if found.
- **Patterns caught**: `>`, `>>`, `sed -i`, `tee`, `cat << EOF`, `python -c` with file writes, `echo >`.
- **Coverage**: ~95%. Claude isn't adversarial — it uses Bash as a fallback when Edit is blocked. Common patterns are sufficient.

### workflow-state.sh

- **Not a hook** — sourced by other scripts.
- **Functions**: `get_phase` (reads state, defaults to "off"), `set_phase <phase>` (writes state with timestamp).
- **State file**: `.claude/state/workflow.json` — consolidated state (phase, active skill, review status).

## Commands

### /implement

Sets phase to `implement`. Code edits are unblocked. Instructs Claude to use `executing-plans` and `test-driven-development` superpowers. Soft gate warns if no plan exists. Use after reviewing and approving a plan.

### /review

Sets phase to `review`. Instructs Claude to use `verification-before-completion` and `requesting-code-review` superpowers. Use when implementation is done and ready for verification.

### /complete

Sets phase to `complete`. Triggers verified completion with outcome validation, docs check, and handover. Soft gate warns if review wasn't completed. After completion, transitions to OFF.

### /discuss

Sets phase to `discuss`. Code edits are blocked. Instructs Claude to use `brainstorming` and `writing-plans` superpowers. Use to start a workflow or abort/rethink from any phase.

## Configuration

Add to `.claude/settings.json`:

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

## Coaching System (PostToolUse)

The `post-tool-navigator.sh` hook provides a three-layer coaching system via PostToolUse messages:

| Layer | Purpose | When |
|-------|---------|------|
| **Phase entry** | Orients Claude to the current phase's goals and allowed actions | On phase transitions |
| **Standards reinforcement** | References professional standards (docs/reference/professional-standards.md) | Periodically during IMPLEMENT and REVIEW |
| **Anti-laziness** | Detects shortcuts like placeholder code, incomplete implementations, skipped tests | After Write/Edit in IMPLEMENT |

Coaching messages are non-blocking guidance — they inform Claude's behavior but do not prevent tool use.

## Known Limitations

1. **Bash bypass is ~95% covered**. A sufficiently creative command can slip through. Anthropic closed this as NOT_PLANNED (GitHub #29709).
2. **Hooks are stateless validators**. They only read `.claude/state/workflow.json`. If the file is deleted or corrupted, enforcement stops (fails open).
3. **No scope enforcement**. Unlike cc-sessions, these hooks don't track which files are "in scope" for the approved plan. Any file can be edited in IMPLEMENT phase.
