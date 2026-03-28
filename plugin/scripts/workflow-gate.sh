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
#   Restrictive (DEFINE/DISCUSS): .claude/state/, docs/superpowers/specs/, docs/superpowers/plans/, docs/plans/
#   Docs-allowed (COMPLETE):      .claude/state/, docs/ (all), *.md at project root

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workflow-state.sh"

# No state file = no enforcement (first run, hooks not yet activated)
if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

PHASE=$(get_phase)

# OFF phase: no enforcement
case "$PHASE" in
    off) exit 0 ;;
esac

# Debug mode (read after OFF exit to avoid unnecessary jq call)
DEBUG_MODE=$(get_debug)

# Parse file path early — needed by guard-system check before phase-based early-exit.
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || FILE_PATH=""

# Reject path traversal attempts
if [ -n "$FILE_PATH" ] && echo "$FILE_PATH" | grep -qE '\.\.'; then
    FILE_PATH=""  # Force deny — traversal paths are never whitelisted
fi

# Normalize path: strip project root prefix for consistent matching
# (Claude Code may pass absolute paths like /Users/.../project/README.md)
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
NORMALIZED_PATH="$FILE_PATH"
if [ -n "$PROJECT_ROOT" ]; then
    NORMALIZED_PATH="${FILE_PATH#"$PROJECT_ROOT"/}"
fi

# ---------------------------------------------------------------------------
# Guard-system self-protection: block Write/Edit to enforcement files in ALL active phases.
# Fires before implement|review early-exit — those phases do not bypass this.
# Claude cannot modify the files that enforce the workflow on Claude.
# This includes: hook scripts, workflow scripts, and command files.
# The user can always use !backtick to make legitimate changes to these files.
# ---------------------------------------------------------------------------
GUARD_SYSTEM_PATTERN='(\.claude/hooks/|plugin/scripts/|plugin/commands/)'
if [ -n "$NORMALIZED_PATH" ] && echo "$NORMALIZED_PATH" | grep -qE "$GUARD_SYSTEM_PATTERN"; then
    if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] PreToolUse DENY: Write/Edit on enforcement file $NORMALIZED_PATH" >&2; fi
    emit_deny "BLOCKED: Edits to enforcement files (.claude/hooks/, plugin/scripts/, plugin/commands/) are not allowed in any phase. These files define the workflow rules. Use !backtick if you need to make legitimate changes."
    exit 0
fi

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
if [ -n "$NORMALIZED_PATH" ]; then
    if echo "$NORMALIZED_PATH" | grep -qE "$WHITELIST"; then
        if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] PreToolUse ALLOW: Write/Edit on $NORMALIZED_PATH — path whitelisted" >&2; fi
        exit 0
    fi
fi

# Phase-aware deny message
case "$PHASE" in
    define)   REASON="BLOCKED: Phase is DEFINE. Code changes are not allowed until you define the problem and outcomes." ;;
    discuss)  REASON="BLOCKED: Phase is DISCUSS. Code changes are not allowed until a plan is discussed and approved. Use /implement to proceed to implementation." ;;
    complete) REASON="BLOCKED: Phase is COMPLETE. Code changes are not allowed during completion. Only documentation updates are permitted." ;;
    error)    REASON="BLOCKED: Workflow state is corrupted. All writes blocked for safety. Run /off to reset." ;;
    *)        REASON="BLOCKED: Unexpected phase ($PHASE)." ;;
esac

if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] PreToolUse DENY: Write/Edit on $NORMALIZED_PATH — $REASON" >&2; fi
emit_deny "$REASON"
exit 0
