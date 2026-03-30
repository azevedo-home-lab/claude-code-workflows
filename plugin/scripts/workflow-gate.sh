#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Workflow Manager: blocks Write/Edit/MultiEdit/NotebookEdit in DEFINE, DISCUSS, and COMPLETE phases
# Matcher: Write|Edit|MultiEdit|NotebookEdit
#
# Whitelist tiers:
#   Restrictive (DEFINE/DISCUSS): .claude/state/, docs/plans/
#   Docs-allowed (COMPLETE):      .claude/state/, docs/ (all), *.md at project root

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workflow-state.sh"



# No state file = no enforcement (first run, hooks not yet activated)
if [ ! -f "$STATE_FILE" ]; then
    _log "EXIT: no state file"
    exit 0
fi

PHASE=$(get_phase)
_log "PHASE=$PHASE"

# OFF phase: no enforcement
case "$PHASE" in
    off) _log "EXIT: off phase"; exit 0 ;;
esac

# Debug mode (read after OFF exit to avoid unnecessary jq call)
DEBUG_MODE=$(get_debug)
source "$SCRIPT_DIR/debug-log.sh" "workflow-gate"


# Parse file path early — needed by guard-system check before phase-based early-exit.
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || FILE_PATH=""
_log "FILE_PATH=$FILE_PATH"

# Determine project root early — needed for path traversal check
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
_log "PROJECT_ROOT=$PROJECT_ROOT"

# Reject path traversal attempts — canonicalize to catch encoded/symlinked traversal
# Uses python3 (already a dependency) because macOS realpath lacks -m (no-exist) flag
if [ -n "$FILE_PATH" ]; then
    if ! command -v python3 &>/dev/null; then
        # Fail closed — without python3, fall back to literal .. check
        if echo "$FILE_PATH" | grep -qE '\.\.'; then
            FILE_PATH=""
            _log "FILE_PATH emptied: dotdot check (no python3)"
        fi
    else
        CANONICAL_PATH=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$FILE_PATH" 2>/dev/null || echo "")
        CANONICAL_ROOT=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$PROJECT_ROOT" 2>/dev/null || echo "")
        _log "CANONICAL_PATH=$CANONICAL_PATH"
        _log "CANONICAL_ROOT=$CANONICAL_ROOT"
        if [ -z "$CANONICAL_PATH" ] || [ -z "$CANONICAL_ROOT" ] || [ "${CANONICAL_PATH#"$CANONICAL_ROOT"/}" = "$CANONICAL_PATH" ]; then
            _log "FILE_PATH emptied: traversal check failed (path outside root or empty canonical)"
            _log "  prefix_strip_test: '${CANONICAL_PATH#"$CANONICAL_ROOT"/}' == '$CANONICAL_PATH' => $([ "${CANONICAL_PATH#"$CANONICAL_ROOT"/}" = "$CANONICAL_PATH" ] && echo true || echo false)"
            FILE_PATH=""  # Force deny — path resolves outside project root
        else
            _log "Traversal check passed"
        fi
    fi
fi

# Normalize path: strip project root prefix for consistent matching
# (Claude Code may pass absolute paths like /Users/.../project/README.md)
NORMALIZED_PATH="$FILE_PATH"
if [ -n "$PROJECT_ROOT" ]; then
    NORMALIZED_PATH="${FILE_PATH#"$PROJECT_ROOT"/}"
fi
_log "NORMALIZED_PATH=$NORMALIZED_PATH"

# ---------------------------------------------------------------------------
# Guard-system self-protection: block Write/Edit to enforcement files in ALL active phases.
# Fires before implement|review early-exit — those phases do not bypass this.
# Claude cannot modify the files that enforce the workflow on Claude.
# This includes: hook scripts, workflow scripts, and command files.
# The user can always use !backtick to make legitimate changes to these files.
# ---------------------------------------------------------------------------
GUARD_SYSTEM_PATTERN='(\.claude/hooks/|(^|[^a-z-])plugin/scripts/|(^|[^a-z-])plugin/commands/)'
if [ -n "$NORMALIZED_PATH" ] && echo "$NORMALIZED_PATH" | grep -qE "$GUARD_SYSTEM_PATTERN"; then
    _log "DENY: guard-system match on '$NORMALIZED_PATH'"
    if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] PreToolUse DENY: Write/Edit on enforcement file $NORMALIZED_PATH" >&2; fi
    emit_deny "BLOCKED: Edits to enforcement files (.claude/hooks/, plugin/scripts/, plugin/commands/) are not allowed in any phase. These files define the workflow rules. Use !backtick if you need to make legitimate changes."
    exit 0
fi
_log "Guard-system check passed"

# Allow everything in implement and review phases
case "$PHASE" in
    implement|review) if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] PreToolUse ALLOW: Write/Edit — phase=$PHASE allows all writes" >&2; fi; exit 0 ;;
esac

# Select whitelist based on phase
case "$PHASE" in
    define|discuss|error) WHITELIST="$RESTRICTED_WRITE_WHITELIST" ;;
    complete)             WHITELIST="$COMPLETE_WRITE_WHITELIST" ;;  # .claude/commands/ excluded — see workflow-state.sh
    *)                    exit 0 ;;
esac

# Allow writes to whitelisted paths
_log "WHITELIST=$WHITELIST"
if [ -n "$NORMALIZED_PATH" ]; then
    if echo "$NORMALIZED_PATH" | grep -qE "$WHITELIST"; then
        _log "ALLOW: whitelist match on '$NORMALIZED_PATH'"
        if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] PreToolUse ALLOW: Write/Edit on $NORMALIZED_PATH — path whitelisted" >&2; fi
        exit 0
    fi
    _log "Whitelist did NOT match '$NORMALIZED_PATH'"
else
    _log "NORMALIZED_PATH is empty — skipping whitelist check"
fi

# Phase-aware deny message
case "$PHASE" in
    define)   REASON="BLOCKED: Phase is DEFINE. Code changes are not allowed until you define the problem and outcomes." ;;
    discuss)  REASON="BLOCKED: Phase is DISCUSS. Code changes are not allowed until the design phase is complete. Use /implement to proceed to implementation." ;;
    complete) REASON="BLOCKED: Phase is COMPLETE. Code changes are not allowed during completion. Only documentation updates are permitted." ;;
    error)    REASON="BLOCKED: Workflow state is corrupted. All writes blocked for safety. Run /off to reset." ;;
    *)        REASON="BLOCKED: Unexpected phase ($PHASE)." ;;
esac

_log "DENY: $REASON"
if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] PreToolUse DENY: Write/Edit on $NORMALIZED_PATH — $REASON" >&2; fi
emit_deny "$REASON"
exit 0
