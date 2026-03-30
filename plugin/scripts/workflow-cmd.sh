#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Shell-independent wrapper for workflow-state.sh functions.
# Always runs under bash (via shebang) regardless of the user's shell.
#
# Usage from command templates:
#   scripts/workflow-cmd.sh agent_set_phase "implement"   ← agent auto-transition only
#   scripts/workflow-cmd.sh set_completion_field "plan_validated" "true"
#   scripts/workflow-cmd.sh get_phase
#
# User phase transitions use user-set-phase.sh (!backtick only) — NOT this file.
#
# Supports chaining multiple commands separated by &&:
#   scripts/workflow-cmd.sh agent_set_phase "implement" && scripts/workflow-cmd.sh set_active_skill ""

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workflow-state.sh"

# ---------------------------------------------------------------------------
# dispatch_agent: load and return an agent prompt from plugin/agents/
# ---------------------------------------------------------------------------
dispatch_agent() {
    local agent_name="$1"
    local agent_dir="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/plugin/agents"
    local agent_file="$agent_dir/${agent_name}.md"
    if [ ! -f "$agent_file" ]; then
        echo "ERROR: Agent file not found: $agent_file" >&2
        return 1
    fi
    local char_count
    char_count=$(wc -c < "$agent_file" | tr -d ' ')
    # Debug output to stderr
    local debug_level
    debug_level=$(get_debug)
    if [ "$debug_level" = "show" ]; then
        echo "[WFM agent] Loaded plugin/agents/${agent_name}.md (${char_count} chars)" >&2
        echo "[WFM agent] Dispatching as: general-purpose" >&2
    fi
    if [ "$debug_level" = "log" ] || [ "$debug_level" = "show" ]; then
        echo "[WFM agent] Loaded plugin/agents/${agent_name}.md (${char_count} chars)" >> "/tmp/wfm-workflow-cmd-debug.log"
    fi
    # Return file content to stdout for use in agent prompt
    cat "$agent_file"
}

# ---------------------------------------------------------------------------
# resolve_skill: look up a skill in the skill registry
# ---------------------------------------------------------------------------
resolve_skill() {
    local operation="$1"
    local registry="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/plugin/config/skill-registry.json"
    if [ ! -f "$registry" ]; then
        echo "ERROR: Skill registry not found: $registry" >&2
        return 1
    fi
    local resolved
    resolved=$(jq -r --arg op "$operation" '.operations[$op].process_skill // empty' "$registry" 2>/dev/null)
    if [ -z "$resolved" ]; then
        resolved=$(jq -r --arg op "$operation" '.operations[$op].reference_skills[0] // empty' "$registry" 2>/dev/null)
    fi
    local debug_level
    debug_level=$(get_debug)
    if [ "$debug_level" = "show" ]; then
        echo "[WFM skill] Lookup: \"$operation\" in skill-registry.json" >&2
        if [ -n "$resolved" ]; then
            echo "[WFM skill] Resolved: $resolved" >&2
        else
            echo "[WFM skill] NOT FOUND: no skill mapped for \"$operation\"" >&2
        fi
    fi
    if [ "$debug_level" = "log" ] || [ "$debug_level" = "show" ]; then
        echo "[WFM skill] Lookup: \"$operation\" → ${resolved:-NOT FOUND}" >> "/tmp/wfm-workflow-cmd-debug.log"
    fi
    # Return resolved skill name to stdout
    echo "$resolved"
}

# Execute the allowed function passed as arguments
case "$1" in
    get_phase|agent_set_phase|get_autonomy_level|set_autonomy_level|\
    get_active_skill|set_active_skill|\
    get_plan_path|set_plan_path|get_spec_path|set_spec_path|\
    get_message_shown|set_message_shown|\
    check_soft_gate|\
    reset_review_status|get_review_field|set_review_field|\
    reset_completion_status|get_completion_field|set_completion_field|\
    reset_implement_status|get_implement_field|set_implement_field|\
    reset_discuss_status|get_discuss_field|set_discuss_field|\
    increment_coaching_counter|reset_coaching_counter|\
    add_coaching_fired|has_coaching_fired|check_coaching_refresh|\
    set_pending_verify|get_pending_verify|\
    get_debug|set_debug|\
    set_tests_passed_at|get_tests_passed_at|\
    get_last_observation_id|set_last_observation_id|\
    get_tracked_observations|set_tracked_observations|\
    add_tracked_observation|remove_tracked_observation|\
    set_issue_mapping|get_issue_url|get_issue_mappings|clear_issue_mapping|\
    emit_deny|\
    dispatch_agent|resolve_skill)
        # Log command invocation in show/log mode
        _CMD_DEBUG_LEVEL=$(get_debug 2>/dev/null) || _CMD_DEBUG_LEVEL="off"
        if [ "$_CMD_DEBUG_LEVEL" = "show" ]; then
            echo "[WFM cmd] $*" >&2
        fi
        if [ "$_CMD_DEBUG_LEVEL" = "log" ] || [ "$_CMD_DEBUG_LEVEL" = "show" ]; then
            echo "[$(date +%H:%M:%S)] [$$] cmd: $*" >> "/tmp/wfm-workflow-cmd-debug.log"
        fi
        "$@"
        ;;
    *)
        echo "ERROR: Unknown command: $1" >&2
        echo "" >&2
        echo "Phase transitions:" >&2
        echo "  User (slash commands): /define /discuss /implement /review /complete /off" >&2
        echo "    These trigger user-set-phase.sh via !backtick. Never call it from Bash tool." >&2
        echo "  Agent (auto mode only): agent_set_phase <phase>" >&2
        echo "    Forward-only. Requires autonomy=auto. Cannot set phase to off." >&2
        echo "" >&2
        echo "Common commands: get_phase, agent_set_phase, get_plan_path, set_plan_path," >&2
        echo "  set_discuss_field, set_implement_field, set_review_field, set_completion_field," >&2
        echo "  set_active_skill, check_soft_gate, get_debug, set_debug" >&2
        echo "See the case statement in workflow-cmd.sh for the full allowlist." >&2
        exit 1
        ;;
esac
