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
source "$SCRIPT_DIR/workflow-state.sh"

# Write pattern — detects file-writing operations (named fragments for readability)
REDIRECT_OPS='(>[^&]|>>)'
INPLACE_EDITORS='(sed[[:space:]]+-i|perl[[:space:]]+-i|ruby[[:space:]]+-i)'
STREAM_WRITERS='(tee[[:space:]])'
HEREDOCS='(cat[[:space:]].*<<|bash[[:space:]].*<<|sh[[:space:]].*<<|python[3]?[[:space:]].*<<)'
FILE_OPS='((^|[;&|[:space:]])(cp|mv|rm|install|patch|ln|touch|truncate)[[:space:]])'
DOWNLOADS='(curl[[:space:]].*-o[[:space:]]|wget[[:space:]].*-O[[:space:]])'
ARCHIVE_OPS='(tar[[:space:]].*-?x|unzip[[:space:]])'
BLOCK_OPS='(dd[[:space:]].*of=)'
SYNC_OPS='(rsync[[:space:]])'
EXEC_WRAPPERS='(eval[[:space:]]|bash[[:space:]]+-c|sh[[:space:]]+-c)'
ECHO_REDIRECT='(echo[[:space:]].*>)'
# Matches: | bash, | env bash, | /bin/bash, | /usr/bin/env bash, | fish, | csh, | tcsh
PIPE_SHELL='(\|[[:space:]]*(/[^[:space:]]*/)?((env[[:space:]]+(/[^[:space:]]*/)?)?'
PIPE_SHELL+='(bash|sh|zsh|dash|ksh|fish|csh|tcsh))(\b|$))'
PROC_SUB='((/[^[:space:]]*/)?((bash|sh|zsh|dash|ksh|fish|csh|tcsh)|source|\.)[[:space:]]+<\()'
XARGS_EXEC='(\|[[:space:]]*xargs[[:space:]]+(bash|sh|rm|mv|cp|tee|sed))'
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
        if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] Bash ALLOW: workflow state command" >&2; fi
        exit 0
    fi
fi

# Allow workflow-cmd.sh calls ONLY when they are the sole command.
# workflow-cmd.sh is the orchestrator's only path to transition phases in auto
# autonomy mode — blocking it traps the workflow in the current phase forever.
if echo "$COMMAND" | grep -qE '(^|[[:space:]/])workflow-cmd\.sh[[:space:]]'; then
    if ! echo "$COMMAND" | grep -qE '(&&|\|\||;|\|)'; then
        if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] Bash ALLOW: workflow-cmd.sh call" >&2; fi
        exit 0
    fi
fi

# Allow git commit — writes to git object store, not arbitrary files.
# Commit message quality monitored by Layer 3 coaching.
# Chain guard: check only the portion before the -m flag for shell operators,
# since the commit message body may legitimately contain &&, ||, ; in examples.
# A chained command like 'git commit -m "msg" && rm -rf /' embeds the chain
# AFTER the quoted message ends — detect by checking the first line only
# (before heredoc expansion) for operators outside the git commit prefix.
if echo "$COMMAND" | grep -qE '^[[:space:]]*(git|/usr/bin/git|/usr/local/bin/git)[[:space:]]+commit\b'; then
    # Extract only the first line of the command (before any heredoc body)
    FIRST_LINE=$(echo "$COMMAND" | head -1)
    # Check for shell operators that appear after the closing quote of -m "..."
    # Strategy: strip the -m "..." or -m '...' inline value, then check for &&/||/;
    STRIPPED=$(echo "$FIRST_LINE" | sed -E 's/-m "[^"]*"/-m MSG/g; s/-m '"'"'[^'"'"']*'"'"'/-m MSG/g; s/-m [^ ;|&]+/-m MSG/g')
    if ! echo "$STRIPPED" | grep -qE '(&&|\|\||;)'; then
        if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] Bash ALLOW: git commit" >&2; fi
        exit 0
    fi
    emit_deny "BLOCKED: 'git commit' chained with other commands is not allowed. Run git commit as a standalone command."
    exit 0
fi

# Allow safe git chains: git add/status/diff/log && git commit
# Splits command on chain operators, checks every non-commit segment is a safe git op
if echo "$COMMAND" | grep -qE '(git|/usr/bin/git|/usr/local/bin/git)[[:space:]]+commit\b'; then
    SAFE=true
    while IFS= read -r segment; do
        segment=$(echo "$segment" | sed 's/^[[:space:]]*//')
        [ -z "$segment" ] && continue
        # Skip the git commit segment itself
        echo "$segment" | grep -qE '^(git|/usr/bin/git|/usr/local/bin/git)[[:space:]]+commit\b' && continue
        # Allow only safe git ops: add, status, diff, stash, log, show
        if ! echo "$segment" | grep -qE '^(git|/usr/bin/git|/usr/local/bin/git)[[:space:]]+(add|status|diff|stash|log|show)\b'; then
            SAFE=false
            break
        fi
    done < <(echo "$COMMAND" | head -1 | sed -E 's/-m "[^"]*"/-m MSG/g; s/-m '"'"'[^'"'"']*'"'"'/-m MSG/g; s/-m [^ ;|&]+/-m MSG/g' | sed 's/&&/\n/g; s/||/\n/g; s/;/\n/g; s/|/\n/g')
    if [ "$SAFE" = true ]; then
        if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] Bash ALLOW: safe git chain with commit" >&2; fi
        exit 0
    fi
fi

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
        if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] Bash DENY: Direct writes to workflow state files are not allowed." >&2; fi
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
    if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] Bash DENY: user-set-phase.sh called via Bash tool" >&2; fi
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
    if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] Bash DENY: destructive git operation blocked" >&2; fi
    emit_deny "BLOCKED: Destructive git operation detected (reset --hard, push --force, branch -D, checkout --, clean -f, rebase --abort). These operations can cause irreversible data loss. Use !backtick if you need to run this command."
    exit 0
fi

# ---------------------------------------------------------------------------
# Phase-gate: ask/auto enforcement by phase
# ---------------------------------------------------------------------------

# Allow everything in implement and review phases
case "$PHASE" in
    implement|review) if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] Bash ALLOW: phase=$PHASE allows all bash" >&2; fi; exit 0 ;;
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
        if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] Bash ALLOW: gh command in COMPLETE" >&2; fi
        exit 0
    elif [ "$PHASE" = "define" ] || [ "$PHASE" = "discuss" ] || [ "$PHASE" = "error" ]; then
        # DEFINE/DISCUSS: read-only gh ops + issue comment (for plan→issue linking)
        if echo "$COMMAND" | grep -qE '^[[:space:]]*gh[[:space:]]+(repo[[:space:]]+view|issue[[:space:]]+view|issue[[:space:]]+list|issue[[:space:]]+comment|pr[[:space:]]+view|pr[[:space:]]+list|release[[:space:]]+(view|list))' && \
           _gh_safe_chain; then
            if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] Bash ALLOW: gh read-only in $PHASE" >&2; fi
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
        if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] Bash ALLOW: rm .claude/tmp/ in COMPLETE" >&2; fi
        exit 0
    fi
fi

# Guard-system path check — runs AFTER gh/rm early exits so that gh commands
# in COMPLETE phase are not blocked by path mentions in --body text.
GUARD_SYSTEM_PATTERN='(\.claude/hooks/|plugin/scripts/|plugin/commands/)'
if echo "$COMMAND" | grep -qE "$GUARD_SYSTEM_PATTERN"; then
    if echo "$CLEAN_CMD" | grep -qE "$WRITE_PATTERN" || [ "$PYTHON_WRITE" = "true" ] || [ "$NODE_WRITE" = "true" ] || [ "$RUBY_WRITE" = "true" ] || [ "$PERL_WRITE" = "true" ]; then
        if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] Bash DENY: write to enforcement file blocked" >&2; fi
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
        if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] Bash ALLOW: write target whitelisted ($WRITE_TARGET)" >&2; fi
        exit 0
    fi
    # Phase-aware deny message
    case "$PHASE" in
        define)   REASON="BLOCKED: Bash write operation detected in DEFINE phase. Code changes are not allowed until you define the problem and outcomes." ;;
        discuss)  REASON="BLOCKED: Bash write operation detected in DISCUSS phase. Code changes are not allowed until a plan is discussed and approved. Use /implement to proceed to implementation." ;;
        complete) REASON="BLOCKED: Bash write operation detected in COMPLETE phase. Code changes are not allowed during completion. Only documentation updates are permitted." ;;
        error)    REASON="BLOCKED: Workflow state is corrupted. All writes blocked for safety. Run /off to reset." ;;
        *)        REASON="BLOCKED: Unexpected phase ($PHASE)." ;;
    esac

    if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] Bash DENY: $REASON" >&2; fi
    emit_deny "$REASON"
    exit 0
fi

# Read-only Bash commands are allowed
if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] Bash ALLOW: no write pattern detected" >&2; fi
exit 0
