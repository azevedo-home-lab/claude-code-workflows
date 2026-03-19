#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# SSH askpass wrapper: only show GUI popup for git signing and GitHub auth.
# All other SSH operations (API calls, SCP, etc.) get silently rejected
# to prevent unwanted YubiKey touch popups.
#
# CUSTOMIZE: Update REAL_ASKPASS path if ssh-askpass is installed elsewhere.

LOGFILE="$HOME/.ssh/askpass.log"
REAL_ASKPASS="${REAL_ASKPASS:-/opt/homebrew/bin/ssh-askpass}"
PARENT=$(ps -o comm= -p $PPID 2>/dev/null)
GRANDPARENT=$(ps -o comm= -p $(ps -o ppid= -p $PPID 2>/dev/null) 2>/dev/null)

echo "$(date '+%Y-%m-%d %H:%M:%S') PARENT=$PARENT GRANDPARENT=$GRANDPARENT ARGS=$* ALLOWED=$([ "$PARENT" = "ssh-keygen" ] && echo YES || echo NO)" >> "$LOGFILE"

# Allow: ssh-keygen (git signing) or ssh-agent (GitHub auth)
if [[ "$PARENT" == *ssh-keygen* ]] || [[ "$PARENT" == *ssh-agent* ]]; then
    exec "$REAL_ASKPASS" "$@"
fi

# Deny everything else silently
exit 1