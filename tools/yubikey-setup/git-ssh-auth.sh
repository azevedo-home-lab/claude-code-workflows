#!/bin/bash
# Git SSH auth wrapper: bypasses ssh-agent for FIDO key authentication.
# Same principle as git-ssh-sign — the macOS ssh-agent can't prompt for
# FIDO touch in non-tty contexts. This wrapper forces SSH to use the
# YubiKey directly via libfido2, requiring only physical touch (no PIN popup).
#
# Install:
#   sudo cp git-ssh-auth.sh /usr/local/bin/git-ssh-auth
#   git config --global core.sshCommand /usr/local/bin/git-ssh-auth
#
# CUSTOMIZE: Change the -i path to your ed25519-sk key file.

YUBIKEY_SSH_KEY="${YUBIKEY_SSH_KEY:-$HOME/.ssh/id_ed25519_sk}"

unset SSH_AUTH_SOCK
unset SSH_ASKPASS
unset SSH_ASKPASS_REQUIRE
export SSH_SK_PROVIDER="/usr/local/lib/sk-libfido2.dylib"
exec /usr/bin/ssh -o IdentitiesOnly=yes -i "$YUBIKEY_SSH_KEY" "$@"
