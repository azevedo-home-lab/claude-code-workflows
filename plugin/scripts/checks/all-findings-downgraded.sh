#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Layer 3 Check: All review findings downgraded to suggestions

check_all_findings_downgraded() {
    CHECK_RESULT=""
    [ "$PHASE" = "review" ] || return 0
    { [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; } || return 0
    echo "$FILE_PATH" | grep -qE 'docs/specs/' || return 0

    # Check if all findings are under Suggestions with no Critical or Warning entries
    local all_suggestions="false"
    if [ -f "$FILE_PATH" ]; then
        local in_review=false has_critical=false has_warning=false line
        while IFS= read -r line; do
            if echo "$line" | grep -q '## Review Findings'; then in_review=true; fi
            if [ "$in_review" = "true" ] && echo "$line" | grep -qE '^## ' && ! echo "$line" | grep -q 'Review Findings'; then break; fi
            if [ "$in_review" = "true" ]; then
                if echo "$line" | grep -q '### Critical'; then has_critical=true; fi
                if echo "$line" | grep -q '### Warning'; then has_warning=true; fi
            fi
        done < "$FILE_PATH"
        if [ "$in_review" = "true" ] && [ "$has_critical" = "false" ] && [ "$has_warning" = "false" ]; then
            all_suggestions="true"
        fi
    fi

    [ "$all_suggestions" = "true" ] || return 0

    local check_body
    check_body=$(load_message "checks/all_findings_downgraded.md")
    if [ -n "$check_body" ] && _should_fire "all_findings_downgraded"; then
        CHECK_RESULT="[Workflow Coach — REVIEW] $check_body"
        _trace "[WFM coach] L3: checks/all_findings_downgraded.md — ${check_body:0:80}..."
    fi
}
