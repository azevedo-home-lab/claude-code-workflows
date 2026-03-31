#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Workflow Manager: PostToolUse three-layer coaching system
# Layer 1: Phase entry — objective, scope, done criteria (once per phase)
# Layer 2: Professional standards reinforcement (periodic, contextual)
# Layer 3: Anti-laziness checks (on every red-flag match)
#
# All messages prefixed with [Workflow Coach — PHASE] for user visibility.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workflow-state.sh"

# Coaching message directory — resolved from project root, not SCRIPT_DIR.
# SCRIPT_DIR resolves to .claude/hooks/ (symlink directory), not plugin/scripts/.
COACHING_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/plugin/coaching"

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

# Skip coaching entirely for infrastructure Bash calls (phase transitions, state queries).
# PostToolUse output for these is swallowed by Claude Code, so L1 would waste
# its once-per-phase message on an invisible call.
if [ "$TOOL_NAME" = "Bash" ]; then
    _INFRA_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || _INFRA_CMD=""
    if echo "$_INFRA_CMD" | grep -qE '(^|/)(user-set-phase\.sh|workflow-cmd\.sh|workflow-state\.sh)'; then
        exit 0
    fi
fi

# ---------------------------------------------------------------------------
# Claude-mem observation ID tracking
# Extracts observation ID from save_observation (dict response) or
# get_observations (list response) and writes to workflow state.
# Runs before phase checks so IDs are captured regardless of phase.
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
    # Validate OBS_ID is numeric before storing
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
source "$SCRIPT_DIR/debug-log.sh" "post-tool-navigator"

# Collect debug trace for systemMessage injection (show mode only).
# _trace() logs via _show (file + stderr) AND collects into DEBUG_TRACE
# so the trace can be prepended to systemMessage — the only user-visible
# channel for PostToolUse hooks in Claude Code.
DEBUG_TRACE=""
_trace() {
    _show "$1"
    if [ "$_WFM_DEBUG_LEVEL" = "show" ]; then
        if [ -n "$DEBUG_TRACE" ]; then
            DEBUG_TRACE="$DEBUG_TRACE
$1"
        else
            DEBUG_TRACE="$1"
        fi
    fi
}

# Emit coaching output as JSON to stdout.
# - MESSAGES → additionalContext (Claude-visible, always)
# - In show mode, MESSAGES also → systemMessage (user-visible)
# - DEBUG_TRACE → systemMessage (user-visible, show mode only)
_emit_output() {
    if [ -n "$DEBUG_TRACE" ]; then
        DEBUG_TRACE="$_TOOL_HEADER
$DEBUG_TRACE"
    fi

    # In show mode, include coaching messages in systemMessage for user visibility
    local user_msg="$DEBUG_TRACE"
    if [ "$_WFM_DEBUG_LEVEL" = "show" ] && [ -n "$MESSAGES" ]; then
        if [ -n "$user_msg" ]; then
            user_msg="$user_msg
$MESSAGES"
        else
            user_msg="$_TOOL_HEADER
$MESSAGES"
        fi
    fi

    if [ -n "$MESSAGES" ] || [ -n "$user_msg" ]; then
        _log "[WFM coach] Message sent to Claude:"
        echo "$MESSAGES" | while IFS= read -r line; do _log "  $line"; done
        if [ -n "$user_msg" ] && [ -n "$MESSAGES" ]; then
            jq -n --arg coach "$MESSAGES" --arg trace "$user_msg" \
                '{"systemMessage": $trace, "hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $coach}}'
        elif [ -n "$user_msg" ]; then
            jq -n --arg trace "$user_msg" \
                '{"systemMessage": $trace}'
        else
            jq -n --arg coach "$MESSAGES" \
                '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $coach}}'
        fi
    fi
}

# Compute uppercased phase once for all layers
PHASE_UPPER=$(echo "$PHASE" | tr '[:lower:]' '[:upper:]')

_TOOL_HEADER="[WFM coach] Tool: $TOOL_NAME (phase=$PHASE_UPPER)"
_log "$_TOOL_HEADER"

# Collect messages from all layers — may combine multiple
MESSAGES=""

# Source coaching throttle engine (provides _should_fire, _reset_throttle, _append_l3)
source "$SCRIPT_DIR/coaching-runner.sh"

# ============================================================
# LAYER 1: Phase entry message (fires once per phase transition)
# ============================================================

if [ "$(get_message_shown)" != "true" ]; then
    # IMPLEMENT phase: only fire on Write/Edit/Bash, skip Read/Grep/Glob
    FIRE_LAYER1=true
    if [ "$PHASE" = "implement" ]; then
        case "$TOOL_NAME" in
            Write|Edit|MultiEdit|NotebookEdit|Bash) ;;
            *) FIRE_LAYER1=false ;;
        esac
    fi

    if [ "$FIRE_LAYER1" = "true" ]; then
        case "$PHASE" in
            error)
                ERR_MSG=$(load_message "objectives/error.md")
                if [ -n "$ERR_MSG" ]; then
                    MESSAGES="[Workflow Coach — ERROR]
$ERR_MSG"
                    _trace "[WFM coach] L1 FIRED: objectives/error.md"
                fi
                ;;
            *)
                OBJ_MSG=$(load_message "objectives/$PHASE.md")
                if [ -n "$OBJ_MSG" ]; then
                    MESSAGES="[Workflow Coach — $PHASE_UPPER]
$OBJ_MSG"
                    _trace "[WFM coach] L1 FIRED: objectives/$PHASE.md"
                fi
                ;;
        esac
        # Append auto-transition guidance if autonomy is "auto"
        AUTONOMY_LEVEL=$(get_autonomy_level)
        if [ "$AUTONOMY_LEVEL" = "auto" ] && [ -n "$MESSAGES" ]; then
            AUTO_MSG=$(load_message "auto-transition/$PHASE.md")
            if [ -z "$AUTO_MSG" ]; then
                AUTO_MSG=$(load_message "auto-transition/default.md")
            fi
            if [ -n "$AUTO_MSG" ]; then
                MESSAGES="$MESSAGES
$AUTO_MSG"
            fi
        fi

        # Skip state update in error phase — state is corrupt, writes will fail
        if [ "$PHASE" != "error" ]; then
            set_message_shown
        fi
    else
        _log "[WFM coach] L1: tool not eligible, skipped"
    fi
else
    _log "[WFM coach] L1: already shown, skipped"
fi

# Early exit for tools that don't participate in Layer 2/3
# These tools don't need coaching evaluation or counter tracking
case "$TOOL_NAME" in
    Agent|Write|Edit|MultiEdit|NotebookEdit|Bash|AskUserQuestion) ;;
    mcp*save_observation|mcp*get_observations) ;;
    *) # Tool is irrelevant to coaching — output any Layer 1 message and exit
        _log "[WFM coach] L2: no trigger matched (tool not tracked)"
        _emit_output
        exit 0
        ;;
esac

# ============================================================
# LAYER 2: Professional standards reinforcement (periodic)
# ============================================================

# Extract FILE_PATH once for Write/Edit/MultiEdit tools (used by multiple Layer 2/3 checks)
FILE_PATH=""
case "$TOOL_NAME" in
    Write|Edit|MultiEdit)
        FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || FILE_PATH=""
        ;;
esac

# Only fire if Layer 1 has already fired (message_shown = true means we're past entry)
if [ "$(get_message_shown)" = "true" ]; then
    # Refresh Layer 2 triggers after 30 calls of silence (before counter reset)
    check_coaching_refresh

    # Track agent dispatch counter
    if [ "$TOOL_NAME" = "Agent" ]; then
        reset_coaching_counter
    else
        increment_coaching_counter
    fi

    # Determine trigger type based on phase + tool pattern
    TRIGGER=""
    L2_MSG=""

    case "$PHASE" in
        define)
            if [ "$TOOL_NAME" = "Agent" ]; then
                TRIGGER="agent_return_define"
            elif [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
                if echo "$FILE_PATH" | grep -qE 'docs/plans/'; then
                    TRIGGER="plan_write_define"
                fi
            fi
            ;;
        discuss)
            if [ "$TOOL_NAME" = "Agent" ]; then
                TRIGGER="agent_return_discuss"
            elif [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
                if echo "$FILE_PATH" | grep -qE 'docs/plans/'; then
                    TRIGGER="plan_write_discuss"
                fi
            fi
            ;;
        implement)
            if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
                TRIGGER="source_edit_implement"
            elif [ "$TOOL_NAME" = "Bash" ]; then
                COMMAND=$(extract_bash_command)
                if echo "$COMMAND" | grep -qE '(pytest|npm test|cargo test|make test|run-tests|jest|vitest|go test)'; then
                    TRIGGER="test_run_implement"
                fi
            fi
            ;;
        review)
            if [ "$TOOL_NAME" = "Agent" ]; then
                TRIGGER="agent_return_review"
            fi
            ;;
        complete)
            if [ "$TOOL_NAME" = "Agent" ]; then
                TRIGGER="agent_return_complete"
            elif [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
                if echo "$FILE_PATH" | grep -qE 'docs/'; then
                    TRIGGER="project_docs_edit_complete"
                fi
            elif [ "$TOOL_NAME" = "Bash" ]; then
                BASH_CMD=$(extract_bash_command)
                if echo "$BASH_CMD" | grep -qE '(pytest|npm test|cargo test|make test|run-tests|jest|vitest|go test)'; then
                    TRIGGER="test_run_complete"
                fi
            fi
            ;;
    esac

    # Load nudge message and fire if trigger matched and hasn't fired yet this phase
    if [ -n "$TRIGGER" ]; then
        L2_MSG_BODY=$(load_message "nudges/$TRIGGER.md")
        if [ -n "$L2_MSG_BODY" ]; then
            L2_MSG="[Workflow Coach — $PHASE_UPPER] $L2_MSG_BODY"
        fi
    fi

    if [ -n "$TRIGGER" ] && [ -n "$L2_MSG" ]; then
        if [ "$(has_coaching_fired "$TRIGGER")" != "true" ]; then
            add_coaching_fired "$TRIGGER"
            if [ -n "$MESSAGES" ]; then
                MESSAGES="$MESSAGES

$L2_MSG"
            else
                MESSAGES="$L2_MSG"
            fi
            _trace "[WFM coach] L2: nudges/$TRIGGER.md — ${L2_MSG_BODY:0:80}..."
        else
            _log "[WFM coach] L2: trigger=$TRIGGER — already fired, skipped"
        fi
    elif [ -n "$TRIGGER" ]; then
        _log "[WFM coach] L2: trigger=$TRIGGER — no message file"
    else
        _log "[WFM coach] L2: no trigger matched"
    fi

    # REVIEW Layer 2 trigger: "After presenting findings"
    # Fires when writing review findings (Write/Edit/MultiEdit to spec in review phase)
    # This is separate from the agent_return_review trigger above
    if [ "$PHASE" = "review" ]; then
        if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
            if echo "$FILE_PATH" | grep -qE 'docs/specs/'; then
                FINDINGS_TRIGGER="findings_present_review"
                if [ "$(has_coaching_fired "$FINDINGS_TRIGGER")" != "true" ]; then
                    add_coaching_fired "$FINDINGS_TRIGGER"
                    FINDINGS_BODY=$(load_message "nudges/findings_present_review.md")
                    [ -n "$FINDINGS_BODY" ] && _trace "[WFM coach] L2: nudges/findings_present_review.md — ${FINDINGS_BODY:0:80}..."
                    if [ -n "$FINDINGS_BODY" ]; then
                        FINDINGS_MSG="[Workflow Coach — REVIEW] $FINDINGS_BODY"
                        if [ -n "$MESSAGES" ]; then
                            MESSAGES="$MESSAGES

$FINDINGS_MSG"
                        else
                            MESSAGES="$FINDINGS_MSG"
                        fi
                    fi
                fi
            fi
        fi
    fi
fi

# ============================================================
# LAYER 3: Anti-laziness checks (dispatched from individual files)
# ============================================================

L3_MSG=""

# Source individual check files
source "$SCRIPT_DIR/checks/short-agent-prompt.sh"
source "$SCRIPT_DIR/checks/generic-commit.sh"
source "$SCRIPT_DIR/checks/all-findings-downgraded.sh"
source "$SCRIPT_DIR/checks/save-observation-quality.sh"
source "$SCRIPT_DIR/checks/skipping-research.sh"
source "$SCRIPT_DIR/checks/options-without-recommendation.sh"
source "$SCRIPT_DIR/checks/no-verify-after-edits.sh"
source "$SCRIPT_DIR/checks/stalled-auto-transition.sh"
source "$SCRIPT_DIR/checks/step-ordering.sh"

# Dispatch all checks — each sets CHECK_RESULT if it fires
# save_observation_quality uses _append_l3 directly (two sub-checks)
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

# Append Layer 3 message if any
if [ -n "$L3_MSG" ]; then
    if [ -n "$MESSAGES" ]; then
        MESSAGES="$MESSAGES

$L3_MSG"
    else
        MESSAGES="$L3_MSG"
    fi
fi

# Debug summary for coaching checks
_log "[WFM coach] L3: fired=[${_L3_CHECKS_FIRED:- none}]"

# Counter summary
_COACH_COUNTER=$(jq -r '.coaching.tool_calls_since_agent // 0' "$STATE_FILE" 2>/dev/null) || _COACH_COUNTER="?"
_COACH_L2_FIRED=$(jq -r '.coaching.layer2_fired // [] | join(",")' "$STATE_FILE" 2>/dev/null) || _COACH_L2_FIRED="?"
_log "[WFM coach] Counters: calls_since_agent=$_COACH_COUNTER, layer2_fired=[$_COACH_L2_FIRED]"

# ============================================================
# OUTPUT: Return combined messages
# ============================================================

_emit_output
