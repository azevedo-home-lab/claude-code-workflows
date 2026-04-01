# Post-Tool Coaching Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `post-tool-coaching.sh` from 264-line sequential script to a dispatch-based architecture, fixing L1 coaching user visibility (#36) and eliminating structural debt (#38).

**Architecture:** Tool classification abstraction (`_classify_tool`) categorizes every tool call into one of four types. Main script dispatches by classification. L1 coaching delivery moves from `user-set-phase.sh` stdout to PostToolUse `additionalContext`/`systemMessage` via unified `_emit_output`. Late split: one variable (`MESSAGES`), two channels.

**Tech Stack:** Bash, jq, Claude Code PostToolUse hooks

**Spec:** `docs/specs/2026-04-01-post-tool-coaching-refactor.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `plugin/scripts/infrastructure/tool-classifier.sh` | Create | `_classify_tool` — single function, returns tool category |
| `plugin/scripts/l1/post-tool-delivery.sh` | Create | `_deliver_l1` — checks state, loads content, appends to MESSAGES |
| `plugin/scripts/post-tool-coaching.sh` | Rewrite | Dispatch-only: classify → track → dispatch → emit |
| `plugin/scripts/user-set-phase.sh` | Modify | Remove L1 stdout emission |
| `plugin/scripts/agent-set-phase.sh` | Modify | Remove L1 stdout emission |
| `plugin/scripts/l1/phase-coaching.sh` | Modify | Remove stderr debug line, pure content loader |
| `plugin/scripts/l2/standards-reinforcement.sh` | Modify | Replace `_trace` with `_log` |
| `plugin/scripts/l3/*.sh` (10 files) | Modify | Replace `_trace` with `_log` |

---

### Task 1: Create tool-classifier.sh

**Files:**
- Create: `plugin/scripts/infrastructure/tool-classifier.sh`

- [ ] **Step 1: Create the tool classifier module**

```bash
#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Tool classification for PostToolUse coaching dispatch.
# Returns one of: phase-transition, infrastructure-query, coaching-participant, irrelevant
#
# Usage: tool_type=$(_classify_tool "$TOOL_NAME" "$INPUT")

[ -n "${_WFM_TOOL_CLASSIFIER_LOADED:-}" ] && return 0
_WFM_TOOL_CLASSIFIER_LOADED=1

_classify_tool() {
    local tool_name="$1"
    local input="$2"

    if [ "$tool_name" = "Bash" ]; then
        local cmd
        cmd=$(echo "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) || cmd=""

        # Phase transitions: user-set-phase.sh or agent_set_phase via workflow-cmd.sh
        if echo "$cmd" | grep -qE '(^|/)user-set-phase\.sh'; then
            echo "phase-transition"
            return
        fi
        if echo "$cmd" | grep -qE '(^|/)workflow-cmd\.sh[[:space:]]+agent_set_phase'; then
            echo "phase-transition"
            return
        fi
        # Also match agent-set-phase.sh directly (sourced by workflow-cmd.sh)
        if echo "$cmd" | grep -qE '(^|/)agent-set-phase\.sh'; then
            echo "phase-transition"
            return
        fi

        # Infrastructure queries: workflow-cmd.sh (non-transition commands)
        if echo "$cmd" | grep -qE '(^|/)workflow-cmd\.sh'; then
            echo "infrastructure-query"
            return
        fi

        # All other Bash commands participate in coaching
        echo "coaching-participant"
        return
    fi

    # Non-Bash tools: check participation list
    case "$tool_name" in
        Agent|Write|Edit|MultiEdit|NotebookEdit|AskUserQuestion)
            echo "coaching-participant"
            ;;
        mcp*save_observation|mcp*get_observations)
            echo "coaching-participant"
            ;;
        *)
            echo "irrelevant"
            ;;
    esac
}
```

- [ ] **Step 2: Verify the file is syntactically valid**

Run: `bash -n plugin/scripts/infrastructure/tool-classifier.sh`
Expected: No output (clean syntax)

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/infrastructure/tool-classifier.sh
git commit -m "feat(#38): add tool classifier for PostToolUse dispatch

Categorizes tool calls into phase-transition, infrastructure-query,
coaching-participant, or irrelevant. Replaces scattered grep/case
checks in post-tool-coaching.sh."
```

---

### Task 2: Create l1/post-tool-delivery.sh

**Files:**
- Create: `plugin/scripts/l1/post-tool-delivery.sh`
- Read: `plugin/scripts/l1/phase-coaching.sh` (reused content loader)

- [ ] **Step 1: Create the L1 delivery module**

```bash
#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# L1 PostToolUse delivery — loads phase coaching content and appends to MESSAGES.
# Called by post-tool-coaching.sh when _classify_tool returns "phase-transition".
#
# Expected variables from caller:
#   PHASE, MESSAGES, _PROJECT_ROOT
# Expected functions from caller:
#   get_message_shown, get_autonomy_level, _update_state, _log

[ -n "${_WFM_L1_DELIVERY_LOADED:-}" ] && return 0
_WFM_L1_DELIVERY_LOADED=1

_SCRIPTS_DIR="${_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$_SCRIPTS_DIR/l1/phase-coaching.sh"

_deliver_l1() {
    # Only fire once per phase — message_shown guards against re-delivery
    if [ "$(get_message_shown)" = "true" ]; then
        _log "[WFM coach] L1: already delivered (message_shown=true), skipping"
        return
    fi

    local autonomy
    autonomy=$(get_autonomy_level)
    [ -z "$autonomy" ] && autonomy="ask"

    # Load L1 coaching content via the existing content loader
    PROJECT_ROOT="$_PROJECT_ROOT"
    local l1_content
    l1_content=$(_emit_phase_coaching "$PHASE" "$autonomy")

    if [ -z "$l1_content" ]; then
        _log "[WFM coach] L1: no coaching content for phase=$PHASE"
        return
    fi

    # Append to MESSAGES (same variable L2/L3 use)
    if [ -n "$MESSAGES" ]; then
        MESSAGES="$MESSAGES

$l1_content"
    else
        MESSAGES="$l1_content"
    fi

    # Mark as delivered so L2 can start firing
    _update_state '.message_shown = true'

    local line_count
    line_count=$(echo "$l1_content" | wc -l | tr -d ' ')
    _log "[WFM coach] L1: ${line_count} coaching lines loaded for $PHASE"
}
```

- [ ] **Step 2: Verify the file is syntactically valid**

Run: `bash -n plugin/scripts/l1/post-tool-delivery.sh`
Expected: No output (clean syntax)

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/l1/post-tool-delivery.sh
git commit -m "feat(#36): add L1 PostToolUse delivery module

Loads phase coaching content and appends to MESSAGES for delivery
via _emit_output. Replaces stdout emission from user-set-phase.sh
and agent-set-phase.sh."
```

---

### Task 3: Clean up l1/phase-coaching.sh

**Files:**
- Modify: `plugin/scripts/l1/phase-coaching.sh:66-73`

- [ ] **Step 1: Remove stderr debug output from _emit_phase_coaching**

The function currently has a stderr block at lines 68-72 that writes `[WFM coach] L1: N coaching lines emitted for phase` to stderr. This never reaches the user from `!backtick` context. The line count logging is now handled by `_deliver_l1` via `_log`.

Change lines 66-73 from:

```bash
    if [ -n "$msg" ]; then
        echo "$msg"
        if [ "${_WFM_DEBUG_LEVEL:-}" = "show" ]; then
            local line_count
            line_count=$(echo "$msg" | wc -l | tr -d ' ')
            echo "[WFM coach] L1: ${line_count} coaching lines emitted for $phase" >&2
        fi
    fi
```

To:

```bash
    if [ -n "$msg" ]; then
        echo "$msg"
    fi
```

- [ ] **Step 2: Remove _WFM_DEBUG_LEVEL from the function's documented dependencies**

The header comment at lines 17-18 mentions `_WFM_DEBUG_LEVEL`. Since the function no longer uses it, update the comment block. Change:

```bash
# Uses: PROJECT_ROOT (must be set by caller)
#       _WFM_DEBUG_LEVEL (set by debug-log.sh, must be sourced before calling)
```

To:

```bash
# Uses: PROJECT_ROOT (must be set by caller)
```

- [ ] **Step 3: Verify syntax**

Run: `bash -n plugin/scripts/l1/phase-coaching.sh`
Expected: No output (clean syntax)

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/l1/phase-coaching.sh
git commit -m "refactor(#38): make phase-coaching.sh a pure content loader

Remove stderr debug output that never reaches user from backtick
context. Logging now handled by _deliver_l1 via _log."
```

---

### Task 4: Remove L1 emission from user-set-phase.sh

**Files:**
- Modify: `plugin/scripts/user-set-phase.sh:22,83-85`

- [ ] **Step 1: Remove the phase-coaching.sh source**

Remove line 22:

```bash
source "$SCRIPT_DIR/l1/phase-coaching.sh"
```

- [ ] **Step 2: Remove the _emit_phase_coaching call**

Remove lines 83-85:

```bash
# Emit L1 coaching immediately at transition — not deferred to next tool call.
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
_emit_phase_coaching "$new_phase" "$current_autonomy"
```

- [ ] **Step 3: Verify syntax**

Run: `bash -n plugin/scripts/user-set-phase.sh`
Expected: No output (clean syntax)

- [ ] **Step 4: Verify the script still outputs the phase confirmation**

Confirm that `echo "Phase set to ${new_phase}. Re-evaluate."` (line 81) remains — this is the only stdout output from user-set-phase.sh going forward.

- [ ] **Step 5: Commit**

```bash
git add plugin/scripts/user-set-phase.sh
git commit -m "refactor(#36): remove L1 stdout emission from user-set-phase.sh

L1 coaching now delivered via PostToolUse hook (post-tool-coaching.sh)
through _deliver_l1, not raw stdout from the transition script."
```

---

### Task 5: Remove L1 emission from agent-set-phase.sh

**Files:**
- Modify: `plugin/scripts/agent-set-phase.sh:18,79-81`

- [ ] **Step 1: Remove the phase-coaching.sh source**

Remove line 18:

```bash
source "$SCRIPT_DIR/l1/phase-coaching.sh"
```

- [ ] **Step 2: Remove the _emit_phase_coaching call**

Remove lines 79-81:

```bash
    # Emit L1 coaching immediately at transition — not deferred to next tool call.
    PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
    _emit_phase_coaching "$new_phase" "$current_autonomy"
```

- [ ] **Step 3: Verify syntax**

Run: `bash -n plugin/scripts/agent-set-phase.sh`
Expected: No output (clean syntax)

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/agent-set-phase.sh
git commit -m "refactor(#36): remove L1 stdout emission from agent-set-phase.sh

Same change as user-set-phase.sh — L1 coaching now delivered via
PostToolUse hook through _deliver_l1."
```

---

### Task 6: Replace _trace with _log in L2/L3 scripts

`_trace` is called from 12 places across L2 and L3 scripts. Since we're eliminating the `_trace`/`DEBUG_TRACE` split, these calls need to become `_log` (file-only debug logging). The actual coaching content already flows into `MESSAGES` — these `_trace` calls are metadata about which checks fired, which belongs in the debug log file, not in `systemMessage`.

**Files:**
- Modify: `plugin/scripts/l2/standards-reinforcement.sh` (lines 16, 112, 132)
- Modify: `plugin/scripts/l3/generic-commit.sh` (line 42)
- Modify: `plugin/scripts/l3/skipping-research.sh` (line 23)
- Modify: `plugin/scripts/l3/all-findings-downgraded.sh` (line 39)
- Modify: `plugin/scripts/l3/no-verify-after-edits.sh` (line 27)
- Modify: `plugin/scripts/l3/stalled-auto-transition.sh` (line 44)
- Modify: `plugin/scripts/l3/short-agent-prompt.sh` (line 22)
- Modify: `plugin/scripts/l3/save-observation-quality.sh` (lines 32, 41)
- Modify: `plugin/scripts/l3/options-without-recommendation.sh` (line 24)
- Modify: `plugin/scripts/l3/step-ordering.sh` (line 104)

- [ ] **Step 1: Replace all `_trace` calls with `_log` in L2/L3 scripts**

In each file listed above, replace `_trace` with `_log`. These are all simple find-and-replace operations — the function signature is identical (`_trace "msg"` → `_log "msg"`).

Also update the dependency comment in `l2/standards-reinforcement.sh` line 16:

Change:
```bash
#   has_coaching_fired, add_coaching_fired, _trace, _log
```
To:
```bash
#   has_coaching_fired, add_coaching_fired, _log
```

- [ ] **Step 2: Verify syntax on all modified files**

Run: `for f in plugin/scripts/l2/standards-reinforcement.sh plugin/scripts/l3/*.sh; do echo "--- $f ---"; bash -n "$f" && echo "OK"; done`
Expected: All files report OK

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/l2/standards-reinforcement.sh plugin/scripts/l3/*.sh
git commit -m "refactor(#38): replace _trace with _log in L2/L3 scripts

_trace accumulated debug output into DEBUG_TRACE for systemMessage.
Since debug:show now mirrors MESSAGES directly (late split), the
trace metadata belongs in the debug log file only via _log."
```

---

### Task 7: Rewrite post-tool-coaching.sh

This is the main task. The file goes from 264 lines to ~150 lines of dispatch logic.

**Files:**
- Rewrite: `plugin/scripts/post-tool-coaching.sh`
- Read: `plugin/scripts/infrastructure/tool-classifier.sh` (from Task 1)
- Read: `plugin/scripts/l1/post-tool-delivery.sh` (from Task 2)
- Read: `plugin/scripts/l2/standards-reinforcement.sh` (from Task 6)
- Read: `plugin/scripts/l3/coaching-runner.sh` (unchanged, sourced)

- [ ] **Step 1: Write the new post-tool-coaching.sh**

Replace the entire file with:

```bash
#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Workflow Manager: PostToolUse coaching dispatch.
#
# Classifies each tool call and dispatches to the appropriate coaching layer:
#   phase-transition     → L1 (phase entry coaching)
#   infrastructure-query → skip (no coaching, no counter)
#   coaching-participant → L2 (standards) + L3 (anti-laziness)
#   irrelevant           → skip (no coaching, no counter)
#
# All output goes through _emit_output (late split):
#   MESSAGES → additionalContext (Claude, always)
#   MESSAGES → systemMessage (user, debug:show only)

set -euo pipefail

SCRIPT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/plugin/scripts"
source "$SCRIPT_DIR/workflow-facade.sh"
source "$SCRIPT_DIR/infrastructure/tool-classifier.sh"

_PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
COACHING_DIR="$_PROJECT_ROOT/plugin/coaching"
PHASES_DIR="$_PROJECT_ROOT/plugin/phases"

# Validate coaching directory exists — silent degradation if misconfigured
if [ ! -d "$COACHING_DIR" ]; then
    exit 0
fi

# Load a coaching message from file. Returns 1 if file missing (message skipped).
# $1: relative path under COACHING_DIR (e.g., "objectives/define.md")
# $2: optional PHASE value to substitute for {{PHASE}}
load_message() {
    local file="$COACHING_DIR/$1"
    if [ ! -f "$file" ]; then
        return 1
    fi
    local msg
    msg=$(cat "$file")
    if [ -n "${2:-}" ]; then
        msg=$(echo "$msg" | sed "s/{{PHASE}}/$2/g")
    fi
    echo "$msg"
}

# Read tool name and input from stdin (must happen before any early exits)
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || TOOL_NAME=""

# Helper: extract bash command from tool input (used by Layer 2/3 checks)
extract_bash_command() {
    echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo ""
}

# ---------------------------------------------------------------------------
# Observation ID tracking — runs before phase checks, captures regardless
# ---------------------------------------------------------------------------
if echo "$TOOL_NAME" | grep -qE 'mcp.*(save_observation|get_observations)'; then
    OBS_ID=$(echo "$INPUT" | jq -r '
    .tool_response.content[]?
    | select(.type == "text")
    | .text
    | try fromjson catch empty
    | if type == "array" then .[-1].id // empty
      elif type == "object" then .id // empty
      else empty end
' 2>/dev/null | tail -1) || OBS_ID=""
    if [[ "$OBS_ID" =~ ^[0-9]+$ ]]; then
        set_last_observation_id "$OBS_ID"
    fi
fi

# No state file = no coaching enforcement
if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

PHASE=$(get_phase)

# OFF phase = no coaching
if [ "$PHASE" = "off" ]; then
    exit 0
fi

# Read debug flag once for all layers
DEBUG_MODE=$(get_debug)
source "$SCRIPT_DIR/infrastructure/debug-log.sh" "post-tool-coaching"

# Collect messages from all layers
MESSAGES=""

# Compute uppercased phase once for all layers
PHASE_UPPER=$(echo "$PHASE" | tr '[:lower:]' '[:upper:]')
_log "[WFM coach] Tool: $TOOL_NAME (phase=$PHASE_UPPER)"

# ---------------------------------------------------------------------------
# Emit coaching output as JSON to stdout (late split).
# MESSAGES → additionalContext (Claude, always)
# MESSAGES → systemMessage (user, show mode only)
# Same content, two channels, one split point.
# ---------------------------------------------------------------------------
_emit_output() {
    if [ -z "$MESSAGES" ]; then return; fi

    _log "[WFM coach] Emitting ${#MESSAGES} chars to Claude"

    if [ "$_WFM_DEBUG_LEVEL" = "show" ]; then
        jq -n --arg m "$MESSAGES" \
            '{"systemMessage": $m, "hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $m}}'
    else
        jq -n --arg m "$MESSAGES" \
            '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $m}}'
    fi
}

# ---------------------------------------------------------------------------
# Classify and dispatch
# ---------------------------------------------------------------------------
tool_type=$(_classify_tool "$TOOL_NAME" "$INPUT")
_log "[WFM coach] Classification: $tool_type"

case "$tool_type" in
    phase-transition)
        # L1 only — no counter increment, no L2/L3
        source "$SCRIPT_DIR/l1/post-tool-delivery.sh"
        _deliver_l1
        ;;

    infrastructure-query)
        # No coaching, no counter — just emit (debug trace only)
        ;;

    coaching-participant)
        # Extract FILE_PATH for Write/Edit/MultiEdit (used by L2/L3 checks)
        FILE_PATH=""
        case "$TOOL_NAME" in
            Write|Edit|MultiEdit)
                FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || FILE_PATH=""
                ;;
        esac

        # Source and run L2
        source "$SCRIPT_DIR/l2/standards-reinforcement.sh"
        _run_l2

        # Source and run L3
        source "$SCRIPT_DIR/l3/coaching-runner.sh"
        L3_MSG=""

        source "$SCRIPT_DIR/l3/short-agent-prompt.sh"
        source "$SCRIPT_DIR/l3/generic-commit.sh"
        source "$SCRIPT_DIR/l3/all-findings-downgraded.sh"
        source "$SCRIPT_DIR/l3/save-observation-quality.sh"
        source "$SCRIPT_DIR/l3/skipping-research.sh"
        source "$SCRIPT_DIR/l3/options-without-recommendation.sh"
        source "$SCRIPT_DIR/l3/no-verify-after-edits.sh"
        source "$SCRIPT_DIR/l3/stalled-auto-transition.sh"
        source "$SCRIPT_DIR/l3/step-ordering.sh"

        _L3_CHECKS_FIRED=""
        for _check_fn in \
            check_short_agent_prompt \
            check_generic_commit \
            check_all_findings_downgraded \
            check_save_observation_quality \
            check_skipping_research \
            check_options_without_recommendation \
            check_no_verify_after_edits \
            check_stalled_auto_transition \
            check_step_ordering; do

            CHECK_RESULT=""
            "$_check_fn"
            if [ -n "$CHECK_RESULT" ]; then
                _append_l3 "$CHECK_RESULT"
                _L3_CHECKS_FIRED="$_L3_CHECKS_FIRED ${_check_fn#check_}"
            fi
        done

        if [ -n "$L3_MSG" ]; then
            if [ -n "$MESSAGES" ]; then
                MESSAGES="$MESSAGES

$L3_MSG"
            else
                MESSAGES="$L3_MSG"
            fi
        fi

        _log "[WFM coach] L3: fired=[${_L3_CHECKS_FIRED:- none}]"

        # Counter summary
        _COACH_COUNTER=$(jq -r '.coaching.tool_calls_since_agent // 0' "$STATE_FILE" 2>/dev/null) || _COACH_COUNTER="?"
        _COACH_L2_FIRED=$(jq -r '.coaching.layer2_fired // [] | join(",")' "$STATE_FILE" 2>/dev/null) || _COACH_L2_FIRED="?"
        _log "[WFM coach] Counters: calls_since_agent=$_COACH_COUNTER, layer2_fired=[$_COACH_L2_FIRED]"
        ;;

    irrelevant)
        _log "[WFM coach] L2: no trigger matched (tool not tracked)"
        ;;
esac

# ---------------------------------------------------------------------------
# OUTPUT: Late split — same content, two channels
# ---------------------------------------------------------------------------
_emit_output
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n plugin/scripts/post-tool-coaching.sh`
Expected: No output (clean syntax)

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/post-tool-coaching.sh
git commit -m "refactor(#38): rewrite post-tool-coaching.sh as dispatch pipeline

Replaces 264-line sequential script with ~150-line dispatch architecture:
- Tool classification via _classify_tool (phase-transition, infrastructure-query,
  coaching-participant, irrelevant)
- L1 delivery via _deliver_l1 on phase transitions
- Eliminates _trace/DEBUG_TRACE split — single MESSAGES variable
- Removes stale workflow-state.sh reference
- Late split in _emit_output: same content to additionalContext (Claude)
  and systemMessage (user in show mode)

Closes #36, closes #38."
```

---

### Task 8: Regenerate hook symlinks

The hook symlinks in `.claude/hooks/` must point to the current scripts. After modifying `post-tool-coaching.sh`, verify the symlinks are intact.

**Files:**
- Read: `.claude/hooks/` directory

- [ ] **Step 1: Verify post-tool-coaching.sh symlink**

Run: `ls -la .claude/hooks/ | grep post-tool`
Expected: `post-tool-coaching.sh -> ../../plugin/scripts/post-tool-coaching.sh` (or similar)

If the symlink is intact, the hook will pick up the rewritten file automatically. If broken, run the setup script:

Run: `plugin/scripts/setup.sh`

- [ ] **Step 2: Verify all hooks are intact**

Run: `ls -la .claude/hooks/`
Expected: All symlinks resolve to files in `plugin/scripts/`

- [ ] **Step 3: No commit needed** (no file changes)

---

### Task 9: Manual Verification

No automated test infrastructure exists. Verify the refactor works end-to-end.

- [ ] **Step 1: Verify L1 visibility in debug:show mode**

1. Ensure debug is set to show: `.claude/hooks/workflow-cmd.sh set_debug show`
2. Start a new session or set phase to off: type `/off`
3. Type `/discuss test`
4. **Expected in user terminal:** Full L1 coaching text appears via `systemMessage` — the `[Workflow Coach — DISCUSS]` objective, phase instructions, and auto-transition guidance
5. **Expected for Claude:** Same content appears as `<system-reminder>` via `additionalContext`

- [ ] **Step 2: Verify L1 invisible in debug:off mode**

1. Set debug to off: `.claude/hooks/workflow-cmd.sh set_debug off`
2. Type `/off` then `/discuss test`
3. **Expected in user terminal:** Only `Phase set to discuss. Re-evaluate.` — no coaching text visible
4. **Expected for Claude:** L1 coaching appears via `additionalContext` (Claude still receives it)

- [ ] **Step 3: Verify infrastructure queries don't trigger coaching**

1. Set debug to show
2. Run: `.claude/hooks/workflow-cmd.sh get_phase`
3. **Expected:** No `systemMessage` coaching output, no counter increment

- [ ] **Step 4: Verify L2/L3 still works**

1. In an active phase (e.g., implement), trigger a Write/Edit tool call
2. **Expected:** L2/L3 coaching fires as before — `systemMessage` in show mode, `additionalContext` always

- [ ] **Step 5: Verify counter not distorted**

1. Check counter before: `jq '.coaching.tool_calls_since_agent' .claude/state/workflow.json`
2. Run a `workflow-cmd.sh` command
3. Check counter after: `jq '.coaching.tool_calls_since_agent' .claude/state/workflow.json`
4. **Expected:** Counter unchanged (infrastructure-query classification skips increment)
