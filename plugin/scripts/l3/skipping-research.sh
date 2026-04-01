#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Layer 3 Check: Skipping research in DEFINE/DISCUSS
# No agent dispatch after 10+ tool calls

check_skipping_research() {
    CHECK_RESULT=""
    { [ "$PHASE" = "define" ] || [ "$PHASE" = "discuss" ]; } || return 0

    local counter
    counter=$(jq -r '.coaching.tool_calls_since_agent // 0' "$STATE_FILE" 2>/dev/null) || counter=0
    [ "$counter" -gt 10 ] || return 0

    local check_body
    check_body=$(load_message "checks/skipping_research.md" "$PHASE_UPPER")
    if [ -n "$check_body" ] && _should_fire "skipping_research"; then
        CHECK_RESULT="[Workflow Coach — $PHASE_UPPER] $check_body"
        _log "[WFM coach] L3: checks/skipping_research.md — ${check_body:0:80}..."
    fi
}
