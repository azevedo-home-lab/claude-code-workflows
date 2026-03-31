#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Configuration getters/setters — autonomy, debug, active skill, plan/spec paths, tests

[ -n "${_WFM_SETTINGS_LOADED:-}" ] && return 0
_WFM_SETTINGS_LOADED=1

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/state-io.sh"

get_autonomy_level() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "ask"
        return
    fi
    local level
    level=$(jq -r '.autonomy_level // "ask"' "$STATE_FILE" 2>/dev/null) || level="ask"
    [ -z "$level" ] && level="ask"
    echo "$level"
}

set_autonomy_level() {
    local level="$1"
    # Backward-compat: map legacy numeric values
    case "$level" in
        1) level="off" ;;
        2) level="ask" ;;
        3) level="auto" ;;
    esac
    case "$level" in
        off|ask|auto) ;;
        *) echo "ERROR: Invalid autonomy level: $level (valid: off, ask, auto)" >&2; return 1 ;;
    esac
    # set_autonomy_level is always user-initiated — called from !backtick in autonomy.md.
    # No authorization check needed here; the user's slash command is the authorization.
    if [ ! -f "$STATE_FILE" ]; then
        echo "WARNING: No workflow state file. Start a workflow phase first (e.g., /define)." >&2
        return 1
    fi
    _show "[WFM state] SET autonomy_level = $level"
    _update_state '.autonomy_level = $v' --arg v "$level"
}

# ---------------------------------------------------------------------------
# Debug mode
# ---------------------------------------------------------------------------

get_debug() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "off"
        return
    fi
    local val
    val=$(jq -r '.debug // "off"' "$STATE_FILE" 2>/dev/null) || val="off"
    # Backwards compat
    case "$val" in
        true) val="log" ;;
        false|null|"") val="off" ;;
        off|log|show) ;;
        *) val="off" ;;
    esac
    echo "$val"
}

set_debug() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "WARNING: No workflow state file. Start a workflow phase first." >&2
        return 1
    fi
    local val="${1:-}"
    # Backwards compat: true->log, false->off
    case "$val" in
        true) val="log" ;;
        false) val="off" ;;
        off|log|show) ;;
        *) echo "ERROR: Invalid debug value: $val (valid: off, log, show)" >&2; return 1 ;;
    esac
    _show "[WFM state] SET debug = $val"
    _update_state '.debug = $v' --arg v "$val"
}

# ---------------------------------------------------------------------------
# Active skill management
# ---------------------------------------------------------------------------

set_active_skill() { if [ ! -f "$STATE_FILE" ]; then return; fi; _show "[WFM state] SET active_skill = $1"; _update_state '.active_skill = $v' --arg v "$1"; }

get_active_skill() {
    if [ ! -f "$STATE_FILE" ]; then
        echo ""
        return
    fi
    local val
    val=$(jq -r '.active_skill // ""' "$STATE_FILE" 2>/dev/null) || val=""
    echo "$val"
}

# ---------------------------------------------------------------------------
# Plan path management
# ---------------------------------------------------------------------------

set_plan_path() { if [ ! -f "$STATE_FILE" ]; then return; fi; _show "[WFM state] SET plan_path = $1"; _update_state '.plan_path = $v' --arg v "$1"; }

get_plan_path() {
    if [ ! -f "$STATE_FILE" ]; then
        echo ""
        return
    fi
    local val
    val=$(jq -r '.plan_path // ""' "$STATE_FILE" 2>/dev/null) || val=""
    echo "$val"
}

# ---------------------------------------------------------------------------
# Spec path management
# ---------------------------------------------------------------------------

set_spec_path() { if [ ! -f "$STATE_FILE" ]; then return; fi; _show "[WFM state] SET spec_path = $1"; _update_state '.spec_path = $v' --arg v "$1"; }

get_spec_path() {
    if [ ! -f "$STATE_FILE" ]; then
        echo ""
        return
    fi
    local val
    val=$(jq -r '.spec_path // ""' "$STATE_FILE" 2>/dev/null) || val=""
    echo "$val"
}

# ---------------------------------------------------------------------------
# Test results tracking (preserved across phase transitions)
# ---------------------------------------------------------------------------

set_tests_passed_at() { if [ ! -f "$STATE_FILE" ]; then return; fi; _show "[WFM state] SET tests_last_passed_at = $1"; _update_state '.tests_last_passed_at = $v' --arg v "$1"; }

get_tests_passed_at() {
    if [ ! -f "$STATE_FILE" ]; then
        echo ""
        return
    fi
    local val
    val=$(jq -r '.tests_last_passed_at // ""' "$STATE_FILE" 2>/dev/null) || val=""
    echo "$val"
}
