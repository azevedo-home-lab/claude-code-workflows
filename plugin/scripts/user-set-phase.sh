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
# bash-write-guard.sh blocks any Bash tool call containing user-set-phase.sh.
#
# Usage: user-set-phase.sh <phase>
# Phases: off define discuss implement review complete

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workflow-state.sh"

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
    preserved_debug="false"
fi

# Initialize autonomy to "ask" when starting a fresh cycle from off
if [ "$current_phase" = "off" ] && [ "$new_phase" != "off" ] && [ -z "$preserved_autonomy" ]; then
    preserved_autonomy="ask"
fi

tracked_json="[]"
if [ -n "$preserved_tracked" ]; then
    tracked_json=$(jq -n --arg csv "$preserved_tracked" '$csv | split(",") | map(select(. != "") | (tonumber? // empty))')
fi

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

echo "Phase set to ${new_phase}."
