#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Test runner for Claude Code Workflows
# Usage: ./tests/run-tests.sh

set -euo pipefail

PASS=0
FAIL=0
ERRORS=""

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required but not found. Install with: brew install jq" >&2
    exit 1
fi

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    if echo "$haystack" | grep -q "$needle"; then
        echo -e "  ${GREEN}PASS${NC} $test_name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $test_name"
        echo "    '$needle' not found in output"
        FAIL=$((FAIL + 1))
        ERRORS="$ERRORS\n  FAIL: $test_name"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    if echo "$haystack" | grep -q "$needle"; then
        echo -e "  ${RED}FAIL${NC} $test_name"
        echo "    '$needle' was found but should not be"
        FAIL=$((FAIL + 1))
        ERRORS="$ERRORS\n  FAIL: $test_name"
    else
        echo -e "  ${GREEN}PASS${NC} $test_name"
        PASS=$((PASS + 1))
    fi
}

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ============================================================
# CCProxy Statusline Indicator
# ============================================================
echo ""
echo "=== CCProxy Statusline Indicator ==="

STATUSLINE="$REPO_DIR/plugin/statusline/statusline.sh"
CCPROXY_DIR=$(mktemp -d)
trap 'rm -rf "$CCPROXY_DIR"' EXIT
SAMPLE_INPUT='{"version":"2.0.0","model":{"display_name":"claude-sonnet-4-6"},"context_window":{"used_percentage":15,"current_usage":{"input_tokens":5000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"context_window_size":200000},"cwd":"'"$REPO_DIR"'"}'

OUTPUT=$(echo "$SAMPLE_INPUT" | HOME="$CCPROXY_DIR" bash "$STATUSLINE" 2>/dev/null)
assert_not_contains "$OUTPUT" "⇄" "CCProxy: no indicator when state files absent"

mkdir -p "$CCPROXY_DIR/.config/ccproxy"
printf 'codex\n8000\n' > "$CCPROXY_DIR/.config/ccproxy/active-provider"
echo "$$" > "$CCPROXY_DIR/.config/ccproxy/ccproxy.pid"
OUTPUT=$(echo "$SAMPLE_INPUT" | HOME="$CCPROXY_DIR" bash "$STATUSLINE" 2>/dev/null)
assert_contains "$OUTPUT" "Codex" "CCProxy: shows Codex label when provider=codex"
assert_contains "$OUTPUT" ":8000" "CCProxy: shows port when valid"

printf 'claude\n8000\n' > "$CCPROXY_DIR/.config/ccproxy/active-provider"
OUTPUT=$(echo "$SAMPLE_INPUT" | HOME="$CCPROXY_DIR" bash "$STATUSLINE" 2>/dev/null)
assert_contains "$OUTPUT" "Claude" "CCProxy: shows Claude label when provider=claude"

printf 'codex\n8000\n' > "$CCPROXY_DIR/.config/ccproxy/active-provider"
echo "999999999" > "$CCPROXY_DIR/.config/ccproxy/ccproxy.pid"
OUTPUT=$(echo "$SAMPLE_INPUT" | HOME="$CCPROXY_DIR" bash "$STATUSLINE" 2>/dev/null)
assert_not_contains "$OUTPUT" "⇄" "CCProxy: no indicator when PID is dead"

echo "-1" > "$CCPROXY_DIR/.config/ccproxy/ccproxy.pid"
OUTPUT=$(echo "$SAMPLE_INPUT" | HOME="$CCPROXY_DIR" bash "$STATUSLINE" 2>/dev/null)
assert_not_contains "$OUTPUT" "⇄" "CCProxy: no indicator when PID is non-numeric (-1 guard)"

echo "$$" > "$CCPROXY_DIR/.config/ccproxy/ccproxy.pid"
printf 'codex\nnotaport\n' > "$CCPROXY_DIR/.config/ccproxy/active-provider"
OUTPUT=$(echo "$SAMPLE_INPUT" | HOME="$CCPROXY_DIR" bash "$STATUSLINE" 2>/dev/null)
assert_contains "$OUTPUT" "Codex" "CCProxy: shows label even when port invalid"
assert_not_contains "$OUTPUT" ":notaport" "CCProxy: no port suffix when port non-numeric"

printf 'codex\n99999\n' > "$CCPROXY_DIR/.config/ccproxy/active-provider"
OUTPUT=$(echo "$SAMPLE_INPUT" | HOME="$CCPROXY_DIR" bash "$STATUSLINE" 2>/dev/null)
assert_not_contains "$OUTPUT" ":99999" "CCProxy: no port suffix when port above 65535"

printf 'gemini\n8000\n' > "$CCPROXY_DIR/.config/ccproxy/active-provider"
OUTPUT=$(echo "$SAMPLE_INPUT" | HOME="$CCPROXY_DIR" bash "$STATUSLINE" 2>/dev/null)
assert_contains "$OUTPUT" "⇄" "CCProxy: indicator shown for unknown provider"
assert_contains "$OUTPUT" "gemini" "CCProxy: unknown provider falls through to raw label"

# ============================================================
# RESULTS
# ============================================================
echo ""
echo "=========================================="
echo -e "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
if [ $FAIL -gt 0 ]; then
    echo -e "\nFailures:$ERRORS"
    echo ""
    exit 1
fi
echo "=========================================="
