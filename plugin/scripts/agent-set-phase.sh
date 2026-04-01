#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# AGENT PHASE TRANSITION — called only via Bash tool by Claude in auto autonomy mode.
# Enforces forward-only transitions and milestone gate checks.
# User transitions use user-set-phase.sh (!backtick only) — NOT this function.
# There is no bypass: no user-override path here. Agent path only.

[ -n "${_WFM_AGENT_SET_PHASE_LOADED:-}" ] && return 0
_WFM_AGENT_SET_PHASE_LOADED=1

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/infrastructure/gate-checks.sh"
source "$SCRIPT_DIR/l1/phase-coaching.sh"

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
    local current
    current=$(get_phase)
    if ! _check_phase_gates "$current" "$new_phase"; then
        return 1
    fi

    # Read existing state to preserve fields across transitions.
    local preserved_skill="" preserved_decision="" preserved_autonomy=""
    local preserved_obs_id="" preserved_tracked=""
    local preserved_issue_mappings="null"
    local preserved_spec=""
    local preserved_tests_passed=""
    local preserved_debug=""
    _read_preserved_state

    # Clear active skill on phase transition
    preserved_skill=""

    # Build tracked observations as JSON array
    local tracked_json="[]"
    if [ -n "$preserved_tracked" ]; then
        tracked_json=$(jq -n --arg csv "$preserved_tracked" '$csv | split(",") | map(select(. != "") | (tonumber? // empty))')
    fi

    # STATE SCHEMA CONTRACT: This template is duplicated in user-set-phase.sh.
    # The duplication is deliberate — agent and user paths must not share transition code.
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

    echo "Phase advanced to ${new_phase}. Re-evaluate."

    # Emit L1 coaching immediately at transition — not deferred to next tool call.
    PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
    _emit_phase_coaching "$new_phase" "$preserved_autonomy"
}
