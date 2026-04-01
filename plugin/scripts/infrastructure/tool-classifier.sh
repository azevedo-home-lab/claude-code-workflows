#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Tool classification for PostToolUse coaching dispatch.
# Returns one of: phase-transition, infrastructure-query, coaching-participant, irrelevant
#
# Usage: tool_type=$(_classify_tool "$TOOL_NAME" "$INPUT")

[ -n "${_WFM_TOOL_CLASSIFIER_LOADED:-}" ] && return 0
_WFM_TOOL_CLASSIFIER_LOADED=1

_classify_tool() {
    local tool_name="$1"
    local input="$2"

    if [ "$tool_name" = "Bash" ]; then
        local cmd
        cmd=$(echo "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) || cmd=""

        # Phase transitions: user-set-phase.sh or agent_set_phase via workflow-cmd.sh
        if echo "$cmd" | grep -qE 'user-set-phase\.sh'; then
            echo "phase-transition"
            return
        fi
        if echo "$cmd" | grep -qE '(^|/)workflow-cmd\.sh[[:space:]]+agent_set_phase'; then
            echo "phase-transition"
            return
        fi
        # Also match agent-set-phase.sh directly (sourced by workflow-cmd.sh)
        if echo "$cmd" | grep -qE 'agent-set-phase\.sh'; then
            echo "phase-transition"
            return
        fi

        # Infrastructure queries: workflow-cmd.sh (non-transition commands)
        if echo "$cmd" | grep -qE '(^|/)workflow-cmd\.sh'; then
            echo "infrastructure-query"
            return
        fi

        # All other Bash commands participate in coaching
        echo "coaching-participant"
        return
    fi

    # Non-Bash tools: check participation list
    case "$tool_name" in
        Agent|Write|Edit|MultiEdit|NotebookEdit|AskUserQuestion)
            echo "coaching-participant"
            ;;
        mcp*save_observation|mcp*get_observations)
            echo "coaching-participant"
            ;;
        *)
            echo "irrelevant"
            ;;
    esac
}
