#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
PJSON="$REPO_ROOT/.claude-plugin/plugin.json"

# Version sync between marketplace.json and plugin.json
V1=$(jq -r '.plugins[0].version' "$MARKETPLACE")
V2=$(jq -r '.version' "$PJSON")

if [[ "$V1" != "$V2" ]]; then
  echo "✗ Version mismatch:"
  echo "  .claude-plugin/marketplace.json → $V1"
  echo "  .claude-plugin/plugin.json      → $V2"
  exit 1
else
  echo "✓ All versions in sync: $V1"
  exit 0
fi
