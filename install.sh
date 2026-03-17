#!/bin/bash
# Install Claude Code Workflow Manager into the current project
#
# Usage:
#   ./install.sh [target-dir] [options]
#   curl -fsSL .../install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --claude-md --iterm --yubikey
#   curl -fsSL .../install.sh | bash -s -- --all
#
# Options:
#   --claude-md   Merge CLAUDE.md template into project (or create if missing)
#   --iterm       Install iTerm launcher with IDE keybindings
#   --yubikey     Install git-yubikey banner wrapper (banner only, not signing wrappers)
#   --all         Install all optional features

set -euo pipefail

# Parse arguments — first non-flag arg is target dir, rest are flags
TARGET=""
OPT_CLAUDE_MD=false
OPT_ITERM=false
OPT_YUBIKEY=false

for arg in "$@"; do
    case "$arg" in
        --claude-md) OPT_CLAUDE_MD=true ;;
        --iterm)     OPT_ITERM=true ;;
        --yubikey)   OPT_YUBIKEY=true ;;
        --all)       OPT_CLAUDE_MD=true; OPT_ITERM=true; OPT_YUBIKEY=true ;;
        --*)         echo "Unknown option: $arg"; exit 1 ;;
        *)           TARGET="$arg" ;;
    esac
done

TARGET="${TARGET:-$(pwd)}"

# Determine source directory (where the hook files live)
# BASH_SOURCE is unset when piped from curl, so handle that case
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR=""
fi

# If running via curl pipe (or source not found), clone the repo to a temp dir
if [ -z "$SCRIPT_DIR" ] || [ ! -f "$SCRIPT_DIR/.claude/hooks/workflow-gate.sh" ]; then
    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT
    echo "Downloading Workflow Manager..."
    git clone --depth 1 --quiet https://github.com/azevedo-home-lab/claude-code-workflows.git "$TMPDIR"
    SCRIPT_DIR="$TMPDIR"
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }

echo "Installing Workflow Manager into: $TARGET"
echo ""

# Validate target is a git repo
if [ ! -d "$TARGET/.git" ]; then
    echo "ERROR: $TARGET is not a git repository."
    echo "Run this from your project root or pass the project path as an argument."
    exit 1
fi

# ============================================================
# Core install — always runs
# ============================================================

# Create directories
mkdir -p "$TARGET/.claude/hooks"
mkdir -p "$TARGET/.claude/commands"
mkdir -p "$TARGET/.claude/state"

# Copy hooks
cp "$SCRIPT_DIR/.claude/hooks/workflow-state.sh" "$TARGET/.claude/hooks/"
cp "$SCRIPT_DIR/.claude/hooks/workflow-gate.sh" "$TARGET/.claude/hooks/"
cp "$SCRIPT_DIR/.claude/hooks/bash-write-guard.sh" "$TARGET/.claude/hooks/"
cp "$SCRIPT_DIR/.claude/hooks/post-tool-navigator.sh" "$TARGET/.claude/hooks/"
chmod +x "$TARGET/.claude/hooks/"*.sh

# Copy commands
cp "$SCRIPT_DIR/.claude/commands/approve.md" "$TARGET/.claude/commands/"
cp "$SCRIPT_DIR/.claude/commands/discuss.md" "$TARGET/.claude/commands/"
cp "$SCRIPT_DIR/.claude/commands/review.md" "$TARGET/.claude/commands/"
cp "$SCRIPT_DIR/.claude/commands/complete.md" "$TARGET/.claude/commands/"
cp "$SCRIPT_DIR/.claude/commands/override.md" "$TARGET/.claude/commands/"

ok "Copied hooks and commands"

# Handle settings.json — merge hooks into existing config or create new
SETTINGS="$TARGET/.claude/settings.json"

if [ -f "$SETTINGS" ]; then
    if grep -q "workflow-gate.sh" "$SETTINGS" 2>/dev/null; then
        ok "Hooks already configured in settings.json"
    else
        python3 -c "
import json, sys

with open(sys.argv[1]) as f:
    settings = json.load(f)

hooks = settings.setdefault('hooks', {})

# PreToolUse entries
pre = hooks.setdefault('PreToolUse', [])
gate_entry = {
    'matcher': 'Write|Edit|MultiEdit|NotebookEdit',
    'hooks': [{'type': 'command', 'command': '\$CLAUDE_PROJECT_DIR/.claude/hooks/workflow-gate.sh'}]
}
bash_entry = {
    'matcher': 'Bash',
    'hooks': [{'type': 'command', 'command': '\$CLAUDE_PROJECT_DIR/.claude/hooks/bash-write-guard.sh'}]
}
pre.append(gate_entry)
pre.append(bash_entry)

# PostToolUse entry
post = hooks.setdefault('PostToolUse', [])
nav_entry = {
    'hooks': [{'type': 'command', 'command': '\$CLAUDE_PROJECT_DIR/.claude/hooks/post-tool-navigator.sh'}]
}
post.append(nav_entry)

with open(sys.argv[1], 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
" "$SETTINGS"
        ok "Merged workflow hooks into existing settings.json"
    fi
else
    cat > "$SETTINGS" <<'HOOKSCFG'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/workflow-gate.sh"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/bash-write-guard.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/post-tool-navigator.sh"
          }
        ]
      }
    ]
  }
}
HOOKSCFG
    ok "Created settings.json with hooks"
fi

# Update .gitignore
GITIGNORE="$TARGET/.gitignore"
if [ -f "$GITIGNORE" ]; then
    if ! grep -q ".claude/state/" "$GITIGNORE" 2>/dev/null; then
        echo "" >> "$GITIGNORE"
        echo "# Workflow enforcement state (per-session)" >> "$GITIGNORE"
        echo ".claude/state/" >> "$GITIGNORE"
        ok "Added .claude/state/ to .gitignore"
    fi
else
    echo "# Workflow enforcement state (per-session)" > "$GITIGNORE"
    echo ".claude/state/" >> "$GITIGNORE"
    ok "Created .gitignore with .claude/state/"
fi

# Initialize workflow state to OFF phase (no enforcement)
cat > "$TARGET/.claude/state/phase.json" <<'INIT'
{
  "phase": "off",
  "message_shown": false,
  "updated": "auto-initialized by installer"
}
INIT
ok "Initialized workflow state to OFF phase"

# Install statusline globally
GLOBAL_SETTINGS="$HOME/.claude/settings.json"
STATUSLINE_DST="$HOME/.claude/statusline.sh"

cp "$SCRIPT_DIR/statusline/statusline.sh" "$STATUSLINE_DST"
chmod +x "$STATUSLINE_DST"
ok "Installed statusline to $STATUSLINE_DST"

if [ -f "$GLOBAL_SETTINGS" ]; then
    if grep -q "statusline.sh" "$GLOBAL_SETTINGS" 2>/dev/null; then
        ok "Statusline already configured in global settings"
    else
        python3 -c "
import json, sys
with open('$GLOBAL_SETTINGS') as f:
    settings = json.load(f)
settings['statusLine'] = {
    'type': 'command',
    'command': '$STATUSLINE_DST',
    'padding': 2
}
with open('$GLOBAL_SETTINGS', 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
" 2>/dev/null && ok "Added statusLine to global settings" || warn "Could not update global settings — add statusLine manually"
    fi
else
    cat > "$GLOBAL_SETTINGS" <<SLCFG
{
  "statusLine": {
    "type": "command",
    "command": "$STATUSLINE_DST",
    "padding": 2
  }
}
SLCFG
    ok "Created global settings with statusLine"
fi

echo ""
ok "Workflow Manager installed!"
echo ""
echo "Usage:"
echo "  /discuss    — start workflow (brainstorming, edits blocked)"
echo "  /approve    — unlock code edits (after plan is approved)"
echo "  /review     — run multi-agent review pipeline"
echo "  /complete   — verified completion (back to off)"
echo "  /override   — jump to any phase (off/discuss/implement/review)"
echo ""
echo "Sessions start in OFF phase (no enforcement). Use /discuss to begin a workflow."

# ============================================================
# Optional features — run if flags set, otherwise show menu
# ============================================================

ANY_OPT=false
$OPT_CLAUDE_MD || $OPT_ITERM || $OPT_YUBIKEY && ANY_OPT=true

# --- CLAUDE.md template ---
if $OPT_CLAUDE_MD; then
    echo ""
    echo "━━━ CLAUDE.md template ━━━"
    CLAUDE_MD="$TARGET/CLAUDE.md"
    TEMPLATE="$SCRIPT_DIR/claude.md.template"
    if [ -f "$CLAUDE_MD" ]; then
        # Merge missing sections using python3
        python3 -c "
import sys

template_path = sys.argv[1]
target_path = sys.argv[2]

with open(template_path) as f:
    template = f.read()
with open(target_path) as f:
    existing = f.read()

# Extract sections from template (## headings)
import re
sections = re.split(r'(?=^## )', template, flags=re.MULTILINE)

added = []
for section in sections:
    if not section.strip():
        continue
    # Get the heading
    heading_match = re.match(r'## (.+)', section)
    if not heading_match:
        continue
    heading = heading_match.group(1).strip()
    # Skip the title line (not a section)
    if 'TEMPLATE' in heading:
        continue
    # Check if this section already exists in target
    # Match by key words in the heading (ignore emoji differences)
    key_words = re.sub(r'[^\w\s]', '', heading).strip().lower().split()
    found = False
    for word in key_words:
        if len(word) > 3 and word.lower() in existing.lower():
            found = True
            break
    if not found:
        added.append(heading)
        with open(target_path, 'a') as f:
            f.write('\n' + section)

if added:
    print('Added sections: ' + ', '.join(added))
else:
    print('All template sections already present')
" "$TEMPLATE" "$CLAUDE_MD"
        ok "CLAUDE.md template merged"
    else
        cp "$TEMPLATE" "$CLAUDE_MD"
        ok "Created CLAUDE.md from template"
    fi
fi

# --- iTerm launcher ---
if $OPT_ITERM; then
    echo ""
    echo "━━━ iTerm Launcher ━━━"
    if [ "$(uname)" != "Darwin" ]; then
        warn "iTerm launcher is macOS only — skipping"
    else
        bash "$SCRIPT_DIR/tools/iterm-launcher/install.sh"
    fi
fi

# --- YubiKey banner ---
if $OPT_YUBIKEY; then
    echo ""
    echo "━━━ YubiKey Git Banner ━━━"
    if [ "$(uname)" != "Darwin" ]; then
        warn "YubiKey setup is macOS only — skipping"
    else
        # Install only git-yubikey banner — not the signing wrappers
        mkdir -p "$HOME/bin"
        cp "$SCRIPT_DIR/tools/yubikey-setup/git-yubikey" "$HOME/bin/git-yubikey"
        chmod +x "$HOME/bin/git-yubikey"
        ok "git-yubikey installed at ~/bin/git-yubikey"

        # Merge CLAUDE.md snippet if project has CLAUDE.md
        CLAUDE_MD="$TARGET/CLAUDE.md"
        if [ -f "$CLAUDE_MD" ]; then
            if grep -q "YubiKey Git Signing" "$CLAUDE_MD"; then
                ok "CLAUDE.md already has YubiKey section"
            else
                echo "" >> "$CLAUDE_MD"
                cat "$SCRIPT_DIR/tools/yubikey-setup/CLAUDE.md.snippet" >> "$CLAUDE_MD"
                ok "YubiKey section added to CLAUDE.md"
            fi
        fi

        if ! echo "$PATH" | tr ':' '\n' | grep -qx "$HOME/bin"; then
            warn "~/bin is not in PATH — add to shell profile:"
            echo "  export PATH=\"\$HOME/bin:\$PATH\""
        fi
    fi
fi

# --- Show optional features menu if none were selected ---
if ! $ANY_OPT; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Optional features (re-run with flags to install)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  --claude-md   Merge CLAUDE.md template (behavioral rules, security, claude-mem)"
    echo "  --iterm       iTerm launcher with VSCode/Zed keybindings (macOS)"
    echo "  --yubikey     git-yubikey touch banner wrapper (macOS)"
    echo "  --all         Install all optional features"
    echo ""
    echo "  Example: ./install.sh --claude-md --yubikey"
fi

echo ""
echo "Restart Claude Code to activate hooks."
