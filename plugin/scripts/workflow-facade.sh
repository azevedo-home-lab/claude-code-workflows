#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Workflow facade — sources all state modules.
# Single entry point for scripts that need the full API.

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

source "$SCRIPT_DIR/infrastructure/state-io.sh"
source "$SCRIPT_DIR/infrastructure/phase.sh"
source "$SCRIPT_DIR/infrastructure/settings.sh"
source "$SCRIPT_DIR/infrastructure/milestones.sh"
source "$SCRIPT_DIR/infrastructure/tracking.sh"
source "$SCRIPT_DIR/infrastructure/gate-checks.sh"
source "$SCRIPT_DIR/l2/coaching-state.sh"
source "$SCRIPT_DIR/agent-set-phase.sh"
