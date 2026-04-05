#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Shared hook bootstrap — sourced by PreToolUse hooks.
# Sets up: SCRIPT_DIR, PROJECT_ROOT, PHASE, _log(), _show()
# Returns early (return 1) if no enforcement needed (no state file or off phase).
# No include guard — must run fresh each invocation.
#
# Usage: source hook-preamble.sh "caller-name" || exit 0

_PREAMBLE_CALLER="${1:-unknown}"

# Resolve SCRIPT_DIR from dev marker or plugin cache (not hardcoded project path).
# See resolve-script-dir.sh for the resolution order and rationale.
# Try CLAUDE_PLUGIN_ROOT first (works from both plugin/ and .claude/hooks/ contexts),
# fall back to BASH_SOURCE (works from plugin/scripts/infrastructure/ context).
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/scripts/infrastructure/resolve-script-dir.sh" ]; then
    source "$CLAUDE_PLUGIN_ROOT/scripts/infrastructure/resolve-script-dir.sh"
else
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve-script-dir.sh"
fi

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

source "$SCRIPT_DIR/infrastructure/state-io.sh"
source "$SCRIPT_DIR/infrastructure/phase.sh"
source "$SCRIPT_DIR/infrastructure/settings.sh"

# Stub _log before debug-log.sh is sourced
_log() { :; }

# No state file = no enforcement
if [ ! -f "$STATE_FILE" ]; then
    return 1
fi

PHASE=$(get_phase)

# OFF phase: no enforcement
if [ "$PHASE" = "off" ]; then
    return 1
fi

# Debug mode (read after OFF exit to avoid unnecessary jq call)
DEBUG_MODE=$(get_debug)
source "$SCRIPT_DIR/infrastructure/debug-log.sh" "$_PREAMBLE_CALLER"
_log "PHASE=$PHASE"
_log "PROJECT_ROOT=$PROJECT_ROOT"
