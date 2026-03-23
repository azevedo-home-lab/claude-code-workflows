#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

V1=$(jq -r '.plugins[0].version' "$REPO_ROOT/.claude-plugin/marketplace.json")
V2=$(jq -r '.version' "$REPO_ROOT/.claude-plugin/plugin.json")
V3=$(jq -r '.version' "$REPO_ROOT/plugin/.claude-plugin/plugin.json")

if [[ "$V1" == "$V2" && "$V2" == "$V3" ]]; then
  echo "✓ All versions in sync: $V1"
  exit 0
else
  echo "✗ Version mismatch detected:"
  echo "  .claude-plugin/marketplace.json → $V1"
  echo "  .claude-plugin/plugin.json      → $V2"
  echo "  plugin/.claude-plugin/plugin.json → $V3"
  exit 1
fi
