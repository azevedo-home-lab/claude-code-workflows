#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Layer 2: Professional standards reinforcement — periodic, contextual nudges.
# Matches phase + tool patterns to fire coaching messages from plugin/coaching/nudges/.
#
# Expected variables from caller (post-tool-coaching.sh):
#   PHASE, PHASE_UPPER, TOOL_NAME, INPUT, FILE_PATH, MESSAGES
# Expected functions from caller:
#   load_message, extract_bash_command, get_message_shown,
#   check_coaching_refresh, reset_coaching_counter, increment_coaching_counter,
#   has_coaching_fired, add_coaching_fired, _trace, _log

[ -n "${_WFM_L2_LOADED:-}" ] && return 0
_WFM_L2_LOADED=1

_run_l2() {
    # Only fire if Layer 1 has already fired (message_shown = true means we're past entry)
    if [ "$(get_message_shown)" != "true" ]; then
        return
    fi

    # Refresh Layer 2 triggers after 30 calls of silence (before counter reset)
    check_coaching_refresh

    # Track agent dispatch counter
    if [ "$TOOL_NAME" = "Agent" ]; then
        reset_coaching_counter
    else
        increment_coaching_counter
    fi

    # Determine trigger type based on phase + tool pattern
    local trigger=""
    local l2_msg=""

    case "$PHASE" in
        define)
            if [ "$TOOL_NAME" = "Agent" ]; then
                trigger="agent_return_define"
            elif [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
                if echo "$FILE_PATH" | grep -qE 'docs/plans/'; then
                    trigger="plan_write_define"
                fi
            fi
            ;;
        discuss)
            if [ "$TOOL_NAME" = "Agent" ]; then
                trigger="agent_return_discuss"
            elif [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
                if echo "$FILE_PATH" | grep -qE 'docs/plans/'; then
                    trigger="plan_write_discuss"
                fi
            fi
            ;;
        implement)
            if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
                trigger="source_edit_implement"
            elif [ "$TOOL_NAME" = "Bash" ]; then
                local cmd
                cmd=$(extract_bash_command)
                if echo "$cmd" | grep -qE '(pytest|npm test|cargo test|make test|run-tests|jest|vitest|go test)'; then
                    trigger="test_run_implement"
                fi
            fi
            ;;
        review)
            if [ "$TOOL_NAME" = "Agent" ]; then
                trigger="agent_return_review"
            fi
            ;;
        complete)
            if [ "$TOOL_NAME" = "Agent" ]; then
                trigger="agent_return_complete"
            elif [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
                if echo "$FILE_PATH" | grep -qE 'docs/'; then
                    trigger="project_docs_edit_complete"
                fi
            elif [ "$TOOL_NAME" = "Bash" ]; then
                local bash_cmd
                bash_cmd=$(extract_bash_command)
                if echo "$bash_cmd" | grep -qE '(pytest|npm test|cargo test|make test|run-tests|jest|vitest|go test)'; then
                    trigger="test_run_complete"
                fi
            fi
            ;;
    esac

    # Load nudge message and fire if trigger matched and hasn't fired yet this phase
    if [ -n "$trigger" ]; then
        local l2_msg_body
        l2_msg_body=$(load_message "nudges/$trigger.md")
        if [ -n "$l2_msg_body" ]; then
            l2_msg="[Workflow Coach — $PHASE_UPPER] $l2_msg_body"
        fi
    fi

    if [ -n "$trigger" ] && [ -n "$l2_msg" ]; then
        if [ "$(has_coaching_fired "$trigger")" != "true" ]; then
            add_coaching_fired "$trigger"
            if [ -n "$MESSAGES" ]; then
                MESSAGES="$MESSAGES

$l2_msg"
            else
                MESSAGES="$l2_msg"
            fi
            _trace "[WFM coach] L2: nudges/$trigger.md — ${l2_msg_body:0:80}..."
        else
            _log "[WFM coach] L2: trigger=$trigger — already fired, skipped"
        fi
    elif [ -n "$trigger" ]; then
        _log "[WFM coach] L2: trigger=$trigger — no message file"
    else
        _log "[WFM coach] L2: no trigger matched"
    fi

    # REVIEW Layer 2 trigger: "After presenting findings"
    # Fires when writing review findings (Write/Edit/MultiEdit to spec in review phase)
    if [ "$PHASE" = "review" ]; then
        if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
            if echo "$FILE_PATH" | grep -qE 'docs/specs/'; then
                local findings_trigger="findings_present_review"
                if [ "$(has_coaching_fired "$findings_trigger")" != "true" ]; then
                    add_coaching_fired "$findings_trigger"
                    local findings_body
                    findings_body=$(load_message "nudges/findings_present_review.md")
                    [ -n "$findings_body" ] && _trace "[WFM coach] L2: nudges/findings_present_review.md — ${findings_body:0:80}..."
                    if [ -n "$findings_body" ]; then
                        local findings_msg="[Workflow Coach — REVIEW] $findings_body"
                        if [ -n "$MESSAGES" ]; then
                            MESSAGES="$MESSAGES

$findings_msg"
                        else
                            MESSAGES="$findings_msg"
                        fi
                    fi
                fi
            fi
        fi
    fi
}
