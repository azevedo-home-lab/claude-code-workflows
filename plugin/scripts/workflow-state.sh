#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Workflow state utility — read/write phase state
# Used by hooks (read only) and commands (read/write)
# All state consolidated in a single workflow.json file

STATE_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/.claude/state"
STATE_FILE="$STATE_DIR/workflow.json"

# Generic state write helper. Atomic: writes to temp file, then mv.
# Usage: _update_state <jq_filter> [--arg name val]... [--argjson name val]...
_update_state() {
    local filter="$1"; shift
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg ts "$ts" "$@" \
        "$filter | .updated = \$ts" \
        "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# Restrictive tier: DEFINE and DISCUSS phases
# NOTE: .claude/hooks/ deliberately excluded — enforcement mechanism must not be self-modifiable
RESTRICTED_WRITE_WHITELIST='(\.claude/state/|docs/superpowers/specs/|docs/superpowers/plans/|docs/plans/)'

# Docs-allowed tier: COMPLETE phase
COMPLETE_WRITE_WHITELIST='(\.claude/state/|\.claude/commands/|docs/|^[^/]*\.md$)'

# ---------------------------------------------------------------------------
# Shared hook helpers
# ---------------------------------------------------------------------------

# Emit a PreToolUse deny JSON response. Used by workflow-gate.sh and bash-write-guard.sh.
# Usage: emit_deny "reason message"
emit_deny() {
    local reason="$1"
    jq -n --arg reason "$reason" '{
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": $reason
        }
    }'
}

# ---------------------------------------------------------------------------
# Phase management
# ---------------------------------------------------------------------------

get_phase() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "off"
        return
    fi
    local phase
    phase=$(jq -r '.phase // "off"' "$STATE_FILE" 2>/dev/null) || phase="off"
    echo "${phase:-off}"
}

get_autonomy_level() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "2"
        return
    fi
    local level
    level=$(jq -r '.autonomy_level // 2' "$STATE_FILE" 2>/dev/null) || level="2"
    echo "${level:-2}"
}

set_autonomy_level() {
    local level="$1"
    case "$level" in
        1|2|3) ;;
        *) echo "ERROR: Invalid autonomy level: $level (valid: 1, 2, 3)" >&2; return 1 ;;
    esac
    if [ ! -f "$STATE_FILE" ]; then
        echo "WARNING: No workflow state file. Start a workflow phase first (e.g., /define)." >&2
        return 1
    fi
    _update_state '.autonomy_level = $v' --argjson v "$level"
}

# ---------------------------------------------------------------------------
# Last observation ID tracking (claude-mem)
# ---------------------------------------------------------------------------

get_last_observation_id() {
    if [ ! -f "$STATE_FILE" ]; then
        echo ""
        return
    fi
    local obs_id
    obs_id=$(jq -r '.last_observation_id // "" | tostring' "$STATE_FILE" 2>/dev/null) || obs_id=""
    # Return empty for null/0
    if [ "$obs_id" = "null" ] || [ "$obs_id" = "0" ]; then obs_id=""; fi
    echo "$obs_id"
}

set_last_observation_id() {
    local obs_id="$1"
    mkdir -p "$STATE_DIR"
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [ ! -f "$STATE_FILE" ]; then
        # Create minimal state file for observation tracking
        jq -n --argjson id "$obs_id" --arg ts "$ts" \
            '{"phase": "off", "last_observation_id": $id, "updated": $ts}' > "$STATE_FILE"
        return
    fi
    _update_state '.last_observation_id = $id' --argjson id "$obs_id"
}

# ---------------------------------------------------------------------------
# Tracked observations (tech debt, open issues, next steps)
# ---------------------------------------------------------------------------

get_tracked_observations() {
    if [ ! -f "$STATE_FILE" ]; then
        echo ""
        return
    fi
    local result
    result=$(jq -r '.tracked_observations // [] | map(tostring) | join(",")' "$STATE_FILE" 2>/dev/null) || result=""
    echo "$result"
}

set_tracked_observations() {
    local ids_csv="$1"
    mkdir -p "$STATE_DIR"
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [ ! -f "$STATE_FILE" ]; then
        jq -n --arg ids "$ids_csv" --arg ts "$ts" \
            '{"phase": "off", "tracked_observations": (if $ids == "" then [] else ($ids | split(",") | map(select(. != "") | tonumber)) end), "updated": $ts}' > "$STATE_FILE"
        return
    fi
    _update_state '.tracked_observations = (if $ids == "" then [] else ($ids | split(",") | map(select(. != "") | tonumber)) end)' --arg ids "$ids_csv"
}

add_tracked_observation() {
    local obs_id="$1"
    if [ -z "$obs_id" ]; then return 1; fi
    mkdir -p "$STATE_DIR"
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [ ! -f "$STATE_FILE" ]; then
        jq -n --argjson id "$obs_id" --arg ts "$ts" \
            '{"phase": "off", "tracked_observations": [$id], "updated": $ts}' > "$STATE_FILE"
        return
    fi
    _update_state '.tracked_observations = ((.tracked_observations // []) + [$id] | unique)' --argjson id "$obs_id"
}

remove_tracked_observation() {
    local obs_id="$1"
    if [ -z "$obs_id" ] || [ ! -f "$STATE_FILE" ]; then return 1; fi
    _update_state '.tracked_observations |= map(select(. != $id))' --argjson id "$obs_id"
}

# ---------------------------------------------------------------------------
# Completion snapshot (loop-back exception from COMPLETE → IMPLEMENT → COMPLETE)
# ---------------------------------------------------------------------------

save_completion_snapshot() { if [ ! -f "$STATE_FILE" ]; then return; fi; _update_state '.completion_snapshot = (.completion // {})'; }
restore_completion_snapshot() { if [ ! -f "$STATE_FILE" ]; then return; fi; _update_state '.completion = (.completion_snapshot // {}) | del(.completion_snapshot)'; }

has_completion_snapshot() {
    if [ ! -f "$STATE_FILE" ]; then echo "false"; return; fi
    local result
    result=$(jq -r 'if (.completion_snapshot != null and .completion_snapshot != {}) then "true" else "false" end' "$STATE_FILE" 2>/dev/null) || result="false"
    echo "$result"
}

# Returns non-zero if a hard gate blocks the phase transition.
# Gate error message is sent to stderr.
# Pure validation — no side effects.
_check_phase_gates() {
    local current="$1" new_phase="$2"

    # IMPLEMENT exit gate: leaving implement → must have completed implementation milestones
    if [ "$current" = "implement" ] && [ "$new_phase" != "implement" ]; then
        local missing=""
        missing=$(_check_milestones "implement" "plan_read" "tests_passing" "all_tasks_complete")
        if [ -n "$missing" ]; then
            echo "HARD GATE: Cannot leave IMPLEMENT — incomplete milestones:$missing. Complete all implementation steps before transitioning." >&2
            return 1
        fi
    fi

    # COMPLETE exit gate: leaving complete → must have completed completion pipeline
    if [ "$current" = "complete" ] && [ "$new_phase" != "complete" ]; then
        local missing=""
        missing=$(_check_milestones "completion" "plan_validated" "outcomes_validated" "results_presented" "docs_checked" "committed" "tech_debt_audited" "handover_saved")
        if [ -n "$missing" ]; then
            echo "HARD GATE: Cannot leave COMPLETE — incomplete pipeline steps:$missing. Complete all completion steps before transitioning." >&2
            return 1
        fi
    fi

    return 0
}

# Reads fields from current state that must be preserved across phase transitions.
# Sets variables in the caller's scope (no `local` — writes to caller's declared locals).
# Caller must declare these variables with `local` before calling this function.
_read_preserved_state() {
    if [ ! -f "$STATE_FILE" ]; then return; fi

    preserved_skill=$(get_active_skill)
    preserved_decision=$(get_decision_record)
    preserved_autonomy=$(get_autonomy_level)
    preserved_obs_id=$(get_last_observation_id)
    preserved_tracked=$(get_tracked_observations)
    preserved_snapshot=$(jq -c '.completion_snapshot // null' "$STATE_FILE" 2>/dev/null) || preserved_snapshot="null"
}

set_phase() {
    local new_phase="$1"

    # Validate phase name
    case "$new_phase" in
        off|define|discuss|implement|review|complete) ;;
        *) echo "ERROR: Invalid phase: $new_phase (valid: off, define, discuss, implement, review, complete)" >&2; return 1 ;;
    esac

    mkdir -p "$STATE_DIR"

    # Hard gate checks: block phase transitions if milestones are incomplete.
    # Only enforced when reset_*_status was called (status object exists).
    # The state write MUST NOT run if a gate blocks.
    if [ -f "$STATE_FILE" ]; then
        local current
        current=$(get_phase)
        if ! _check_phase_gates "$current" "$new_phase"; then
            return 1
        fi
    fi

    # Read existing state to preserve fields across transitions
    local preserved_skill="" preserved_decision="" preserved_autonomy=""
    local preserved_obs_id="" preserved_tracked="" preserved_snapshot="null"
    local current_phase="off"
    if [ -f "$STATE_FILE" ]; then
        current_phase=$(get_phase)
        _read_preserved_state
    fi

    # If new phase is off, clear active_skill, decision_record, and autonomy_level (cycle complete)
    # Note: last_observation_id is preserved — it's useful in the statusline even when workflow is OFF
    if [ "$new_phase" = "off" ]; then
        preserved_skill=""
        preserved_decision=""
        preserved_autonomy=""
    fi

    # Initialize autonomy_level to 2 when transitioning from OFF to active phase.
    # Note: this guard only fires on the very first set_phase call (no state file yet),
    # because get_autonomy_level returns "2" as default when a file exists.
    # After set_phase("off") clears autonomy_level, the next get_autonomy_level still
    # returns "2" (default), so preserved_autonomy is never empty in normal cycling.
    if [ "$current_phase" = "off" ] && [ "$new_phase" != "off" ] && [ -z "$preserved_autonomy" ]; then
        preserved_autonomy="2"
    fi

    # Build tracked observations as JSON array
    local tracked_json="[]"
    if [ -n "$preserved_tracked" ]; then
        tracked_json=$(jq -n --arg csv "$preserved_tracked" '$csv | split(",") | map(select(. != "") | tonumber)')
    fi

    # Build the new state: preserve active_skill, decision_record, and autonomy_level,
    # reset message_shown, fresh coaching, clean up review if leaving review
    local snapshot_json="${preserved_snapshot:-null}"
    # Treat empty string as null for jq
    if [ -z "$snapshot_json" ]; then snapshot_json="null"; fi

    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n --arg phase "$new_phase" --arg ts "$ts" \
        --arg skill "$preserved_skill" --arg decision "$preserved_decision" \
        --argjson autonomy "${preserved_autonomy:-null}" \
        --arg obs_id "$preserved_obs_id" \
        --argjson tracked "$tracked_json" \
        --argjson snapshot "$snapshot_json" \
        '{
            phase: $phase,
            message_shown: false,
            active_skill: $skill,
            decision_record: $decision,
            coaching: {tool_calls_since_agent: 0, layer2_fired: []},
            updated: $ts
        }
        + (if $autonomy != null then {autonomy_level: $autonomy} else {} end)
        + (if $obs_id != "" and $obs_id != "null" then {last_observation_id: ($obs_id | tonumber)} else {} end)
        + (if ($tracked | length) > 0 then {tracked_observations: $tracked} else {} end)
        + (if $snapshot != null then {completion_snapshot: $snapshot} else {} end)' \
        > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

get_message_shown() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "false"
        return
    fi
    local val
    val=$(jq -r 'if .message_shown == true then "true" else "false" end' "$STATE_FILE" 2>/dev/null) || val="false"
    echo "${val:-false}"
}

set_message_shown() { if [ ! -f "$STATE_FILE" ]; then return; fi; _update_state '.message_shown = true'; }

# ---------------------------------------------------------------------------
# Active skill management
# ---------------------------------------------------------------------------

set_active_skill() { if [ ! -f "$STATE_FILE" ]; then return; fi; _update_state '.active_skill = $v' --arg v "$1"; }

get_active_skill() {
    if [ ! -f "$STATE_FILE" ]; then
        echo ""
        return
    fi
    local val
    val=$(jq -r '.active_skill // ""' "$STATE_FILE" 2>/dev/null) || val=""
    echo "$val"
}

# ---------------------------------------------------------------------------
# Decision record management
# ---------------------------------------------------------------------------

set_decision_record() { if [ ! -f "$STATE_FILE" ]; then return; fi; _update_state '.decision_record = $v' --arg v "$1"; }

get_decision_record() {
    if [ ! -f "$STATE_FILE" ]; then
        echo ""
        return
    fi
    local val
    val=$(jq -r '.decision_record // ""' "$STATE_FILE" 2>/dev/null) || val=""
    echo "$val"
}

# ---------------------------------------------------------------------------
# Soft gate checks — return warning message or empty string
# ---------------------------------------------------------------------------

check_soft_gate() {
    local target_phase="$1"
    local project_root
    project_root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

    case "$target_phase" in
        implement)
            # Check if any plan file exists
            local plan_files
            plan_files=$(ls "$project_root"/docs/superpowers/plans/*.md "$project_root"/docs/plans/*.md 2>/dev/null)
            if [ -z "$plan_files" ]; then
                echo "No plan exists. The workflow recommends /discuss first. Proceed without a plan?"
                return
            fi
            ;;
        review)
            # Check if there are code changes
            local changes
            changes=$(git diff --name-only main...HEAD 2>/dev/null; git diff --name-only 2>/dev/null)
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

# ---------------------------------------------------------------------------
# Generic phase status helpers (used by review, completion, implement)
# Parameterized by section name to avoid tripling the code.
# ---------------------------------------------------------------------------

# Initialize a status section with all fields set to False
# Usage: _reset_section "review" "verification_complete" "agents_dispatched" ...
_reset_section() {
    local section="$1"; shift
    if [ ! -f "$STATE_FILE" ]; then return; fi
    local filter=".${section} = {"
    local first=true
    for field in "$@"; do
        $first || filter+=", "
        filter+="\"$field\": false"
        first=false
    done
    filter+="}"
    _update_state "$filter"
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
    if [ "$value" = "true" ] || [ "$value" = "false" ]; then
        _update_state ".${section}.${field} = ${value}"
    else
        _update_state ".${section}.${field} = \$v" --arg v "$value"
    fi
}

# Check if a status section exists in the state file
# Usage: _section_exists "review"
_section_exists() {
    local section="$1"
    if [ ! -f "$STATE_FILE" ]; then echo "false"; return; fi
    jq -e --arg s "$section" 'has($s)' "$STATE_FILE" >/dev/null 2>&1 && echo "true" || echo "false"
}

# Check milestones for a section, return missing fields or empty string
# Usage: _check_milestones "implement" "plan_read" "tests_passing" "all_tasks_complete"
_check_milestones() {
    local section="$1"; shift
    if [ "$(_section_exists "$section")" != "true" ]; then
        echo ""
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
reset_completion_status() { _reset_section "completion" "plan_validated" "outcomes_validated" "results_presented" "docs_checked" "committed" "tech_debt_audited" "handover_saved"; }
get_completion_field() { _get_section_field "completion" "$1"; }
set_completion_field() { _set_section_field "completion" "$1" "$2"; }

# ---------------------------------------------------------------------------
# Implement status (public API)
# ---------------------------------------------------------------------------
reset_implement_status() { _reset_section "implement" "plan_read" "tests_passing" "all_tasks_complete"; }
get_implement_field() { _get_section_field "implement" "$1"; }
set_implement_field() { _set_section_field "implement" "$1" "$2"; }

# ---------------------------------------------------------------------------
# Coaching helpers
# ---------------------------------------------------------------------------

increment_coaching_counter() { if [ ! -f "$STATE_FILE" ]; then return; fi; _update_state '.coaching.tool_calls_since_agent += 1'; }
reset_coaching_counter() { if [ ! -f "$STATE_FILE" ]; then return; fi; _update_state '.coaching.tool_calls_since_agent = 0'; }

add_coaching_fired() {
    if [ ! -f "$STATE_FILE" ]; then return; fi
    _update_state '.coaching.layer2_fired += [$t] | .coaching.last_layer2_at = .coaching.tool_calls_since_agent' --arg t "$1"
}

has_coaching_fired() {
    local trigger_type="$1"
    if [ ! -f "$STATE_FILE" ]; then
        echo "false"
        return
    fi
    local result
    result=$(jq -r --arg t "$trigger_type" 'if ([.coaching.layer2_fired[]? | select(. == $t)] | length) > 0 then "true" else "false" end' "$STATE_FILE" 2>/dev/null) || result="false"
    echo "$result"
}

# Check if Layer 2 coaching should be refreshed (30+ calls of silence)
# Silently clears layer2_fired array if threshold exceeded — no stdout output
# to avoid corrupting hook JSON stream.
check_coaching_refresh() {
    if [ ! -f "$STATE_FILE" ]; then return; fi
    _update_state 'if (.coaching.tool_calls_since_agent - (.coaching.last_layer2_at // 0)) >= 30 then .coaching.layer2_fired = [] | .coaching.last_layer2_at = .coaching.tool_calls_since_agent else . end'
}

# ---------------------------------------------------------------------------
# Pending verify tracking
# ---------------------------------------------------------------------------

set_pending_verify() { if [ ! -f "$STATE_FILE" ]; then return; fi; _update_state '.coaching.pending_verify = $c' --argjson c "${1:-0}"; }

get_pending_verify() {
    if [ ! -f "$STATE_FILE" ]; then echo "0"; return; fi
    local val
    val=$(jq -r '.coaching.pending_verify // 0' "$STATE_FILE" 2>/dev/null) || val="0"
    echo "$val"
}
