#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Workflow Manager: blocks Bash write operations in DEFINE, DISCUSS, and COMPLETE phases
# Matcher: Bash
# Catches: redirections, sed -i, tee, heredocs, python/node/ruby/perl file writes, pipe-to-shell, gh API ops
#
# Whitelist tiers:
#   Restrictive (DEFINE/DISCUSS): .claude/state/, docs/plans/
#   Docs-allowed (COMPLETE):      .claude/state/, docs/ (all), *.md at project root

set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/state-io.sh"
source "$SCRIPT_DIR/phase.sh"
source "$SCRIPT_DIR/settings.sh"

# Stub _log before debug-log.sh is sourced (called in early-exit paths)
_log() { :; }

# Write pattern — detects file-writing operations (named fragments for readability)

# --- Shell operators (redirects, heredocs, echo redirect) ---
REDIRECT_OPS='(>[^&]|>>)'
HEREDOCS='(cat[[:space:]].*<<|bash[[:space:]].*<<|sh[[:space:]].*<<|python[3]?[[:space:]].*<<)'
ECHO_REDIRECT='(echo[[:space:]].*>)'

# --- Editors and writers (sed -i, perl -i, tee) ---
INPLACE_EDITORS='(sed[[:space:]]+-i|perl[[:space:]]+-i|ruby[[:space:]]+-i)'
STREAM_WRITERS='(tee[[:space:]])'

# --- File operations (cp, mv, rm, touch, etc.) ---
FILE_OPS='((^|[;&|[:space:]])(cp|mv|rm|install|patch|ln|touch|truncate)[[:space:]])'

# --- Network operations (curl, wget) ---
DOWNLOADS='(curl[[:space:]].*-o[[:space:]]|wget[[:space:]].*-O[[:space:]])'

# --- Archive/block operations (tar, unzip, dd, rsync) ---
ARCHIVE_OPS='(tar[[:space:]].*-?x|unzip[[:space:]])'
BLOCK_OPS='(dd[[:space:]].*of=)'
SYNC_OPS='(rsync[[:space:]])'

# --- Execution wrappers (eval, bash -c, pipe-to-shell, process substitution, xargs) ---
EXEC_WRAPPERS='(eval[[:space:]]|bash[[:space:]]+-c|sh[[:space:]]+-c)'
# Matches: | bash, | env bash, | /bin/bash, | /usr/bin/env bash, | fish, | csh, | tcsh
PIPE_SHELL='(\|[[:space:]]*(/[^[:space:]]*/)?((env[[:space:]]+(/[^[:space:]]*/)?)?'\
'(bash|sh|zsh|dash|ksh|fish|csh|tcsh))(\b|$))'
PROC_SUB='((/[^[:space:]]*/)?((bash|sh|zsh|dash|ksh|fish|csh|tcsh)|source|\.)[[:space:]]+<\()'
XARGS_EXEC='(\|[[:space:]]*xargs[[:space:]]+(bash|sh|rm|mv|cp|tee|sed))'

# --- External tools (gh) ---
GH_OPS='(gh[[:space:]])'

WRITE_PATTERN="$REDIRECT_OPS|$INPLACE_EDITORS|$STREAM_WRITERS|$HEREDOCS|$FILE_OPS|$DOWNLOADS|$ARCHIVE_OPS|$BLOCK_OPS|$SYNC_OPS|$EXEC_WRAPPERS|$ECHO_REDIRECT|$PIPE_SHELL|$PROC_SUB|$XARGS_EXEC|$GH_OPS"

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
source "$SCRIPT_DIR/debug-log.sh" "bash-write-guard"

# ---------------------------------------------------------------------------
# Shared command parsing — runs once, used by both autonomy and phase-gate paths
# ---------------------------------------------------------------------------

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || COMMAND=""

# If we can't extract the command, deny (fail-closed — security over availability)
if [ -z "$COMMAND" ]; then
    emit_deny "BLOCKED: Could not parse Bash command in $PHASE phase. Fail-closed for security."
    exit 0
fi

# Allow workflow state commands ONLY when they are the sole command
# (prevents bypass by chaining: source workflow-state.sh && echo pwned > evil)
if echo "$COMMAND" | grep -qE '^[[:space:]]*(source[[:space:]]|\.[ /]).*workflow-state\.sh'; then
    if ! echo "$COMMAND" | grep -qE '(&&|\|\||;|\|)'; then
        _log "ALLOW: workflow state command"
        exit 0
    fi
fi

# Allow workflow-cmd.sh calls ONLY when they are the sole command.
# workflow-cmd.sh is the orchestrator's only path to transition phases in auto
# autonomy mode — blocking it traps the workflow in the current phase forever.
if echo "$COMMAND" | grep -qE '(^|[[:space:]/])workflow-cmd\.sh[[:space:]]'; then
    if ! echo "$COMMAND" | grep -qE '(&&|\|\||;|\|)'; then
        _log "ALLOW: workflow-cmd.sh call"
        exit 0
    fi
fi

# Returns 0 if the command is an allowed git commit (standalone or safe chain)
# Returns 1 if the commit is chained with unsafe commands (should be denied)
# Returns 2 if the command is not a git commit at all
_check_git_commit() {
    local cmd="$1"

    # Strategy 1: single commit command (may have -m message with shell chars)
    # Chain guard: strip the -m "..." value, then check for &&/||/;
    if echo "$cmd" | grep -qE '^[[:space:]]*(git|/usr/bin/git|/usr/local/bin/git)[[:space:]]+commit\b'; then
        local first_line stripped
        first_line=$(echo "$cmd" | head -1)
        stripped=$(echo "$first_line" | sed -E 's/-m "[^"]*"/-m MSG/g; s/-m '"'"'[^'"'"']*'"'"'/-m MSG/g; s/-m [^ ;|&]+/-m MSG/g')
        if ! echo "$stripped" | grep -qE '(&&|\|\||;)'; then
            return 0  # standalone commit
        fi
        return 1  # commit chained with unsafe commands
    fi

    # Strategy 2: safe git chain (git add && git commit)
    # Splits on chain operators, checks every non-commit segment is a safe git op
    if echo "$cmd" | grep -qE '(git|/usr/bin/git|/usr/local/bin/git)[[:space:]]+commit\b'; then
        local safe=true segment
        while IFS= read -r segment; do
            segment=$(echo "$segment" | sed 's/^[[:space:]]*//')
            [ -z "$segment" ] && continue
            echo "$segment" | grep -qE '^(git|/usr/bin/git|/usr/local/bin/git)[[:space:]]+commit\b' && continue
            if ! echo "$segment" | grep -qE '^(git|/usr/bin/git|/usr/local/bin/git)[[:space:]]+(add|status|diff|stash|log|show)\b'; then
                safe=false
                break
            fi
        done < <(echo "$cmd" | head -1 | sed -E 's/-m "[^"]*"/-m MSG/g; s/-m '"'"'[^'"'"']*'"'"'/-m MSG/g; s/-m [^ ;|&]+/-m MSG/g' | sed 's/&&/\n/g; s/||/\n/g; s/;/\n/g; s/|/\n/g')
        if [ "$safe" = true ]; then
            return 0  # safe chain
        fi
        # Unsafe chain — fall through to "not a commit" so normal write checks apply
    fi

    return 2  # not a git commit
}

_git_rc=0; _check_git_commit "$COMMAND" || _git_rc=$?
case $_git_rc in
    0) _log "ALLOW: git commit"; exit 0 ;;
    1) emit_deny "BLOCKED: 'git commit' chained with other commands is not allowed. Run git commit as a standalone command."; exit 0 ;;
    2) ;;  # not a commit, continue checking
esac

# Strip safe redirects before checking write patterns
# 2>/dev/null, 2>&1, 1>&2 etc. are not file writes
CLEAN_CMD=$(echo "$COMMAND" | sed -E 's/[0-9]+>\/dev\/null//g; s/[0-9]*>&[0-9]+//g; s/>>[[:space:]]*\/dev\/null//g; s/>[[:space:]]*\/dev\/null//g')

# Multi-line python3 write detection — separate from WRITE_PATTERN because
# the compound pattern (python -c + write indicator) can span lines.
PYTHON_WRITE=false
if echo "$COMMAND" | grep -qE 'python[3]?[[:space:]]+-c'; then
    if echo "$COMMAND" | grep -qiE '\.(write|open|read_text|write_text)|os\.(system|remove|rename|unlink|makedirs)|subprocess\.(run|call|Popen|check_call|check_output)|shutil\.(copy|move|rmtree|copytree)'; then
        PYTHON_WRITE=true
    fi
fi

# Node.js write detection
NODE_WRITE=false
if echo "$COMMAND" | grep -qE 'node[[:space:]]+(--eval|-e)[[:space:]]'; then
    if echo "$COMMAND" | grep -qiE 'fs\.|writeFile|appendFile|createWriteStream|child_process|exec\(|spawn\('; then
        NODE_WRITE=true
    fi
fi

# Ruby write detection
RUBY_WRITE=false
if echo "$COMMAND" | grep -qE 'ruby[[:space:]]+-e[[:space:]]'; then
    if echo "$COMMAND" | grep -qiE 'File\.|IO\.|open\(|system\(|exec\(|`'; then
        RUBY_WRITE=true
    fi
fi

# Perl write detection
PERL_WRITE=false
if echo "$COMMAND" | grep -qE 'perl[[:space:]]+-e[[:space:]]'; then
    if echo "$COMMAND" | grep -qiE 'open\(|system\(|unlink|rename'; then
        PERL_WRITE=true
    fi
fi

# ---------------------------------------------------------------------------
# Defense-in-depth: block writes to workflow state files in ALL active phases.
# Only triggers when a write operation targets these files (not on reads like cat/jq).
# Fires before the implement/review early-exit to catch forgery attempts.
# NOTE: PreToolUse blocking is unreliable — this is a speed bump, not a wall.
# ---------------------------------------------------------------------------

STATE_FILE_PATTERN='\.claude/(state/workflow\.json|state/phase-intent\.json)'
if echo "$COMMAND" | grep -qE "$STATE_FILE_PATTERN"; then
    if echo "$CLEAN_CMD" | grep -qE "$WRITE_PATTERN" || [ "$PYTHON_WRITE" = "true" ] || [ "$NODE_WRITE" = "true" ] || [ "$RUBY_WRITE" = "true" ] || [ "$PERL_WRITE" = "true" ]; then
        _log "DENY: direct write to workflow state file"
        emit_deny "BLOCKED: Direct writes to workflow state files are not allowed."
        exit 0
    fi
fi

# ---------------------------------------------------------------------------
# Guard-system self-protection: block writes to enforcement files in ALL active phases.
# Fires before the implement|review early-exit — those phases do not bypass this.
# Claude cannot modify the files that enforce the workflow on Claude.
# This includes: hook scripts, workflow scripts, and command files.
# The user can always use !backtick to make legitimate changes to these files.
# ---------------------------------------------------------------------------

# Block execution of user-set-phase.sh — !backtick only, never a Bash tool call.
# Matches execution contexts (direct call, source, bash -c) but not read-only ops (cat, git diff).
if echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])(\\./|source[[:space:]]|bash[[:space:]]|sh[[:space:]]|/)[^[:space:]]*user-set-phase\.sh'; then
    _log "DENY: user-set-phase.sh called via Bash tool"
    emit_deny "BLOCKED: user-set-phase.sh is the user-only phase transition path. It cannot be called via Bash tool — only from !backtick command files."
    exit 0
fi

# ---------------------------------------------------------------------------
# Destructive git operations: blocked in ALL active phases.
# Fires before the implement/review early-exit — no phase bypasses this.
# The user can always use !backtick for legitimate destructive operations.
# ---------------------------------------------------------------------------

DESTRUCTIVE_GIT='(git|/usr/bin/git|/usr/local/bin/git)[[:space:]]+(reset[[:space:]]+--hard|push[[:space:]]+--force|push[[:space:]]+-f[[:space:]]|branch[[:space:]]+-D[[:space:]]|checkout[[:space:]]+--[[:space:]]\.|clean[[:space:]]+-f|rebase[[:space:]]+--abort)'
if echo "$COMMAND" | grep -qE "$DESTRUCTIVE_GIT"; then
    _log "DENY: destructive git operation blocked"
    emit_deny "BLOCKED: Destructive git operation detected (reset --hard, push --force, branch -D, checkout --, clean -f, rebase --abort). These operations can cause irreversible data loss. Use !backtick if you need to run this command."
    exit 0
fi

# ---------------------------------------------------------------------------
# Phase-gate: ask/auto enforcement by phase
# ---------------------------------------------------------------------------

# Allow everything in implement and review phases
case "$PHASE" in
    implement|review) _log "ALLOW: phase=$PHASE allows all bash"; exit 0 ;;
esac

# Select whitelist based on phase
case "$PHASE" in
    define|discuss|error) WHITELIST="$RESTRICTED_WRITE_WHITELIST" ;;
    complete)             WHITELIST="$COMPLETE_WRITE_WHITELIST" ;;
    *)                    exit 0 ;;
esac

# gh command handling — split by phase:
#   DEFINE/DISCUSS: named read-only gh ops only (view, list) — no gh api (allows POST/PATCH)
#   COMPLETE:       all gh ops allowed (need to create issues, PRs for handover)
# Guard: no shell chaining, no pipe to file writers (applies to both tiers).
_gh_safe_chain() {
    # Strip harmless "|| true" / "|| echo ..." suffixes before chain check
    local _gh_stripped
    _gh_stripped=$(echo "$COMMAND" | sed -E 's/\|\|[[:space:]]*(true|echo[[:space:]][^;&|]*)$//')
    ! echo "$_gh_stripped" | grep -qE '(&&|\|\||;)' && \
    ! echo "$COMMAND" | grep -qE "$PIPE_SHELL" && \
    ! echo "$COMMAND" | grep -qE "$PROC_SUB" && \
    ! echo "$COMMAND" | grep -qE "$XARGS_EXEC" && \
    ! echo "$COMMAND" | grep -qE '\|[[:space:]]*(tee|sed|dd|cp|mv|install|python[3]?|node|ruby|perl|awk)\b'
}

if echo "$COMMAND" | grep -qE '^[[:space:]]*(gh)[[:space:]]'; then
    if [ "$PHASE" = "complete" ] && _gh_safe_chain; then
        # COMPLETE: all gh ops allowed (issue create, pr create, etc.)
        _log "ALLOW: gh command in COMPLETE"
        exit 0
    elif [ "$PHASE" = "define" ] || [ "$PHASE" = "discuss" ] || [ "$PHASE" = "error" ]; then
        # DEFINE/DISCUSS: read-only gh ops + issue comment (for plan→issue linking)
        if echo "$COMMAND" | grep -qE '^[[:space:]]*gh[[:space:]]+(repo[[:space:]]+view|issue[[:space:]]+view|issue[[:space:]]+list|issue[[:space:]]+comment|pr[[:space:]]+view|pr[[:space:]]+list|release[[:space:]]+(view|list))' && \
           _gh_safe_chain; then
            _log "ALLOW: gh read-only in $PHASE"
            exit 0
        fi
    fi
fi

# COMPLETE phase: allow rm for .claude/tmp/ cleanup
if [ "$PHASE" = "complete" ]; then
    _rm_stripped=$(echo "$COMMAND" | sed -E 's/\|\|[[:space:]]*(true|echo[[:space:]][^;&|]*)$//')
    if echo "$_rm_stripped" | grep -qE '^[[:space:]]*rm[[:space:]]' && \
       echo "$_rm_stripped" | grep -qE '\.claude/tmp/' && \
       ! echo "$_rm_stripped" | grep -qE '\.\.' && \
       ! echo "$_rm_stripped" | grep -qE '(&&|\|\||;|\|)'; then
        _log "ALLOW: rm .claude/tmp/ in COMPLETE"
        exit 0
    fi
fi

# Guard-system path check — runs AFTER gh/rm early exits so that gh commands
# in COMPLETE phase are not blocked by path mentions in --body text.
GUARD_SYSTEM_PATTERN='(\.claude/hooks/|plugin/scripts/|plugin/commands/)'
if echo "$COMMAND" | grep -qE "$GUARD_SYSTEM_PATTERN"; then
    if echo "$CLEAN_CMD" | grep -qE "$WRITE_PATTERN" || [ "$PYTHON_WRITE" = "true" ] || [ "$NODE_WRITE" = "true" ] || [ "$RUBY_WRITE" = "true" ] || [ "$PERL_WRITE" = "true" ]; then
        _log "DENY: write to enforcement file blocked"
        emit_deny "BLOCKED: Writes to enforcement files (.claude/hooks/, plugin/scripts/, plugin/commands/) are not allowed in any phase. These files define the workflow rules. Use !backtick if you need to make legitimate changes."
        exit 0
    fi
fi

if echo "$CLEAN_CMD" | grep -qE "$WRITE_PATTERN" || [ "$PYTHON_WRITE" = "true" ] || [ "$NODE_WRITE" = "true" ] || [ "$RUBY_WRITE" = "true" ] || [ "$PERL_WRITE" = "true" ]; then
    # Extract the write target path from the command for whitelist checking
    # For redirections: extract path after > or >>
    # For cp/mv: extract the last argument
    WRITE_TARGET=$(echo "$COMMAND" | sed -n 's/.*>[[:space:]]*\([^[:space:];|&]*\).*/\1/p' | head -1)
    if [ -z "$WRITE_TARGET" ]; then
        WRITE_TARGET=$(echo "$COMMAND" | sed -n 's/.*\(cp\|mv\|install\)[[:space:]].*[[:space:]]\([^[:space:];|&]*\)[[:space:]]*$/\2/p' | head -1)
    fi

    # Reject path traversal attempts (../ in the target)
    if [ -n "$WRITE_TARGET" ] && echo "$WRITE_TARGET" | grep -qE '\.\.'; then
        WRITE_TARGET=""  # Force deny — traversal paths are never whitelisted
    fi

    # If we can identify a write target, check it against the whitelist
    if [ -n "$WRITE_TARGET" ] && echo "$WRITE_TARGET" | grep -qE "$WHITELIST"; then
        _log "ALLOW: write target whitelisted ($WRITE_TARGET)"
        exit 0
    fi
    # Phase-aware deny message
    case "$PHASE" in
        define)   REASON="BLOCKED: Bash write operation detected in DEFINE phase. Code changes are not allowed until you define the problem and outcomes." ;;
        discuss)  REASON="BLOCKED: Bash write operation detected in DISCUSS phase. Code changes are not allowed until the design phase is complete. Use /implement to proceed to implementation." ;;
        complete) REASON="BLOCKED: Bash write operation detected in COMPLETE phase. Code changes are not allowed during completion. Only documentation updates are permitted." ;;
        error)    REASON="BLOCKED: Workflow state is corrupted. All writes blocked for safety. Run /off to reset." ;;
        *)        REASON="BLOCKED: Unexpected phase ($PHASE)." ;;
    esac

    _log "DENY: $REASON"
    emit_deny "$REASON"
    exit 0
fi

# Read-only Bash commands are allowed
_log "ALLOW: no write pattern detected"
exit 0
