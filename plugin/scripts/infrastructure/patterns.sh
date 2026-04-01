#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Shared path pattern constants for hook enforcement.
# Sourced by pre-tool-bash-guard.sh and pre-tool-write-gate.sh.

[ -n "${_WFM_PATTERNS_LOADED:-}" ] && return 0
_WFM_PATTERNS_LOADED=1

# Enforcement files — protected from writes in ALL phases including implement/review.
# Matches: .claude/hooks/, plugin/scripts/, plugin/commands/
GUARD_SYSTEM_PATTERN='(\.claude/hooks/|(^|[^a-z-])plugin/scripts/|(^|[^a-z-])plugin/commands/)'

# State files — protected from direct writes in ALL phases.
# All state writes must go through _update_state() / _safe_write().
STATE_FILE_PATTERN='\.claude/(state/workflow\.json|state/phase-intent\.json)'
