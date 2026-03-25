#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# UserPromptSubmit hook: writes intent files for phase and autonomy commands.
# Intent files are consumed by set_phase() and set_autonomy_level() in workflow-state.sh.
# Claude cannot trigger this hook — it only fires on actual user input.
#
# Security model: Only explicit slash commands generate intent files.
# No bare set_phase/set_autonomy_level matching — prevents false positives.
# Uses printf (shell builtin) — no jq, no openssl, no PATH dependencies.

set -euo pipefail

# Read stdin JSON — extract prompt using shell builtins + grep/sed
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | grep -o '"prompt"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"prompt"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || PROMPT=""
[ -z "$PROMPT" ] && exit 0

# Resolve STATE_DIR (same logic as workflow-state.sh)
STATE_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/.claude/state"

# Detect phase commands: explicit slash commands only
# Regex: ^\s*/<command>(\s|$) — anchored to line start, must start with /
TARGET=""
if echo "$PROMPT" | grep -qE '^\s*/define(\s|$)'; then
    TARGET="define"
elif echo "$PROMPT" | grep -qE '^\s*/discuss(\s|$)'; then
    TARGET="discuss"
elif echo "$PROMPT" | grep -qE '^\s*/implement(\s|$)'; then
    TARGET="implement"
elif echo "$PROMPT" | grep -qE '^\s*/review(\s|$)'; then
    TARGET="review"
elif echo "$PROMPT" | grep -qE '^\s*/complete(\s|$)'; then
    TARGET="complete"
elif echo "$PROMPT" | grep -qE '^\s*/off(\s|$)'; then
    TARGET="off"
fi

# Detect autonomy commands: /autonomy <level>
AUTONOMY_TARGET=""
if echo "$PROMPT" | grep -qE '^\s*/autonomy\s+'; then
    RAW_LEVEL=$(echo "$PROMPT" | grep -oE '/autonomy\s+\S+' | head -1 | awk '{print $2}')
    case "$RAW_LEVEL" in
        1|off) AUTONOMY_TARGET="autonomy:off" ;;
        2|ask) AUTONOMY_TARGET="autonomy:ask" ;;
        3|auto) AUTONOMY_TARGET="autonomy:auto" ;;
    esac
fi

# No matching command — exit silently
[ -z "$TARGET" ] && [ -z "$AUTONOMY_TARGET" ] && exit 0

# Write phase intent file
if [ -n "$TARGET" ]; then
    printf '{"intent":"%s"}\n' "$TARGET" > "$STATE_DIR/phase-intent.json"
    if [ ! -s "$STATE_DIR/phase-intent.json" ]; then
        echo "ERROR: Failed to write phase intent file to $STATE_DIR/phase-intent.json" >&2
        # exit 0, not exit 1 — let the prompt through, set_phase() will produce diagnostics
    fi
fi

# Write autonomy intent file (separate file — prevents overwrite when both in same prompt)
if [ -n "$AUTONOMY_TARGET" ]; then
    printf '{"intent":"%s"}\n' "$AUTONOMY_TARGET" > "$STATE_DIR/autonomy-intent.json"
    if [ ! -s "$STATE_DIR/autonomy-intent.json" ]; then
        echo "ERROR: Failed to write autonomy intent file to $STATE_DIR/autonomy-intent.json" >&2
    fi
fi

exit 0
