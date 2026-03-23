#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PJSON_ROOT="$REPO_ROOT/.claude-plugin/plugin.json"
PJSON_PLUGIN="$REPO_ROOT/plugin/.claude-plugin/plugin.json"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"

# Version sync across all three files
V1=$(jq -r '.plugins[0].version' "$MARKETPLACE")
V2=$(jq -r '.version' "$PJSON_ROOT")
V3=$(jq -r '.version' "$PJSON_PLUGIN")

ERRORS=""

if [[ "$V1" != "$V2" || "$V2" != "$V3" ]]; then
  ERRORS+="✗ Version mismatch:\n"
  ERRORS+="  .claude-plugin/marketplace.json → $V1\n"
  ERRORS+="  .claude-plugin/plugin.json      → $V2\n"
  ERRORS+="  plugin/.claude-plugin/plugin.json → $V3\n"
fi

# Field sync between the two plugin.json files (should be identical)
for field in name description license repository; do
  F_ROOT=$(jq -r --arg f "$field" '.[$f] // ""' "$PJSON_ROOT")
  F_PLUGIN=$(jq -r --arg f "$field" '.[$f] // ""' "$PJSON_PLUGIN")
  if [[ "$F_ROOT" != "$F_PLUGIN" ]]; then
    ERRORS+="✗ Field '$field' mismatch:\n"
    ERRORS+="  .claude-plugin/plugin.json       → $F_ROOT\n"
    ERRORS+="  plugin/.claude-plugin/plugin.json → $F_PLUGIN\n"
  fi
done

if [ -n "$ERRORS" ]; then
  printf '%b' "$ERRORS"
  exit 1
else
  echo "✓ All versions in sync: $V1"
  exit 0
fi
