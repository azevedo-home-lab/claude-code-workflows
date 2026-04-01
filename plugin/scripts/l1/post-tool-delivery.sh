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
