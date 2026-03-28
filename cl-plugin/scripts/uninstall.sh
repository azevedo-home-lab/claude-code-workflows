#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"

echo "=== CL Plugin Uninstall ==="

# Strip sentinel from complete.md
COMPLETE_MD="$PROJECT_DIR/plugin/commands/complete.md"
if [ -f "$COMPLETE_MD" ] && grep -q 'CL-INJECT-START' "$COMPLETE_MD"; then
  echo "Removing CL trigger from complete.md..."
  # Use awk for cross-platform compatibility (avoids sed -i differences between macOS/GNU)
  awk '/<!-- CL-INJECT-START -->/{skip=1; next} /<!-- CL-INJECT-END -->/{skip=0; next} !skip{print}' \
    "$COMPLETE_MD" > "$COMPLETE_MD.tmp" && mv "$COMPLETE_MD.tmp" "$COMPLETE_MD"
  echo "CL trigger removed"
fi

# Remove state files
echo "Removing state files..."
rm -f "$PROJECT_DIR/.claude/state/cl-state.json"
rm -f "$PROJECT_DIR/.claude/state/cl-state.lock"
rm -f "$PROJECT_DIR/.claude/state/cl-active-rules.json"

# Remove from marketplace.json
MARKETPLACE="$PROJECT_DIR/.claude-plugin/marketplace.json"
if [ -f "$MARKETPLACE" ] && jq -e '.plugins[] | select(.name=="continuous-learning")' "$MARKETPLACE" &>/dev/null; then
  echo "Removing from marketplace.json..."
  jq '.plugins = [.plugins[] | select(.name != "continuous-learning")]' \
    "$MARKETPLACE" > "$MARKETPLACE.tmp" && mv "$MARKETPLACE.tmp" "$MARKETPLACE"
  echo "Removed from marketplace.json"
fi

# Remove symlink
rm -f "$PROJECT_DIR/.claude/commands/evolve.md"
echo "Removed /evolve command symlink"

echo ""
echo "=== CL Plugin Uninstalled ==="
echo "Remove cl-plugin/ directory manually to delete config and prompts."
