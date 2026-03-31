#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Gate checks and agent phase transitions

[ -n "${_WFM_PHASE_GATES_LOADED:-}" ] && return 0
_WFM_PHASE_GATES_LOADED=1

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/state-io.sh"
source "$SCRIPT_DIR/phase.sh"
source "$SCRIPT_DIR/settings.sh"
source "$SCRIPT_DIR/milestones.sh"
source "$SCRIPT_DIR/tracking.sh"

# Returns non-zero if a hard gate blocks the phase transition.
# Gate error message is sent to stderr.
# Pure validation — no side effects.
_check_phase_gates() {
    local current="$1" new_phase="$2"

    # DISCUSS exit gate: leaving discuss → must have approach_selected
    if [ "$current" = "discuss" ] && [ "$new_phase" != "discuss" ]; then
        local missing=""
        missing=$(_check_milestones "discuss" "approach_selected")
        if [ -n "$missing" ]; then
            echo "HARD GATE: Cannot leave DISCUSS — approach not selected." >&2
            echo "  Why: The design decision is the contract between DISCUSS and IMPLEMENT." >&2
            echo "  Unset milestones:$missing" >&2
            echo "  Fix: Complete the converge phase and mark approach_selected=true." >&2
            return 1
        fi
    fi

    # IMPLEMENT exit gate: leaving implement → must have completed implementation milestones
    if [ "$current" = "implement" ] && [ "$new_phase" != "implement" ]; then
        local missing=""
        # Check if a test suite exists; skip tests_passing milestone if not
        local project_root
        project_root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
        local has_tests=false
        if find "$project_root" -maxdepth 3 -name 'run-tests.sh' -o -name 'pytest.ini' -o -name 'jest.config.*' -o -name 'vitest.config.*' -o -name 'Cargo.toml' -o -name 'go.mod' 2>/dev/null | grep -q .; then
            has_tests=true
        elif [ -d "$project_root/tests" ] || [ -d "$project_root/test" ] || [ -d "$project_root/__tests__" ]; then
            has_tests=true
        fi


          if [ "$has_tests" = "true" ]; then
              missing=$(_check_milestones "implement" "plan_written" "plan_read" "tests_passing" "all_tasks_complete")
          else
              missing=$(_check_milestones "implement" "plan_written" "plan_read" "all_tasks_complete")
          fi
        if [ -n "$missing" ]; then
            echo "HARD GATE: Cannot leave IMPLEMENT — incomplete milestones." >&2
            echo "  Why: These milestones prove the plan was executed and tests actually passed." >&2
            echo "  Unset milestones:$missing" >&2
            echo "  Fix each missing milestone:" >&2
            echo "    plan_written       — write the implementation plan with writing-plans skill" >&2
            echo "    all_tasks_complete — verify every plan task done, files exist on disk" >&2
            echo "    tests_passing      — run the test suite and show output before setting this" >&2
            return 1
        fi
    fi

    # REVIEW skip gate: agent cannot jump to COMPLETE without REVIEW having run.
    # Only fires when transitioning INTO complete (not when leaving complete).
    # User bypasses this (user_initiated=true skips _check_phase_gates entirely).
    if [ "$new_phase" = "complete" ] && [ "$current" != "complete" ]; then
        local review_done=""
        review_done=$(_check_milestones "review" "findings_acknowledged")
        if [ -n "$review_done" ]; then
            echo "HARD GATE: Cannot enter COMPLETE — REVIEW phase was not completed." >&2
            echo "  Why: REVIEW is mandatory before COMPLETE. Skipping it means unreviewed" >&2
            echo "       code may ship with quality, security, or architecture issues." >&2
            echo "  Fix: Transition to review first, complete it, then proceed to complete." >&2
            echo "  Override: Only the user can skip this by running /complete directly." >&2
            return 1
        fi
    fi

    # COMPLETE exit gate: leaving complete → must have completed completion pipeline
    if [ "$current" = "complete" ] && [ "$new_phase" != "complete" ]; then
        local missing=""
        missing=$(_check_milestones "completion" "plan_validated" "outcomes_validated" "results_presented" "docs_checked" "committed" "pushed" "issues_reconciled" "tech_debt_audited" "handover_saved")
        if [ -n "$missing" ]; then
            echo "HARD GATE: Cannot leave COMPLETE — pipeline not finished." >&2
            echo "  Why: Each pipeline step produces artifacts needed by the next session." >&2
            echo "  Unset milestones:$missing" >&2
            echo "  Fix: Complete all remaining pipeline steps in complete.md." >&2
            return 1
        fi
    fi

    return 0
}

# Reads fields from current state that must be preserved across phase transitions.
# Sets variables in the caller's scope (no `local` — writes to caller's declared locals).
# Caller must declare these variables with `local` before calling this function.
#
# Sets these variables in caller's scope (caller MUST declare them first):
#   preserved_skill, preserved_decision, preserved_autonomy, preserved_obs_id,
#   preserved_tracked, preserved_issue_mappings, preserved_spec, preserved_tests_passed,
#   preserved_debug
_read_preserved_state() {
    if [ ! -f "$STATE_FILE" ]; then return; fi

    preserved_skill=$(get_active_skill)
    preserved_decision=$(get_plan_path)
    preserved_autonomy=$(get_autonomy_level)
    preserved_obs_id=$(get_last_observation_id)
    preserved_tracked=$(get_tracked_observations)
    preserved_issue_mappings=$(jq -c '.issue_mappings // null' "$STATE_FILE" 2>/dev/null) || preserved_issue_mappings="null"
    preserved_spec=$(get_spec_path)
    preserved_tests_passed=$(get_tests_passed_at)
    preserved_debug=$(get_debug)
}

# AGENT PHASE TRANSITION — called only via Bash tool by Claude in auto autonomy mode.
# Enforces forward-only transitions and milestone gate checks.
# User transitions use user-set-phase.sh (!backtick only) — NOT this function.
# There is no bypass: no user-override path here. Agent path only.
agent_set_phase() {
    local new_phase="$1"

    # Validate phase name.
    # Agents cannot set phase to 'off' — only the user can end a cycle.
    case "$new_phase" in
        define|discuss|implement|review|complete) ;;
        off) echo "BLOCKED: Agents cannot set phase to 'off'. Only the user can end a workflow cycle." >&2; return 1 ;;
        *) echo "ERROR: Invalid phase: $new_phase (valid: define, discuss, implement, review, complete)" >&2; return 1 ;;
    esac

    # Authorization: forward-only auto-transition only.
    # Agents may only advance the pipeline — never retreat, never skip to off.
    if [ ! -f "$STATE_FILE" ]; then
        echo "BLOCKED: No workflow state. The user must start a phase with a slash command first." >&2
        return 1
    fi

    local current_autonomy
    current_autonomy=$(get_autonomy_level)
    if [ "$current_autonomy" != "auto" ]; then
        echo "BLOCKED: Phase transition to '$new_phase' requires user authorization." >&2
        echo "  Current autonomy: $current_autonomy" >&2
        echo "  Agent transitions are only allowed in 'auto' autonomy mode." >&2
        echo "" >&2
        echo "  Agent instructions:" >&2
        echo "    - Do NOT retry agent_set_phase — it will keep failing." >&2
        echo "    - Present your completed work to the user." >&2
        echo "    - Tell the user to run /$new_phase to proceed." >&2
        return 1
    fi

    local current_ordinal new_ordinal
    current_ordinal=$(_phase_ordinal "$(get_phase)")
    new_ordinal=$(_phase_ordinal "$new_phase")
    if [ "$new_ordinal" -le "$current_ordinal" ]; then
        echo "BLOCKED: Agent may only advance the phase (forward-only)." >&2
        echo "  Current: $(get_phase) (ordinal $current_ordinal)" >&2
        echo "  Requested: $new_phase (ordinal $new_ordinal)" >&2
        echo "  To go back or reset: the user must run the phase command directly." >&2
        return 1
    fi

    # Hard gate checks: milestones must be complete before advancing.
    # Gates always run for agent transitions — agents cannot bypass them.
    local current
    current=$(get_phase)
    if ! _check_phase_gates "$current" "$new_phase"; then
        return 1
    fi

    # Read existing state to preserve fields across transitions.
    # NOTE: Milestone sections (discuss, implement, review, completion) are intentionally
    # NOT preserved — the jq template rebuilds state from scratch, dropping them.
    # There is no need to reset them here; they do not survive phase transitions.
    local preserved_skill="" preserved_decision="" preserved_autonomy=""
    local preserved_obs_id="" preserved_tracked=""
    local preserved_issue_mappings="null"
    local preserved_spec=""
    local preserved_tests_passed=""
    local preserved_debug=""
    _read_preserved_state

    # Build tracked observations as JSON array
    local tracked_json="[]"
    if [ -n "$preserved_tracked" ]; then
        tracked_json=$(jq -n --arg csv "$preserved_tracked" '$csv | split(",") | map(select(. != "") | (tonumber? // empty))')
    fi

    # STATE SCHEMA CONTRACT: This template is duplicated in user-set-phase.sh.
    # The duplication is deliberate — agent and user paths must not share transition code.
    # If you modify the schema fields, update BOTH locations and run:
    #   diff <(grep -oP '"[a-z_]+"' plugin/scripts/phase-gates.sh | sort) \
    #        <(grep -oP '"[a-z_]+"' plugin/scripts/user-set-phase.sh | sort)
    # to verify they match.
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    ( set -o pipefail
      jq -n --arg phase "$new_phase" --arg ts "$ts" \
          --arg skill "$preserved_skill" --arg decision "$preserved_decision" \
          --arg autonomy "${preserved_autonomy}" \
          --arg obs_id "$preserved_obs_id" \
          --argjson tracked "$tracked_json" \
          --argjson issue_maps "${preserved_issue_mappings:-null}" \
          --arg spec "$preserved_spec" \
          --arg tests_passed "$preserved_tests_passed" \
          --arg debug "$preserved_debug" \
          '{
              phase: $phase,
              message_shown: false,
              active_skill: $skill,
              plan_path: $decision,
              spec_path: $spec,
              coaching: {tool_calls_since_agent: 0, layer2_fired: []},
              updated: $ts
          }
          + (if $autonomy != "" then {autonomy_level: $autonomy} else {} end)
          + (if $obs_id != "" and $obs_id != "null" then {last_observation_id: ($obs_id | tonumber)} else {} end)
          + (if ($tracked | length) > 0 then {tracked_observations: $tracked} else {} end)
          + (if $issue_maps != null then {issue_mappings: $issue_maps} else {} end)
          + (if $tests_passed != "" then {tests_last_passed_at: $tests_passed} else {} end)
          + (if $debug != "" and $debug != "off" then {debug: $debug} else {} end)' \
          | _safe_write
    )

    echo "Phase advanced to ${new_phase}."
}

# ---------------------------------------------------------------------------
# Soft gate checks — return warning message or empty string
# ---------------------------------------------------------------------------

check_soft_gate() {
    local target_phase="$1"

    case "$target_phase" in
        implement)
            # Check if a plan was registered for the current workflow cycle
            local plan_path=""
            if [ -f "$STATE_FILE" ]; then
                plan_path=$(jq -r '.plan_path // ""' "$STATE_FILE" 2>/dev/null) || plan_path=""
            fi
            if [ -z "$plan_path" ]; then
                echo "No plan registered for this workflow cycle. The workflow recommends /discuss first. Proceed without a plan?"
                return
            fi
            ;;
        review)
            # Check if there are code changes
            local changes
            changes=$(git diff --name-only origin/main...HEAD 2>/dev/null; git diff --name-only main...HEAD 2>/dev/null; git diff --name-only 2>/dev/null)
            if [ -z "$changes" ]; then
                echo "No code changes detected. The review pipeline requires changed files to analyze. Proceed anyway?"
                return
            fi
            ;;
        complete)
            # Check if review findings were acknowledged
            if [ ! -f "$STATE_FILE" ]; then
                echo "Review hasn't been run. The workflow should be followed for best results. Proceed anyway?"
                return
            fi
            local acknowledged
            acknowledged=$(jq -r '.review.findings_acknowledged // false | tostring' "$STATE_FILE" 2>/dev/null) || acknowledged="false"
            if [ "$acknowledged" != "true" ]; then
                echo "Review hasn't been run. The workflow should be followed for best results. Proceed anyway?"
                return
            fi
            ;;
    esac

    # No gate triggered — return empty
    echo ""
}
