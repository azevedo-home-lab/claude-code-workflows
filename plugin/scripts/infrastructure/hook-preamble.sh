#!/bin/bash
# Shared hook bootstrap — sourced by PreToolUse hooks.
# Sets up: SCRIPT_DIR, PROJECT_ROOT, PHASE, _log(), _show()
# Returns early (return 0) if no enforcement needed (no state file or off phase).
# No include guard — must run fresh each invocation.
#
# Usage: source hook-preamble.sh "caller-name" || exit 0

_PREAMBLE_CALLER="${1:-unknown}"

SCRIPT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/plugin/scripts"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

source "$SCRIPT_DIR/infrastructure/state-io.sh"
source "$SCRIPT_DIR/infrastructure/phase.sh"
source "$SCRIPT_DIR/infrastructure/settings.sh"

# Stub _log before debug-log.sh is sourced
_log() { :; }

# No state file = no enforcement
if [ ! -f "$STATE_FILE" ]; then
    return 0
fi

PHASE=$(get_phase)

# OFF phase: no enforcement
if [ "$PHASE" = "off" ]; then
    return 0
fi

# Debug mode (read after OFF exit to avoid unnecessary jq call)
DEBUG_MODE=$(get_debug)
source "$SCRIPT_DIR/infrastructure/debug-log.sh" "$_PREAMBLE_CALLER"
_log "PHASE=$PHASE"
_log "PROJECT_ROOT=$PROJECT_ROOT"
