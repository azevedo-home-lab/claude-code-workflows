#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# UserPromptSubmit hook: generates one-time tokens for phase and autonomy commands.
# Tokens are consumed by set_phase() and set_autonomy_level() in workflow-state.sh.
# Claude cannot trigger this hook — it only fires on actual user input.
#
# Security model: Only explicit slash commands generate tokens.
# No bare set_phase/set_autonomy_level matching — prevents false positives.
# No TTL — tokens are consumed immediately when the slash command executes.

set -euo pipefail

# Read stdin JSON
INPUT=$(cat)

# Extract prompt
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""' 2>/dev/null) || PROMPT=""
[ -z "$PROMPT" ] && exit 0

# Token directory
TOKEN_DIR="${CLAUDE_PLUGIN_DATA:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/.claude/plugin-data}/.phase-tokens"

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
    # Normalize numeric values
    case "$RAW_LEVEL" in
        1|off) AUTONOMY_TARGET="autonomy:off" ;;
        2|ask) AUTONOMY_TARGET="autonomy:ask" ;;
        3|auto) AUTONOMY_TARGET="autonomy:auto" ;;
    esac
fi

# No matching command — exit silently
[ -z "$TARGET" ] && [ -z "$AUTONOMY_TARGET" ] && exit 0

# Create token directory
mkdir -p "$TOKEN_DIR"

# Generate nonce
NONCE=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')

# Write phase token (no timestamp — consumed immediately, no TTL)
if [ -n "$TARGET" ]; then
    jq -n --arg target "$TARGET" --arg nonce "$NONCE" \
        '{"target": $target, "nonce": $nonce}' > "$TOKEN_DIR/$NONCE"
fi

# Write autonomy token (separate nonce)
if [ -n "$AUTONOMY_TARGET" ]; then
    ANONCE=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
    jq -n --arg target "$AUTONOMY_TARGET" --arg nonce "$ANONCE" \
        '{"target": $target, "nonce": $nonce}' > "$TOKEN_DIR/$ANONCE"
fi

exit 0
