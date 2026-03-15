#!/bin/bash
# Claude Code Status Line — minimal single-line with worktree support
# Input: JSON session data via stdin

DATA=$(cat)

# Parse fields
MODEL=$(echo "$DATA" | jq -r '.model.display_name // "?"')
USED_PCT=$(echo "$DATA" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
CWD=$(echo "$DATA" | jq -r '.cwd // ""')
WORKTREE_NAME=$(echo "$DATA" | jq -r '.worktree.name // empty' 2>/dev/null)
WORKTREE_BRANCH=$(echo "$DATA" | jq -r '.worktree.branch // empty' 2>/dev/null)

# Colors
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
MAGENTA='\033[35m'

# Context bar color based on usage
if [ "$USED_PCT" -lt 50 ]; then
  BAR_COLOR="$GREEN"
elif [ "$USED_PCT" -lt 80 ]; then
  BAR_COLOR="$YELLOW"
else
  BAR_COLOR="$RED"
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
OUTPUT+="${BAR_COLOR}${BAR}${RESET} ${USED_PCT}%"

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

# Workflow Manager detection
WM_STATE_FILE="${CWD}/.claude/state/phase.json"
WM_GATE_FILE="${CWD}/.claude/hooks/workflow-gate.sh"
if [ -f "$WM_GATE_FILE" ]; then
  OUTPUT+="  ${DIM}│${RESET}  ${GREEN}Workflow Manager ✓${RESET}"
  # Show phase if state file exists
  if [ -f "$WM_STATE_FILE" ]; then
    WM_PHASE=$(grep -o '"phase"[[:space:]]*:[[:space:]]*"[^"]*"' "$WM_STATE_FILE" | grep -o '"[^"]*"$' | tr -d '"')
    if [ "$WM_PHASE" = "discuss" ]; then
      OUTPUT+=" ${YELLOW}[DISCUSS]${RESET}"
    elif [ "$WM_PHASE" = "implement" ]; then
      OUTPUT+=" ${GREEN}[IMPLEMENT]${RESET}"
    fi
  fi
else
  OUTPUT+="  ${DIM}│${RESET}  ${DIM}Workflow Manager ✗${RESET}"
fi

# Claude-Mem detection
if echo "$DATA" | jq -e '.mcp_servers[]? | select(. == "claude-mem" or test("claude.mem"; "i"))' >/dev/null 2>&1; then
  OUTPUT+="  ${DIM}│${RESET}  ${GREEN}Claude-Mem ✓${RESET}"
elif command -v claude-mem >/dev/null 2>&1 || [ -d "$HOME/.claude/plugins/cache/thedotmack" ]; then
  OUTPUT+="  ${DIM}│${RESET}  ${GREEN}Claude-Mem ✓${RESET}"
else
  OUTPUT+="  ${DIM}│${RESET}  ${DIM}Claude-Mem ✗${RESET}"
fi

printf '%b' "$OUTPUT"
