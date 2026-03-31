#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Coaching counters and throttle state

[ -n "${_WFM_COACHING_STATE_LOADED:-}" ] && return 0
_WFM_COACHING_STATE_LOADED=1

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/state-io.sh"

increment_coaching_counter() { if [ ! -f "$STATE_FILE" ]; then return; fi; _update_state '.coaching.tool_calls_since_agent += 1'; }
reset_coaching_counter() { if [ ! -f "$STATE_FILE" ]; then return; fi; _update_state '.coaching.tool_calls_since_agent = 0'; }

add_coaching_fired() {
    if [ ! -f "$STATE_FILE" ]; then return; fi
    _update_state '.coaching.layer2_fired += [$t] | .coaching.last_layer2_at = .coaching.tool_calls_since_agent' --arg t "$1"
}

has_coaching_fired() {
    local trigger_type="$1"
    if [ ! -f "$STATE_FILE" ]; then
        echo "false"
        return
    fi
    local result
    result=$(jq -r --arg t "$trigger_type" 'if ([.coaching.layer2_fired[]? | select(. == $t)] | length) > 0 then "true" else "false" end' "$STATE_FILE" 2>/dev/null) || result="false"
    echo "$result"
}

# Check if Layer 2 coaching should be refreshed (30+ calls of silence)
# Silently clears layer2_fired array if threshold exceeded — no stdout output
# to avoid corrupting hook JSON stream.
check_coaching_refresh() {
    if [ ! -f "$STATE_FILE" ]; then return; fi
    _update_state 'if (.coaching.tool_calls_since_agent - (.coaching.last_layer2_at // 0)) >= 30 then .coaching.layer2_fired = [] | .coaching.last_layer2_at = .coaching.tool_calls_since_agent else . end'
}

# ---------------------------------------------------------------------------
# Pending verify tracking
# ---------------------------------------------------------------------------

set_pending_verify() { if [ ! -f "$STATE_FILE" ]; then return; fi; _update_state '.coaching.pending_verify = $c' --argjson c "${1:-0}"; }

get_pending_verify() {
    if [ ! -f "$STATE_FILE" ]; then echo "0"; return; fi
    local val
    val=$(jq -r '.coaching.pending_verify // 0' "$STATE_FILE" 2>/dev/null) || val="0"
    echo "$val"
}
