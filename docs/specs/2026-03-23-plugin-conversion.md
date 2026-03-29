# Plugin Conversion & Versioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert Workflow Manager from a script-copy installer to a Claude Code plugin following the thedotmack/claude-mem single-plugin marketplace pattern, adding version display to the status line for all three components.

**Architecture:** Repo root becomes a marketplace with `.claude-plugin/marketplace.json`. A `plugin/` subdirectory contains the distributable artifact (hooks, commands, scripts, statusline, docs). The repo's `.claude/` directory uses symlinks to `plugin/` for dogfooding. Version detection in the status line reads from the plugin cache directory structure.

**Tech Stack:** Bash (hooks/scripts), JSON (manifests/hooks.json), Markdown (commands), Python3 (settings.json manipulation in setup.sh)

**Spec:** `docs/superpowers/specs/2026-03-23-plugin-conversion-design.md`

---

### Task 1: Create Plugin Directory Structure and Manifests

**Files:**
- Create: `plugin/.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`
- Create: `.claude-plugin/plugin.json`
- Create: `plugin/hooks/hooks.json`

- [ ] **Step 1: Create plugin/.claude-plugin/plugin.json**

```json
{
  "name": "workflow-manager",
  "version": "1.0.0",
  "description": "Structured workflow enforcement for Claude Code with phase gates, coaching, and autonomy levels",
  "author": {
    "name": "azevedo-home-lab"
  },
  "repository": "https://github.com/azevedo-home-lab/claude-code-workflows",
  "license": "GPL-3.0-only",
  "keywords": [
    "workflow",
    "enforcement",
    "hooks",
    "phases",
    "coaching",
    "autonomy"
  ]
}
```

- [ ] **Step 2: Create .claude-plugin/marketplace.json**

```json
{
  "name": "azevedo-home-lab",
  "owner": {
    "name": "azevedo-home-lab"
  },
  "metadata": {
    "description": "Claude Code Workflow Manager",
    "homepage": "https://github.com/azevedo-home-lab/claude-code-workflows"
  },
  "plugins": [
    {
      "name": "workflow-manager",
      "version": "1.0.0",
      "source": "./plugin",
      "description": "Structured workflow enforcement for Claude Code with phase gates, coaching, and autonomy levels"
    }
  ]
}
```

- [ ] **Step 3: Create .claude-plugin/plugin.json (marketplace root copy)**

Identical content to `plugin/.claude-plugin/plugin.json` from Step 1. This is required by the plugin system — see thedotmack/claude-mem pattern.

- [ ] **Step 4: Create plugin/hooks/hooks.json**

```json
{
  "description": "Workflow Manager enforcement hooks",
  "hooks": {
    "Setup": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-gate.sh"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/bash-write-guard.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/post-tool-navigator.sh"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add plugin/.claude-plugin/plugin.json .claude-plugin/marketplace.json .claude-plugin/plugin.json plugin/hooks/hooks.json
git commit -m "feat: create plugin manifests and hooks.json for marketplace structure"
```

---

### Task 2: Move Scripts to Plugin Directory

**Files:**
- Move: `.claude/hooks/workflow-state.sh` → `plugin/scripts/workflow-state.sh`
- Move: `.claude/hooks/workflow-cmd.sh` → `plugin/scripts/workflow-cmd.sh`
- Move: `.claude/hooks/workflow-gate.sh` → `plugin/scripts/workflow-gate.sh`
- Move: `.claude/hooks/bash-write-guard.sh` → `plugin/scripts/bash-write-guard.sh`
- Move: `.claude/hooks/post-tool-navigator.sh` → `plugin/scripts/post-tool-navigator.sh`
- Create: symlinks in `.claude/hooks/` pointing to `plugin/scripts/`

- [ ] **Step 1: Create plugin/scripts/ and copy scripts**

```bash
mkdir -p plugin/scripts
cp .claude/hooks/workflow-state.sh plugin/scripts/
cp .claude/hooks/workflow-cmd.sh plugin/scripts/
cp .claude/hooks/workflow-gate.sh plugin/scripts/
cp .claude/hooks/bash-write-guard.sh plugin/scripts/
cp .claude/hooks/post-tool-navigator.sh plugin/scripts/
chmod +x plugin/scripts/*.sh
```

- [ ] **Step 2: Update cosmetic comments in plugin/scripts/workflow-cmd.sh**

Change header comments from `.claude/hooks/workflow-cmd.sh` references to `scripts/workflow-cmd.sh`. No functional changes — all `$SCRIPT_DIR` resolution stays the same.

- [ ] **Step 3: Replace .claude/hooks/ files with symlinks**

```bash
rm .claude/hooks/workflow-state.sh .claude/hooks/workflow-cmd.sh .claude/hooks/workflow-gate.sh .claude/hooks/bash-write-guard.sh .claude/hooks/post-tool-navigator.sh
ln -s ../../plugin/scripts/workflow-state.sh .claude/hooks/workflow-state.sh
ln -s ../../plugin/scripts/workflow-cmd.sh .claude/hooks/workflow-cmd.sh
ln -s ../../plugin/scripts/workflow-gate.sh .claude/hooks/workflow-gate.sh
ln -s ../../plugin/scripts/bash-write-guard.sh .claude/hooks/bash-write-guard.sh
ln -s ../../plugin/scripts/post-tool-navigator.sh .claude/hooks/post-tool-navigator.sh
```

- [ ] **Step 4: Verify symlinks work — run existing test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass (symlinks resolve to the same scripts)

- [ ] **Step 5: Commit**

```bash
git add plugin/scripts/ .claude/hooks/
git commit -m "refactor: move hook scripts to plugin/scripts/ with symlinks for dogfooding"
```

---

### Task 3: Move Commands to Plugin Directory

**Files:**
- Move: `.claude/commands/*.md` → `plugin/commands/*.md`
- Modify: all 6 command files (replace `WF_DIR` boilerplate with `WF` shorthand)
- Create: symlinks in `.claude/commands/` pointing to `plugin/commands/`

- [ ] **Step 1: Copy commands to plugin/commands/**

```bash
mkdir -p plugin/commands
cp .claude/commands/define.md plugin/commands/
cp .claude/commands/discuss.md plugin/commands/
cp .claude/commands/implement.md plugin/commands/
cp .claude/commands/review.md plugin/commands/
cp .claude/commands/complete.md plugin/commands/
cp .claude/commands/autonomy.md plugin/commands/
```

- [ ] **Step 2: Update all commands — replace WF_DIR boilerplate with WF shorthand**

In every command file, replace all instances of:
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
```
and
```bash
"$WF_DIR/.claude/hooks/workflow-cmd.sh"
```
with:
```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh"
```
and
```bash
"$WF"
```

For example, `plugin/commands/discuss.md` changes from:
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && "$WF_DIR/.claude/hooks/workflow-cmd.sh" set_phase "discuss" && "$WF_DIR/.claude/hooks/workflow-cmd.sh" set_active_skill ""
```
To:
```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_phase "discuss" && "$WF" set_active_skill ""
```

Apply this transformation to all 6 command files. Each file has multiple bash blocks — update every one.

- [ ] **Step 3: Update professional-standards.md references**

In every command that has `Read docs/reference/professional-standards.md`, change to:
```
Read `${CLAUDE_PLUGIN_ROOT}/docs/reference/professional-standards.md`
```

- [ ] **Step 4: Copy professional-standards.md into plugin**

```bash
mkdir -p plugin/docs/reference
cp docs/reference/professional-standards.md plugin/docs/reference/
```

- [ ] **Step 5: Replace .claude/commands/ files with symlinks**

```bash
rm .claude/commands/define.md .claude/commands/discuss.md .claude/commands/implement.md .claude/commands/review.md .claude/commands/complete.md .claude/commands/autonomy.md
ln -s ../../plugin/commands/define.md .claude/commands/define.md
ln -s ../../plugin/commands/discuss.md .claude/commands/discuss.md
ln -s ../../plugin/commands/implement.md .claude/commands/implement.md
ln -s ../../plugin/commands/review.md .claude/commands/review.md
ln -s ../../plugin/commands/complete.md .claude/commands/complete.md
ln -s ../../plugin/commands/autonomy.md .claude/commands/autonomy.md
```

- [ ] **Step 6: Commit**

```bash
git add plugin/commands/ plugin/docs/ .claude/commands/
git commit -m "refactor: move commands to plugin/commands/ with WF shorthand and symlinks"
```

---

### Task 4: Create Setup Hook

**Files:**
- Create: `plugin/scripts/setup.sh`
- Test: manual verification (setup.sh is run by the plugin system on first activation)

- [ ] **Step 1: Write plugin/scripts/setup.sh**

```bash
#!/bin/bash
# Workflow Manager plugin setup — runs on first activation
# Initializes project state and installs statusline globally
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
STATE_DIR="$PROJECT_DIR/.claude/state"
STATE_FILE="$STATE_DIR/workflow.json"
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- A. Project state initialization ---

mkdir -p "$STATE_DIR"

if [ ! -f "$STATE_FILE" ]; then
  cat > "$STATE_FILE" <<'INIT'
{
  "phase": "off",
  "message_shown": false,
  "active_skill": "",
  "decision_record": "",
  "coaching": {
    "tool_calls_since_agent": 0,
    "layer2_fired": []
  },
  "updated": "auto-initialized by plugin setup"
}
INIT
fi

GITIGNORE="$PROJECT_DIR/.gitignore"
if [ -f "$GITIGNORE" ]; then
  if ! grep -q ".claude/state/" "$GITIGNORE" 2>/dev/null; then
    echo "" >> "$GITIGNORE"
    echo "# Workflow enforcement state (per-session)" >> "$GITIGNORE"
    echo ".claude/state/" >> "$GITIGNORE"
  fi
fi

# --- B. Global statusline installation ---

GLOBAL_SETTINGS="$HOME/.claude/settings.json"
STATUSLINE_DST="$HOME/.claude/statusline.sh"
STATUSLINE_SRC="$PLUGIN_ROOT/statusline/statusline.sh"

if [ -f "$STATUSLINE_SRC" ]; then
  if [ -f "$STATUSLINE_DST" ]; then
    cp "$STATUSLINE_DST" "$STATUSLINE_DST.backup"
  fi
  cp "$STATUSLINE_SRC" "$STATUSLINE_DST"
  chmod +x "$STATUSLINE_DST"

  if [ -f "$GLOBAL_SETTINGS" ]; then
    if ! grep -q "statusline.sh" "$GLOBAL_SETTINGS" 2>/dev/null; then
      python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    settings = json.load(f)
settings['statusLine'] = {
    'type': 'command',
    'command': sys.argv[2],
    'padding': 2
}
with open(sys.argv[1], 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
" "$GLOBAL_SETTINGS" "$STATUSLINE_DST" 2>/dev/null || true
    fi
  else
    mkdir -p "$HOME/.claude"
    cat > "$GLOBAL_SETTINGS" <<SLCFG
{
  "statusLine": {
    "type": "command",
    "command": "$STATUSLINE_DST",
    "padding": 2
  }
}
SLCFG
  fi
fi
```

- [ ] **Step 2: Test setup.sh idempotency**

Run setup.sh twice in a row against a temp directory. Verify:
- First run: creates state file, creates .gitignore entry
- Second run: no errors, state file unchanged, .gitignore not duplicated

```bash
TMPDIR=$(mktemp -d) && mkdir -p "$TMPDIR/.claude/state" && touch "$TMPDIR/.gitignore"
CLAUDE_PROJECT_DIR="$TMPDIR" bash plugin/scripts/setup.sh
CLAUDE_PROJECT_DIR="$TMPDIR" bash plugin/scripts/setup.sh
cat "$TMPDIR/.claude/state/workflow.json"
grep -c ".claude/state/" "$TMPDIR/.gitignore"  # should be 1, not 2
rm -rf "$TMPDIR"
```

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/setup.sh
git commit -m "feat: add plugin setup hook for state initialization and statusline install"
```

---

### Task 5: Move Statusline into Plugin and Add Version Detection

**Files:**
- Move: `statusline/statusline.sh` → `plugin/statusline/statusline.sh`
- Modify: `plugin/statusline/statusline.sh` (add version detection for all 3 components)
- Remove: `statusline/` directory at repo root
- Remove: `statusline/settings.json.example`

- [ ] **Step 1: Write failing test — version detection from plugin cache dirs**

Add to `tests/run-tests.sh` a new test group that verifies the statusline can detect versions from directory names:

```bash
echo ""
echo "=== Statusline Version Detection ==="

# Create mock plugin cache structure
MOCK_CACHE="$TEST_DIR/mock-plugins"
mkdir -p "$MOCK_CACHE/azevedo-home-lab/workflow-manager/1.0.0"
mkdir -p "$MOCK_CACHE/superpowers-marketplace/superpowers/4.1.1"
mkdir -p "$MOCK_CACHE/thedotmack/claude-mem/10.4.0"

# Test: highest version is detected
mkdir -p "$MOCK_CACHE/azevedo-home-lab/workflow-manager/1.1.0"
WM_VERSION=$(ls -1 "$MOCK_CACHE/azevedo-home-lab/workflow-manager" | sort -V | tail -1)
assert_eq "1.1.0" "$WM_VERSION" "Detects highest workflow-manager version"

SP_VERSION=$(ls -1 "$MOCK_CACHE/superpowers-marketplace/superpowers" | sort -V | tail -1)
assert_eq "4.1.1" "$SP_VERSION" "Detects superpowers version"

CM_VERSION=$(ls -1 "$MOCK_CACHE/thedotmack/claude-mem" | sort -V | tail -1)
assert_eq "10.4.0" "$CM_VERSION" "Detects claude-mem version"
```

- [ ] **Step 2: Run test to verify it passes** (these are unit tests of the detection logic)

Run: `bash tests/run-tests.sh`
Expected: New version detection tests PASS

- [ ] **Step 3: Copy statusline to plugin and update detection**

```bash
mkdir -p plugin/statusline
cp statusline/statusline.sh plugin/statusline/statusline.sh
```

Then modify `plugin/statusline/statusline.sh` — replace the three component detection blocks (Workflow Manager, Superpowers, Claude-Mem) with version-aware detection using plugin cache directories. Keep all existing phase/autonomy/skill/observation display logic.

Replace the Workflow Manager detection (currently checks for `$CWD/.claude/hooks/workflow-gate.sh`):

```bash
# Workflow Manager: version from plugin cache, phase/autonomy from project state
WM_PLUGIN_DIR="$HOME/.claude/plugins/cache/azevedo-home-lab/workflow-manager"
WM_STATE_FILE="${CWD}/.claude/state/workflow.json"
if [ -d "$WM_PLUGIN_DIR" ]; then
  WM_VERSION=$(ls -1 "$WM_PLUGIN_DIR" | sort -V | tail -1)
  OUTPUT+="  ${DIM}│${RESET}  ${GREEN}Workflow Manager ${WM_VERSION} ✓${RESET}"
  # Phase display (same logic as current, reading from WM_STATE_FILE)
  if [ -f "$WM_STATE_FILE" ]; then
    WM_PHASE=$(grep -o '"phase"[[:space:]]*:[[:space:]]*"[^"]*"' "$WM_STATE_FILE" | grep -o '"[^"]*"$' | tr -d '"')
    WM_AUTONOMY=$(grep -o '"autonomy_level"[[:space:]]*:[[:space:]]*[0-9]*' "$WM_STATE_FILE" | grep -o '[0-9]*$')
    AUTONOMY_SYM=""
    if [ "$WM_PHASE" != "off" ] && [ -n "$WM_AUTONOMY" ]; then
      case "$WM_AUTONOMY" in
        1) AUTONOMY_SYM="▶ " ;; 2) AUTONOMY_SYM="▶▶ " ;; 3) AUTONOMY_SYM="▶▶▶ " ;;
      esac
    fi
    if [ "$WM_PHASE" = "off" ]; then
      OUTPUT+=" ${DIM}[OFF]${RESET}"
    elif [ "$WM_PHASE" = "define" ]; then
      OUTPUT+=" ${BLUE}${AUTONOMY_SYM}[DEFINE]${RESET}"
    elif [ "$WM_PHASE" = "discuss" ]; then
      OUTPUT+=" ${YELLOW}${AUTONOMY_SYM}[DISCUSS]${RESET}"
    elif [ "$WM_PHASE" = "implement" ]; then
      OUTPUT+=" ${GREEN}${AUTONOMY_SYM}[IMPLEMENT]${RESET}"
    elif [ "$WM_PHASE" = "review" ]; then
      OUTPUT+=" ${CYAN}${AUTONOMY_SYM}[REVIEW]${RESET}"
    elif [ "$WM_PHASE" = "complete" ]; then
      OUTPUT+=" ${MAGENTA}${AUTONOMY_SYM}[COMPLETE]${RESET}"
    fi
  fi
else
  OUTPUT+="  ${DIM}│${RESET}  ${DIM}Workflow Manager ✗${RESET}"
fi
```

Replace Superpowers detection:

```bash
# Superpowers: version from plugin cache
SP_PLUGIN_DIR="$HOME/.claude/plugins/cache/superpowers-marketplace/superpowers"
if [ -d "$SP_PLUGIN_DIR" ]; then
  SP_VERSION=$(ls -1 "$SP_PLUGIN_DIR" | sort -V | tail -1)
  OUTPUT+="  ${DIM}│${RESET}  ${GREEN}Superpowers ${SP_VERSION} ✓${RESET}"
  if [ -f "$WM_STATE_FILE" ]; then
    ACTIVE_SKILL=$(grep -o '"active_skill"[[:space:]]*:[[:space:]]*"[^"]*"' "$WM_STATE_FILE" | grep -o '"[^"]*"$' | tr -d '"')
    if [ -n "$ACTIVE_SKILL" ]; then
      OUTPUT+=" ${CYAN}[${ACTIVE_SKILL}]${RESET}"
    fi
  fi
else
  OUTPUT+="  ${DIM}│${RESET}  ${DIM}Superpowers ✗${RESET}"
fi
```

Replace Claude-Mem detection:

```bash
# Claude-Mem: version from plugin cache
CM_PLUGIN_DIR="$HOME/.claude/plugins/cache/thedotmack/claude-mem"
if [ -d "$CM_PLUGIN_DIR" ]; then
  CM_VERSION=$(ls -1 "$CM_PLUGIN_DIR" | sort -V | tail -1)
  CM_SUFFIX=""
  if [ -f "$WM_STATE_FILE" ]; then
    CM_OBS_ID=$(grep -o '"last_observation_id"[[:space:]]*:[[:space:]]*[0-9]*' "$WM_STATE_FILE" | grep -o '[0-9]*$')
    [ -n "$CM_OBS_ID" ] && CM_SUFFIX=" ${CYAN}#${CM_OBS_ID}${RESET}"
  fi
  OUTPUT+="  ${DIM}│${RESET}  ${GREEN}Claude-Mem ${CM_VERSION} ✓${RESET}${CM_SUFFIX}"
else
  OUTPUT+="  ${DIM}│${RESET}  ${DIM}Claude-Mem ✗${RESET}"
fi
```

- [ ] **Step 4: Remove old statusline/ directory from repo root**

```bash
git rm -r statusline/
```

- [ ] **Step 5: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add plugin/statusline/ tests/run-tests.sh
git commit -m "feat: move statusline into plugin with version detection for all 3 components"
```

---

### Task 6: Update Test Suite for Plugin Paths

**Files:**
- Modify: `tests/run-tests.sh` (change `HOOKS_DIR` to point to `plugin/scripts/`)

- [ ] **Step 1: Update HOOKS_DIR reference**

In `tests/run-tests.sh`, change:
```bash
HOOKS_DIR="$REPO_DIR/.claude/hooks"
```
To:
```bash
HOOKS_DIR="$REPO_DIR/plugin/scripts"
```

The test setup function copies from `$HOOKS_DIR` to `$TEST_DIR/.claude/hooks/`, so all test paths within the test directory remain `.claude/hooks/` — only the source location changes.

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All existing tests pass (scripts are identical, just sourced from `plugin/scripts/`)

- [ ] **Step 3: Commit**

```bash
git add tests/run-tests.sh
git commit -m "test: update test suite to source scripts from plugin/scripts/"
```

---

### Task 7: Rewrite install.sh as Migration Tool

**Files:**
- Modify: `install.sh` (rewrite as migration-only tool)

- [ ] **Step 1: Rewrite install.sh**

Replace the entire file with a migration tool that:
1. Detects old installation (`.claude/hooks/workflow-gate.sh` exists as a regular file, not symlink)
2. Removes old hook files and hook entries from `.claude/settings.json`
3. Prints instructions to install the plugin via marketplace

```bash
#!/bin/bash
# Migration tool — converts old install.sh installations to plugin format
#
# Usage: ./install.sh [target-dir]

set -euo pipefail

TARGET="${1:-$(pwd)}"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }

echo "Workflow Manager Migration Tool"
echo ""

# Check for old installation
OLD_GATE="$TARGET/.claude/hooks/workflow-gate.sh"
if [ -f "$OLD_GATE" ] && [ ! -L "$OLD_GATE" ]; then
    echo "Found old-style installation. Migrating..."
    echo ""

    # Remove old hook files (only regular files, not symlinks)
    for f in workflow-gate.sh bash-write-guard.sh post-tool-navigator.sh workflow-cmd.sh workflow-state.sh; do
        OLD_FILE="$TARGET/.claude/hooks/$f"
        if [ -f "$OLD_FILE" ] && [ ! -L "$OLD_FILE" ]; then
            rm "$OLD_FILE"
            ok "Removed old $f"
        fi
    done

    # Remove hook entries from settings.json
    SETTINGS="$TARGET/.claude/settings.json"
    if [ -f "$SETTINGS" ] && grep -q "workflow-gate.sh" "$SETTINGS" 2>/dev/null; then
        python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    settings = json.load(f)
if 'hooks' in settings:
    del settings['hooks']
with open(sys.argv[1], 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
" "$SETTINGS" 2>/dev/null && ok "Removed hook entries from settings.json" || warn "Could not update settings.json — remove hooks section manually"
    fi

    ok "Migration complete!"
else
    echo "No old-style installation detected."
fi

echo ""
echo "To install the Workflow Manager plugin:"
echo ""
echo "  1. Add the marketplace:"
echo "     /plugin marketplace add azevedo-home-lab/claude-code-workflows"
echo ""
echo "  2. Install the plugin:"
echo "     /plugin install workflow-manager"
echo ""
echo "The plugin auto-wires hooks, installs the statusline, and initializes project state."
```

- [ ] **Step 2: Commit**

```bash
git add install.sh
git commit -m "refactor: rewrite install.sh as migration-only tool for plugin conversion"
```

---

### Task 8: Version Sync Check Script

**Files:**
- Create: `scripts/check-version-sync.sh`

- [ ] **Step 1: Write version sync checker**

```bash
#!/bin/bash
# Verify version numbers are in sync across all three manifest files
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

V1=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/.claude-plugin/marketplace.json'))['plugins'][0]['version'])")
V2=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/.claude-plugin/plugin.json'))['version'])")
V3=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/plugin/.claude-plugin/plugin.json'))['version'])")

if [ "$V1" = "$V2" ] && [ "$V2" = "$V3" ]; then
    echo "✓ All versions in sync: $V1"
    exit 0
else
    echo "✗ Version mismatch!"
    echo "  .claude-plugin/marketplace.json: $V1"
    echo "  .claude-plugin/plugin.json:      $V2"
    echo "  plugin/.claude-plugin/plugin.json: $V3"
    exit 1
fi
```

- [ ] **Step 2: Write test for version sync**

Add to `tests/run-tests.sh`:

```bash
echo ""
echo "=== Version Sync ==="
SYNC_OUTPUT=$(bash "$REPO_DIR/scripts/check-version-sync.sh" 2>&1)
SYNC_EXIT=$?
assert_eq "0" "$SYNC_EXIT" "Version sync check passes"
assert_contains "$SYNC_OUTPUT" "All versions in sync" "Version sync reports success"
```

- [ ] **Step 3: Run tests**

Run: `bash tests/run-tests.sh`
Expected: Version sync tests PASS

- [ ] **Step 4: Commit**

```bash
git add scripts/check-version-sync.sh tests/run-tests.sh
git commit -m "feat: add version sync checker for the three manifest files"
```

---

### Task 9: Update README and Documentation

**Files:**
- Modify: `README.md` (update installation instructions)
- Modify: `docs/guides/statusline-guide.md` (update paths)
- Modify: `docs/guides/getting-started.md` (if it references install.sh)
- Remove: `uninstall.sh` (no longer applicable — plugin system handles uninstall)

- [ ] **Step 1: Update README.md installation section**

Replace the `install.sh` instructions with plugin installation:

```markdown
## Installation

### As a Claude Code Plugin (recommended)

1. Add the marketplace:
   ```
   /plugin marketplace add azevedo-home-lab/claude-code-workflows
   ```

2. Install the plugin:
   ```
   /plugin install workflow-manager
   ```

The plugin auto-wires hooks, installs the statusline, and initializes project state. No manual configuration needed.

### Migrating from install.sh

If you previously installed via `install.sh`, run the migration tool first:
```bash
./install.sh
```
This removes old hook files and settings, then guides you to install the plugin.
```

- [ ] **Step 2: Update docs/guides/statusline-guide.md**

Update the installation section — the statusline is now bundled with the plugin and installed automatically by the Setup hook. Remove the manual `cp` and `settings.json` instructions. Keep the customization and testing sections.

- [ ] **Step 3: Remove uninstall.sh**

```bash
git rm uninstall.sh
```

- [ ] **Step 4: Commit**

```bash
git add README.md docs/guides/statusline-guide.md
git rm uninstall.sh
git commit -m "docs: update installation instructions for plugin distribution"
```

---

### Task 10: Final Integration Test

**Files:**
- Modify: `tests/run-tests.sh` (add integration tests)

- [ ] **Step 1: Add integration tests for plugin structure**

Add to `tests/run-tests.sh`:

```bash
echo ""
echo "=== Plugin Structure ==="

# Verify all required plugin files exist
assert_eq "true" "$([ -f "$REPO_DIR/plugin/.claude-plugin/plugin.json" ] && echo true || echo false)" "plugin/.claude-plugin/plugin.json exists"
assert_eq "true" "$([ -f "$REPO_DIR/.claude-plugin/marketplace.json" ] && echo true || echo false)" ".claude-plugin/marketplace.json exists"
assert_eq "true" "$([ -f "$REPO_DIR/.claude-plugin/plugin.json" ] && echo true || echo false)" ".claude-plugin/plugin.json exists"
assert_eq "true" "$([ -f "$REPO_DIR/plugin/hooks/hooks.json" ] && echo true || echo false)" "plugin/hooks/hooks.json exists"
assert_eq "true" "$([ -f "$REPO_DIR/plugin/scripts/setup.sh" ] && echo true || echo false)" "plugin/scripts/setup.sh exists"
assert_eq "true" "$([ -f "$REPO_DIR/plugin/statusline/statusline.sh" ] && echo true || echo false)" "plugin/statusline/statusline.sh exists"
assert_eq "true" "$([ -f "$REPO_DIR/plugin/docs/reference/professional-standards.md" ] && echo true || echo false)" "plugin/docs/reference/professional-standards.md exists"

# Verify all 6 commands exist
for cmd in define discuss implement review complete autonomy; do
  assert_eq "true" "$([ -f "$REPO_DIR/plugin/commands/$cmd.md" ] && echo true || echo false)" "plugin/commands/$cmd.md exists"
done

# Verify all 5 scripts exist
for script in workflow-state.sh workflow-cmd.sh workflow-gate.sh bash-write-guard.sh post-tool-navigator.sh; do
  assert_eq "true" "$([ -f "$REPO_DIR/plugin/scripts/$script" ] && echo true || echo false)" "plugin/scripts/$script exists"
done

# Verify symlinks in .claude/ point to plugin/
for script in workflow-state.sh workflow-cmd.sh workflow-gate.sh bash-write-guard.sh post-tool-navigator.sh; do
  assert_eq "true" "$([ -L "$REPO_DIR/.claude/hooks/$script" ] && echo true || echo false)" ".claude/hooks/$script is a symlink"
done
for cmd in define discuss implement review complete autonomy; do
  assert_eq "true" "$([ -L "$REPO_DIR/.claude/commands/$cmd.md" ] && echo true || echo false)" ".claude/commands/$cmd.md is a symlink"
done

# Verify commands no longer contain WF_DIR boilerplate
for cmd in define discuss implement review complete autonomy; do
  BOILERPLATE_COUNT=$(grep -c 'CLAUDE_PROJECT_DIR.*git rev-parse' "$REPO_DIR/plugin/commands/$cmd.md" || true)
  assert_eq "0" "$BOILERPLATE_COUNT" "plugin/commands/$cmd.md has no WF_DIR boilerplate"
done

# Verify hooks.json references ${CLAUDE_PLUGIN_ROOT}
assert_contains "$(cat "$REPO_DIR/plugin/hooks/hooks.json")" 'CLAUDE_PLUGIN_ROOT' "hooks.json uses CLAUDE_PLUGIN_ROOT"
```

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: ALL tests pass — both existing enforcement tests and new plugin structure tests

- [ ] **Step 3: Commit**

```bash
git add tests/run-tests.sh
git commit -m "test: add integration tests for plugin structure and command boilerplate removal"
```

---

### Task 11: Update .gitignore and Clean Up

**Files:**
- Modify: `.gitignore` (add plugin cache exclusions if needed)
- Verify: no stale references to old paths remain

- [ ] **Step 1: Grep for stale path references**

```bash
grep -r '\.claude/hooks/workflow' --include='*.sh' --include='*.md' --include='*.json' . | grep -v plugin/ | grep -v .git/ | grep -v tests/ | grep -v node_modules/ | grep -v docs/superpowers/
```

Expected: No results (all references should be in `plugin/` or test fixtures)

- [ ] **Step 2: Fix any stale references found**

If any files outside `plugin/` still reference `.claude/hooks/workflow-*`, update them.

- [ ] **Step 3: Final full test run**

Run: `bash tests/run-tests.sh`
Expected: ALL tests pass

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: clean up stale path references after plugin conversion"
```
