#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Observation IDs and issue mappings

[ -n "${_WFM_TRACKING_LOADED:-}" ] && return 0
_WFM_TRACKING_LOADED=1

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/state-io.sh"

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

clear_issue_mapping() {
    local obs_id="$1"
    if [ -z "$obs_id" ]; then return 1; fi
    if [ ! -f "$STATE_FILE" ]; then return 0; fi
    _update_state 'if .issue_mappings then .issue_mappings |= del(.[$id]) else . end' \
        --arg id "$obs_id"
}
