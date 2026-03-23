# Plugin Conversion & Versioning Design

## Problem

Workflow Manager has no version numbers. Superpowers and Claude-Mem display versions in the status line because they're distributed as Claude Code plugins with versioned directory paths (`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`). Workflow Manager uses a manual `install.sh` that copies scripts into `.claude/hooks/` — no version tracking, no auto-updates, no consistency with the other two components.

Secondary problems the current install model causes:
- Users must manually wire hooks into `.claude/settings.json`
- No upgrade path — re-running `install.sh` overwrites without version awareness
- Hook customization per-project was never documented but is accidentally possible, creating drift risk

## Approaches Considered (DISCUSS phase — diverge)

### Approach A: Repo-is-the-plugin (chosen)

Convert the repository into a single-plugin marketplace following the `thedotmack/claude-mem` pattern exactly. The repo root is the marketplace; a `plugin/` subdirectory contains the distributable plugin.

- **Pros:** Unified versioning with Superpowers and Claude-Mem. Auto-wired hooks (no settings.json injection). Auto-updates via plugin system. Clean separation of development files vs distributed artifact.
- **Cons:** Breaking change for existing `install.sh` users. Per-project hook customization no longer possible. Requires marketplace registration.
- **Source:** Pattern observed in `~/.claude/plugins/marketplaces/thedotmack/` and `~/.claude/plugins/cache/thedotmack/claude-mem/10.4.0/`

### Approach B: Plugin subdirectory (dual distribution)

Keep current `install.sh` working alongside a new `plugin/` directory. Both distribution methods maintained.

- **Pros:** Backwards compatible. No migration required.
- **Cons:** Duplication — scripts and commands exist in two places. Maintenance burden causes drift bugs over time.
- **Source:** N/A — hypothetical hybrid approach

### Approach C: VERSION file only (minimal)

Add a `VERSION` file to the repo. Installer copies it. Status line reads it.

- **Pros:** Trivial to implement. Ships immediately.
- **Cons:** Doesn't solve the manual hook wiring, no auto-updates, doesn't match how the other two components work. Adds a bespoke versioning mechanism when the plugin system already provides one.
- **Source:** Common pattern in shell projects

## Decision (DISCUSS phase — converge)

- **Chosen approach:** A — full plugin conversion following thedotmack/claude-mem pattern
- **Rationale:** Unifies all three components under the same distribution model. The plugin system already solves versioning, hook wiring, and updates. Adding a VERSION file (Approach C) would be a stopgap that doesn't address the root friction.
- **Trade-offs accepted:** Breaking change for existing `install.sh` users (mitigated by migration tool). Per-project hook customization lost (never documented, acceptable).
- **Risks identified:** `$CLAUDE_PLUGIN_ROOT` not available as env var in bash tool (GitHub issue #9354) — mitigated by text substitution in command markdown content. Plugin system API could change.
- **Constraints applied:** Must follow thedotmack/claude-mem structure exactly — single-plugin marketplace, `plugin/` subdirectory, `hooks/hooks.json` for auto-wiring.
- **Tech debt acknowledged:** `install.sh` becomes a migration-only tool. It can be removed once all existing users have migrated to the plugin.

---

## Design

### 1. Repository Structure

The repo restructures into marketplace + plugin:

```
claude-code-workflows/                  # REPO = marketplace
├── .claude-plugin/
│   ├── marketplace.json                # source: "./plugin"
│   └── plugin.json                     # duplicates plugin manifest (required by plugin system)
├── .claude/                            # This repo's own dev config
│   ├── hooks/                          # symlinks to plugin/scripts/ for dogfooding
│   ├── commands/                       # symlinks to plugin/commands/ for dogfooding
│   ├── settings.json
│   ├── settings.local.json
│   └── state/
├── plugin/                             # THE PLUGIN (what gets installed)
│   ├── .claude-plugin/
│   │   └── plugin.json                 # name, version: "1.0.0", author, etc.
│   ├── hooks/
│   │   └── hooks.json                  # auto-wires PreToolUse, PostToolUse
│   ├── commands/
│   │   ├── autonomy.md
│   │   ├── define.md
│   │   ├── discuss.md
│   │   ├── implement.md
│   │   ├── review.md
│   │   └── complete.md
│   ├── scripts/
│   │   ├── workflow-gate.sh
│   │   ├── bash-write-guard.sh
│   │   ├── post-tool-navigator.sh
│   │   ├── workflow-cmd.sh
│   │   ├── workflow-state.sh
│   │   └── setup.sh
│   ├── statusline/
│   │   └── statusline.sh              # Bundled — installed globally by Setup hook
│   └── docs/
│       └── reference/
│           └── professional-standards.md
├── docs/
├── tests/
├── tools/
├── install.sh                          # Repurposed as migration helper only
├── README.md
└── LICENSE
```

### 2. Marketplace Manifest

`.claude-plugin/marketplace.json` (repo root):

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

`.claude-plugin/plugin.json` (repo root — required alongside marketplace.json, matches claude-mem pattern):

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

### 3. Plugin Manifest

`plugin/.claude-plugin/plugin.json` (identical to marketplace root copy):

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

### 4. Hook Auto-Wiring

`plugin/hooks/hooks.json`:

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

The `Setup` hook runs on first plugin activation. It creates `.claude/state/workflow.json` if it doesn't exist (same initialization the current `install.sh` does).

### 5. Script Path Changes

**No functional changes to hook scripts.** They already use `$SCRIPT_DIR` (resolved via `dirname "$0"`) for inter-script sourcing, and `$CLAUDE_PROJECT_DIR` for project-relative state access. Moving from `.claude/hooks/` to `plugin/scripts/` requires zero code changes.

The only updates are cosmetic comments referencing `.claude/hooks/workflow-cmd.sh` → `scripts/workflow-cmd.sh`.

### 6. Command Path Changes — Eliminating Boilerplate

Commands currently repeat verbose boilerplate in every bash snippet:

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && "$WF_DIR/.claude/hooks/workflow-cmd.sh" set_phase "discuss" && "$WF_DIR/.claude/hooks/workflow-cmd.sh" set_active_skill ""
```

This produces noisy Bash tool calls that the user sees every time. The `WF_DIR` resolution is redundant — `workflow-state.sh` (sourced by `workflow-cmd.sh`) already resolves `$CLAUDE_PROJECT_DIR` internally on its own line 12.

**New pattern:** Commands use a short `WF` variable set from `${CLAUDE_PLUGIN_ROOT}` (which Claude Code text-substitutes to the actual path before Claude reads the markdown):

```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh"
"$WF" set_phase "discuss" && "$WF" set_active_skill ""
```

The user sees clean Bash tool calls like:
```
Bash("$WF" set_phase "discuss" && "$WF" set_active_skill "")
```

**How it works:** Claude Code performs inline text replacement of `${CLAUDE_PLUGIN_ROOT}` in all command markdown content before it reaches the model. The resolved absolute path appears in the code block. Known limitation: `$CLAUDE_PLUGIN_ROOT` is NOT available as a runtime environment variable in Bash tool (GitHub issue #9354), but the text substitution handles this since the path is baked into the content Claude reads.

**All commands updated:** Every `/define`, `/discuss`, `/implement`, `/review`, `/complete`, and `/autonomy` command replaces the `WF_DIR=...` boilerplate with the short `WF=...` pattern.

**Professional standards reference:** Commands that instruct Claude to read `docs/reference/professional-standards.md` update to `${CLAUDE_PLUGIN_ROOT}/docs/reference/professional-standards.md`. The text substitution resolves this to the absolute path inside the plugin cache, so Claude can read it regardless of what project the plugin is active in.

### 7. Status Line Versioning

`statusline/statusline.sh` changes to read version from plugin cache directory names for all three components:

```bash
# Workflow Manager: version from plugin cache, phase/autonomy from project state
WM_PLUGIN_DIR="$HOME/.claude/plugins/cache/azevedo-home-lab/workflow-manager"
WM_STATE_FILE="${CWD}/.claude/state/workflow.json"
if [ -d "$WM_PLUGIN_DIR" ]; then
  WM_VERSION=$(ls -1 "$WM_PLUGIN_DIR" | sort -V | tail -1)
  OUTPUT+="  ${DIM}│${RESET}  ${GREEN}Workflow Manager ${WM_VERSION} ✓${RESET}"
  # Phase and autonomy display (reads from project state, same as current)
  if [ -f "$WM_STATE_FILE" ]; then
    WM_PHASE=$(grep -o '"phase"[[:space:]]*:[[:space:]]*"[^"]*"' "$WM_STATE_FILE" | grep -o '"[^"]*"$' | tr -d '"')
    WM_AUTONOMY=$(grep -o '"autonomy_level"[[:space:]]*:[[:space:]]*[0-9]*' "$WM_STATE_FILE" | grep -o '[0-9]*$')
    AUTONOMY_SYM=""
    if [ "$WM_PHASE" != "off" ] && [ -n "$WM_AUTONOMY" ]; then
      case "$WM_AUTONOMY" in
        1) AUTONOMY_SYM="▶ " ;; 2) AUTONOMY_SYM="▶▶ " ;; 3) AUTONOMY_SYM="▶▶▶ " ;;
      esac
    fi
    # Phase color coding (same as current: off=dim, define=blue, discuss=yellow, etc.)
    # ... phase display logic unchanged from current statusline.sh
  fi
else
  OUTPUT+="  ${DIM}│${RESET}  ${DIM}Workflow Manager ✗${RESET}"
fi

# Superpowers: version from plugin cache, active skill from project state
SP_PLUGIN_DIR="$HOME/.claude/plugins/cache/superpowers-marketplace/superpowers"
if [ -d "$SP_PLUGIN_DIR" ]; then
  SP_VERSION=$(ls -1 "$SP_PLUGIN_DIR" | sort -V | tail -1)
  OUTPUT+="  ${DIM}│${RESET}  ${GREEN}Superpowers ${SP_VERSION} ✓${RESET}"
  # Active skill display (reads from project state, same as current)
  if [ -f "$WM_STATE_FILE" ]; then
    ACTIVE_SKILL=$(grep -o '"active_skill"[[:space:]]*:[[:space:]]*"[^"]*"' "$WM_STATE_FILE" | grep -o '"[^"]*"$' | tr -d '"')
    if [ -n "$ACTIVE_SKILL" ]; then
      OUTPUT+=" ${CYAN}[${ACTIVE_SKILL}]${RESET}"
    fi
  fi
else
  OUTPUT+="  ${DIM}│${RESET}  ${DIM}Superpowers ✗${RESET}"
fi

# Claude-Mem: version from plugin cache, observation ID from project state
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

All three components use the same detection pattern: version from plugin cache directory name, runtime state from project's `.claude/state/workflow.json`. The phase/autonomy/skill/observation display logic is preserved from the current statusline — only the detection method changes (plugin cache dir instead of checking for hook files).

### 8. Setup Hook

`plugin/scripts/setup.sh` — runs on first plugin activation. Handles two responsibilities:

**A. Project state initialization** (per-project, runs in `$CLAUDE_PROJECT_DIR`):

```bash
#!/bin/bash
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
STATE_DIR="$PROJECT_DIR/.claude/state"
STATE_FILE="$STATE_DIR/workflow.json"
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Create state directory
mkdir -p "$STATE_DIR"

# Initialize state if missing
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

# Ensure .gitignore excludes state
GITIGNORE="$PROJECT_DIR/.gitignore"
if [ -f "$GITIGNORE" ]; then
  if ! grep -q ".claude/state/" "$GITIGNORE" 2>/dev/null; then
    echo "" >> "$GITIGNORE"
    echo "# Workflow enforcement state (per-session)" >> "$GITIGNORE"
    echo ".claude/state/" >> "$GITIGNORE"
  fi
fi
```

**B. Global statusline installation** (once, writes to `~/.claude/`):

```bash
GLOBAL_SETTINGS="$HOME/.claude/settings.json"
STATUSLINE_DST="$HOME/.claude/statusline.sh"
STATUSLINE_SRC="$PLUGIN_ROOT/statusline/statusline.sh"

# Install statusline
if [ -f "$STATUSLINE_DST" ]; then
  # Back up existing statusline
  cp "$STATUSLINE_DST" "$STATUSLINE_DST.backup"
  echo "Existing statusline backed up to $STATUSLINE_DST.backup"
fi
cp "$STATUSLINE_SRC" "$STATUSLINE_DST"
chmod +x "$STATUSLINE_DST"

# Configure global settings
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
" "$GLOBAL_SETTINGS" "$STATUSLINE_DST" 2>/dev/null
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
```

The statusline is bundled and opinionated — this plugin owns the status line. If an existing statusline is found, it's backed up to `~/.claude/statusline.sh.backup` so the user can recover or merge manually.

### 9. Migration Path

`install.sh` is repurposed as a migration-only tool:

1. **Detection of old installation:** Check for `.claude/hooks/workflow-gate.sh` in the target project
2. **Cleanup:** Remove old hook files, remove hook entries from `.claude/settings.json`
3. **Guidance:** Print instructions to run `/plugin marketplace add azevedo-home-lab/claude-code-workflows` and `/plugin install workflow-manager`

Statusline installation is now handled by the plugin's Setup hook (Section 8B) — no longer part of `install.sh`.

### 10. Dogfooding (This Repo)

The repo's own `.claude/` directory continues to work for development:
- `.claude/hooks/` contains symlinks pointing to `../../plugin/scripts/`
- `.claude/commands/` contains symlinks pointing to `../../plugin/commands/`
- `.claude/settings.json` keeps the existing hook wiring (pointing to the symlinks)

This way, developing on this repo uses the exact same scripts that get distributed as the plugin.

### 11. Version Bumping

Version numbers live in three places (kept in sync):
- `.claude-plugin/marketplace.json` → `plugins[0].version`
- `.claude-plugin/plugin.json` → `version` (marketplace root copy)
- `plugin/.claude-plugin/plugin.json` → `version`

Bumping strategy:
- **Patch** (1.0.x): Bug fixes
- **Minor** (1.x.0): New features, new commands, new hook behaviors
- **Major** (x.0.0): Breaking changes to workflow state format, hook interface changes

Version bumps are manual — update both files before tagging a release. A pre-push hook or CI check can verify they match.

## Outcomes (verifiable)

1. Running `/plugin install workflow-manager@azevedo-home-lab` installs the plugin with hooks auto-wired
2. Status line shows `Workflow Manager 1.0.0 ✓`, `Superpowers X.Y.Z ✓`, `Claude-Mem X.Y.Z ✓`
3. All slash commands (`/define`, `/discuss`, `/implement`, `/review`, `/complete`, `/autonomy`) work from the plugin
4. Phase enforcement (write gates, bash guards, coaching) works identically to current behavior
5. Existing `install.sh` users get a clean migration path
6. `tests/run-tests.sh` passes against the plugin script locations
7. No hook wiring in project `.claude/settings.json` required for end users
