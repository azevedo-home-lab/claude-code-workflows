#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Workflow Manager: blocks Bash write operations in DEFINE, DISCUSS, and COMPLETE phases
# Matcher: Bash
# Catches: redirections, sed -i, tee, heredocs, python file writes
#
# Whitelist tiers:
#   Restrictive (DEFINE/DISCUSS): .claude/state/, docs/superpowers/specs/, docs/superpowers/plans/, docs/plans/
#   Docs-allowed (COMPLETE):      .claude/state/, docs/ (all), *.md at project root

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workflow-state.sh"

# Write pattern — detects file-writing operations
# Groups:
#   1. Redirections: >, >>, echo >
#   2. In-place editors: sed -i, perl -i, ruby -i
#   3. Stream writers: tee
#   4. Heredocs: cat <<, bash <<, sh <<, python3 <<
#   5. File operations (no ^ anchor — catches mid-command): cp, mv, rm, install, patch, ln, touch, truncate
#   6. Network downloads: curl -o, wget -O
#   7. Archive extraction: tar -x, tar x, unzip
#   8. Block devices: dd of=
#   9. Sync: rsync
#  10. Wrappers: eval, bash -c, sh -c
WRITE_PATTERN='(>[^&]|>>|sed[[:space:]]+-i|perl[[:space:]]+-i|ruby[[:space:]]+-i|tee[[:space:]]|cat[[:space:]].*<<|bash[[:space:]].*<<|sh[[:space:]].*<<|python[3]?[[:space:]].*<<|echo[[:space:]].*>|cp[[:space:]]|mv[[:space:]]|rm[[:space:]]|install[[:space:]]|curl[[:space:]].*-o[[:space:]]|wget[[:space:]].*-O[[:space:]]|dd[[:space:]].*of=|patch[[:space:]]|ln[[:space:]]|touch[[:space:]]|truncate[[:space:]]|tar[[:space:]].*-?x|unzip[[:space:]]|rsync[[:space:]]|eval[[:space:]]|bash[[:space:]]+-c|sh[[:space:]]+-c)'

# No state file = no enforcement (first run, hooks not yet activated)
if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

PHASE=$(get_phase)

# OFF phase: no enforcement
case "$PHASE" in
    off) exit 0 ;;
esac

# ---------------------------------------------------------------------------
# Shared command parsing — runs once, used by both autonomy and phase-gate paths
# ---------------------------------------------------------------------------

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# If we can't extract the command, deny (fail-closed — security over availability)
if [ -z "$COMMAND" ]; then
    emit_deny "BLOCKED: Could not parse Bash command in $PHASE phase. Fail-closed for security."
    exit 0
fi

# Allow workflow state commands ONLY when they are the sole command
# (prevents bypass by chaining: source workflow-state.sh && echo pwned > evil)
if echo "$COMMAND" | grep -qE '^[[:space:]]*(source[[:space:]]|\.[ /]).*workflow-state\.sh'; then
    if ! echo "$COMMAND" | grep -qE '(&&|\|\||;|\|)'; then
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
if echo "$COMMAND" | grep -qE '^[[:space:]]*git[[:space:]]+commit\b'; then
    # Extract only the first line of the command (before any heredoc body)
    FIRST_LINE=$(echo "$COMMAND" | head -1)
    # Check for shell operators that appear after the closing quote of -m "..."
    # Strategy: strip the -m "..." or -m '...' inline value, then check for &&/||/;
    STRIPPED=$(echo "$FIRST_LINE" | python3 -c "
import sys, re
line = sys.stdin.read().strip()
# Strip inline quoted -m argument: -m \"...\" or -m '...'
line = re.sub(r'\s-m\s+\"[^\"]*\"', ' -m MSG', line)
line = re.sub(r'\s-m\s+[^\s]+', ' -m MSG', line)
print(line)
" 2>/dev/null)
    if ! echo "$STRIPPED" | grep -qE '(&&|\|\||;)'; then
        exit 0
    fi
    emit_deny "BLOCKED: 'git commit' chained with other commands is not allowed. Run git commit as a standalone command."
    exit 0
fi

# Strip safe redirects before checking write patterns
# 2>/dev/null, 2>&1, 1>&2 etc. are not file writes
CLEAN_CMD=$(echo "$COMMAND" | sed -E 's/[0-9]+>\/dev\/null//g; s/[0-9]*>&[0-9]+//g')

# Multi-line python3 write detection — separate from WRITE_PATTERN because
# the compound pattern (python -c + write indicator) can span lines.
PYTHON_WRITE=false
if echo "$COMMAND" | grep -qE 'python[3]?[[:space:]]+-c'; then
    if echo "$COMMAND" | grep -qiE '\.(write|open|read_text|write_text)|os\.(system|remove|rename|unlink|makedirs)|subprocess\.(run|call|Popen|check_call|check_output)|shutil\.(copy|move|rmtree|copytree)'; then
        PYTHON_WRITE=true
    fi
fi

# ---------------------------------------------------------------------------
# Autonomy Level 1: block ALL Bash write commands regardless of phase
# ---------------------------------------------------------------------------

AUTONOMY_LEVEL=$(get_autonomy_level)
if [ "$AUTONOMY_LEVEL" = "1" ]; then
    if echo "$CLEAN_CMD" | grep -qE "$WRITE_PATTERN" || [ "$PYTHON_WRITE" = "true" ]; then
        emit_deny "BLOCKED: ▶ Level 1 (supervised) — read-only mode. No Bash write operations allowed. Run /autonomy 2 to enable writes."
        exit 0
    fi
    # Read-only Bash commands allowed at Level 1
    exit 0
fi

# ---------------------------------------------------------------------------
# Phase-gate: Level 2/3 enforcement by phase
# ---------------------------------------------------------------------------

# Allow everything in implement and review phases (Level 2/3 only reach here)
case "$PHASE" in
    implement|review) exit 0 ;;
esac

# Select whitelist based on phase
case "$PHASE" in
    define|discuss) WHITELIST="$RESTRICTED_WRITE_WHITELIST" ;;
    complete)       WHITELIST="$COMPLETE_WRITE_WHITELIST" ;;
    *)              exit 0 ;;
esac

if echo "$CLEAN_CMD" | grep -qE "$WRITE_PATTERN" || [ "$PYTHON_WRITE" = "true" ]; then
    # Extract the write target path from the command for whitelist checking
    # For redirections: extract path after > or >>
    # For cp/mv: extract the last argument
    WRITE_TARGET=$(echo "$COMMAND" | python3 -c "
import sys, re
cmd = sys.stdin.read().strip()
# Try redirect target first (most common)
m = re.search(r'>{1,2}\s*(\S+)', cmd)
if m:
    print(m.group(1))
else:
    # For cp/mv/install: last argument is typically the target
    parts = cmd.split()
    if len(parts) >= 3 and parts[0] in ('cp', 'mv', 'install'):
        print(parts[-1])
    else:
        print('')
" 2>/dev/null || echo "")

    # Reject path traversal attempts (../ in the target)
    if [ -n "$WRITE_TARGET" ] && echo "$WRITE_TARGET" | grep -qE '\.\.'; then
        WRITE_TARGET=""  # Force deny — traversal paths are never whitelisted
    fi

    # If we can identify a write target, check it against the whitelist
    if [ -n "$WRITE_TARGET" ] && echo "$WRITE_TARGET" | grep -qE "$WHITELIST"; then
        exit 0
    fi
    # Phase-aware deny message
    case "$PHASE" in
        define)   REASON="BLOCKED: Bash write operation detected in DEFINE phase. Code changes are not allowed until you define the problem and outcomes." ;;
        discuss)  REASON="BLOCKED: Bash write operation detected in DISCUSS phase. Code changes are not allowed until a plan is discussed and approved. Use /implement to proceed to implementation." ;;
        complete) REASON="BLOCKED: Bash write operation detected in COMPLETE phase. Code changes are not allowed during completion. Only documentation updates are permitted." ;;
        *)        REASON="BLOCKED: Unexpected phase ($PHASE)." ;;
    esac

    emit_deny "$REASON"
    exit 0
fi

# Read-only Bash commands are allowed
exit 0
