#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Phase management — ordinal, get/set phase, message_shown

[ -n "${_WFM_PHASE_LOADED:-}" ] && return 0
_WFM_PHASE_LOADED=1

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/infrastructure/state-io.sh"

# Phase ordinal for forward-only auto-transition enforcement
_phase_ordinal() {
    case "$1" in
        off)       echo 0 ;;
        error)     echo 0 ;;
        define)    echo 1 ;;
        discuss)   echo 2 ;;
        implement) echo 3 ;;
        review)    echo 4 ;;
        complete)  echo 5 ;;
        *)         echo 0 ;;
    esac
}

get_phase() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "off"
        return
    fi
    local phase
    phase=$(jq -r '.phase // "off"' "$STATE_FILE" 2>/dev/null) || phase="error"
    [ -z "$phase" ] && phase="error"
    case "$phase" in
        off|define|discuss|implement|review|complete) ;;
        *) phase="error" ;;
    esac
    echo "$phase"
}

get_message_shown() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "false"
        return
    fi
    local val
    val=$(jq -r 'if .message_shown == true then "true" else "false" end' "$STATE_FILE" 2>/dev/null) || val="false"
    [ -z "$val" ] && val="false"
    echo "$val"
}

set_message_shown() { if [ ! -f "$STATE_FILE" ]; then return; fi; _show "[WFM state] SET message_shown = true"; _update_state '.message_shown = true'; }
