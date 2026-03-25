#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# UserPromptSubmit hook: generates one-time tokens for phase and autonomy commands.
# Tokens are consumed by set_phase() and set_autonomy_level() in workflow-state.sh.
# Claude cannot trigger this hook — it only fires on actual user input.

set -euo pipefail

# Read stdin JSON
INPUT=$(cat)

# Extract prompt
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""' 2>/dev/null) || PROMPT=""
[ -z "$PROMPT" ] && exit 0

# Token directory
TOKEN_DIR="${CLAUDE_PLUGIN_DATA:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/.claude/plugin-data}/.phase-tokens"

# Detect phase commands: /define, /discuss, /implement, /review, /complete
# Also detect bare set_phase calls (user running via ! prefix)
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
elif echo "$PROMPT" | grep -qE "set_phase\s+[\"']?(off|define|discuss|implement|review|complete)[\"']?"; then
    TARGET=$(echo "$PROMPT" | grep -oE "set_phase\s+[\"']?(off|define|discuss|implement|review|complete)[\"']?" | head -1 | sed 's/set_phase[[:space:]]*//' | tr -d "\"'")
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
elif echo "$PROMPT" | grep -qE 'set_autonomy_level\s+"?(off|ask|auto|1|2|3)"?'; then
    RAW_LEVEL=$(echo "$PROMPT" | grep -oE 'set_autonomy_level\s+"?(off|ask|auto|1|2|3)"?' | head -1 | sed 's/set_autonomy_level[[:space:]]*//' | tr -d '"')
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

# Clean up expired tokens (>60 seconds old)
NOW=$(date +%s)
for old_token in "$TOKEN_DIR"/*; do
    [ -f "$old_token" ] || continue
    TOKEN_TS=$(jq -r '.ts // 0' "$old_token" 2>/dev/null) || TOKEN_TS=0
    if [ $((NOW - TOKEN_TS)) -ge 60 ]; then
        rm -f "$old_token"
    fi
done

# Generate nonce
NONCE=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')

# Write phase token
if [ -n "$TARGET" ]; then
    jq -n --arg target "$TARGET" --argjson ts "$NOW" --arg nonce "$NONCE" \
        '{"target": $target, "ts": $ts, "nonce": $nonce}' > "$TOKEN_DIR/$NONCE"
fi

# /complete also needs an "off" token for Step 9 (set_phase "off" at pipeline end)
if [ "$TARGET" = "complete" ]; then
    OFF_NONCE=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
    jq -n --arg target "off" --argjson ts "$NOW" --arg nonce "$OFF_NONCE" \
        '{"target": $target, "ts": $ts, "nonce": $nonce}' > "$TOKEN_DIR/$OFF_NONCE"
fi

# Write autonomy token (separate nonce)
if [ -n "$AUTONOMY_TARGET" ]; then
    ANONCE=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
    jq -n --arg target "$AUTONOMY_TARGET" --argjson ts "$NOW" --arg nonce "$ANONCE" \
        '{"target": $target, "ts": $ts, "nonce": $nonce}' > "$TOKEN_DIR/$ANONCE"
fi

exit 0
