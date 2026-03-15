# Workflow Manager Hooks Reference

## Overview

Two PreToolUse hooks enforce a plan-before-code workflow by blocking Write/Edit tool calls until the user explicitly approves a plan. This complements superpowers' prompt-based discipline with deterministic enforcement that Claude cannot rationalize away.

## Architecture

```
Layer 1: PreToolUse Hooks (Deterministic)       Layer 2: Superpowers Skills (Behavioral)
┌──────────────────────────────────────┐        ┌──────────────────────────────────┐
│ workflow-gate.sh                     │        │ /superpowers:brainstorm          │
│   Blocks Write/Edit in DISCUSS       │        │ /superpowers:write-plan          │
│                                      │        │ /superpowers:execute-plan        │
│ bash-write-guard.sh                  │        │ /superpowers:tdd                 │
│   Blocks Bash write ops in DISCUSS   │        │ /superpowers:verify              │
│                                      │        │ /superpowers:code-review         │
│ State: .claude/state/phase.json      │        │                                  │
└──────────────────────────────────────┘        └──────────────────────────────────┘
```

Hooks read state but never write it. Phase transitions are driven by user commands (`/approve`, `/discuss`).

## Phase Model

```
DISCUSS ──(/approve)──> IMPLEMENT ──(/review)──> REVIEW ──(/complete)──> DISCUSS
                              │                      │
                              └───── (/discuss) ─────┘ → DISCUSS
```

| Phase | Write/Edit/MultiEdit | Bash writes | Read/Grep/Glob/Agent | Git |
|-------|---------------------|-------------|---------------------|-----|
| DISCUSS | **BLOCKED** | **BLOCKED** | Allowed | Allowed |
| IMPLEMENT | Allowed | Allowed | Allowed | Allowed |
| REVIEW | Allowed | Allowed | Allowed | Allowed |

New sessions default to DISCUSS if no state file exists.

## Files

```
.claude/
├── hooks/
│   ├── workflow-state.sh       # State read/write utility (sourced by other scripts)
│   ├── workflow-gate.sh        # PreToolUse: blocks Write/Edit in DISCUSS
│   └── bash-write-guard.sh     # PreToolUse: blocks Bash writes in DISCUSS
├── commands/
│   ├── approve.md              # /approve → DISCUSS to IMPLEMENT
│   ├── review.md               # /review → IMPLEMENT to REVIEW
│   ├── complete.md             # /complete → REVIEW to DISCUSS
│   └── discuss.md              # /discuss → any phase to DISCUSS
├── state/
│   └── phase.json              # Current phase (gitignored)
└── settings.json               # Hook configuration
```

## Hook Details

### workflow-gate.sh

- **Matcher**: `Write|Edit|MultiEdit|NotebookEdit`
- **Logic**: Read phase from state file. If `discuss` → deny with message. If `implement` → allow.
- **No state file**: Allow (no enforcement on first run before setup).

### bash-write-guard.sh

- **Matcher**: `Bash`
- **Logic**: Read phase. If `implement` → allow all. If `discuss` → extract command, pattern-match for write operations, deny if found.
- **Patterns caught**: `>`, `>>`, `sed -i`, `tee`, `cat << EOF`, `python -c` with file writes, `echo >`.
- **Coverage**: ~95%. Claude isn't adversarial — it uses Bash as a fallback when Edit is blocked. Common patterns are sufficient.

### workflow-state.sh

- **Not a hook** — sourced by other scripts.
- **Functions**: `get_phase` (reads state, defaults to "discuss"), `set_phase <phase>` (writes state with timestamp).

## Commands

### /approve

Sets phase to `implement`. Code edits are unblocked. Instructs Claude to use `executing-plans` and `test-driven-development` superpowers. Use after reviewing and approving a plan.

### /review

Sets phase to `review`. Instructs Claude to use `verification-before-completion` and `requesting-code-review` superpowers. Use when implementation is done and ready for verification.

### /complete

Sets phase back to `discuss`. Signals task completion after successful review. Ready for next task.

### /discuss

Sets phase back to `discuss`. Code edits are blocked. Instructs Claude to use `brainstorming` and `writing-plans` superpowers. Use to abort/rethink from any phase.

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

## Known Limitations

1. **Bash bypass is ~95% covered**. A sufficiently creative command can slip through. Anthropic closed this as NOT_PLANNED (GitHub #29709).
2. **Hooks are stateless validators**. They only read `.claude/state/phase.json`. If the file is deleted or corrupted, enforcement stops (fails open).
3. **No scope enforcement**. Unlike cc-sessions, these hooks don't track which files are "in scope" for the approved plan. Any file can be edited in IMPLEMENT phase.
