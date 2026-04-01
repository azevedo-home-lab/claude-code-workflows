#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Workflow Manager: blocks Bash write operations based on phase
# Matcher: Bash
#
# DEFINE/DISCUSS/ERROR: allowlist — only known read-only commands pass
# COMPLETE: denylist — known write operations blocked, rest passes
# IMPLEMENT/REVIEW: everything allowed (except guard-system and destructive git)

set -euo pipefail

# --- Preamble: shared hook bootstrap ---
SCRIPT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/plugin/scripts"
source "$SCRIPT_DIR/infrastructure/hook-preamble.sh" "bash-write-guard" || exit 0

source "$SCRIPT_DIR/infrastructure/deny-messages.sh"
source "$SCRIPT_DIR/infrastructure/git-safety.sh"
source "$SCRIPT_DIR/infrastructure/gh-safety.sh"
source "$SCRIPT_DIR/infrastructure/write-patterns.sh"
source "$SCRIPT_DIR/infrastructure/read-allowlist.sh"
source "$SCRIPT_DIR/infrastructure/patterns.sh"

# --- Parse command ---
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || COMMAND=""

if [ -z "$COMMAND" ]; then
    emit_deny "BLOCKED: Could not parse Bash command in $PHASE phase. Fail-closed for security."
    exit 0
fi

# --- Allow workflow state commands (sole command, no chaining) ---
if echo "$COMMAND" | grep -qE '^[[:space:]]*(source[[:space:]]|\.[ /]).*workflow-(state|facade)\.sh'; then
    if ! echo "$COMMAND" | grep -qE '(&&|\|\||;|\|)'; then
        _log "ALLOW: workflow state command"
        exit 0
    fi
fi

if echo "$COMMAND" | grep -qE '(^|[[:space:]/])workflow-cmd\.sh[[:space:]]'; then
    if ! echo "$COMMAND" | grep -qE '(&&|\|\||;|\|)'; then
        _log "ALLOW: workflow-cmd.sh call"
        exit 0
    fi
fi

# --- Git commit check ---
_git_rc=0; _check_git_commit "$COMMAND" || _git_rc=$?
case $_git_rc in
    0) _log "ALLOW: git commit"; exit 0 ;;
    1) emit_deny "$(_phase_deny_message "$PHASE" "chained-commit")"; exit 0 ;;
    2) ;;  # not a commit, continue
esac

# --- Destructive git (ALL phases including implement/review) ---
if _is_destructive_git "$COMMAND"; then
    _log "DENY: destructive git"
    emit_deny "$(_phase_deny_message "$PHASE" "destructive-git")"
    exit 0
fi

# --- user-set-phase.sh execution block (ALL phases) ---
if echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])(\\./|source[[:space:]]|bash[[:space:]]|sh[[:space:]]|/)[^[:space:]]*user-set-phase\.sh'; then
    _log "DENY: user-set-phase.sh via Bash"
    emit_deny "$(_phase_deny_message "$PHASE" "user-set-phase")"
    exit 0
fi

# --- Write target protection (ALL phases including implement/review) ---
# Check write target against state-file and guard-system patterns.
# Uses _extract_write_target to match the actual destination, not the full command string.
if _detect_write_operation "$COMMAND"; then
    write_target=$(_extract_write_target "$COMMAND")
    if [ -n "$write_target" ]; then
        if echo "$write_target" | grep -qE "$STATE_FILE_PATTERN"; then
            _log "DENY: write to state file ($write_target)"
            emit_deny "$(_phase_deny_message "$PHASE" "state-file")"
            exit 0
        fi
        if echo "$write_target" | grep -qE "$GUARD_SYSTEM_PATTERN"; then
            _log "DENY: write to enforcement file ($write_target)"
            emit_deny "$(_phase_deny_message "$PHASE" "guard-system")"
            exit 0
        fi
    fi
fi

# --- implement/review: allow everything else ---
case "$PHASE" in
    implement|review) _log "ALLOW: phase=$PHASE"; exit 0 ;;
esac

# --- Phase gate ---
case "$PHASE" in
    # DEFINE/DISCUSS/ERROR: allowlist enforcement
    define|discuss|error)
        # gh commands get special handling
        if echo "$COMMAND" | grep -qE '^[[:space:]]*(gh)[[:space:]]'; then
            if _check_gh_command "$COMMAND" "$PHASE"; then
                _log "ALLOW: gh read-only in $PHASE"
                exit 0
            fi
        fi

        # Check against read-only allowlist
        if _is_allowed_readonly "$COMMAND"; then
            _log "ALLOW: allowlist match"
            exit 0
        fi

        # Check write target against phase whitelist (for allowed writes like docs/plans/)
        if _detect_write_operation "$COMMAND"; then
            write_target=$(_extract_write_target "$COMMAND")
            if [ -n "$write_target" ] && echo "$write_target" | grep -qE "$RESTRICTED_WRITE_WHITELIST"; then
                _log "ALLOW: write target whitelisted ($write_target)"
                exit 0
            fi
        fi

        _log "DENY: not on allowlist in $PHASE"
        emit_deny "$(_phase_deny_message "$PHASE" "bash-write")"
        exit 0
        ;;

    # COMPLETE: denylist enforcement
    complete)
        # gh commands — all allowed in COMPLETE if safe chain
        if echo "$COMMAND" | grep -qE '^[[:space:]]*(gh)[[:space:]]'; then
            if _check_gh_command "$COMMAND" "$PHASE"; then
                _log "ALLOW: gh in COMPLETE"
                exit 0
            fi
        fi

        # rm .claude/tmp/ cleanup
        _rm_stripped=$(echo "$COMMAND" | sed -E 's/\|\|[[:space:]]*(true|echo[[:space:]][^;&|]*)$//')
        if echo "$_rm_stripped" | grep -qE '^[[:space:]]*rm[[:space:]]' && \
           echo "$_rm_stripped" | grep -qE '\.claude/tmp/' && \
           ! echo "$_rm_stripped" | grep -qE '\.\.' && \
           ! echo "$_rm_stripped" | grep -qE '(&&|\|\||;|\|)'; then
            _log "ALLOW: rm .claude/tmp/ in COMPLETE"
            exit 0
        fi

        # Write detection
        if _detect_write_operation "$COMMAND"; then
            write_target=$(_extract_write_target "$COMMAND")
            if [ -n "$write_target" ] && echo "$write_target" | grep -qE "$COMPLETE_WRITE_WHITELIST"; then
                _log "ALLOW: write target whitelisted ($write_target)"
                exit 0
            fi
            _log "DENY: write detected in COMPLETE ($DETECTED_WRITE_TYPE)"
            emit_deny "$(_phase_deny_message "$PHASE" "bash-write")"
            exit 0
        fi

        # No write detected — read-only command, allow
        _log "ALLOW: no write pattern in COMPLETE"
        exit 0
        ;;

    *)
        exit 0
        ;;
esac
