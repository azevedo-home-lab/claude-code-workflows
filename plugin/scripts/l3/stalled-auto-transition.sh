#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Layer 3 Check: Stalled auto-transition
# Milestones complete but Claude hasn't moved to next phase

check_stalled_auto_transition() {
    CHECK_RESULT=""
    local autonomy_level
    autonomy_level=$(get_autonomy_level 2>/dev/null) || autonomy_level=""
    [ "$autonomy_level" = "auto" ] || return 0

    local stall_fire=false
    if [ "$PHASE" = "implement" ]; then
        local impl_missing
        impl_missing=$(_check_milestones "implement" "plan_written" "plan_read" "tests_passing" "all_tasks_complete" 2>/dev/null) || impl_missing="skip"
        [ -z "$impl_missing" ] && stall_fire=true
    elif [ "$PHASE" = "discuss" ]; then
        local discuss_done=true field val
        for field in problem_confirmed research_done approach_selected; do
            val=$(get_discuss_field "$field" 2>/dev/null) || val=""
            [ "$val" != "true" ] && discuss_done=false && break
        done
        [ "$discuss_done" = "true" ] && stall_fire=true
    elif [ "$PHASE" = "review" ]; then
        local review_done=true field val
        for field in verification_complete agents_dispatched findings_presented findings_acknowledged; do
            val=$(get_review_field "$field" 2>/dev/null) || val=""
            [ "$val" != "true" ] && review_done=false && break
        done
        [ "$review_done" = "true" ] && stall_fire=true
    fi

    [ "$stall_fire" = "true" ] || return 0

    local stall_body
    stall_body=$(load_message "checks/stalled_auto_transition/$PHASE.md")
    if [ -n "$stall_body" ] && _should_fire "stalled_$PHASE"; then
        CHECK_RESULT="[Workflow Coach — $PHASE_UPPER] $stall_body"
        _log "[WFM coach] L3: checks/stalled_auto_transition/$PHASE.md — ${stall_body:0:80}..."
    fi
}
