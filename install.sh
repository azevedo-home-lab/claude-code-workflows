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

# Save installer and optional feature files for re-running with flags
cp "$SCRIPT_DIR/install.sh" "$TARGET/.claude/install.sh"
chmod +x "$TARGET/.claude/install.sh"
cp "$SCRIPT_DIR/claude.md.template" "$TARGET/.claude/claude.md.template"
if [ -d "$SCRIPT_DIR/tools/yubikey-setup" ]; then
    mkdir -p "$TARGET/.claude/tools/yubikey-setup"
    cp "$SCRIPT_DIR/tools/yubikey-setup/git-yubikey" "$TARGET/.claude/tools/yubikey-setup/"
    cp "$SCRIPT_DIR/tools/yubikey-setup/CLAUDE.md.snippet" "$TARGET/.claude/tools/yubikey-setup/"
fi
if [ -d "$SCRIPT_DIR/tools/iterm-launcher" ]; then
    mkdir -p "$TARGET/.claude/tools/iterm-launcher"
    cp "$SCRIPT_DIR/tools/iterm-launcher/install.sh" "$TARGET/.claude/tools/iterm-launcher/"
    cp "$SCRIPT_DIR/tools/iterm-launcher/launch-claude-iterm.sh" "$TARGET/.claude/tools/iterm-launcher/"
    cp "$SCRIPT_DIR/tools/iterm-launcher/claude-code-profile.json" "$TARGET/.claude/tools/iterm-launcher/"
fi

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

# Initialize workflow state to OFF phase (only if not already set)
if [ ! -f "$TARGET/.claude/state/phase.json" ]; then
    cat > "$TARGET/.claude/state/phase.json" <<'INIT'
{
  "phase": "off",
  "message_shown": false,
  "updated": "auto-initialized by installer"
}
INIT
    ok "Initialized workflow state to OFF phase"
else
    ok "Workflow state preserved ($(grep -o '"phase": "[^"]*"' "$TARGET/.claude/state/phase.json"))"
fi

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

    # Build allowed merge tags based on selected flags
    MERGE_TAGS="always,claude-md,claude-mem"
    $OPT_YUBIKEY && MERGE_TAGS="$MERGE_TAGS,yubikey"

    if [ -f "$CLAUDE_MD" ]; then
        # Merge missing sections using python3, filtered by merge tags
        python3 -c "
import sys, re

template_path = sys.argv[1]
target_path = sys.argv[2]
allowed_tags = set(sys.argv[3].split(','))

with open(template_path) as f:
    template = f.read()
with open(target_path) as f:
    existing = f.read()

# Split into sections, keeping the merge comment that precedes each ## heading
# Each section starts with an optional <!-- merge: tag --> followed by ## heading
chunks = re.split(r'(?=<!-- merge:)', template)

added = []
for chunk in chunks:
    chunk = chunk.strip()
    if not chunk:
        continue

    # Extract merge tag
    tag_match = re.match(r'<!-- merge:\s*(\S+)\s*-->', chunk)
    if not tag_match:
        continue
    tag = tag_match.group(1)

    # Skip sections not matching selected flags
    if tag not in allowed_tags:
        continue

    # Extract heading
    heading_match = re.search(r'^## (.+)', chunk, re.MULTILINE)
    if not heading_match:
        continue
    heading = heading_match.group(1).strip()

    # Check if heading already exists in target
    heading_text = re.sub(r'[^\w\s]', '', heading).strip().lower()
    found = False
    for line in existing.splitlines():
        if line.startswith('## '):
            existing_text = re.sub(r'[^\w\s]', '', line[3:]).strip().lower()
            if heading_text == existing_text:
                found = True
                break
    if not found:
        # Strip the merge comment before appending
        clean_section = re.sub(r'<!-- merge:\s*\S+\s*-->\n?', '', chunk).strip()
        added.append(heading)
        with open(target_path, 'a') as f:
            f.write('\n\n' + clean_section + '\n')

if added:
    print('Added sections: ' + ', '.join(added))
else:
    print('All template sections already present')
" "$TEMPLATE" "$CLAUDE_MD" "$MERGE_TAGS"
        ok "CLAUDE.md template merged"
    else
        # New file — filter template by allowed tags, strip merge comments
        python3 -c "
import sys, re

template_path = sys.argv[1]
target_path = sys.argv[2]
allowed_tags = set(sys.argv[3].split(','))

with open(template_path) as f:
    template = f.read()

chunks = re.split(r'(?=<!-- merge:)', template)
output = []

# Keep the title (before first merge comment)
title_match = re.match(r'(.*?)(?=<!-- merge:)', template, re.DOTALL)
if title_match:
    title = title_match.group(1).strip()
    if title:
        output.append(title)

for chunk in chunks:
    chunk = chunk.strip()
    if not chunk:
        continue
    tag_match = re.match(r'<!-- merge:\s*(\S+)\s*-->', chunk)
    if not tag_match:
        continue
    if tag_match.group(1) not in allowed_tags:
        continue
    clean = re.sub(r'<!-- merge:\s*\S+\s*-->\n?', '', chunk).strip()
    output.append(clean)

with open(target_path, 'w') as f:
    f.write('\n\n'.join(output) + '\n')
" "$TEMPLATE" "$CLAUDE_MD" "$MERGE_TAGS"
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
    echo "  Optional features (re-run installer with flags)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  --claude-md   Merge CLAUDE.md template (behavioral rules, security, claude-mem)"
    echo "  --iterm       iTerm launcher with VSCode/Zed keybindings (macOS)"
    echo "  --yubikey     git-yubikey touch banner wrapper (macOS)"
    echo "  --all         Install all optional features"
    echo ""
    echo "  .claude/install.sh --claude-md --yubikey"
fi

# Clean up installer artifacts after optional features are installed
if $ANY_OPT; then
    rm -f "$TARGET/.claude/install.sh"
    rm -f "$TARGET/.claude/claude.md.template"
    rm -rf "$TARGET/.claude/tools"
    ok "Cleaned up installer artifacts"
fi

echo ""
echo "Restart Claude Code to activate hooks."
