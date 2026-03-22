# YubiKey Git Signing Setup for Claude Code

Git commit signing and push authentication via YubiKey FIDO2. No-touch signing, one-touch-per-session push, presence-gated git operations.

## What It Does

- **git-yubikey**: Git wrapper with tiered YubiKey enforcement. Checks presence (blocks all git if absent), passes safe commands through silently, and requires confirmation for destructive operations (push --force, push --delete, branch -D/-M).
- **git-ssh-sign**: Bypasses macOS ssh-agent to sign commits directly via YubiKey (libfido2).
- **git-ssh-auth**: Bypasses macOS ssh-agent to authenticate push/pull directly via YubiKey.
- **ssh-askpass-wrapper**: Filters SSH askpass popups — only allows git signing and GitHub auth.
- **CLAUDE.md.snippet**: YubiKey section to merge into your project's CLAUDE.md so Claude Code knows to use `git-yubikey`.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/azevedo-home-lab/claude-code-workflows/main/tools/yubikey-setup/install.sh | bash
```

Or from a local clone:

```bash
cd tools/yubikey-setup
./install.sh
./install.sh --uninstall
```

The installer:
1. Installs `git-yubikey` to `~/bin/`
2. Installs SSH wrappers to `/usr/local/bin/` (requires sudo)
3. Configures `git config --global` for signing and auth
4. Merges the YubiKey section into your project's `CLAUDE.md` (if present)

## Key Setup

Two SSH keys work together: a **no-touch key** for commit signing (no tap needed) and the **original touch key** for push authentication (GitHub requires user presence for SSH auth).

SSH connection multiplexing means you only touch once per session — the first push opens a persistent connection that subsequent pushes reuse for 10 minutes.

```bash
# Generate no-touch key for signing (one-time, requires YubiKey PIN)
ssh-keygen -t ed25519-sk -O no-touch-required -O resident -C "yubikey-no-touch" -f ~/.ssh/id_ed25519_sk_no_touch

# Register on GitHub (both signing AND authentication):
gh ssh-key add ~/.ssh/id_ed25519_sk_no_touch.pub --title "yubikey-no-touch (signing)" --type signing
gh ssh-key add ~/.ssh/id_ed25519_sk_no_touch.pub --title "yubikey-no-touch (auth)" --type authentication

# Configure git to sign with the no-touch key:
git config --global user.signingkey ~/.ssh/id_ed25519_sk_no_touch.pub

# Create allowed_signers:
echo "$(git config --global user.email) $(cat ~/.ssh/id_ed25519_sk_no_touch.pub)" > ~/.ssh/allowed_signers
git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers

# Enable SSH connection multiplexing for GitHub:
# Add to ~/.ssh/config under Host github.com:
#   ControlMaster auto
#   ControlPath ~/.ssh/sockets/%r@%h-%p
#   ControlPersist 600
mkdir -p ~/.ssh/sockets && chmod 700 ~/.ssh/sockets
```

### How the two keys work

| Operation | Key used | Touch? | Why |
|-----------|----------|--------|-----|
| `git commit` (signing) | no-touch key | No | Git signing uses `ssh-keygen` locally — no server policy |
| `git push` (first in session) | touch key | Yes | GitHub requires FIDO2 user presence for SSH auth |
| `git push` (subsequent) | reused connection | No | SSH multiplexing reuses the authenticated connection |
| YubiKey unplugged | — | — | `git-yubikey` blocks all git operations |

## Prerequisites

- macOS with YubiKey FIDO2 key already set up (ed25519-sk resident key)
- `/usr/local/lib/sk-libfido2.dylib` built from openssh-portable (required because Apple's system SSH lacks FIDO2 support)
- Public key registered on GitHub as both authentication and signing key

This tool installs the **wrappers and banner** — it does not set up the YubiKey itself. For initial YubiKey provisioning (generating keys, registering on GitHub, building sk-libfido2.dylib), see your project's YubiKey setup documentation.

## Usage

Use `git-yubikey` instead of `git` for all git operations:

```bash
git-yubikey commit -m "my message"    # passes through (no touch needed)
git-yubikey push origin main          # passes through (no touch needed)
git-yubikey push --force origin main  # shows DESTRUCTIVE warning, asks confirmation
git-yubikey branch -D old-branch      # shows DESTRUCTIVE warning, asks confirmation
git-yubikey log                       # passes through
# With YubiKey unplugged:
git-yubikey status                    # blocked — "YubiKey not detected"
```

## Customization

### SSH key path

Default: `~/.ssh/id_ed25519_sk_no_touch`

Override with environment variable:
```bash
export YUBIKEY_SSH_KEY=~/.ssh/id_ed25519_sk_mykey
```

### ssh-askpass path

Default: `/opt/homebrew/bin/ssh-askpass`

Override with environment variable:
```bash
export REAL_ASKPASS=/path/to/ssh-askpass
```

## Files

| File | Installs to | Purpose |
|------|-------------|---------|
| `git-yubikey` | `~/bin/` | Presence check + destructive gate |
| `git-ssh-sign.sh` | `/usr/local/bin/git-ssh-sign` | Commit signing (bypasses ssh-agent) |
| `git-ssh-auth.sh` | `/usr/local/bin/git-ssh-auth` | Push/pull auth (bypasses ssh-agent) |
| `ssh-askpass-wrapper.sh` | `/usr/local/bin/ssh-askpass-wrapper` | Askpass popup filter |
| `CLAUDE.md.snippet` | Appended to `CLAUDE.md` | Instructions for Claude Code |
| `install.sh` | — | Installer (works from curl or local) |
