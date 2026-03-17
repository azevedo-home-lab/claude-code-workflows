#!/bin/bash
# Install YubiKey git signing wrappers and touch banner
#
# curl -fsSL https://raw.githubusercontent.com/azevedo-home-lab/claude-code-workflows/main/tools/yubikey-setup/install.sh | bash
# ./install.sh
# ./install.sh --uninstall

set -euo pipefail

REPO_BASE="https://raw.githubusercontent.com/azevedo-home-lab/claude-code-workflows/main/tools/yubikey-setup"
BIN_DIR="$HOME/bin"
SYSTEM_DIR="/usr/local/bin"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }

SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

fetch_file() {
    local filename="$1"
    local dest="$2"
    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$filename" ]; then
        cp "$SCRIPT_DIR/$filename" "$dest"
    else
        curl -fsSL "$REPO_BASE/$filename" -o "$dest"
    fi
}

if [ "${1:-}" = "--uninstall" ]; then
    echo "Uninstalling YubiKey git wrappers..."
    rm -f "$BIN_DIR/git-yubikey"
    sudo rm -f "$SYSTEM_DIR/git-ssh-sign" "$SYSTEM_DIR/git-ssh-auth" "$SYSTEM_DIR/ssh-askpass-wrapper"
    ok "Removed all wrappers"
    echo "Git config entries remain — remove manually if needed:"
    echo "  git config --global --unset gpg.ssh.program"
    echo "  git config --global --unset core.sshCommand"
    exit 0
fi

echo "Installing YubiKey git signing wrappers..."
echo ""

# git-yubikey (touch banner) → ~/bin/
mkdir -p "$BIN_DIR"
fetch_file "git-yubikey" "$BIN_DIR/git-yubikey"
chmod +x "$BIN_DIR/git-yubikey"
ok "git-yubikey installed at $BIN_DIR/git-yubikey"

# SSH wrappers → /usr/local/bin/ (needs sudo)
echo ""
echo "Installing SSH wrappers to $SYSTEM_DIR (requires sudo)..."

for script in git-ssh-sign.sh git-ssh-auth.sh ssh-askpass-wrapper.sh; do
    target="$SYSTEM_DIR/${script%.sh}"
    fetch_file "$script" "/tmp/$script"
    sudo cp "/tmp/$script" "$target"
    sudo chmod +x "$target"
    rm -f "/tmp/$script"
    ok "$target"
done

# Configure git
git config --global gpg.ssh.program "$SYSTEM_DIR/git-ssh-sign"
ok "git config gpg.ssh.program set"

git config --global core.sshCommand "$SYSTEM_DIR/git-ssh-auth"
ok "git config core.sshCommand set"

if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
    warn "$BIN_DIR is not in PATH — add to shell profile:"
    echo "  export PATH=\"\$HOME/bin:\$PATH\""
fi

# Merge snippet into CLAUDE.md if present
CLAUDE_MD="$(git rev-parse --show-toplevel 2>/dev/null)/CLAUDE.md"
if [ -f "$CLAUDE_MD" ]; then
    if grep -q "YubiKey Git Signing" "$CLAUDE_MD"; then
        ok "CLAUDE.md already has YubiKey section"
    else
        echo "" >> "$CLAUDE_MD"
        if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/CLAUDE.md.snippet" ]; then
            cat "$SCRIPT_DIR/CLAUDE.md.snippet" >> "$CLAUDE_MD"
        else
            curl -fsSL "$REPO_BASE/CLAUDE.md.snippet" >> "$CLAUDE_MD"
        fi
        ok "YubiKey section added to $CLAUDE_MD"
    fi
else
    warn "No CLAUDE.md found in project root — snippet not merged"
    echo "  Manually add the contents of CLAUDE.md.snippet to your project's CLAUDE.md"
fi

echo ""
ok "Installation complete!"
echo ""
echo "Usage in Claude Code:"
echo "  git-yubikey commit -m \"message\"    # shows touch banner, then commits"
echo "  git-yubikey push                    # shows touch banner, then pushes"
