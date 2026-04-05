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
#   Restrictive (DEFINE/DISCUSS/ERROR): .claude/state/, docs/plans/, docs/specs/
#   Docs-allowed (COMPLETE):            .claude/state/, docs/ (all), *.md at project root

set -euo pipefail

# Exit silently when running as a project-deployed copy (missing infrastructure/).
# Claude Code materializes plugin hooks into .claude/hooks/ but without subdirectories,
# so the real work is done by the plugin-scoped copy (which has CLAUDE_PLUGIN_ROOT set).
_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -z "${CLAUDE_PLUGIN_ROOT:-}" ] && [ ! -d "$_self_dir/infrastructure" ] && exit 0

# --- Preamble: shared hook bootstrap (resolves SCRIPT_DIR, PROJECT_ROOT, PHASE) ---
# Bootstrap resolver: CLAUDE_PLUGIN_ROOT (always set by Claude Code hook runner),
# then BASH_SOURCE fallback for manual invocation.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/scripts/infrastructure/resolve-script-dir.sh" ]; then
    source "$CLAUDE_PLUGIN_ROOT/scripts/infrastructure/resolve-script-dir.sh"
else
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/infrastructure/resolve-script-dir.sh"
fi
source "$SCRIPT_DIR/infrastructure/hook-preamble.sh" "workflow-gate" || exit 0

source "$SCRIPT_DIR/infrastructure/deny-messages.sh"
source "$SCRIPT_DIR/infrastructure/patterns.sh"

# --- Parse file path ---
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || FILE_PATH=""
_log "FILE_PATH=$FILE_PATH"

# --- Path traversal check ---
_canonicalize() {
    realpath "$1" 2>/dev/null || \
    python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1" 2>/dev/null || \
    echo ""
}

if [ -n "$FILE_PATH" ]; then
    CANONICAL_PATH=$(_canonicalize "$FILE_PATH")
    CANONICAL_ROOT=$(_canonicalize "$PROJECT_ROOT")
    _log "CANONICAL_PATH=$CANONICAL_PATH CANONICAL_ROOT=$CANONICAL_ROOT"

    if [ -n "$CANONICAL_PATH" ] && [ -n "$CANONICAL_ROOT" ]; then
        if [ "${CANONICAL_PATH#"$CANONICAL_ROOT"/}" = "$CANONICAL_PATH" ]; then
            FILE_PATH=""
            _log "FILE_PATH emptied: traversal check failed"
        fi
    else
        if echo "$FILE_PATH" | grep -qE '\.\.'; then
            FILE_PATH=""
            _log "FILE_PATH emptied: dotdot check (no realpath or python3)"
        fi
    fi
fi

# Normalize: strip project root prefix
NORMALIZED_PATH="$FILE_PATH"
[ -n "$PROJECT_ROOT" ] && NORMALIZED_PATH="${FILE_PATH#"$PROJECT_ROOT"/}"
_log "NORMALIZED_PATH=$NORMALIZED_PATH"

# --- Guard-system self-protection (ALL phases) ---
if [ -n "$NORMALIZED_PATH" ] && echo "$NORMALIZED_PATH" | grep -qE "$GUARD_SYSTEM_PATTERN"; then
    _log "DENY: guard-system match on '$NORMALIZED_PATH'"
    emit_deny "$(_phase_deny_message "$PHASE" "guard-system")"
    exit 0
fi

# --- implement/review: allow everything ---
case "$PHASE" in
    implement|review) _log "ALLOW: phase=$PHASE"; exit 0 ;;
esac

# --- Phase-gate: whitelist check ---
case "$PHASE" in
    define|discuss|error) WHITELIST="$RESTRICTED_WRITE_WHITELIST" ;;
    complete)             WHITELIST="$COMPLETE_WRITE_WHITELIST" ;;
    *)                    exit 0 ;;
esac

_log "WHITELIST=$WHITELIST"
if [ -n "$NORMALIZED_PATH" ] && echo "$NORMALIZED_PATH" | grep -qE "$WHITELIST"; then
    _log "ALLOW: whitelist match on '$NORMALIZED_PATH'"
    exit 0
fi

# --- Deny ---
_log "DENY: phase=$PHASE path=$NORMALIZED_PATH"
emit_deny "$(_phase_deny_message "$PHASE" "write")"
exit 0
