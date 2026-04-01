#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Hard gate validation, soft gate checks, and state preservation reader.
# Pure functions — no side effects, no state writes.

[ -n "${_WFM_GATE_CHECKS_LOADED:-}" ] && return 0
_WFM_GATE_CHECKS_LOADED=1

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$SCRIPT_DIR/infrastructure/state-io.sh"
source "$SCRIPT_DIR/infrastructure/phase.sh"
source "$SCRIPT_DIR/infrastructure/settings.sh"
source "$SCRIPT_DIR/infrastructure/milestones.sh"
source "$SCRIPT_DIR/infrastructure/tracking.sh"

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
            echo "  Fix: Complete all remaining pipeline steps." >&2
            return 1
        fi
    fi

    return 0
}

# Soft gate checks — return warning message or empty string
check_soft_gate() {
    local target_phase="$1"

    case "$target_phase" in
        implement)
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
            local changes
            changes=$(git diff --name-only origin/main...HEAD 2>/dev/null; git diff --name-only main...HEAD 2>/dev/null; git diff --name-only 2>/dev/null)
            if [ -z "$changes" ]; then
                echo "No code changes detected. The review pipeline requires changed files to analyze. Proceed anyway?"
                return
            fi
            ;;
        complete)
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

    echo ""
}
