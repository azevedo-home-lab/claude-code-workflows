#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# L1 Phase coaching loader — builds the coaching message for a phase transition.
# Called by user-set-phase.sh and agent-set-phase.sh at transition time.

[ -n "${_WFM_PHASE_COACHING_LOADED:-}" ] && return 0
_WFM_PHASE_COACHING_LOADED=1

# Emit the L1 coaching message for a phase transition.
# Outputs: objective + phase instructions + auto-transition guidance (if auto).
# Args: $1 = phase name, $2 = autonomy level
# Uses: PROJECT_ROOT (must be set by caller)
#       _WFM_DEBUG_LEVEL (set by debug-log.sh, must be sourced before calling)
_emit_phase_coaching() {
    local phase="$1"
    local autonomy="${2:-ask}"

    # "off" phase has no coaching
    [ "$phase" = "off" ] && return 0

    local project_root="${PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"
    local coaching_dir="$project_root/plugin/coaching"
    local phases_dir="$project_root/plugin/phases"
    local phase_upper
    phase_upper=$(echo "$phase" | tr '[:lower:]' '[:upper:]')

    # Coaching directory must exist
    [ -d "$coaching_dir" ] || return 0

    local msg=""

    # Objective
    local obj_file="$coaching_dir/objectives/$phase.md"
    if [ -f "$obj_file" ]; then
        msg="[Workflow Coach — $phase_upper]
$(cat "$obj_file")"
    fi

    # Phase instructions
    local phase_file="$phases_dir/$phase/phase.md"
    if [ -f "$phase_file" ]; then
        if [ -n "$msg" ]; then
            msg="$msg

$(cat "$phase_file")"
        else
            msg="$(cat "$phase_file")"
        fi
    fi

    # Auto-transition guidance
    if [ "$autonomy" = "auto" ] && [ -n "$msg" ]; then
        local auto_file="$coaching_dir/auto-transition/$phase.md"
        [ -f "$auto_file" ] || auto_file="$coaching_dir/auto-transition/default.md"
        if [ -f "$auto_file" ]; then
            msg="$msg
$(cat "$auto_file")"
        fi
    fi

    if [ -n "$msg" ]; then
        echo "$msg"
        if [ "${_WFM_DEBUG_LEVEL:-}" = "show" ]; then
            local line_count
            line_count=$(echo "$msg" | wc -l | tr -d ' ')
            echo "[WFM coach] L1: ${line_count} coaching lines emitted for $phase" >&2
        fi
    fi
}
