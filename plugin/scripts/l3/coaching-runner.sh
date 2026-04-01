#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Coaching throttle engine — rate-limiting and grace period for Layer 3 checks.
# Reduces coaching noise by:
#   1. Grace period: Don't fire until N tool calls after condition first becomes true
#   2. Rate limit: After grace period, only fire every Nth tool call
# Configurable via coaching state or defaults below.

[ "${_WFM_COACHING_RUNNER_LOADED:-}" = "1" ] && return 0; _WFM_COACHING_RUNNER_LOADED=1

# ---------------------------------------------------------------------------
# Throttle configuration
# ---------------------------------------------------------------------------
_COACHING_GRACE_PERIOD=3    # tool calls before first fire after condition becomes true
_COACHING_RATE_LIMIT=5      # fire every Nth attempt after grace period

# Load overrides from state file if configured
_COACHING_GRACE_OVERRIDE=$(jq -r '.coaching.grace_period // empty' "$STATE_FILE" 2>/dev/null) || _COACHING_GRACE_OVERRIDE=""
_COACHING_RATE_OVERRIDE=$(jq -r '.coaching.rate_limit // empty' "$STATE_FILE" 2>/dev/null) || _COACHING_RATE_OVERRIDE=""
[ -n "$_COACHING_GRACE_OVERRIDE" ] && _COACHING_GRACE_PERIOD="$_COACHING_GRACE_OVERRIDE"
[ -n "$_COACHING_RATE_OVERRIDE" ] && _COACHING_RATE_LIMIT="$_COACHING_RATE_OVERRIDE"

# Get current total tool call count for throttle tracking
_COACHING_CALL_COUNT=$(jq -r '.coaching.tool_calls_since_agent // 0' "$STATE_FILE" 2>/dev/null) || _COACHING_CALL_COUNT=0

# ---------------------------------------------------------------------------
# _should_fire CHECK_NAME
# Returns 0 (true) if the check should fire, 1 (false) if throttled.
# Tracks per-check state in coaching.throttle.<check_name>
# ---------------------------------------------------------------------------
_should_fire() {
    local check_name="$1"
    local first_true fire_count

    # Read per-check throttle state (--arg avoids shell interpolation in jq filter)
    first_true=$(jq -r --arg cn "$check_name" '.coaching.throttle[$cn].first_true // 0' "$STATE_FILE" 2>/dev/null) || first_true=0
    fire_count=$(jq -r --arg cn "$check_name" '.coaching.throttle[$cn].fire_count // 0' "$STATE_FILE" 2>/dev/null) || fire_count=0

    # First time this check is true — record the call count
    if [ "$first_true" -eq 0 ]; then
        _update_state '.coaching.throttle[$cn].first_true = $cc' --arg cn "$check_name" --argjson cc "$_COACHING_CALL_COUNT"
        first_true=$_COACHING_CALL_COUNT
    fi

    # Grace period: don't fire until N calls after first_true
    local calls_since=$(( _COACHING_CALL_COUNT - first_true ))
    if [ "$calls_since" -lt "$_COACHING_GRACE_PERIOD" ]; then
        _log "[WFM coach] throttle: $check_name — grace period ($calls_since/$_COACHING_GRACE_PERIOD)"
        return 1
    fi

    # Rate limit: fire every Nth attempt
    fire_count=$(( fire_count + 1 ))
    _update_state '.coaching.throttle[$cn].fire_count = $fc' --arg cn "$check_name" --argjson fc "$fire_count"

    if [ $(( fire_count % _COACHING_RATE_LIMIT )) -ne 1 ] && [ "$fire_count" -ne 1 ]; then
        _log "[WFM coach] throttle: $check_name — rate limited ($fire_count, every $_COACHING_RATE_LIMIT)"
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------------------
# _reset_throttle CHECK_NAME
# Reset throttle state for a check when its condition becomes false
# ---------------------------------------------------------------------------
_reset_throttle() {
    local check_name="$1"
    local has_state
    has_state=$(jq -r --arg cn "$check_name" '.coaching.throttle[$cn] // empty' "$STATE_FILE" 2>/dev/null) || has_state=""
    if [ -n "$has_state" ]; then
        _update_state 'del(.coaching.throttle[$cn])' --arg cn "$check_name"
    fi
}

# ---------------------------------------------------------------------------
# _append_l3 MESSAGE
# Helper: append a check message to L3_MSG
# ---------------------------------------------------------------------------
_append_l3() {
    if [ -n "$L3_MSG" ]; then
        L3_MSG="$L3_MSG

$1"
    else
        L3_MSG="$1"
    fi
}
