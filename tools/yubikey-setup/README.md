# YubiKey Git Signing Setup for Claude Code

Git commit signing and push authentication via YubiKey FIDO2, with visible touch banners for Claude Code sessions.

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

The no-touch-required SSH key allows YubiKey presence to authorize safe operations without physical tap.

```bash
# Generate no-touch key (one-time)
ssh-keygen -t ed25519-sk -O no-touch-required -O resident -C "yubikey-no-touch"

# Then register on GitHub:
# 1. Add the .pub as a signing key
# 2. Add the .pub as an authentication key
# 3. Update ~/.ssh/allowed_signers
# 4. Update git config: git config --global user.signingkey ~/.ssh/<new-key>.pub
```

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
