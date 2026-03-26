# Design Spec: Autonomy Off Redesign, /complete Push, /wf: Aliases

**Date:** 2026-03-26
**Decision Record:** `docs/plans/2026-03-26-autonomy-aliases-decisions.md`
**Issues:** #4228, #4194.1, #4194.2, #4197

## Overview

Three workstreams in a single implementation session:

1. **Autonomy `off` redesign** — Change from "block all writes" to "same permissions as `ask`, step-by-step discipline via command instructions"
2. **`/complete` push** — Ensure the completion pipeline pushes to remote
3. **`/wf:` aliases + observation commands** — Add namespaced aliases for all WFM commands and 3 new observation management commands

## Workstream 1: Autonomy `off` Redesign

### Current Behavior

When autonomy is `off`:
- `workflow-gate.sh` (lines 32-38): Blocks ALL Write/Edit/MultiEdit/NotebookEdit operations regardless of phase
- `bash-write-guard.sh` (lines 104-115): Blocks ALL Bash write operations regardless of phase
- `autonomy.md`: Calls `EnterPlanMode`, announces "read-only mode"
- Result: `off` is unusable during IMPLEMENT/REVIEW — no writes possible

### New Behavior

When autonomy is `off`:
- Hooks: Same write permissions as `ask` — phase-gated (DEFINE/DISCUSS block non-whitelisted writes, IMPLEMENT/REVIEW allow all, COMPLETE allows docs)
- `autonomy.md`: No `EnterPlanMode`. Announces "supervised step-by-step mode"
- Command files: Add `off`-specific instructions — after each plan step, present diff and wait for user approval

### Three Autonomy Levels (Corrected Mental Model)

| Level | Checkpoint granularity | Hook enforcement | Instruction enforcement |
|---|---|---|---|
| **off** | Every plan step | Same as `ask` (phase-gated) | "After each step, present diff, wait for approval" |
| **ask** | Every phase boundary | Phase-gated writes | "Work freely within phase, stop at transitions" |
| **auto** | End-to-end | Phase-gated writes + auto-transition | "Full pipeline, stop only for user input or push" |

### Hook Changes

#### `workflow-gate.sh`

Remove the autonomy `off` block (lines 32-38):

```bash
# REMOVE THIS BLOCK:
# Autonomy off: block ALL writes regardless of phase
AUTONOMY_LEVEL=$(get_autonomy_level)
if [ "$AUTONOMY_LEVEL" = "off" ]; then
    cat > /dev/null  # consume stdin
    emit_deny "BLOCKED: ▶ Supervised (off) — read-only mode. No file writes allowed. Run /autonomy ask to enable writes."
    exit 0
fi
```

After removal, `off` falls through to the phase-gate logic (same path as `ask`/`auto`).

#### `bash-write-guard.sh`

Remove the autonomy `off` block (lines 104-115):

```bash
# REMOVE THIS BLOCK:
AUTONOMY_LEVEL=$(get_autonomy_level)
if [ "$AUTONOMY_LEVEL" = "off" ]; then
    if echo "$CLEAN_CMD" | grep -qE "$WRITE_PATTERN" || [ "$PYTHON_WRITE" = "true" ]; then
        emit_deny "BLOCKED: ▶ Supervised (off) — read-only mode. No Bash write operations allowed. Run /autonomy ask to enable writes."
        exit 0
    fi
    # Read-only Bash commands allowed at autonomy off
    exit 0
fi
```

After removal, `off` falls through to the phase-gate logic. The `AUTONOMY_LEVEL` variable is no longer read in this file.

Note: The defense-in-depth block (lines 117-130, blocks writes to workflow state files) and git commit allowlist (lines 77-88) are unchanged — they apply to all autonomy levels.

#### `autonomy.md`

Change from:
```markdown
- **off**: Call `EnterPlanMode`. Say: "▶ **Supervised** — read-only mode."
```

To:
```markdown
- **off**: Say: "▶ **Supervised** — step-by-step mode. I'll work within phase rules and pause after each plan step for your review."
```

No `EnterPlanMode` call. No `ExitPlanMode` needed (not in plan mode).

### Command File Changes

Add autonomy-aware `off` behavior to all 5 phase commands. The instruction block is inserted alongside existing autonomy-aware sections.

**Pattern for IMPLEMENT (implement.md):**
```markdown
**Autonomy-aware behavior:**
- **auto (▶▶▶):** [existing]
- **ask (▶▶):** [existing]
- **off (▶):** Work within phase rules. After completing each plan step, present the change (files modified, key diff), and wait for the user's explicit approval before proceeding to the next step. Never batch multiple steps.
```

**Pattern for other phases:**
- **define.md:** After each problem discovery exchange, summarize findings and wait for user direction.
- **discuss.md:** After each design decision, present the rationale and wait for confirmation.
- **review.md:** After each review agent returns, present findings individually and wait before dispatching the next.
- **complete.md:** After each pipeline step, present results and wait for approval before the next step.

### Test Changes

**Tests to modify (workflow-gate.sh suite):**

| Current test | Current assertion | New assertion |
|---|---|---|
| "Level 1 blocks Write in IMPLEMENT phase" | `assert_contains deny` | `assert_not_contains deny` "Level 1 allows Write in IMPLEMENT (same as ask)" |
| "Level 1 denial message mentions /autonomy" | `assert_contains /autonomy` | DELETE (no longer relevant) |
| "Level 1 does NOT block writes when phase is OFF" | unchanged | unchanged |

**Tests to modify (bash-write-guard.sh suite):**

| Current test | Current assertion | New assertion |
|---|---|---|
| "Level 1 blocks Bash write in IMPLEMENT phase" | `assert_contains deny` | `assert_not_contains deny` "Level 1 allows Bash write in IMPLEMENT (same as ask)" |
| "Level 1 denial message mentions /autonomy" | `assert_contains /autonomy` | DELETE |
| "Level 1 allows read-only Bash in IMPLEMENT" | unchanged | unchanged |
| "Level 1 blocks chained workflow-state bypass" | `assert_contains deny` | Change phase to DISCUSS. In IMPLEMENT, chained commands are allowed for ask/auto, so off should match. |
| "git commit allowed at Level 1" | unchanged | unchanged |
| "python3 write blocked at Level 1 in IMPLEMENT" | `assert_contains deny` | `assert_not_contains deny` — Level 1 in IMPLEMENT now allows writes |

**New tests to add:**

1. "Level 1 allows Write in IMPLEMENT (same as ask)" — workflow-gate
2. "Level 1 allows Bash write in IMPLEMENT (same as ask)" — bash-write-guard
3. "Level 1 blocks Write in DISCUSS (phase gate preserved)" — workflow-gate (verify off respects phase gates)
4. "Level 1 blocks Bash write in DISCUSS (phase gate preserved)" — bash-write-guard

### Documentation Changes

Update autonomy level descriptions in:

1. **README.md** — Autonomy levels table
2. **docs/reference/architecture.md** — Autonomy levels table
3. **docs/reference/hooks.md** — Autonomy enforcement section

Change `off` description from "All writes blocked regardless of phase" to "Step-by-step supervised. Same write permissions as ask. Claude pauses after each plan step for review."

## Workstream 1b: Git Commit in DISCUSS Verification

### Analysis

The `bash-write-guard.sh` git commit allowlist (lines 77-88) fires BEFORE the autonomy `off` block. Git commit is already allowed at all autonomy levels and phases. The test "git commit allowed at Level 1" (line 889-895) confirms this.

The reported issue (#4194.1) needs verification:
- If the issue is `git commit` being blocked → should be fixed by existing allowlist
- If the issue is `git add` being blocked → `git add` doesn't match WRITE_PATTERN, so it should pass
- If the issue is Write tool being blocked when writing spec files → the RESTRICTED_WRITE_WHITELIST already covers `docs/superpowers/specs/`

### Action

Add a verification test step in the implementation plan to reproduce the exact scenario: DISCUSS phase → write spec → git add → git commit. If any step fails, fix the specific blocker. If all pass, mark #4194.1 as working-as-intended.

## Workstream 2: /complete Push

### Current Behavior

`complete.md` Step 5 includes push instructions with YubiKey warning. The autonomy-aware section says auto should "only stop for git push (always requires confirmation)."

### Issue

The push instruction may not be prominent enough, or may be skipped when the working tree is clean. The issue (#4194.2) reports push never happens.

### Fix

Make push a distinct sub-step with its own milestone tracking rather than buried in the commit step:

1. Rename current Step 5 to "Step 5: Commit"
2. Add new "Step 5b: Push" as an explicit sub-step after commit
3. Push instructions:
   - All autonomy levels: Always ask "Push to remote?" with YubiKey warning
   - If user says yes: `git push origin HEAD`
   - Mark milestone: `set_completion_field "pushed" "true"` (new field, but NOT an exit gate — push is optional)

### Changes

- `complete.md`: Split Step 5 into commit + push sub-steps. Add explicit push block.
- `workflow-state.sh`: No changes needed — the `pushed` field is informational, not a gate milestone.

## Workstream 3: /wf: Aliases + Observation Commands

### Aliases

Create symlinks in `plugin/commands/` (the canonical source, not `.claude/commands/`):

```
plugin/commands/wf:define.md     → define.md
plugin/commands/wf:discuss.md    → discuss.md
plugin/commands/wf:implement.md  → implement.md
plugin/commands/wf:review.md     → review.md
plugin/commands/wf:complete.md   → complete.md
plugin/commands/wf:off.md        → off.md
plugin/commands/wf:autonomy.md   → autonomy.md
plugin/commands/wf:proposals.md  → proposals.md
```

8 symlinks total. These are relative symlinks within the same directory.

### Setup.sh Update

Add the `wf:` prefixed commands to the symlink creation loop in setup.sh section D:

```bash
# Create symlinks for plugin commands (idempotent)
COMMANDS_DIR="$PROJECT_DIR/.claude/commands"
mkdir -p "$COMMANDS_DIR"
for cmd in define discuss implement review complete off autonomy proposals; do
  # Short name
  if [ -f "$PLUGIN_ROOT/commands/$cmd.md" ] && [ ! -e "$COMMANDS_DIR/$cmd.md" ]; then
    ln -s "../../plugin/commands/$cmd.md" "$COMMANDS_DIR/$cmd.md"
  fi
  # wf: prefixed alias
  if [ -f "$PLUGIN_ROOT/commands/wf:$cmd.md" ] && [ ! -e "$COMMANDS_DIR/wf:$cmd.md" ]; then
    ln -s "../../plugin/commands/wf:$cmd.md" "$COMMANDS_DIR/wf:$cmd.md"
  fi
done
```

Wait — I need to check: does `setup.sh` currently create command symlinks? Let me re-read... No, it doesn't. The existing symlinks in `.claude/commands/` were created manually or by a previous setup mechanism. The current `setup.sh` only handles hooks, statusline, and permissions.

**Decision:** Add command symlink creation to setup.sh. This covers both existing short names and new `wf:` aliases. Existing symlinks won't be overwritten (the `[ ! -e ]` guard).

### Observation Commands

Three new command files in `plugin/commands/`:

#### `wf:obs-read.md`
```markdown
---
description: Read an observation by ID from claude-mem
---
Read observation $ARGUMENTS from claude-mem and display it.

Use the `get_observations` MCP tool with IDs: [$ARGUMENTS]. Present the observation title, type, and narrative to the user.
```

#### `wf:obs-track.md`
```markdown
---
description: Track an observation ID in the workflow status line
---
!`.claude/hooks/workflow-cmd.sh add_tracked_observation $ARGUMENTS && echo "Tracking observation #$ARGUMENTS"`

Confirm to the user that observation #$ARGUMENTS is now tracked and will appear in the status line.
```

#### `wf:obs-untrack.md`
```markdown
---
description: Stop tracking an observation ID
---
!`.claude/hooks/workflow-cmd.sh remove_tracked_observation $ARGUMENTS && echo "Untracked observation #$ARGUMENTS"`

Confirm to the user that observation #$ARGUMENTS is no longer tracked.
```

These use `wf:` prefix only — no short name aliases. They're utility commands, not core workflow phases.

### Test Changes

Add tests for:
1. `wf:` symlinks exist in plugin/commands/ and point to correct targets
2. `wf:obs-track` adds to tracked_observations (via workflow-state.sh function — already tested)
3. `wf:obs-untrack` removes from tracked_observations (already tested)
4. Setup.sh creates command symlinks in .claude/commands/

## Files Modified Summary

| File | Workstream | Change |
|---|---|---|
| `plugin/scripts/workflow-gate.sh` | WS1 | Remove autonomy `off` block |
| `plugin/scripts/bash-write-guard.sh` | WS1 | Remove autonomy `off` block |
| `plugin/commands/autonomy.md` | WS1 | Remove EnterPlanMode, update description |
| `plugin/commands/define.md` | WS1 | Add `off` behavior instructions |
| `plugin/commands/discuss.md` | WS1 | Add `off` behavior instructions |
| `plugin/commands/implement.md` | WS1 | Add `off` behavior instructions |
| `plugin/commands/review.md` | WS1 | Add `off` behavior instructions |
| `plugin/commands/complete.md` | WS1 + WS2 | Add `off` behavior + split push into sub-step |
| `plugin/scripts/setup.sh` | WS3 | Add command symlink creation |
| `plugin/commands/wf:*.md` (8 files) | WS3 | New symlink aliases |
| `plugin/commands/wf:obs-read.md` | WS3 | New observation read command |
| `plugin/commands/wf:obs-track.md` | WS3 | New observation track command |
| `plugin/commands/wf:obs-untrack.md` | WS3 | New observation untrack command |
| `tests/run-tests.sh` | WS1 | Update autonomy off tests, add new tests |
| `README.md` | WS1 | Update autonomy descriptions |
| `docs/reference/architecture.md` | WS1 | Update autonomy descriptions |
| `docs/reference/hooks.md` | WS1 | Update autonomy descriptions |

**Estimated total:** ~19 files modified/created, ~200 lines changed, ~100 lines added.
