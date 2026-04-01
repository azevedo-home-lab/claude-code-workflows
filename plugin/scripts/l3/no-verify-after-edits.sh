#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Layer 3 Check: No verify after code changes
# Source edits without test run (5+ edits triggers warning)

check_no_verify_after_edits() {
    CHECK_RESULT=""
    { [ "$PHASE" = "implement" ] || [ "$PHASE" = "review" ]; } || return 0

    if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
        if [ -n "$FILE_PATH" ] && ! echo "$FILE_PATH" | grep -qE '(test|spec|docs/|plans/|specs/|\.md$)'; then
            local verify_count
            verify_count=$(get_pending_verify)
            verify_count=$((verify_count + 1))
            set_pending_verify "$verify_count"
            if [ "$verify_count" -ge 5 ]; then
                local verify_body
                verify_body=$(load_message "checks/no_verify_after_edits.md")
                if [ -n "$verify_body" ] && _should_fire "no_verify_after_edits"; then
                    verify_body="$verify_body ($verify_count edits without test run)"
                    CHECK_RESULT="[Workflow Coach — $PHASE_UPPER] $verify_body"
                    _log "[WFM coach] L3: checks/no_verify_after_edits.md — ${verify_body:0:80}..."
                fi
                set_pending_verify 0
            fi
        fi
    elif [ "$TOOL_NAME" = "Bash" ]; then
        local bash_cmd
        bash_cmd=$(extract_bash_command)
        if echo "$bash_cmd" | grep -qE '(pytest|npm test|cargo test|make test|run-tests|jest|vitest|go test)'; then
            set_pending_verify 0
        fi
    fi
}
