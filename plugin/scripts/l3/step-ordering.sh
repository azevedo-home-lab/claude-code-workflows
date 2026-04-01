#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Layer 3 Check: Within-phase step ordering violations

check_step_ordering() {
    CHECK_RESULT=""

    # Helper: load step ordering message and set local vars
    local step_msg="" step_file="" step_body=""
    _load_step() {
        local body
        body=$(load_message "checks/step_ordering/$1.md")
        if [ -n "$body" ]; then
            step_msg="[Workflow Coach — $PHASE_UPPER] $body"
            step_file="checks/step_ordering/$1.md"
            step_body="$body"
        fi
    }

    if [ "$PHASE" = "complete" ]; then
        if [ "$(_section_exists "completion")" = "true" ]; then
            if [ "$TOOL_NAME" = "Bash" ]; then
                local bash_cmd
                bash_cmd=$(extract_bash_command)
                if echo "$bash_cmd" | grep -qE 'git[[:space:]]+commit'; then
                    if [ "$(get_completion_field "results_presented")" != "true" ]; then
                        _load_step "complete_commit_before_validation"
                    elif [ "$(get_completion_field "docs_checked")" != "true" ]; then
                        _load_step "complete_commit_before_docs"
                    fi
                fi
                if echo "$bash_cmd" | grep -qE 'git[[:space:]]+push'; then
                    if [ "$(get_completion_field "committed")" != "true" ]; then
                        _load_step "complete_push_before_commit"
                    fi
                fi
            fi
            if echo "$TOOL_NAME" | grep -qE 'mcp.*save_observation'; then
                if [ "$(get_completion_field "tech_debt_audited")" != "true" ]; then
                    _load_step "complete_handover_before_audit"
                fi
            fi
            # Pipeline-abandoned: pushed but later steps not done
            if [ "$(get_completion_field "pushed")" = "true" ] && [ "$(get_completion_field "handover_saved")" != "true" ]; then
                _load_step "complete_pipeline_incomplete"
            fi
        fi
    elif [ "$PHASE" = "discuss" ]; then
        if [ "$(_section_exists "discuss")" = "true" ]; then
            if [ "$IS_WRITE_TOOL" = true ]; then
                if echo "$FILE_PATH" | grep -qE 'docs/plans/'; then
                    if [ "$(get_discuss_field "research_done")" != "true" ]; then
                        _load_step "discuss_plan_before_research"
                    elif [ "$(get_discuss_field "approach_selected")" != "true" ]; then
                        _load_step "discuss_plan_before_approach"
                    fi
                fi
            fi
        fi
    elif [ "$PHASE" = "implement" ]; then
        if [ "$(_section_exists "implement")" = "true" ]; then
            if [ "$IS_WRITE_TOOL" = true ]; then
                if [ -n "$FILE_PATH" ] && ! echo "$FILE_PATH" | grep -qE '(test|spec|docs/|plans/|specs/|\.md$)'; then
                    if [ "$(get_implement_field "plan_written")" != "true" ]; then
                        _load_step "implement_code_before_plan"
                    elif [ "$(get_implement_field "plan_read")" != "true" ]; then
                        _load_step "implement_code_before_plan_read"
                    fi
                fi
            fi
            # Pipeline-abandoned: tasks complete but tests not run
            if [ "$(get_implement_field "all_tasks_complete")" = "true" ] && [ "$(get_implement_field "tests_passing")" != "true" ]; then
                _load_step "implement_pipeline_incomplete"
            fi
        fi
    elif [ "$PHASE" = "review" ]; then
        if [ "$(_section_exists "review")" = "true" ]; then
            if [ "$IS_WRITE_TOOL" = true ]; then
                if echo "$FILE_PATH" | grep -qE 'docs/specs/'; then
                    if [ "$(get_review_field "agents_dispatched")" != "true" ]; then
                        _load_step "review_findings_before_agents"
                    fi
                fi
            fi
            if [ "$TOOL_NAME" = "AskUserQuestion" ]; then
                if [ "$(get_review_field "findings_presented")" != "true" ]; then
                    _load_step "review_ack_before_findings"
                fi
            fi
            # Pipeline-abandoned: agents dispatched but findings not presented
            if [ "$(get_review_field "agents_dispatched")" = "true" ] && [ "$(get_review_field "findings_presented")" != "true" ]; then
                _load_step "review_pipeline_incomplete"
            fi
        fi
    fi

    if [ -n "$step_msg" ] && _should_fire "step_ordering"; then
        CHECK_RESULT="$step_msg"
        _log "[WFM coach] L3: $step_file — ${step_body:0:80}..."
    fi
}
