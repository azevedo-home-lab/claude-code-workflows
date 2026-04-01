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

SCRIPT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/plugin/scripts"
source "$SCRIPT_DIR/workflow-facade.sh"

# Coaching message directory — resolved from project root, not SCRIPT_DIR.
# SCRIPT_DIR resolves to .claude/hooks/ (symlink directory), not plugin/scripts/.
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
source "$SCRIPT_DIR/infrastructure/debug-log.sh" "post-tool-navigator"

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
source "$SCRIPT_DIR/l3/coaching-runner.sh"

# L1 (phase entry coaching) now fires at transition time in user-set-phase.sh
# and agent-set-phase.sh — no longer deferred to the next tool call.

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

source "$SCRIPT_DIR/l2/standards-reinforcement.sh"
_run_l2

# ============================================================
# LAYER 3: Anti-laziness checks (dispatched from individual files)
# ============================================================

L3_MSG=""

# Source individual check files
source "$SCRIPT_DIR/l3/short-agent-prompt.sh"
source "$SCRIPT_DIR/l3/generic-commit.sh"
source "$SCRIPT_DIR/l3/all-findings-downgraded.sh"
source "$SCRIPT_DIR/l3/save-observation-quality.sh"
source "$SCRIPT_DIR/l3/skipping-research.sh"
source "$SCRIPT_DIR/l3/options-without-recommendation.sh"
source "$SCRIPT_DIR/l3/no-verify-after-edits.sh"
source "$SCRIPT_DIR/l3/stalled-auto-transition.sh"
source "$SCRIPT_DIR/l3/step-ordering.sh"

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
