#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Git SSH signing wrapper: bypasses ssh-agent to use FIDO key directly.
# The macOS ssh-agent intercepts SK key operations but can't prompt for
# FIDO touch in non-tty contexts. Unsetting SSH_AUTH_SOCK forces
# ssh-keygen to talk to the YubiKey directly via libfido2.
#
# Install: git config --global gpg.ssh.program /usr/local/bin/git-ssh-sign

unset SSH_AUTH_SOCK
unset SSH_ASKPASS
unset SSH_ASKPASS_REQUIRE
export SSH_SK_PROVIDER="/usr/local/lib/sk-libfido2.dylib"
exec /usr/bin/ssh-keygen "$@"