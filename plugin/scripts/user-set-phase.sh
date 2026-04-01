#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# USER PHASE TRANSITION — called only from !backtick in command files.
# Writes phase state directly. No authorization checks. No gate checks.
# The user's intent is expressed by the fact they typed a slash command.
#
# SECURITY: This script must NOT be callable via Bash tool.
# pre-tool-bash-guard.sh blocks any Bash tool call containing user-set-phase.sh.
#
# Usage: user-set-phase.sh <phase>
# Phases: off define discuss implement review complete

set -euo pipefail

SCRIPT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/plugin/scripts"
source "$SCRIPT_DIR/workflow-facade.sh"

new_phase="${1:-}"

case "$new_phase" in
    off|define|discuss|implement|review|complete) ;;
    *) echo "ERROR: Invalid phase: $new_phase (valid: off, define, discuss, implement, review, complete)" >&2; exit 1 ;;
esac

mkdir -p "$STATE_DIR"

# NOTE: No `local` here — this is top-level script scope, not a function.
# Plain variable assignments are used throughout.

preserved_skill=""
preserved_decision=""
preserved_autonomy=""
preserved_obs_id=""
preserved_tracked=""
preserved_issue_mappings="null"
preserved_tests_passed=""
preserved_spec=""
preserved_debug=""
current_phase="off"

if [ -f "$STATE_FILE" ]; then
    current_phase=$(get_phase)
    _read_preserved_state
fi

# Clearing off phase: reset cycle fields, keep last_observation_id for statusline
if [ "$new_phase" = "off" ]; then
    preserved_skill=""
    preserved_decision=""
    preserved_autonomy=""
    preserved_tests_passed=""
    preserved_debug="off"
else
    # Clear active skill on every phase transition — new phase starts fresh
    preserved_skill=""
fi

# Initialize autonomy to "ask" when starting a fresh cycle from off
if [ "$current_phase" = "off" ] && [ "$new_phase" != "off" ] && [ -z "$preserved_autonomy" ]; then
    preserved_autonomy="ask"
fi

# Debug logging for phase transitions (read preserved_debug BEFORE sourcing debug-log.sh)
DEBUG_MODE="$preserved_debug"
source "$SCRIPT_DIR/infrastructure/debug-log.sh" "user-set-phase"
_show "[WFM phase] User transition: $current_phase → $new_phase"

tracked_json="[]"
if [ -n "$preserved_tracked" ]; then
    tracked_json=$(jq -n --arg csv "$preserved_tracked" '$csv | split(",") | map(select(. != "") | (tonumber? // empty))')
fi

# STATE SCHEMA CONTRACT: This template is duplicated in phase-gates.sh (agent_set_phase).
# The duplication is deliberate — agent and user paths must not share transition code.
# If you modify the schema fields, update BOTH locations and run:
#   diff <(grep -oP '"[a-z_]+"' plugin/scripts/phase-gates.sh | sort) \
#        <(grep -oP '"[a-z_]+"' plugin/scripts/user-set-phase.sh | sort)
# to verify they match.
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

_show "[WFM phase] State rebuilt — preserved: plan_path=$preserved_decision, autonomy=$preserved_autonomy, debug=$preserved_debug"
_show "[WFM phase] Milestones reset: discuss={}, implement={}, review={}, completion={}"

echo "Phase set to ${new_phase}. Re-evaluate."
