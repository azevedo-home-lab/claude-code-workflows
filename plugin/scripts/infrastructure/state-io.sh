#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# State I/O primitives — variable declarations, atomic writes, whitelists, deny helper

[ -n "${_WFM_STATE_IO_LOADED:-}" ] && return 0
_WFM_STATE_IO_LOADED=1

STATE_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/.claude/state"
STATE_FILE="$STATE_DIR/workflow.json"

# Stub _show for debug output — will be overridden by debug-log.sh if sourced by caller
if ! declare -f _show >/dev/null 2>&1; then
    _show() { :; }
fi

# Atomic write helper. Reads stdin → mktemp temp file → guards → mv.
# All state file writes MUST go through this function.
# Rejects: zero-byte input, >10KB output, invalid JSON, mv failure.
_safe_write() {
    local tmpfile
    tmpfile=$(mktemp "${STATE_FILE}.tmp.XXXXXX") || return 1
    cat > "$tmpfile" || { rm -f "$tmpfile"; return 1; }
    local size
    size=$(wc -c < "$tmpfile")
    if [ "$size" -eq 0 ]; then
        rm -f "$tmpfile"
        echo "ERROR: State file write rejected (zero bytes — possible jq failure)." >&2
        return 1
    fi
    if [ "$size" -gt 10240 ]; then
        rm -f "$tmpfile"
        echo "ERROR: State file would exceed 10KB ($size bytes). Write rejected." >&2
        return 1
    fi
    if ! jq -e . "$tmpfile" >/dev/null 2>&1; then
        rm -f "$tmpfile"
        echo "ERROR: State file write rejected (invalid JSON — possible partial write)." >&2
        return 1
    fi
    mv "$tmpfile" "$STATE_FILE" || { rm -f "$tmpfile"; return 1; }
}

# Generic state write helper. Pipes jq output through _safe_write for atomic,
# size-guarded writes.
# SECURITY NOTE: The $filter parameter is interpolated into jq. This is safe
# because all callers are within this file with hardcoded filter strings.
# Do not expose _update_state to untrusted input.
# Usage: _update_state <jq_filter> [--arg name val]... [--argjson name val]...
_update_state() {
    if [ ! -f "$STATE_FILE" ]; then return 1; fi
    local filter="$1"; shift
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    ( set -o pipefail
      jq --arg ts "$ts" "$@" \
          "$filter | .updated = \$ts" \
          "$STATE_FILE" | _safe_write
    )
}

# Restrictive tier: DEFINE and DISCUSS phases
# NOTE: .claude/hooks/ deliberately excluded — enforcement mechanism must not be self-modifiable
RESTRICTED_WRITE_WHITELIST='(\.claude/state/|docs/plans/|docs/specs/|/tmp/|\.claude/tmp/)'

# Docs-allowed tier: COMPLETE phase
# NOTE: .claude/commands/ deliberately excluded — no phase may rewrite command files.
# Command files define phase behavior; an AI rewriting them under pressure is a backdoor.
COMPLETE_WRITE_WHITELIST='(\.claude/state/|\.claude-plugin/|docs/|^[^/]*\.md$)'

# ---------------------------------------------------------------------------
# Shared hook helpers
# ---------------------------------------------------------------------------

# emit_deny moved to deny-messages.sh. Re-export for backward compatibility.
# Use BASH_SOURCE to resolve path relative to this file, not caller's SCRIPT_DIR.
if [ -z "${_WFM_DENY_MESSAGES_LOADED:-}" ]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deny-messages.sh"
fi
