#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Layer 1: Phase entry message — fires once per phase transition.
# Loads coaching objective + full phase instructions from plugin/phases/.
# Appends auto-transition guidance if autonomy is "auto".
#
# Expected variables from caller (post-tool-coaching.sh):
#   PHASE, PHASE_UPPER, TOOL_NAME, MESSAGES, COACHING_DIR, PHASES_DIR
# Expected functions from caller:
#   load_message, get_message_shown, set_message_shown, get_autonomy_level,
#   _trace, _log

[ -n "${_WFM_L1_LOADED:-}" ] && return 0
_WFM_L1_LOADED=1

_run_l1() {
    if [ "$(get_message_shown)" != "true" ]; then
        # IMPLEMENT phase: only fire on Write/Edit/Bash, skip Read/Grep/Glob
        local fire=true
        if [ "$PHASE" = "implement" ]; then
            case "$TOOL_NAME" in
                Write|Edit|MultiEdit|NotebookEdit|Bash) ;;
                *) fire=false ;;
            esac
        fi

        if [ "$fire" = "true" ]; then
            case "$PHASE" in
                error)
                    local err_msg
                    err_msg=$(load_message "objectives/error.md")
                    if [ -n "$err_msg" ]; then
                        MESSAGES="[Workflow Coach — ERROR]
$err_msg"
                        _trace "[WFM coach] L1 FIRED: objectives/error.md"
                    fi
                    ;;
                *)
                    local obj_msg
                    obj_msg=$(load_message "objectives/$PHASE.md")
                    if [ -n "$obj_msg" ]; then
                        MESSAGES="[Workflow Coach — $PHASE_UPPER]
$obj_msg"
                        _trace "[WFM coach] L1 FIRED: objectives/$PHASE.md"
                    fi
                    # Load full phase instructions from plugin/phases/{phase}/phase.md
                    local phase_file="$PHASES_DIR/$PHASE/phase.md"
                    if [ -f "$phase_file" ]; then
                        local phase_instructions
                        phase_instructions=$(cat "$phase_file")
                        if [ -n "$MESSAGES" ]; then
                            MESSAGES="$MESSAGES

$phase_instructions"
                        else
                            MESSAGES="$phase_instructions"
                        fi
                        _trace "[WFM coach] L1: loaded phases/$PHASE/phase.md"
                    fi
                    ;;
            esac
            # Append auto-transition guidance if autonomy is "auto"
            local autonomy_level
            autonomy_level=$(get_autonomy_level)
            if [ "$autonomy_level" = "auto" ] && [ -n "$MESSAGES" ]; then
                local auto_msg
                auto_msg=$(load_message "auto-transition/$PHASE.md")
                if [ -z "$auto_msg" ]; then
                    auto_msg=$(load_message "auto-transition/default.md")
                fi
                if [ -n "$auto_msg" ]; then
                    MESSAGES="$MESSAGES
$auto_msg"
                fi
            fi

            # Skip state update in error phase — state is corrupt, writes will fail
            if [ "$PHASE" != "error" ]; then
                set_message_shown
            fi
        else
            _log "[WFM coach] L1: tool not eligible, skipped"
        fi
    else
        _log "[WFM coach] L1: already shown, skipped"
    fi
}
