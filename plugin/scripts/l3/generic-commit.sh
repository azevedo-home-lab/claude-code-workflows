#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Layer 3 Check: Generic commit messages (< 30 chars)

check_generic_commit() {
    CHECK_RESULT=""
    [ "$TOOL_NAME" = "Bash" ] || return 0

    local command
    command=$(extract_bash_command)
    echo "$command" | grep -qE 'git commit' || return 0

    local commit_msg_len
    commit_msg_len=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null | {
        cmd=$(cat)
        # Try -m "..." or -m '...' (single-line, no HEREDOC)
        msg=$(echo "$cmd" | sed -n 's/.*-m[[:space:]]*"\([^"]*\)".*/\1/p; s/.*-m[[:space:]]*'"'"'\([^'"'"']*\)'"'"'.*/\1/p' | head -1)
        if [ -n "$msg" ] && ! echo "$msg" | grep -qE '(\$\(cat|<<)'; then
            echo "${#msg}"
        else
            # Try HEREDOC: normalise literal \n to real newlines, then extract first line after EOF
            first_line=$(echo "$cmd" | sed 's/\\n/\n/g' | awk 'found && !/^EOF/{print; exit} /EOF/{found=1}' | head -1)
            if [ -n "$first_line" ]; then
                echo "${#first_line}"
            else
                echo "999"
            fi
        fi
    }) || commit_msg_len=999

    [ "$commit_msg_len" -lt 30 ] || return 0

    local check_body
    check_body=$(load_message "checks/generic_commit.md" "$PHASE_UPPER")
    if [ -n "$check_body" ] && _should_fire "generic_commit"; then
        CHECK_RESULT="[Workflow Coach — $PHASE_UPPER] $check_body"
        _trace "[WFM coach] L3: checks/generic_commit.md — ${check_body:0:80}..."
    fi
}
