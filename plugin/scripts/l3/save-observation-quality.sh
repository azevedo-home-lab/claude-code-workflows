#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Layer 3 Check: save_observation quality
# Combines minimal-handover (4a) and missing-project-field (4b)
# since they share the same jq extraction.

check_save_observation_quality() {
    CHECK_RESULT=""
    echo "$TOOL_NAME" | grep -qE 'mcp.*save_observation' || return 0

    local obs_check obs_len has_project
    obs_check=$(echo "$INPUT" | jq -r '
        (.tool_input.narrative // .tool_input.text // "") as $t |
        (.tool_input.project // "") as $p |
        "\($t | length) \(if $p != "" then "true" else "false" end)"
    ' 2>/dev/null) || obs_check="999 true"
    obs_len="${obs_check%% *}"
    has_project="${obs_check##* }"

    local check_body

    # 4a: Minimal handover (COMPLETE phase only)
    if [ "$PHASE" = "complete" ] && [ "$obs_len" -lt 200 ]; then
        check_body=$(load_message "checks/minimal_handover.md")
        if [ -n "$check_body" ] && _should_fire "minimal_handover"; then
            _append_l3 "[Workflow Coach — COMPLETE] $check_body"
            _log "[WFM coach] L3: checks/minimal_handover.md — ${check_body:0:80}..."
        fi
    fi

    # 4b: Missing project field (any phase)
    if [ "$has_project" = "false" ]; then
        check_body=$(load_message "checks/missing_project_field.md" "$PHASE_UPPER")
        if [ -n "$check_body" ] && _should_fire "missing_project_field"; then
            _append_l3 "[Workflow Coach — $PHASE_UPPER] $check_body"
            _log "[WFM coach] L3: checks/missing_project_field.md — ${check_body:0:80}..."
        fi
    fi
}
