#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# USER PHASE TRANSITION — called only from !backtick in command files.
# Writes phase state directly. No authorization checks. No gate checks.
# The user's intent is expressed by the fact they typed a slash command.
#
# SECURITY: This script must NOT be callable via Bash tool.
# pre-tool-bash-guard.sh blocks any Bash tool call containing user-set-phase.sh.
#
# Usage: user-set-phase.sh <phase>
# Phases: off define discuss implement review complete

set -euo pipefail

SCRIPT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/plugin/scripts"
source "$SCRIPT_DIR/workflow-facade.sh"
source "$SCRIPT_DIR/l1/phase-coaching.sh"

new_phase="${1:-}"

case "$new_phase" in
    off|define|discuss|implement|review|complete) ;;
    *) echo "ERROR: Invalid phase: $new_phase (valid: off, define, discuss, implement, review, complete)" >&2; exit 1 ;;
esac

mkdir -p "$STATE_DIR"

# Read current state for debug logging
current_phase="off"
current_autonomy="ask"
if [ -f "$STATE_FILE" ]; then
    current_phase=$(get_phase)
    current_autonomy=$(get_autonomy_level)
    [ -z "$current_autonomy" ] && current_autonomy="ask"
fi

# Debug logging for phase transitions
DEBUG_MODE=$(get_debug 2>/dev/null || echo "")
source "$SCRIPT_DIR/infrastructure/debug-log.sh" "user-set-phase"
_show "[WFM phase] User transition: $current_phase → $new_phase"

# In-place state update — only change what the transition requires.
# Everything else (debug, autonomy, tracked_observations, issue_mappings, etc.)
# survives automatically.
if [ "$new_phase" = "off" ]; then
    # Off: reset cycle fields but keep session-wide settings
    _update_state \
        '.phase = "off" | .message_shown = false | .active_skill = "" | .plan_path = "" | .spec_path = "" | .tests_last_passed_at = "" | .coaching = {tool_calls_since_agent: 0, layer2_fired: []}' \
        || { echo "ERROR: Failed to write state." >&2; exit 1; }
else
    # Normal transition: reset coaching and skill, keep everything else
    if [ ! -f "$STATE_FILE" ]; then
        # First transition — create initial state
        local_autonomy="$current_autonomy"
        ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        jq -n --arg phase "$new_phase" --arg ts "$ts" --arg autonomy "$local_autonomy" '{
            phase: $phase,
            message_shown: false,
            active_skill: "",
            plan_path: "",
            spec_path: "",
            coaching: {tool_calls_since_agent: 0, layer2_fired: []},
            autonomy_level: $autonomy,
            updated: $ts
        }' | _safe_write
    else
        _update_state \
            '.phase = $p | .message_shown = false | .active_skill = "" | .coaching = {tool_calls_since_agent: 0, layer2_fired: []}' \
            --arg p "$new_phase" \
            || { echo "ERROR: Failed to write state." >&2; exit 1; }
    fi
fi

_show "[WFM phase] State updated in-place for $new_phase"

echo "Phase set to ${new_phase}. Re-evaluate."

# Emit L1 coaching immediately at transition — not deferred to next tool call.
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
_emit_phase_coaching "$new_phase" "$current_autonomy"
