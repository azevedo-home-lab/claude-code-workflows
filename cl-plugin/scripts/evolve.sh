#!/usr/bin/env bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows — CL Plugin.
# See LICENSE for details.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
STATE_DIR="$PROJECT_DIR/.claude/state"
STATE_FILE="$STATE_DIR/cl-state.json"
LOCK_FILE="$STATE_DIR/cl-state.lock"
CONFIG_FILE="$PLUGIN_ROOT/config/cl-config.json"

# --- State helpers ---

init_state() {
  mkdir -p "$STATE_DIR"
  if [ ! -f "$STATE_FILE" ] || ! jq empty "$STATE_FILE" 2>/dev/null; then
    jq -n '{
      version: "0.1.0",
      last_run: null,
      last_obs_id: 0,
      completion_count: 0,
      stats: {
        total_runs: 0,
        total_proposals_generated: 0,
        total_proposals_approved: 0,
        total_proposals_rejected: 0
      }
    }' > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
    echo "CL: State file initialized" >&2
  fi
}

read_state() {
  local field="$1"
  jq -r ".$field // empty" "$STATE_FILE"
}

update_state() {
  local updates="$1"
  jq "$updates" "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
}

# --- Lock management ---

acquire_lock() {
  # NOTE: No EXIT trap here — evolve.md calls --lock and --unlock as separate
  # bash invocations, so a trap would fire immediately when the subshell exits.
  # Stale locks are handled by age check only.
  if [ -f "$LOCK_FILE" ]; then
    local lock_age
    lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK_FILE" 2>/dev/null || stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 9999) ))
    if [ "$lock_age" -lt 600 ]; then
      echo "CL: Pipeline already running (lock is ${lock_age}s old). Exiting." >&2
      exit 0
    fi
    echo "CL: Stale lock found (${lock_age}s old). Removing." >&2
    rm -f "$LOCK_FILE"
  fi
  echo $$ > "$LOCK_FILE"
}

release_lock() {
  rm -f "$LOCK_FILE"
}

# --- Counter logic ---

increment_counter() {
  init_state
  local count
  count=$(read_state "completion_count")
  count=$((count + 1))
  update_state ".completion_count = $count"
  echo "$count"
}

get_threshold() {
  jq -r '.trigger.completions_per_run // 5' "$CONFIG_FILE"
}

check_threshold() {
  local count threshold
  count=$(read_state "completion_count")
  threshold=$(get_threshold)
  if [ "$count" -ge "$threshold" ]; then
    echo "ready"
  else
    echo "waiting"
  fi
}

reset_counter() {
  update_state '.completion_count = 0'
}

# --- CLI dispatch ---

case "${1:-}" in
  --trigger=complete)
    count=$(increment_counter)
    threshold=$(get_threshold)
    status=$(check_threshold)
    if [ "$status" = "ready" ]; then
      echo "CL_READY"
    else
      echo "CL_WAITING ($count/$threshold)"
    fi
    ;;
  --init)
    init_state
    ;;
  --read)
    read_state "${2:-version}"
    ;;
  --update)
    update_state "${2:-.}"
    ;;
  --lock)
    acquire_lock
    ;;
  --unlock)
    release_lock
    ;;
  --reset-counter)
    reset_counter
    ;;
  --check-threshold)
    check_threshold
    ;;
  *)
    echo "Usage: evolve.sh --trigger=complete | --init | --read <field> | --update <jq-expr> | --lock | --unlock | --reset-counter | --check-threshold" >&2
    exit 1
    ;;
esac
