#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Claude Code Status Line — minimal single-line with worktree support
# Input: JSON session data via stdin

DATA=$(cat)

# Parse fields (single jq call, tab-separated)
IFS=$'\t' read -r MODEL USED_PCT USED_TOKENS TOTAL_TOKENS CWD WORKTREE_NAME WORKTREE_BRANCH < <(
  echo "$DATA" | jq -r '[
    (.model.display_name // "?"),
    ((.context_window.used_percentage // 0) | floor | tostring),
    (((.context_window.current_usage.input_tokens // 0) + (.context_window.current_usage.cache_creation_input_tokens // 0) + (.context_window.current_usage.cache_read_input_tokens // 0)) | tostring),
    ((.context_window.context_window_size // 0) | tostring),
    (.cwd // ""),
    (.worktree.name // ""),
    (.worktree.branch // "")
  ] | @tsv'
)

# Colors
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
BLUE='\033[34m'
CYAN='\033[36m'
MAGENTA='\033[35m'

# Context bar color: blue base, yellow >50%, red >80%
if [ "$USED_PCT" -lt 50 ]; then
  BAR_COLOR="$BLUE"
elif [ "$USED_PCT" -lt 80 ]; then
  BAR_COLOR="$YELLOW"
else
  BAR_COLOR="$RED"
fi

# Format token counts as "Xk/Yk"
if [ "$TOTAL_TOKENS" -gt 0 ]; then
  USED_K="$((USED_TOKENS / 1000))k"
  TOTAL_K="$((TOTAL_TOKENS / 1000))k"
  TOKEN_INFO=" (${USED_K}/${TOTAL_K})"
else
  TOKEN_INFO=""
fi

# Build 10-char progress bar
FILLED=$((USED_PCT / 10))
EMPTY=$((10 - FILLED))
BAR=""
for ((i = 0; i < FILLED; i++)); do BAR+="▓"; done
for ((i = 0; i < EMPTY; i++)); do BAR+="░"; done

# Shorten home directory in path
SHORT_CWD="${CWD/#$HOME/~}"
# Show only last 2 path components if long
if [ "${#SHORT_CWD}" -gt 30 ]; then
  SHORT_CWD="…/$(echo "$SHORT_CWD" | rev | cut -d/ -f1-2 | rev)"
fi

# Git branch (from worktree or local git)
if [ -n "$WORKTREE_BRANCH" ]; then
  BRANCH="$WORKTREE_BRANCH"
elif [ -d "$CWD/.git" ] || git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git -C "$CWD" symbolic-ref --short HEAD 2>/dev/null || git -C "$CWD" rev-parse --short HEAD 2>/dev/null)
else
  BRANCH=""
fi

# Assemble output
OUTPUT=""

# Model
OUTPUT+="${BOLD}${MODEL}${RESET}"

# Separator
OUTPUT+="  ${DIM}│${RESET}  "

# Context bar
OUTPUT+="${BAR_COLOR}${BAR}${RESET} ${USED_PCT}%${TOKEN_INFO}"

# Branch
if [ -n "$BRANCH" ]; then
  OUTPUT+="  ${DIM}│${RESET}  ${CYAN} ${BRANCH}${RESET}"
fi

# Worktree indicator
if [ -n "$WORKTREE_NAME" ]; then
  OUTPUT+=" ${MAGENTA}⊟ ${WORKTREE_NAME}${RESET}"
fi

# Directory
OUTPUT+="  ${DIM}│${RESET}  ${DIM}${SHORT_CWD}${RESET}"

# --- Component detection (version from plugin cache) ---

# Shared state file used by all three components
WM_STATE_FILE="${CWD}/.claude/state/workflow.json"

# _plugin_version: read version from the latest cached plugin.json
# Falls back to directory name if plugin.json is missing, then "?" as last resort
_plugin_version() {
  local plugin_dir="$1"
  local latest_dir
  latest_dir=$(ls -1 "$plugin_dir" 2>/dev/null | sort -V | tail -1)
  [ -z "$latest_dir" ] && return 1
  local pjson="$plugin_dir/$latest_dir/.claude-plugin/plugin.json"
  if [ -f "$pjson" ]; then
    jq -r '.version // "?"' "$pjson" 2>/dev/null
  else
    echo "$latest_dir"
  fi
}

# Workflow Manager: prefer source plugin.json (avoids stale cache), fall back to cache
WM_PLUGIN_DIR="$HOME/.claude/plugins/cache/azevedo-home-lab/workflow-manager"
WM_SOURCE_JSON="${CWD}/plugin/.claude-plugin/plugin.json"
if [ -f "$WM_SOURCE_JSON" ] || [ -d "$WM_PLUGIN_DIR" ]; then
  if [ -f "$WM_SOURCE_JSON" ]; then
    WM_VERSION=$(jq -r '.version // "?"' "$WM_SOURCE_JSON" 2>/dev/null)
  else
    WM_VERSION=$(_plugin_version "$WM_PLUGIN_DIR")
  fi
  WM_VERSION="${WM_VERSION:-?}"
  OUTPUT+="  ${DIM}│${RESET}  ${GREEN}Workflow Manager ${WM_VERSION} ✓${RESET}"
  # Show phase if state file exists
  if [ -f "$WM_STATE_FILE" ]; then
    WM_PHASE=$(grep -o '"phase"[[:space:]]*:[[:space:]]*"[^"]*"' "$WM_STATE_FILE" | grep -o '"[^"]*"$' | tr -d '"')
    WM_AUTONOMY=$(grep -o '"autonomy_level"[[:space:]]*:[[:space:]]*[0-9]*' "$WM_STATE_FILE" | grep -o '[0-9]*$')
    # Autonomy symbol (only when phase is not OFF and level is set)
    AUTONOMY_SYM=""
    if [ "$WM_PHASE" != "off" ] && [ -n "$WM_AUTONOMY" ]; then
      case "$WM_AUTONOMY" in
        1) AUTONOMY_SYM="▶ " ;;
        2) AUTONOMY_SYM="▶▶ " ;;
        3) AUTONOMY_SYM="▶▶▶ " ;;
      esac
    fi
    if [ "$WM_PHASE" = "off" ]; then
      OUTPUT+=" ${DIM}[OFF]${RESET}"
    elif [ "$WM_PHASE" = "define" ]; then
      OUTPUT+=" ${BLUE}${AUTONOMY_SYM}[DEFINE]${RESET}"
    elif [ "$WM_PHASE" = "discuss" ]; then
      OUTPUT+=" ${YELLOW}${AUTONOMY_SYM}[DISCUSS]${RESET}"
    elif [ "$WM_PHASE" = "implement" ]; then
      OUTPUT+=" ${GREEN}${AUTONOMY_SYM}[IMPLEMENT]${RESET}"
    elif [ "$WM_PHASE" = "review" ]; then
      OUTPUT+=" ${CYAN}${AUTONOMY_SYM}[REVIEW]${RESET}"
    elif [ "$WM_PHASE" = "complete" ]; then
      OUTPUT+=" ${MAGENTA}${AUTONOMY_SYM}[COMPLETE]${RESET}"
    fi
  fi
else
  OUTPUT+="  ${DIM}│${RESET}  ${DIM}Workflow Manager ✗${RESET}"
fi

# Superpowers: version from cache, active skill from project state
SP_PLUGIN_DIR="$HOME/.claude/plugins/cache/superpowers-marketplace/superpowers"
if [ -d "$SP_PLUGIN_DIR" ]; then
  SP_VERSION=$(_plugin_version "$SP_PLUGIN_DIR")
  SP_VERSION="${SP_VERSION:-?}"
  OUTPUT+="  ${DIM}│${RESET}  ${GREEN}Superpowers ${SP_VERSION} ✓${RESET}"
  # Read active skill from workflow.json (same file as phase)
  if [ -f "$WM_STATE_FILE" ]; then
    ACTIVE_SKILL=$(grep -o '"active_skill"[[:space:]]*:[[:space:]]*"[^"]*"' "$WM_STATE_FILE" | grep -o '"[^"]*"$' | tr -d '"')
    if [ -n "$ACTIVE_SKILL" ]; then
      OUTPUT+=" ${CYAN}[${ACTIVE_SKILL}]${RESET}"
    fi
  fi
else
  OUTPUT+="  ${DIM}│${RESET}  ${DIM}Superpowers ✗${RESET}"
fi

# Claude-Mem: version from cache, observation ID from project state
CM_PLUGIN_DIR="$HOME/.claude/plugins/cache/thedotmack/claude-mem"
if [ -d "$CM_PLUGIN_DIR" ]; then
  CM_VERSION=$(_plugin_version "$CM_PLUGIN_DIR")
  CM_VERSION="${CM_VERSION:-?}"
  CM_SUFFIX=""
  if [ -f "$WM_STATE_FILE" ]; then
    CM_OBS_ID=$(grep -o '"last_observation_id"[[:space:]]*:[[:space:]]*[0-9]*' "$WM_STATE_FILE" | grep -o '[0-9]*$')
    [ -n "$CM_OBS_ID" ] && CM_SUFFIX=" ${CYAN}[#${CM_OBS_ID}]${RESET}"
    # Tracked observations (tech debt, open issues, next steps)
    CM_TRACKED=$(jq -r '.tracked_observations // [] | map("#" + tostring) | join(",")' "$WM_STATE_FILE" 2>/dev/null)
    [ -n "$CM_TRACKED" ] && CM_SUFFIX+=" ${DIM}Open:[${CM_TRACKED}]${RESET}"
  fi
  OUTPUT+="  ${DIM}│${RESET}  ${GREEN}Claude-Mem ${CM_VERSION} ✓${RESET}${CM_SUFFIX}"
else
  OUTPUT+="  ${DIM}│${RESET}  ${DIM}Claude-Mem ✗${RESET}"
fi

printf '%b' "$OUTPUT"
