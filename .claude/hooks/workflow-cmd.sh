#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Shell-independent wrapper for workflow-state.sh functions.
# Always runs under bash (via shebang) regardless of the user's shell.
#
# Usage from command templates:
#   .claude/hooks/workflow-cmd.sh set_phase "implement"
#   .claude/hooks/workflow-cmd.sh set_completion_field "plan_validated" "true"
#   .claude/hooks/workflow-cmd.sh get_phase
#
# Supports chaining multiple commands separated by &&:
#   .claude/hooks/workflow-cmd.sh set_phase "implement" && .claude/hooks/workflow-cmd.sh set_active_skill ""

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workflow-state.sh"

# Execute the function passed as arguments
"$@"
