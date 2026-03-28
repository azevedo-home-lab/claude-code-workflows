#!/usr/bin/env bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows — CL Plugin.
# See LICENSE for details.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"

echo "=== CL Plugin Setup ==="

# Guard: jq required
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required. Install: brew install jq (macOS) or apt install jq (Linux)" >&2
  exit 1
fi

# Check ANTHROPIC_API_KEY (non-blocking — agents dispatch via Claude Code, not direct API)
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "WARNING: ANTHROPIC_API_KEY not set. Pattern detection agents may fail if Claude Code" >&2
  echo "         is not already authenticated. Do NOT store this key in cl-config.json." >&2
fi

# Check gh auth (non-blocking)
if ! gh auth status &>/dev/null 2>&1; then
  echo "WARNING: gh CLI not authenticated. Issue creation will fail until you run: gh auth login" >&2
fi

# Init state
echo "Initializing state..."
bash "$PLUGIN_ROOT/scripts/evolve.sh" --init

# Gitignore guard
if ! grep -qxF '.claude/state/' "$PROJECT_DIR/.gitignore" 2>/dev/null; then
  printf '\n.claude/state/\n' >> "$PROJECT_DIR/.gitignore"
  echo "Added .claude/state/ to .gitignore"
fi

# Inject sentinel into complete.md using awk (avoids sed escaping issues with embedded shell syntax)
COMPLETE_MD="$PROJECT_DIR/plugin/commands/complete.md"
if [ -f "$COMPLETE_MD" ] && ! grep -q 'CL-INJECT-START' "$COMPLETE_MD"; then
  echo "Injecting CL trigger into complete.md..."
  # Write injection block to a temp file to avoid multiline variable issues with macOS awk
  INJECT_FILE=$(mktemp)
  cat > "$INJECT_FILE" <<'BLOCK'
<!-- CL-INJECT-START -->
If the CL plugin is installed, check whether analysis should run:

```bash
CL_STATUS=$(bash "$(git rev-parse --show-toplevel)/cl-plugin/scripts/evolve.sh" --trigger=complete 2>/dev/null || echo "CL_UNAVAILABLE")
echo "$CL_STATUS"
```

If the output is `CL_READY`, invoke `/evolve` to run the analysis pipeline before closing.
<!-- CL-INJECT-END -->
BLOCK
  # Insert block before the anchor line using awk reading block from file
  # Actual line in complete.md is: Run `/off` to close the workflow.
  awk -v injectfile="$INJECT_FILE" '
    /Run.*\/off.*to close the workflow/ {
      while ((getline line < injectfile) > 0) print line
      close(injectfile)
      print; next
    }
    { print }
  ' "$COMPLETE_MD" > "$COMPLETE_MD.tmp" && mv "$COMPLETE_MD.tmp" "$COMPLETE_MD"
  rm -f "$INJECT_FILE"
  echo "CL trigger injected into complete.md"
else
  echo "complete.md already has CL trigger (or not found)"
fi

# Register in marketplace.json
MARKETPLACE="$PROJECT_DIR/.claude-plugin/marketplace.json"
if [ -f "$MARKETPLACE" ] && ! jq -e '.plugins[] | select(.name=="continuous-learning")' "$MARKETPLACE" &>/dev/null; then
  echo "Registering in marketplace.json..."
  jq '.plugins += [{"name":"continuous-learning","version":"0.1.0","source":"./cl-plugin","description":"Continuous Learning — detects patterns and proposes workflow improvements"}]' \
    "$MARKETPLACE" > "$MARKETPLACE.tmp" && mv "$MARKETPLACE.tmp" "$MARKETPLACE"
  echo "Registered in marketplace.json"
fi

# Symlink evolve command
mkdir -p "$PROJECT_DIR/.claude/commands"
ln -sf "$PLUGIN_ROOT/commands/evolve.md" "$PROJECT_DIR/.claude/commands/evolve.md"
echo "Symlinked /evolve command"

echo ""
echo "=== CL Plugin Ready ==="
echo "Will analyze after every 5 /complete cycles."
echo "Run /evolve to trigger manually."
