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

# Atomic write helper. Reads stdin → mktemp temp file → guards → mv.
# All state file writes MUST go through this function.
# Rejects: zero-byte input, >10KB output, invalid JSON, mv failure.
_safe_write() {
    local tmpfile
    tmpfile=$(mktemp "${STATE_FILE}.tmp.XXXXXX") || return 1
    cat > "$tmpfile" || { rm -f "$tmpfile"; return 1; }
    local size
    size=$(wc -c < "$tmpfile")
    if [ "$size" -eq 0 ]; then
        rm -f "$tmpfile"
        echo "ERROR: State file write rejected (zero bytes — possible jq failure)." >&2
        return 1
    fi
    if [ "$size" -gt 10240 ]; then
        rm -f "$tmpfile"
        echo "ERROR: State file would exceed 10KB ($size bytes). Write rejected." >&2
        return 1
    fi
    if ! jq -e . "$tmpfile" >/dev/null 2>&1; then
        rm -f "$tmpfile"
        echo "ERROR: State file write rejected (invalid JSON — possible partial write)." >&2
        return 1
    fi
    mv "$tmpfile" "$STATE_FILE" || { rm -f "$tmpfile"; return 1; }
}

# Generic state write helper. Pipes jq output through _safe_write for atomic,
# size-guarded writes.
# SECURITY NOTE: The $filter parameter is interpolated into jq. This is safe
# because all callers are within this file with hardcoded filter strings.
# Do not expose _update_state to untrusted input.
# Usage: _update_state <jq_filter> [--arg name val]... [--argjson name val]...
_update_state() {
    if [ ! -f "$STATE_FILE" ]; then return 1; fi
    local filter="$1"; shift
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    ( set -o pipefail
      jq --arg ts "$ts" "$@" \
          "$filter | .updated = \$ts" \
          "$STATE_FILE" | _safe_write
    )
}

# Restrictive tier: DEFINE and DISCUSS phases
# NOTE: .claude/hooks/ deliberately excluded — enforcement mechanism must not be self-modifiable
RESTRICTED_WRITE_WHITELIST='(\.claude/state/|docs/superpowers/specs/|docs/superpowers/plans/|docs/plans/)'

# Docs-allowed tier: COMPLETE phase
COMPLETE_WRITE_WHITELIST='(\.claude/state/|docs/|^[^/]*\.md$)'

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

# Phase ordinal for forward-only auto-transition enforcement
_phase_ordinal() {
    case "$1" in
        off)       echo 0 ;;
        error)     echo 0 ;;
        define)    echo 1 ;;
        discuss)   echo 2 ;;
        implement) echo 3 ;;
        review)    echo 4 ;;
        complete)  echo 5 ;;
        *)         echo 0 ;;
    esac
}

get_phase() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "off"
        return
    fi
    local phase
    phase=$(jq -r '.phase // "off"' "$STATE_FILE" 2>/dev/null) || phase="error"
    [ -z "$phase" ] && phase="error"
    case "$phase" in
        off|define|discuss|implement|review|complete) ;;
        *) phase="error" ;;
    esac
    echo "$phase"
}

get_autonomy_level() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "ask"
        return
    fi
    local level
    level=$(jq -r '.autonomy_level // "ask"' "$STATE_FILE" 2>/dev/null) || level="ask"
    [ -z "$level" ] && level="ask"
    echo "$level"
}

set_autonomy_level() {
    local level="$1"
    # Backward-compat: map legacy numeric values
    case "$level" in
        1) level="off" ;;
        2) level="ask" ;;
        3) level="auto" ;;
    esac
    case "$level" in
        off|ask|auto) ;;
        *) echo "ERROR: Invalid autonomy level: $level (valid: off, ask, auto)" >&2; return 1 ;;
    esac
    # set_autonomy_level is always user-initiated — called from !backtick in autonomy.md.
    # No authorization check needed here; the user's slash command is the authorization.
    if [ ! -f "$STATE_FILE" ]; then
        echo "WARNING: No workflow state file. Start a workflow phase first (e.g., /define)." >&2
        return 1
    fi
    _update_state '.autonomy_level = $v' --arg v "$level"
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
        ( set -o pipefail; jq -n --argjson id "$obs_id" --arg ts "$ts" \
            '{"phase": "off", "last_observation_id": $id, "updated": $ts}' | _safe_write )
        return $?
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
        ( set -o pipefail; jq -n --arg ids "$ids_csv" --arg ts "$ts" \
            '{"phase": "off", "tracked_observations": (if $ids == "" then [] else ($ids | split(",") | map(select(. != "") | (tonumber? // empty))) end), "updated": $ts}' | _safe_write )
        return $?
    fi
    _update_state '.tracked_observations = (if $ids == "" then [] else ($ids | split(",") | map(select(. != "") | (tonumber? // empty))) end)' --arg ids "$ids_csv"
}

add_tracked_observation() {
    local obs_id="$1"
    if [ -z "$obs_id" ]; then return 1; fi
    mkdir -p "$STATE_DIR"
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [ ! -f "$STATE_FILE" ]; then
        ( set -o pipefail; jq -n --argjson id "$obs_id" --arg ts "$ts" \
            '{"phase": "off", "tracked_observations": [$id], "updated": $ts}' | _safe_write )
        return $?
    fi
    _update_state '.tracked_observations = ((.tracked_observations // []) + [$id] | unique)' --argjson id "$obs_id"
}

remove_tracked_observation() {
    local obs_id="$1"
    if [ -z "$obs_id" ] || [ ! -f "$STATE_FILE" ]; then return 1; fi
    _update_state '.tracked_observations |= map(select(. != $id))' --argjson id "$obs_id"
}

# ---------------------------------------------------------------------------
# Issue mappings (observation ID → GitHub issue URL)
# ---------------------------------------------------------------------------

set_issue_mapping() {
    local obs_id="$1" issue_url="$2"
    if [ -z "$obs_id" ] || [ -z "$issue_url" ]; then return 1; fi
    mkdir -p "$STATE_DIR"
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [ ! -f "$STATE_FILE" ]; then
        ( set -o pipefail; jq -n --arg id "$obs_id" --arg url "$issue_url" --arg ts "$ts" \
            '{"phase": "off", "issue_mappings": {($id): $url}, "updated": $ts}' | _safe_write )
        return $?
    fi
    _update_state '.issue_mappings = ((.issue_mappings // {}) + {($id): $url})' \
        --arg id "$obs_id" --arg url "$issue_url"
}

get_issue_url() {
    local obs_id="$1"
    if [ ! -f "$STATE_FILE" ]; then echo ""; return; fi
    jq -r --arg id "$obs_id" '.issue_mappings[$id] // ""' "$STATE_FILE" 2>/dev/null
}

get_issue_mappings() {
    if [ ! -f "$STATE_FILE" ]; then echo "{}"; return; fi
    jq -r '.issue_mappings // {}' "$STATE_FILE" 2>/dev/null
}

# Returns non-zero if a hard gate blocks the phase transition.
# Gate error message is sent to stderr.
# Pure validation — no side effects.
_check_phase_gates() {
    local current="$1" new_phase="$2"

    # DISCUSS exit gate: leaving discuss → must have plan_written
    if [ "$current" = "discuss" ] && [ "$new_phase" != "discuss" ]; then
        local missing=""
        missing=$(_check_milestones "discuss" "plan_written")
        if [ -n "$missing" ]; then
            echo "HARD GATE: Cannot leave DISCUSS — plan not written." >&2
            echo "  Why: The plan is the contract between DISCUSS and IMPLEMENT." >&2
            echo "  Unset milestones:$missing" >&2
            echo "  Fix: Complete the implementation plan and mark plan_written=true." >&2
            return 1
        fi
    fi

    # IMPLEMENT exit gate: leaving implement → must have completed implementation milestones
    if [ "$current" = "implement" ] && [ "$new_phase" != "implement" ]; then
        local missing=""
        missing=$(_check_milestones "implement" "plan_read" "tests_passing" "all_tasks_complete")
        if [ -n "$missing" ]; then
            echo "HARD GATE: Cannot leave IMPLEMENT — incomplete milestones." >&2
            echo "  Why: These milestones prove the plan was executed and tests actually passed." >&2
            echo "  Unset milestones:$missing" >&2
            echo "  Fix each missing milestone:" >&2
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
        missing=$(_check_milestones "completion" "plan_validated" "outcomes_validated" "results_presented" "docs_checked" "committed" "pushed" "tech_debt_audited" "handover_saved")
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
_read_preserved_state() {
    if [ ! -f "$STATE_FILE" ]; then return; fi

    preserved_skill=$(get_active_skill)
    preserved_decision=$(get_decision_record)
    preserved_autonomy=$(get_autonomy_level)
    preserved_obs_id=$(get_last_observation_id)
    preserved_tracked=$(get_tracked_observations)
    preserved_issue_mappings=$(jq -c '.issue_mappings // null' "$STATE_FILE" 2>/dev/null) || preserved_issue_mappings="null"
    preserved_tests_passed=$(get_tests_passed_at)
    preserved_debug=$(get_debug)
}

# AGENT PHASE TRANSITION — called only via Bash tool by Claude in auto autonomy mode.
# Enforces forward-only transitions and milestone gate checks.
# User transitions use user-set-phase.sh (!backtick only) — NOT this function.
# There is no bypass: no WF_SKIP_AUTH, no intent file, no user-override path here.
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
    local preserved_tests_passed=""
    local preserved_debug=""
    _read_preserved_state

    # Build tracked observations as JSON array
    local tracked_json="[]"
    if [ -n "$preserved_tracked" ]; then
        tracked_json=$(jq -n --arg csv "$preserved_tracked" '$csv | split(",") | map(select(. != "") | (tonumber? // empty))')
    fi

    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    ( set -o pipefail
      jq -n --arg phase "$new_phase" --arg ts "$ts" \
          --arg skill "$preserved_skill" --arg decision "$preserved_decision" \
          --arg autonomy "${preserved_autonomy}" \
          --arg obs_id "$preserved_obs_id" \
          --argjson tracked "$tracked_json" \
          --argjson issue_maps "${preserved_issue_mappings:-null}" \
          --arg tests_passed "$preserved_tests_passed" \
          --arg debug "$preserved_debug" \
          '{
              phase: $phase,
              message_shown: false,
              active_skill: $skill,
              decision_record: $decision,
              coaching: {tool_calls_since_agent: 0, layer2_fired: []},
              updated: $ts
          }
          + (if $autonomy != "" then {autonomy_level: $autonomy} else {} end)
          + (if $obs_id != "" and $obs_id != "null" then {last_observation_id: ($obs_id | tonumber)} else {} end)
          + (if ($tracked | length) > 0 then {tracked_observations: $tracked} else {} end)
          + (if $issue_maps != null then {issue_mappings: $issue_maps} else {} end)
          + (if $tests_passed != "" then {tests_last_passed_at: $tests_passed} else {} end)
          + (if $debug == "true" then {debug: true} else {} end)' \
          | _safe_write
    )

    echo "Phase advanced to ${new_phase}."
}

get_message_shown() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "false"
        return
    fi
    local val
    val=$(jq -r 'if .message_shown == true then "true" else "false" end' "$STATE_FILE" 2>/dev/null) || val="false"
    [ -z "$val" ] && val="false"
    echo "$val"
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
# Test results tracking (preserved across phase transitions)
# ---------------------------------------------------------------------------

set_tests_passed_at() { if [ ! -f "$STATE_FILE" ]; then return; fi; _update_state '.tests_last_passed_at = $v' --arg v "$1"; }

get_tests_passed_at() {
    if [ ! -f "$STATE_FILE" ]; then
        echo ""
        return
    fi
    local val
    val=$(jq -r '.tests_last_passed_at // ""' "$STATE_FILE" 2>/dev/null) || val=""
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
            plan_files=$(find "$project_root/docs/superpowers/plans" "$project_root/docs/plans" -maxdepth 1 -name '*.md' 2>/dev/null | head -1)
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
reset_completion_status() { _reset_section "completion" "plan_validated" "outcomes_validated" "results_presented" "docs_checked" "committed" "pushed" "tech_debt_audited" "handover_saved"; }
get_completion_field() { _get_section_field "completion" "$1"; }
set_completion_field() { _set_section_field "completion" "$1" "$2"; }

# ---------------------------------------------------------------------------
# Discuss status (public API)
# ---------------------------------------------------------------------------
reset_discuss_status() { _reset_section "discuss" "problem_confirmed" "research_done" "approach_selected" "plan_written"; }
get_discuss_field() { _get_section_field "discuss" "$1"; }
set_discuss_field() { _set_section_field "discuss" "$1" "$2"; }

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

# ---------------------------------------------------------------------------
# Debug mode
# ---------------------------------------------------------------------------

get_debug() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "false"
        return
    fi
    local val
    val=$(jq -r 'if .debug == true then "true" else "false" end' "$STATE_FILE" 2>/dev/null) || val="false"
    [ -z "$val" ] && val="false"
    echo "$val"
}

set_debug() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "WARNING: No workflow state file. Start a workflow phase first." >&2
        return 1
    fi
    local val="${1:-}"
    case "$val" in
        true|false) ;;
        *) echo "ERROR: Invalid debug value: $val (valid: true, false)" >&2; return 1 ;;
    esac
    _update_state '.debug = ($v == "true")' --arg v "$val"
}
