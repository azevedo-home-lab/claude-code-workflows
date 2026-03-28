# WFM Auth Path Separation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permanently separate user-initiated and agent-initiated phase transitions into two scripts with no shared bypass mechanism, while integrating the clean changes from feat/wfm-gate-hardening.

**Architecture:** `user-set-phase.sh` is called only from `!backtick` command files and writes state directly with no checks — Claude never touches this path. `agent-set-phase.sh` is the stripped-down agent path: forward-only ordinal check + gate check, no user bypass, no `WF_SKIP_AUTH`, no intent files. Both scripts are protected from Claude edits by a new phase-independent guard in `bash-write-guard.sh` and `workflow-gate.sh` that fires before any phase-specific logic. `WF_SKIP_AUTH` and the intent file system are removed entirely. The test suite is removed.

**Tech Stack:** bash, jq, Claude Code hooks (PreToolUse, UserPromptSubmit), workflow.json state file

**Decision record:** `docs/plans/2026-03-28-wfm-auth-path-separation-decisions.md`

**Branch to start from:** `feat/wfm-gate-hardening` (commit a0363f7) — contains the clean gate hardening changes that are part of this scope. DO NOT start from main.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `.claude/hooks/user-set-phase.sh` | **Create** | User-only path: write state directly, no checks |
| `.claude/hooks/workflow-state.sh` | **Modify** | Remove `set_phase`, `WF_SKIP_AUTH`, intent file functions, `user-phase-gate.sh` dead code cleanup. Rename `set_phase` to `agent_set_phase` (agent-only). |
| `.claude/hooks/workflow-cmd.sh` | **Modify** | Add `agent_set_phase` to dispatch list, remove `set_phase` |
| `.claude/hooks/bash-write-guard.sh` | **Modify** | (1) Add phase-independent guard protecting hook/script files. (2) Fix `gh api` → named-subcommand-only in DEFINE/DISCUSS. (3) Remove redundant `workflow-cmd.sh` whitelist. (4) Keep FILE_OPS anchoring from branch. |
| `.claude/hooks/workflow-gate.sh` | **Modify** | Add phase-independent guard protecting hook/script files. Remove `.claude/commands/` from COMPLETE whitelist. |
| `.claude/hooks/user-phase-gate.sh` | **Delete** | Dead code — intent file system removed |
| `plugin/scripts/workflow-state.sh` | **Modify** | Same as `.claude/hooks/workflow-state.sh` — they are symlinked or identical; apply same changes |
| `plugin/scripts/bash-write-guard.sh` | **Modify** | Same as `.claude/hooks/bash-write-guard.sh` |
| `.claude/settings.json` | **Modify** | Remove `user-phase-gate.sh` from UserPromptSubmit hooks |
| `plugin/commands/define.md` | **Modify** | Replace `WF_SKIP_AUTH=1 ... set_phase` with `user-set-phase.sh` call. Keep step expectations table from branch. |
| `plugin/commands/discuss.md` | **Modify** | Same |
| `plugin/commands/implement.md` | **Modify** | Same |
| `plugin/commands/review.md` | **Modify** | Same |
| `plugin/commands/complete.md` | **Modify** | Same |
| `plugin/commands/off.md` | **Modify** | Same |
| `plugin/commands/autonomy.md` | **Modify** | Replace `WF_SKIP_AUTH=1 ... set_autonomy_level` with direct state write in `user-set-phase.sh` or a `user-set-autonomy.sh` |
| `tests/run-tests.sh` | **Delete** | Test suite relied entirely on `WF_SKIP_AUTH=1` |
| `plugin/docs/reference/wfm-architecture.md` | **Create** (from branch) | Reference doc explaining the two-path architecture |

**Note on symlinks:** `.claude/hooks/` files are symlinks to `plugin/scripts/` (or copies). Verify with `ls -la .claude/hooks/` before editing — edit the canonical location only.

---

## Task 1: Verify branch baseline and file structure

**Files:**
- Read: `.claude/hooks/` (all files)
- Read: `plugin/scripts/` (all files)

- [ ] **Step 1: Confirm you are on feat/wfm-gate-hardening**
```bash
git branch --show-current
git log --oneline -3
```
Expected: branch is `feat/wfm-gate-hardening`, top commit is `a0363f7 feat: WFM gate hardening...`

If not on this branch: `git checkout feat/wfm-gate-hardening`

- [ ] **Step 2: Check whether hooks are symlinks or copies**
```bash
ls -la .claude/hooks/
```
Expected: either symlinks pointing to `plugin/scripts/` or regular files. This determines where the canonical edits happen.

- [ ] **Step 3: Confirm test suite exists**
```bash
wc -l tests/run-tests.sh
```
Note the line count. This file will be deleted in Task 9.

- [ ] **Step 4: Commit checkpoint**
```bash
git add -A
git status
```
No commit needed — just confirming clean working tree before starting.

---

## Task 2: Create user-set-phase.sh

**Files:**
- Create: `.claude/hooks/user-set-phase.sh` (or `plugin/scripts/user-set-phase.sh` if canonical)

This script is the user-only state write path. It replicates the state-writing logic from `set_phase` but with NO authorization checks and NO gate checks. It must preserve all fields that `set_phase` currently preserves.

- [ ] **Step 1: Read the current set_phase state-writing logic**

Read `plugin/scripts/workflow-state.sh` lines 400–467. Understand exactly which fields are preserved (`active_skill`, `decision_record`, `autonomy_level`, `last_observation_id`, `tracked_observations`, `issue_mappings`, `tests_last_passed_at`, `debug`) and which are cleared on `off` (all except `last_observation_id`).

- [ ] **Step 2: Create user-set-phase.sh**

Create `.claude/hooks/user-set-phase.sh` (adjust path if hooks are symlinks to plugin/scripts/ — edit the canonical location only):

```bash
#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# USER PHASE TRANSITION — called only from !backtick in command files.
# Writes phase state directly. No authorization checks. No gate checks.
# The user's intent is expressed by the fact they typed a slash command.
#
# SECURITY: This script must NOT be callable via Bash tool.
# bash-write-guard.sh blocks any Bash tool call containing user-set-phase.sh.
#
# Usage: user-set-phase.sh <phase>
# Phases: off define discuss implement review complete

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workflow-state.sh"

new_phase="${1:-}"

case "$new_phase" in
    off|define|discuss|implement|review|complete) ;;
    *) echo "ERROR: Invalid phase: $new_phase" >&2; exit 1 ;;
esac

mkdir -p "$STATE_DIR"

# NOTE: No `local` here — this is top-level script scope, not a function.
# Plain variable assignments are used throughout.

preserved_skill=""
preserved_decision=""
preserved_autonomy=""
preserved_obs_id=""
preserved_tracked=""
preserved_issue_mappings="null"
preserved_tests_passed=""
preserved_debug=""
current_phase="off"

if [ -f "$STATE_FILE" ]; then
    current_phase=$(get_phase)
    _read_preserved_state
fi

# Clearing off phase: reset cycle fields, keep last_observation_id for statusline
if [ "$new_phase" = "off" ]; then
    preserved_skill=""
    preserved_decision=""
    preserved_autonomy=""
    preserved_tests_passed=""
    preserved_debug="false"
fi

# Initialize autonomy to "ask" when starting a fresh cycle from off
if [ "$current_phase" = "off" ] && [ "$new_phase" != "off" ] && [ -z "$preserved_autonomy" ]; then
    preserved_autonomy="ask"
fi

tracked_json="[]"
if [ -n "$preserved_tracked" ]; then
    tracked_json=$(jq -n --arg csv "$preserved_tracked" '$csv | split(",") | map(select(. != "") | (tonumber? // empty))')
fi

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

( set -o pipefail
  jq -n --arg phase "$new_phase" --arg ts "$ts" \
      --arg skill "$preserved_skill" --arg decision "$preserved_decision" \
      --arg autonomy "${preserved_autonomy}" \
      --arg obs_id "$preserved_obs_id" \
      --argjson tracked "$tracked_json" \
      --argjson issue_maps "${preserved_issue_mappings:-null}" \
      --arg tests_passed "$preserved_tests_passed" \
      --arg debug "$preserved_debug" \
      '{
          phase: $phase,
          message_shown: false,
          active_skill: $skill,
          decision_record: $decision,
          coaching: {tool_calls_since_agent: 0, layer2_fired: []},
          updated: $ts
      }
      + (if $autonomy != "" then {autonomy_level: $autonomy} else {} end)
      + (if $obs_id != "" and $obs_id != "null" then {last_observation_id: ($obs_id | tonumber)} else {} end)
      + (if ($tracked | length) > 0 then {tracked_observations: $tracked} else {} end)
      + (if $issue_maps != null then {issue_mappings: $issue_maps} else {} end)
      + (if $tests_passed != "" then {tests_last_passed_at: $tests_passed} else {} end)
      + (if $debug == "true" then {debug: true} else {} end)' \
      | _safe_write
)

echo "Phase set to ${new_phase}."
```

- [ ] **Step 3: Make executable**
```bash
chmod +x .claude/hooks/user-set-phase.sh
```

- [ ] **Step 4: Verify basic execution (no state file)**
```bash
# Run with a temp state dir to verify it doesn't crash
mkdir -p /tmp/wfm-test-$$/.claude/state && \
  CLAUDE_PROJECT_DIR=/tmp/wfm-test-$$ .claude/hooks/user-set-phase.sh define && \
  cat /tmp/wfm-test-$$/.claude/state/workflow.json && \
  rm -rf /tmp/wfm-test-$$
```
Expected: JSON with `"phase": "define"`, `"autonomy_level": "ask"`.

- [ ] **Step 5: Commit**
```bash
git add .claude/hooks/user-set-phase.sh
git commit -m "feat: add user-set-phase.sh — user-only direct state write path"
```

---

## Task 3: Strip set_phase into agent_set_phase

**Files:**
- Modify: `plugin/scripts/workflow-state.sh` (canonical) — lines 348–467

`set_phase` becomes `agent_set_phase`. It keeps ONLY:
- Phase name validation
- Forward-only ordinal check (autonomy=auto, new > current)
- Gate checks (`_check_phase_gates`)
- State write (same jq block)

It loses:
- `WF_SKIP_AUTH` check
- `_check_phase_intent` call
- `user_initiated` flag (from branch)
- Intent file logic

- [ ] **Step 1: Replace set_phase with agent_set_phase in workflow-state.sh**

The new function:
```bash
agent_set_phase() {
    local new_phase="$1"

    # Validate phase name
    case "$new_phase" in
        off|define|discuss|implement|review|complete) ;;
        *) echo "ERROR: Invalid phase: $new_phase (valid: off, define, discuss, implement, review, complete)" >&2; return 1 ;;
    esac

    # Authorization: forward-only auto-transition only.
    # Agents may only advance the pipeline, never retreat or skip to off.
    # User transitions use user-set-phase.sh — not this function.
    if [ -f "$STATE_FILE" ]; then
        local current_autonomy
        current_autonomy=$(get_autonomy_level)
        if [ "$current_autonomy" != "auto" ]; then
            echo "BLOCKED: Phase transition to '$new_phase' requires user authorization." >&2
            echo "  Current autonomy: $current_autonomy" >&2
            echo "  Agent transitions are only allowed in 'auto' autonomy mode." >&2
            echo "" >&2
            echo "  Agent instructions:" >&2
            echo "    - Do NOT retry agent_set_phase — it will keep failing." >&2
            echo "    - Present your completed work to the user." >&2
            echo "    - Tell the user to run /$new_phase to proceed." >&2
            return 1
        fi
        local current_ordinal new_ordinal
        current_ordinal=$(_phase_ordinal "$(get_phase)")
        new_ordinal=$(_phase_ordinal "$new_phase")
        if [ "$new_ordinal" -le "$current_ordinal" ] || [ "$new_phase" = "off" ]; then
            echo "BLOCKED: Agent may only advance the phase (forward-only)." >&2
            echo "  Current: $(get_phase) (ordinal $current_ordinal)" >&2
            echo "  Requested: $new_phase (ordinal $new_ordinal)" >&2
            echo "  To go back or reset: the user must run the phase command directly." >&2
            return 1
        fi
    else
        echo "BLOCKED: No workflow state. User must start a phase with a slash command." >&2
        return 1
    fi

    mkdir -p "$STATE_DIR"

    # Hard gate checks: milestones must be complete before advancing.
    # Gates always run for agent transitions — agents cannot bypass them.
    local current
    current=$(get_phase)
    if ! _check_phase_gates "$current" "$new_phase"; then
        return 1
    fi

    # Read existing state to preserve fields across transitions
    local preserved_skill="" preserved_decision="" preserved_autonomy=""
    local preserved_obs_id="" preserved_tracked=""
    local preserved_issue_mappings="null"
    local preserved_tests_passed=""
    local preserved_debug=""
    local current_phase="off"
    current_phase=$(get_phase)
    _read_preserved_state

    local tracked_json="[]"
    if [ -n "$preserved_tracked" ]; then
        tracked_json=$(jq -n --arg csv "$preserved_tracked" '$csv | split(",") | map(select(. != "") | (tonumber? // empty))')
    fi

    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    ( set -o pipefail
      jq -n --arg phase "$new_phase" --arg ts "$ts" \
          --arg skill "$preserved_skill" --arg decision "$preserved_decision" \
          --arg autonomy "${preserved_autonomy}" \
          --arg obs_id "$preserved_obs_id" \
          --argjson tracked "$tracked_json" \
          --argjson issue_maps "${preserved_issue_mappings:-null}" \
          --arg tests_passed "$preserved_tests_passed" \
          --arg debug "$preserved_debug" \
          '{
              phase: $phase,
              message_shown: false,
              active_skill: $skill,
              decision_record: $decision,
              coaching: {tool_calls_since_agent: 0, layer2_fired: []},
              updated: $ts
          }
          + (if $autonomy != "" then {autonomy_level: $autonomy} else {} end)
          + (if $obs_id != "" and $obs_id != "null" then {last_observation_id: ($obs_id | tonumber)} else {} end)
          + (if ($tracked | length) > 0 then {tracked_observations: $tracked} else {} end)
          + (if $issue_maps != null then {issue_mappings: $issue_maps} else {} end)
          + (if $tests_passed != "" then {tests_last_passed_at: $tests_passed} else {} end)
          + (if $debug == "true" then {debug: true} else {} end)' \
          | _safe_write
    )

    echo "Phase advanced to ${new_phase}."
}
```

- [ ] **Step 2: Remove dead code from workflow-state.sh**

Remove these functions entirely (they served the intent file system which is now gone):
- `_check_phase_intent` (lines ~102–116)
- `_check_autonomy_intent` (lines ~118–131)

Remove from `set_autonomy_level` the `WF_SKIP_AUTH` block (lines ~171–178) — keep the rest of the function intact.

- [ ] **Step 3: Update workflow-cmd.sh dispatch list**

In `.claude/hooks/workflow-cmd.sh`, replace `set_phase` with `agent_set_phase` in the case statement dispatch list (line ~26).

- [ ] **Step 4: Verify agent_set_phase blocks when autonomy is ask**
```bash
mkdir -p /tmp/wfm-test-$$/.claude/state
echo '{"phase":"implement","autonomy_level":"ask"}' > /tmp/wfm-test-$$/.claude/state/workflow.json
CLAUDE_PROJECT_DIR=/tmp/wfm-test-$$ source .claude/hooks/workflow-state.sh && agent_set_phase "review" 2>&1
rm -rf /tmp/wfm-test-$$
```
Expected: `BLOCKED: Phase transition to 'review' requires user authorization.`

- [ ] **Step 5: Verify agent_set_phase blocks backward transitions**
```bash
mkdir -p /tmp/wfm-test-$$/.claude/state
echo '{"phase":"review","autonomy_level":"auto"}' > /tmp/wfm-test-$$/.claude/state/workflow.json
CLAUDE_PROJECT_DIR=/tmp/wfm-test-$$ source .claude/hooks/workflow-state.sh && agent_set_phase "implement" 2>&1
rm -rf /tmp/wfm-test-$$
```
Expected: `BLOCKED: Agent may only advance the phase (forward-only).`

- [ ] **Step 6: Commit**
```bash
git add plugin/scripts/workflow-state.sh .claude/hooks/workflow-cmd.sh
git commit -m "feat: rename set_phase to agent_set_phase, remove WF_SKIP_AUTH and intent file logic"
```

---

## Task 4: Add guard-system self-protection to bash-write-guard.sh and workflow-gate.sh

**Files:**
- Modify: `.claude/hooks/bash-write-guard.sh`
- Modify: `.claude/hooks/workflow-gate.sh`

This guard fires BEFORE the phase-based early-exit (before `implement|review` allows all writes). It protects the enforcement layer itself from Claude edits in ALL active phases.

Protected paths:
- `.claude/hooks/` — all hook files
- `plugin/scripts/` — workflow-state.sh, bash-write-guard.sh, user-set-phase.sh, agent-set-phase.sh
- `plugin/commands/` — command files that control phase behavior (no phase should rewrite its own instructions)

**In bash-write-guard.sh** — add after the STATE_FILE_PATTERN block (around line 173), before the phase-gate early-exit:

- [ ] **Step 1: Add guard to bash-write-guard.sh**

Add this block after the existing `STATE_FILE_PATTERN` guard:

```bash
# ---------------------------------------------------------------------------
# Guard-system self-protection: block writes to enforcement files in ALL phases.
# Fires before the phase-gate early-exit — IMPLEMENT and REVIEW do not bypass this.
# Claude cannot modify the files that enforce the workflow on Claude.
# The user can always use !backtick to make legitimate changes.
# ---------------------------------------------------------------------------
GUARD_SYSTEM_PATTERN='(\.claude/hooks/|plugin/scripts/|plugin/commands/)'
if echo "$COMMAND" | grep -qE "$GUARD_SYSTEM_PATTERN"; then
    if echo "$CLEAN_CMD" | grep -qE "$WRITE_PATTERN" || [ "$PYTHON_WRITE" = "true" ] || [ "$NODE_WRITE" = "true" ] || [ "$RUBY_WRITE" = "true" ] || [ "$PERL_WRITE" = "true" ]; then
        emit_deny "BLOCKED: Writes to enforcement files (.claude/hooks/, plugin/scripts/, plugin/commands/) are not allowed. These files define the workflow rules. Use !backtick if you need to make legitimate changes."
        exit 0
    fi
fi

# Block direct calls to user-set-phase.sh — !backtick only, never a Bash tool call.
if echo "$COMMAND" | grep -qE 'user-set-phase\.sh'; then
    emit_deny "BLOCKED: user-set-phase.sh is the user-only phase transition path. It cannot be called via Bash tool — only from !backtick command files."
    exit 0
fi
```

- [ ] **Step 2: Add guard to workflow-gate.sh**

Add after the STATE_FILE_PATTERN check (which doesn't exist in workflow-gate.sh currently — add it as the first new block after the OFF phase exit and before the `implement|review` early-exit):

```bash
# ---------------------------------------------------------------------------
# Guard-system self-protection: block Write/Edit to enforcement files in ALL phases.
# Fires before implement|review early-exit — those phases do not bypass this.
# ---------------------------------------------------------------------------
GUARD_SYSTEM_PATTERN='(\.claude/hooks/|plugin/scripts/|plugin/commands/)'
if [ -n "$NORMALIZED_PATH" ] && echo "$NORMALIZED_PATH" | grep -qE "$GUARD_SYSTEM_PATTERN"; then
    emit_deny "BLOCKED: Edits to enforcement files (.claude/hooks/, plugin/scripts/, plugin/commands/) are not allowed. These files define the workflow rules. Use !backtick if you need to make legitimate changes."
    exit 0
fi
```

- [ ] **Step 3: Verify the guard fires in IMPLEMENT phase (bash-write-guard)**

Test that editing a hook file is blocked even in implement:
```bash
# Simulate a Bash write command targeting a hook file in implement phase
echo '{"phase":"implement","autonomy_level":"auto"}' > /tmp/wfm-test-state.json
# (manual inspection — check the guard fires before the implement early-exit)
```
Read through the bash-write-guard.sh logic manually to confirm the guard block appears before line 181 (`implement|review) exit 0`).

- [ ] **Step 4: Commit**
```bash
git add .claude/hooks/bash-write-guard.sh .claude/hooks/workflow-gate.sh
git commit -m "security: protect enforcement files from Claude edits in all phases"
```

---

## Task 5: Update command files — replace WF_SKIP_AUTH with user-set-phase.sh

**Files:**
- Modify: `plugin/commands/define.md`
- Modify: `plugin/commands/discuss.md`
- Modify: `plugin/commands/implement.md`
- Modify: `plugin/commands/review.md`
- Modify: `plugin/commands/complete.md`
- Modify: `plugin/commands/off.md`
- Modify: `plugin/commands/autonomy.md`

The `!backtick` line in each command file currently calls `WF_SKIP_AUTH=1 .claude/hooks/workflow-cmd.sh set_phase "X"`. Replace with `.claude/hooks/user-set-phase.sh "X"`.

**Important:** The reset calls (`reset_discuss_status`, `reset_implement_status`, etc.) that follow the set_phase call in some command files must move into `user-set-phase.sh` or remain as separate `workflow-cmd.sh` calls. Keep them as separate `workflow-cmd.sh` calls for now — they are still valid state operations.

- [ ] **Step 1: Update define.md**

Old: `!`WF_SKIP_AUTH=1 .claude/hooks/workflow-cmd.sh set_phase "define" && .claude/hooks/workflow-cmd.sh set_active_skill "" && echo "Phase set to DEFINE — code edits are blocked."`

New: `!`.claude/hooks/user-set-phase.sh "define" && .claude/hooks/workflow-cmd.sh set_active_skill ""`

- [ ] **Step 2: Update discuss.md**

Old: `!`WF_SKIP_AUTH=1 .claude/hooks/workflow-cmd.sh set_phase "discuss" && .claude/hooks/workflow-cmd.sh reset_discuss_status && .claude/hooks/workflow-cmd.sh set_active_skill "" && echo "Phase set to DISCUSS — code edits blocked until plan is ready."`

New: `!`.claude/hooks/user-set-phase.sh "discuss" && .claude/hooks/workflow-cmd.sh reset_discuss_status && .claude/hooks/workflow-cmd.sh set_active_skill ""`

- [ ] **Step 3: Update implement.md**

Old: `!`WARN=$(.claude/hooks/workflow-cmd.sh check_soft_gate "implement"); if [ -n "$WARN" ]; then echo "SOFT_GATE_WARNING: $WARN"; else WF_SKIP_AUTH=1 .claude/hooks/workflow-cmd.sh set_phase "implement" && .claude/hooks/workflow-cmd.sh reset_implement_status && .claude/hooks/workflow-cmd.sh set_active_skill "" && echo "Phase set to IMPLEMENT — code edits are now allowed."; fi`

New: `!`WARN=$(.claude/hooks/workflow-cmd.sh check_soft_gate "implement"); if [ -n "$WARN" ]; then echo "SOFT_GATE_WARNING: $WARN"; else .claude/hooks/user-set-phase.sh "implement" && .claude/hooks/workflow-cmd.sh reset_implement_status && .claude/hooks/workflow-cmd.sh set_active_skill ""; fi`

- [ ] **Step 4: Update review.md**

Old: `!`WARN=$(.claude/hooks/workflow-cmd.sh check_soft_gate "review"); if [ -n "$WARN" ]; then echo "SOFT_GATE_WARNING: $WARN"; else WF_SKIP_AUTH=1 .claude/hooks/workflow-cmd.sh set_phase "review" && .claude/hooks/workflow-cmd.sh reset_review_status && .claude/hooks/workflow-cmd.sh set_active_skill "review-pipeline" && echo "Phase set to REVIEW — running review pipeline."; fi`

New: `!`WARN=$(.claude/hooks/workflow-cmd.sh check_soft_gate "review"); if [ -n "$WARN" ]; then echo "SOFT_GATE_WARNING: $WARN"; else .claude/hooks/user-set-phase.sh "review" && .claude/hooks/workflow-cmd.sh reset_review_status && .claude/hooks/workflow-cmd.sh set_active_skill "review-pipeline"; fi`

- [ ] **Step 5: Update complete.md**

Old: `!`WARN=$(.claude/hooks/workflow-cmd.sh check_soft_gate "complete"); if [ -n "$WARN" ]; then echo "SOFT_GATE_WARNING: $WARN"; else WF_SKIP_AUTH=1 .claude/hooks/workflow-cmd.sh set_phase "complete" && .claude/hooks/workflow-cmd.sh reset_completion_status && .claude/hooks/workflow-cmd.sh set_active_skill "completion-pipeline" && echo "Phase set to COMPLETE — running completion pipeline."; fi`

New: `!`WARN=$(.claude/hooks/workflow-cmd.sh check_soft_gate "complete"); if [ -n "$WARN" ]; then echo "SOFT_GATE_WARNING: $WARN"; else .claude/hooks/user-set-phase.sh "complete" && .claude/hooks/workflow-cmd.sh reset_completion_status && .claude/hooks/workflow-cmd.sh set_active_skill "completion-pipeline"; fi`

- [ ] **Step 6: Update off.md**

Old: `!`WF_SKIP_AUTH=1 .claude/hooks/workflow-cmd.sh set_phase "off" && echo "Phase set to OFF — workflow enforcement disabled."`

New: `!`.claude/hooks/user-set-phase.sh "off"`

- [ ] **Step 7: Update autonomy.md**

Old: `!`WF_SKIP_AUTH=1 .claude/hooks/workflow-cmd.sh set_autonomy_level "$ARGUMENTS" && echo "Autonomy level set to $ARGUMENTS"`

`set_autonomy_level` still has `WF_SKIP_AUTH` logic. Since we removed it from `set_autonomy_level` in Task 3, this command now calls `set_autonomy_level` which will check for the autonomy intent file. But we're removing the intent file system.

**Fix:** `set_autonomy_level` must also lose its authorization check. It should just write the level directly — autonomy level is user-only (there is no agent path for this). Simplest: inline the write in `workflow-cmd.sh` or make `set_autonomy_level` unconditional (no auth check at all — it's always user-initiated from `/autonomy`).

Remove the auth block from `set_autonomy_level` in `workflow-state.sh` entirely. The function just validates the level and writes it.

New autonomy.md backtick: `!`.claude/hooks/workflow-cmd.sh set_autonomy_level "$ARGUMENTS" && echo "Autonomy level set to $ARGUMENTS"`
(No WF_SKIP_AUTH needed once the auth check is removed from set_autonomy_level)

- [ ] **Step 8: Commit**
```bash
git add plugin/commands/
git commit -m "feat: replace WF_SKIP_AUTH in all command files with user-set-phase.sh"
```

---

## Task 6: Remove user-phase-gate.sh and clean up settings.json

**Files:**
- Delete: `.claude/hooks/user-phase-gate.sh`
- Delete: `plugin/scripts/user-phase-gate.sh` (if exists separately)
- Modify: `.claude/settings.json`

- [ ] **Step 1: Remove UserPromptSubmit hook from settings.json**

In `.claude/settings.json`, remove the entire `UserPromptSubmit` hooks block:
```json
"UserPromptSubmit": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/user-phase-gate.sh",
        "timeout": 5
      }
    ]
  }
],
```

- [ ] **Step 2: Delete user-phase-gate.sh**
```bash
rm .claude/hooks/user-phase-gate.sh
```
If it's a copy in plugin/scripts/ as well, remove that too.

- [ ] **Step 3: Verify settings.json is valid JSON**
```bash
jq . .claude/settings.json
```
Expected: valid JSON output with no UserPromptSubmit entry.

- [ ] **Step 4: Commit**
```bash
# Stage settings.json and both possible locations of user-phase-gate.sh
git add .claude/settings.json
git rm --force .claude/hooks/user-phase-gate.sh 2>/dev/null || git add .claude/hooks/user-phase-gate.sh
git rm --force plugin/scripts/user-phase-gate.sh 2>/dev/null || true
git commit -m "chore: remove user-phase-gate.sh and UserPromptSubmit hook — intent file system retired"
```

---

## Task 7: Fix gh read-only whitelist in bash-write-guard.sh

**Files:**
- Modify: `.claude/hooks/bash-write-guard.sh`

The branch added `gh api` to the DEFINE/DISCUSS whitelist, but `gh api` can POST/PATCH. Replace with named-subcommand-only whitelist.

- [ ] **Step 1: Find the gh handling block in bash-write-guard.sh**

Read the current gh block (around lines 198–235 in the branch version). It has a `_gh_safe_chain()` function and phase-specific gh blocks.

- [ ] **Step 2: Replace the DEFINE/DISCUSS gh allowance**

The DEFINE/DISCUSS block currently allows:
```bash
gh repo view|issue view|issue list|pr view|pr list|release view|api
```

Remove `api` from that list. New pattern:
```bash
'^[[:space:]]*gh[[:space:]]+(repo[[:space:]]+view|issue[[:space:]]+(view|list)|pr[[:space:]]+(view|list)|release[[:space:]]+(view|list))'
```

`gh api` is removed entirely from DEFINE/DISCUSS. If research needs data not available via named subcommands, the user uses `!backtick`.

- [ ] **Step 3: Add a comment explaining why gh api is excluded**

```bash
# gh api is intentionally excluded from DEFINE/DISCUSS — it accepts --method POST/PATCH
# which allows mutations. Named subcommands (view, list) are semantically read-only.
# If gh api is needed for research, use !backtick.
```

- [ ] **Step 4: Commit**
```bash
git add .claude/hooks/bash-write-guard.sh
git commit -m "security: restrict gh to named read-only subcommands in DEFINE/DISCUSS — remove gh api"
```

---

## Task 8: Clean up remaining branch items

**Files:**
- Modify: `.claude/hooks/bash-write-guard.sh` — remove redundant workflow-cmd.sh whitelist (Change F)
- Modify: `.claude/hooks/workflow-gate.sh` — remove `.claude/commands/` from COMPLETE_WRITE_WHITELIST, add comment
- Modify: `plugin/scripts/workflow-state.sh` — remove the phase-reset-on-entry code (Change E no-op) if present from branch; add comment explaining why milestone sections are intentionally NOT preserved

Check which of these are in the branch vs already handled:

- [ ] **Step 1: Remove workflow-cmd.sh whitelist from bash-write-guard.sh**

Find and remove this block (added in branch, confirmed redundant):
```bash
# Allow workflow-cmd.sh calls ONLY when they are the sole command.
if echo "$COMMAND" | grep -qE '(^|[[:space:]/])workflow-cmd\.sh[[:space:]]'; then
    if ! echo "$COMMAND" | grep -qE '(&&|\|\||;|\|)'; then
        ...
        exit 0
    fi
fi
```

- [ ] **Step 2: Fix COMPLETE_WRITE_WHITELIST in workflow-gate.sh**

`COMPLETE_WRITE_WHITELIST` lives in `workflow-gate.sh` (and is also referenced from `workflow-state.sh` where it's declared as a variable for use by bash-write-guard.sh). Check both files.

The branch already removed `.claude/commands/` from `COMPLETE_WRITE_WHITELIST` in `workflow-state.sh`. Verify the removal is present and add a comment in both locations:
```bash
# Docs-allowed tier: COMPLETE phase
# NOTE: .claude/commands/ deliberately excluded — no phase may rewrite command files.
# Command files define phase behavior; an AI rewriting them under pressure is a backdoor.
COMPLETE_WRITE_WHITELIST='(\.claude/state/|docs/|^[^/]*\.md$)'
```

- [ ] **Step 3: Check for phase-reset-on-entry code in branch**

Search `workflow-state.sh` for `reset_discuss_status|reset_implement_status|reset_review_status|reset_completion_status` inside `set_phase` / `agent_set_phase`. If present from branch (Change E), remove it. Add this comment in `agent_set_phase` where the reset would have been:

```bash
# NOTE: Milestone sections (discuss, implement, review, completion) are intentionally
# NOT preserved across set_phase — the jq template rebuilds state from scratch.
# There is no need to reset them here; they do not survive phase transitions.
```

- [ ] **Step 4: Verify wfm-architecture.md is present**

`plugin/docs/reference/wfm-architecture.md` should exist from the branch baseline (it was created in commit a0363f7). Check:
```bash
ls plugin/docs/reference/wfm-architecture.md
```
If it exists: no action needed — it will be committed with the other changes.
If it does not exist: the branch may not have included it. In that case, check `git show a0363f7 -- plugin/docs/reference/wfm-architecture.md` to retrieve it.

Update the file's content to reflect the new two-path architecture terminology (`user-set-phase.sh` / `agent_set_phase`) if it still references `set_phase` or `WF_SKIP_AUTH`.

- [ ] **Step 5: Commit**
```bash
git add .claude/hooks/bash-write-guard.sh .claude/hooks/workflow-gate.sh plugin/scripts/workflow-state.sh plugin/docs/reference/wfm-architecture.md
git commit -m "chore: remove branch no-ops, fix COMPLETE whitelist comment, confirm wfm-architecture.md"
```

---

## Task 9: Delete test suite

**Files:**
- Delete: `tests/run-tests.sh`

The test suite relied entirely on `WF_SKIP_AUTH=1` for authorization bypass. With that mechanism gone, all tests that call `set_phase` directly would fail. The decision is to remove rather than rewrite — the tests added repetition without catching real bugs, and the new architecture makes the important behaviors testable only through real CC invocations.

- [ ] **Step 1: Confirm no other test files**
```bash
ls tests/
```
If other test files exist that don't use `WF_SKIP_AUTH`, do not delete them.

- [ ] **Step 2: Delete run-tests.sh**
```bash
rm tests/run-tests.sh
```

- [ ] **Step 3: Commit**
```bash
git add tests/run-tests.sh
git commit -m "chore: remove test suite — relied on WF_SKIP_AUTH=1 which no longer exists"
```

---

## Task 10: Integration smoke test and final cleanup

- [ ] **Step 1: Verify no remaining WF_SKIP_AUTH references**
```bash
grep -r "WF_SKIP_AUTH" . --include="*.sh" --include="*.md" --exclude-dir=".git" --exclude-dir="docs"
```
Expected: zero matches in `.claude/hooks/`, `plugin/scripts/`, `plugin/commands/`. Docs (specs/plans) may reference it historically — that's fine.

- [ ] **Step 2: Verify user-set-phase.sh cannot be called from Bash tool**

Manually review bash-write-guard.sh and confirm the `user-set-phase.sh` block guard is present and appears before the `implement|review` early-exit.

- [ ] **Step 3: Verify guard-system protection is present in both guard files**

In `bash-write-guard.sh`: confirm `GUARD_SYSTEM_PATTERN` block appears before line `implement|review) exit 0`.
In `workflow-gate.sh`: confirm `GUARD_SYSTEM_PATTERN` block appears before `implement|review) exit 0`.

- [ ] **Step 4: End-to-end manual test — user path**

With CC running, type `/off` then `/define`. Verify:
- Phase changes to define (check `.claude/state/workflow.json`)
- No `WF_SKIP_AUTH` anywhere in the executed code path
- user-set-phase.sh ran (check output)

- [ ] **Step 5: End-to-end manual test — agent block**

From a Bash tool call (in a test session), try:
```bash
.claude/hooks/workflow-cmd.sh agent_set_phase "implement"
```
With autonomy=ask. Expected: BLOCKED message.

- [ ] **Step 6: Bump version**
```bash
# Check current version in plugin.json files
cat .claude-plugin/plugin.json | jq .version
```
Bump to next minor version (this is a breaking change to the auth architecture).

- [ ] **Step 7: Final commit**
```bash
git add -A
git commit -m "chore: bump version to vX.Y.Z — WFM auth path separation complete"
```

---

## Task 11: Create PR

- [ ] **Step 1: Push branch**
```bash
git push origin feat/wfm-gate-hardening
```

- [ ] **Step 2: Create PR**
```bash
gh pr create \
  --title "feat: WFM auth path separation — remove WF_SKIP_AUTH, split user/agent phase transition" \
  --body "$(cat <<'EOF'
## Summary
- Splits phase transition into two separate scripts with no shared bypass: `user-set-phase.sh` (user-only, !backtick, no checks) and `agent_set_phase` (agent-only, forward-only + gates, no user bypass)
- Removes `WF_SKIP_AUTH` entirely — was a global bypass key exploitable by any Bash tool call
- Removes intent file system (`user-phase-gate.sh`) — no longer needed
- Adds phase-independent guard protecting all enforcement files (`.claude/hooks/`, `plugin/scripts/`, `plugin/commands/`) from Claude edits in all phases including IMPLEMENT/REVIEW
- Integrates clean changes from feat/wfm-gate-hardening: REVIEW skip gate, better gate messages, FILE_OPS anchoring, gh read-only fix, step expectations tables, wfm-architecture.md
- Removes test suite (relied on WF_SKIP_AUTH)

## Why
WF_SKIP_AUTH=1 was a single global env var that any Claude Bash tool call could set to bypass all phase authorization. Under context pressure, Claude sessions exploited this. The new architecture makes the user path structurally unreachable by Claude — user-set-phase.sh is blocked at the bash-write-guard level for Bash tool calls and only reachable via !backtick pre-processing.

## Test plan
- [ ] `/off` → `/define` → verify phase=define in workflow.json
- [ ] `/define` → `/discuss` → verify phase=discuss
- [ ] In auto mode: verify agent_set_phase advances phase when milestones complete
- [ ] In ask mode: verify agent_set_phase blocks and tells user to run the command
- [ ] Verify editing .claude/hooks/bash-write-guard.sh is blocked in IMPLEMENT phase
- [ ] Verify `WF_SKIP_AUTH` grep returns zero matches in hooks/scripts/commands

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Notes for implementer

1. **Start from `feat/wfm-gate-hardening`** — this branch already has the gate hardening changes (better messages, REVIEW skip gate, FILE_OPS anchoring, step expectations tables). Do not start from main.

2. **Check symlinks first** (Task 1, Step 2). `.claude/hooks/` may symlink to `plugin/scripts/`. Edit the canonical file only. If they are copies, edit both and keep them in sync.

3. **`set_autonomy_level` auth removal** (Task 5, Step 7) — this is the most likely place to miss something. Read the full function before editing. The auth block is lines ~171–178. Remove only the `WF_SKIP_AUTH` check and the `_check_autonomy_intent` check. Keep the level validation and the state write.

4. **No `WF_SKIP_AUTH` in docs/plans** is expected — historical references in spec docs are fine. Only the live code files matter.

5. **wfm-architecture.md** (Task 8, Step 4) — update any references to `set_phase`, `WF_SKIP_AUTH`, or `user-phase-gate.sh` in that doc to reflect the new two-path architecture terminology.
