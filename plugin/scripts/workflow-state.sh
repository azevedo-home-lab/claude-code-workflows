#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Workflow state facade — sources all modules for backward compatibility.
# Existing `source workflow-state.sh` calls continue to work unchanged.

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

source "$SCRIPT_DIR/state-io.sh"
source "$SCRIPT_DIR/phase.sh"
source "$SCRIPT_DIR/settings.sh"
source "$SCRIPT_DIR/milestones.sh"
source "$SCRIPT_DIR/tracking.sh"
source "$SCRIPT_DIR/coaching-state.sh"
source "$SCRIPT_DIR/phase-gates.sh"
