#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Section/milestone helpers — generic status sections and public API wrappers

[ -n "${_WFM_MILESTONES_LOADED:-}" ] && return 0
_WFM_MILESTONES_LOADED=1

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/infrastructure/state-io.sh"

# ---------------------------------------------------------------------------
# Generic phase status helpers (used by review, completion, implement)
# Parameterized by section name to avoid tripling the code.
# ---------------------------------------------------------------------------

# Initialize a status section with all fields set to False
# Usage: _reset_section "review" "verification_complete" "agents_dispatched" ...
_reset_section() {
    local section="$1"; shift
    if [ ! -f "$STATE_FILE" ]; then return; fi
    local fields_json
    fields_json=$(printf '%s\n' "$@" | jq -R -s 'split("\n") | map(select(. != ""))' 2>/dev/null)
    _update_state '.[$s] = ($fields | reduce .[] as $f ({}; .[$f] = false))' --arg s "$section" --argjson fields "$fields_json"
}

# Read a field from a status section
# Usage: _get_section_field "review" "verification_complete"
_get_section_field() {
    local section="$1" field="$2"
    if [ ! -f "$STATE_FILE" ]; then echo ""; return; fi
    local val
    val=$(jq -r --arg s "$section" --arg f "$field" '(.[$s] // {})[$f] | if . == null then "" elif type == "boolean" then tostring else . end' "$STATE_FILE" 2>/dev/null) || val=""
    echo "$val"
}

# Write a field to a status section
# Usage: _set_section_field "review" "verification_complete" "true"
_set_section_field() {
    local section="$1" field="$2" value="$3"
    if [ ! -f "$STATE_FILE" ]; then return; fi
    _show "[WFM state] SET $section.$field = $value"
    if [ "$value" = "true" ] || [ "$value" = "false" ]; then
        _update_state 'setpath([$s, $f]; ($v == "true"))' --arg s "$section" --arg f "$field" --arg v "$value"
    else
        _update_state 'setpath([$s, $f]; $v)' --arg s "$section" --arg f "$field" --arg v "$value"
    fi
}

# Check if a status section exists in the state file
# Usage: _section_exists "review"
_section_exists() {
    local section="$1"
    if [ ! -f "$STATE_FILE" ]; then echo "false"; return; fi
    jq -e --arg s "$section" 'has($s)' "$STATE_FILE" >/dev/null 2>&1 && echo "true" || echo "false"
}

# Check milestones for a section, return missing fields or empty string.
# If section does not exist, returns ALL fields as missing (fail-closed).
# Usage: _check_milestones "implement" "plan_read" "tests_passing" "all_tasks_complete"
_check_milestones() {
    local section="$1"; shift
    if [ "$(_section_exists "$section")" != "true" ]; then
        echo " $*"
        return
    fi
    local missing=""
    local val=""
    for field in "$@"; do
        val=$(_get_section_field "$section" "$field")
        [ "$val" != "true" ] && missing="$missing $field"
    done
    echo "$missing"
}

# ---------------------------------------------------------------------------
# Review status (public API — preserves backward compatibility)
# ---------------------------------------------------------------------------
reset_review_status() { _reset_section "review" "verification_complete" "agents_dispatched" "findings_presented" "findings_acknowledged"; }
get_review_field() { _get_section_field "review" "$1"; }
set_review_field() { _set_section_field "review" "$1" "$2"; }

# ---------------------------------------------------------------------------
# Completion status (public API)
# ---------------------------------------------------------------------------
reset_completion_status() { _reset_section "completion" "plan_validated" "outcomes_validated" "results_presented" "docs_checked" "committed" "pushed" "issues_reconciled" "tech_debt_audited" "handover_saved"; }
get_completion_field() { _get_section_field "completion" "$1"; }
set_completion_field() { _set_section_field "completion" "$1" "$2"; }

# ---------------------------------------------------------------------------
# Discuss status (public API)
# ---------------------------------------------------------------------------
reset_discuss_status() { _reset_section "discuss" "problem_confirmed" "research_done" "approach_selected"; }
get_discuss_field() { _get_section_field "discuss" "$1"; }
set_discuss_field() { _set_section_field "discuss" "$1" "$2"; }

# ---------------------------------------------------------------------------
# Implement status (public API)
# ---------------------------------------------------------------------------
reset_implement_status() { _reset_section "implement" "plan_written" "plan_read" "tests_passing" "all_tasks_complete"; }
get_implement_field() { _get_section_field "implement" "$1"; }
set_implement_field() { _set_section_field "implement" "$1" "$2"; }
