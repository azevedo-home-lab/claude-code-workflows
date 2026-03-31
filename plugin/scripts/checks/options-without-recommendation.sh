#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Layer 3 Check: Options without recommendation
# AskUserQuestion after agent returns without recommendation

check_options_without_recommendation() {
    CHECK_RESULT=""
    [ "$TOOL_NAME" = "AskUserQuestion" ] || return 0

    # Check if any agent has returned in this phase (any agent_return_* trigger fired)
    local agents_returned
    agents_returned=$(jq -r '[.coaching.layer2_fired[]? | select(startswith("agent_return"))] | if length > 0 then "true" else "false" end' "$STATE_FILE" 2>/dev/null) || agents_returned="false"
    [ "$agents_returned" = "true" ] || return 0

    local check_body
    check_body=$(load_message "checks/options_without_recommendation.md" "$PHASE_UPPER")
    if [ -n "$check_body" ] && _should_fire "options_without_recommendation"; then
        CHECK_RESULT="[Workflow Coach — $PHASE_UPPER] $check_body"
        _trace "[WFM coach] L3: checks/options_without_recommendation.md — ${check_body:0:80}..."
    fi
}
