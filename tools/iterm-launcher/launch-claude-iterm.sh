#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Launch Claude Code in iTerm2 with project-aware badge
#
# Usage:
#   launch-claude-iterm.sh [project-dir]
#
# If project-dir is omitted, uses current working directory.
# Sets iTerm badge to "Claude <project-name>" for visual identification.
#
# Prerequisites:
#   - iTerm2 installed
#   - Claude Code installed (~/.local/bin/claude)
#   - iTerm2 "Claude Code" profile (install with: ./install.sh)

set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"

# Escape single quotes for safe interpolation into AppleScript write text commands
SAFE_PROJECT_DIR="${PROJECT_DIR//\'/\'\\\'\'}"
SAFE_CLAUDE_BIN="${CLAUDE_BIN//\'/\'\\\'\'}"

# Verify prerequisites
if ! command -v osascript &>/dev/null; then
    echo "ERROR: osascript not found — this tool requires macOS." >&2
    exit 1
fi

if [ ! -x "$CLAUDE_BIN" ]; then
    echo "ERROR: Claude Code not found at $CLAUDE_BIN" >&2
    echo "Install: https://docs.anthropic.com/en/docs/claude-code/overview" >&2
    exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
    echo "ERROR: Project directory does not exist: $PROJECT_DIR" >&2
    exit 1
fi

# Launch iTerm2 with Claude Code profile, set badge, run claude
osascript \
    -e 'tell application "iTerm2"' \
    -e '  create window with profile "Claude Code"' \
    -e '  tell current session of current window' \
    -e "    write text \"cd '$SAFE_PROJECT_DIR'\"" \
    -e "    write text \"printf \\\"\\\\e]1337;SetBadgeFormat=%s\\\\a\\\" \\\"$(echo -n "Claude $PROJECT_NAME" | base64)\\\"\"" \
    -e "    write text \"$SAFE_CLAUDE_BIN\"" \
    -e '  end tell' \
    -e 'end tell'