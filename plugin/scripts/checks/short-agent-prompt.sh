#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Layer 3 Check: Short agent prompts (< 150 chars)

check_short_agent_prompt() {
    CHECK_RESULT=""
    [ "$TOOL_NAME" = "Agent" ] || return 0

    local prompt_len
    prompt_len=$(echo "$INPUT" | jq -r '.tool_input.prompt // "" | length' 2>/dev/null) || prompt_len=999
    [ "$prompt_len" -lt 150 ] || return 0

    local check_body
    check_body=$(load_message "checks/short_agent_prompt.md" "$PHASE_UPPER")
    if [ -n "$check_body" ] && _should_fire "short_agent_prompt"; then
        CHECK_RESULT="[Workflow Coach — $PHASE_UPPER] $check_body"
        _trace "[WFM coach] L3: checks/short_agent_prompt.md — ${check_body:0:80}..."
    fi
}
