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

# Exit silently when running as a project-deployed copy (missing infrastructure/).
# Claude Code materializes plugin hooks into .claude/hooks/ but without subdirectories,
# so the real work is done by the plugin-scoped copy (which has CLAUDE_PLUGIN_ROOT set).
_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -z "${CLAUDE_PLUGIN_ROOT:-}" ] && [ ! -d "$_self_dir/infrastructure" ] && exit 0

# Resolve SCRIPT_DIR from dev marker or plugin cache (not hardcoded project path).
# See resolve-script-dir.sh for the resolution order and rationale.
# Try CLAUDE_PLUGIN_ROOT first (works from both plugin/ and .claude/hooks/ contexts),
# fall back to BASH_SOURCE (works from plugin/scripts/ context only).
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/scripts/infrastructure/resolve-script-dir.sh" ]; then
    source "$CLAUDE_PLUGIN_ROOT/scripts/infrastructure/resolve-script-dir.sh"
else
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/infrastructure/resolve-script-dir.sh"
fi

source "$SCRIPT_DIR/workflow-facade.sh"
source "$SCRIPT_DIR/infrastructure/tool-classifier.sh"

COACHING_DIR="$PLUGIN_ASSETS_ROOT/coaching"
PHASES_DIR="$PLUGIN_ASSETS_ROOT/phases"

# Shared pattern for test command detection (used by L2/L3)
_TEST_CMD_REGEX='(pytest|npm test|cargo test|make test|run-tests|jest|vitest|go test)'

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
        msg="${msg//\{\{PHASE\}\}/$2}"
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

# Helper: append content to MESSAGES with blank-line separator
_append_msg() {
    if [ -n "$MESSAGES" ]; then
        MESSAGES="$MESSAGES

$1"
    else
        MESSAGES="$1"
    fi
}

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
        # Extract FILE_PATH and IS_WRITE_TOOL for Write/Edit/MultiEdit (used by L2/L3 checks)
        FILE_PATH=""
        IS_WRITE_TOOL=false
        case "$TOOL_NAME" in
            Write|Edit|MultiEdit)
                FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || FILE_PATH=""
                IS_WRITE_TOOL=true
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

        [ -n "$L3_MSG" ] && _append_msg "$L3_MSG"

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
