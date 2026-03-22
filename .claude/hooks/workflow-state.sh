#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Workflow state utility — read/write phase state
# Used by hooks (read only) and commands (read/write)
# All state consolidated in a single workflow.json file

STATE_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/.claude/state"
STATE_FILE="$STATE_DIR/workflow.json"

# Restrictive tier: DEFINE and DISCUSS phases
# NOTE: .claude/hooks/ deliberately excluded — enforcement mechanism must not be self-modifiable
RESTRICTED_WRITE_WHITELIST='(\.claude/state/|docs/superpowers/specs/|docs/superpowers/plans/|docs/plans/)'

# Docs-allowed tier: COMPLETE phase
COMPLETE_WRITE_WHITELIST='(\.claude/state/|docs/|^[^/]*\.md$)'

# ---------------------------------------------------------------------------
# Shared hook helpers
# ---------------------------------------------------------------------------

# Emit a PreToolUse deny JSON response. Used by workflow-gate.sh and bash-write-guard.sh.
# Usage: emit_deny "reason message"
emit_deny() {
    local reason="$1"
    REASON="$reason" python3 -c "
import json, os
output = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': os.environ['REASON']
    }
}
print(json.dumps(output))
"
}

# ---------------------------------------------------------------------------
# Phase management
# ---------------------------------------------------------------------------

get_phase() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "off"
        return
    fi
    local phase
    phase=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    print(d.get('phase', 'off'))
except Exception:
    print('off')
" "$STATE_FILE" 2>/dev/null)
    echo "${phase:-off}"
}

get_autonomy_level() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "2"
        return
    fi
    local level
    level=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    print(d.get('autonomy_level', 2))
except Exception:
    print(2)
" "$STATE_FILE" 2>/dev/null)
    echo "${level:-2}"
}

set_autonomy_level() {
    local level="$1"
    case "$level" in
        1|2|3) ;;
        *) echo "ERROR: Invalid autonomy level: $level (valid: 1, 2, 3)" >&2; return 1 ;;
    esac
    if [ ! -f "$STATE_FILE" ]; then
        echo "WARNING: No workflow state file. Start a workflow phase first (e.g., /define)." >&2
        return 1
    fi
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    python3 -c "
import json, sys
level, ts, filepath = int(sys.argv[1]), sys.argv[2], sys.argv[3]
with open(filepath, 'r') as f:
    d = json.load(f)
d['autonomy_level'] = level
d['updated'] = ts
with open(filepath, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$level" "$ts" "$STATE_FILE"
}

# ---------------------------------------------------------------------------
# Last observation ID tracking (claude-mem)
# ---------------------------------------------------------------------------

get_last_observation_id() {
    if [ ! -f "$STATE_FILE" ]; then
        echo ""
        return
    fi
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    v = d.get('last_observation_id', '')
    print(v if v else '')
except Exception:
    print('')
" "$STATE_FILE" 2>/dev/null
}

set_last_observation_id() {
    local obs_id="$1"
    if [ ! -f "$STATE_FILE" ]; then
        return
    fi
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    python3 -c "
import json, sys
obs_id, ts, filepath = sys.argv[1], sys.argv[2], sys.argv[3]
with open(filepath, 'r') as f:
    d = json.load(f)
d['last_observation_id'] = int(obs_id) if obs_id else ''
d['updated'] = ts
with open(filepath, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$obs_id" "$ts" "$STATE_FILE"
}

set_phase() {
    local new_phase="$1"

    # Validate phase name
    case "$new_phase" in
        off|define|discuss|implement|review|complete) ;;
        *) echo "ERROR: Invalid phase: $new_phase (valid: off, define, discuss, implement, review, complete)" >&2; return 1 ;;
    esac

    mkdir -p "$STATE_DIR"

    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Read existing state to preserve fields
    local existing_active_skill=""
    local existing_decision_record=""
    local existing_autonomy_level=""
    local existing_last_observation_id=""
    local current_phase="off"
    if [ -f "$STATE_FILE" ]; then
        current_phase=$(get_phase)
        existing_active_skill=$(get_active_skill)
        existing_decision_record=$(get_decision_record)
        existing_autonomy_level=$(get_autonomy_level)
        existing_last_observation_id=$(get_last_observation_id)
    fi

    # If new phase is off, clear active_skill, decision_record, autonomy_level, and last_observation_id (cycle complete)
    if [ "$new_phase" = "off" ]; then
        existing_active_skill=""
        existing_decision_record=""
        existing_autonomy_level=""
        existing_last_observation_id=""
    fi

    # Initialize autonomy_level to 2 when transitioning from OFF to active phase.
    # Note: this guard only fires on the very first set_phase call (no state file yet),
    # because get_autonomy_level returns "2" as default when a file exists.
    # After set_phase("off") clears autonomy_level, the next get_autonomy_level still
    # returns "2" (default), so existing_autonomy_level is never empty in normal cycling.
    if [ "$current_phase" = "off" ] && [ "$new_phase" != "off" ] && [ -z "$existing_autonomy_level" ]; then
        existing_autonomy_level="2"
    fi

    # Build the new state: preserve active_skill, decision_record, and autonomy_level,
    # reset message_shown, fresh coaching, clean up review if leaving review
    python3 -c "
import json, sys

new_phase = sys.argv[1]
current_phase = sys.argv[2]
active_skill = sys.argv[3]
decision_record = sys.argv[4]
ts = sys.argv[5]
filepath = sys.argv[6]
autonomy_level = sys.argv[7]
last_observation_id = sys.argv[8]

state = {
    'phase': new_phase,
    'message_shown': False,
    'active_skill': active_skill,
    'decision_record': decision_record,
    'coaching': {
        'tool_calls_since_agent': 0,
        'layer2_fired': []
    },
    'updated': ts
}

if autonomy_level:
    state['autonomy_level'] = int(autonomy_level)

if last_observation_id:
    state['last_observation_id'] = int(last_observation_id)

# Only include review sub-object if we are NOT leaving review
# (i.e., if current was review and new is not, we omit it)
# The review sub-object is only present during REVIEW phase
# and is created explicitly via reset_review_status()

with open(filepath, 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
" "$new_phase" "$current_phase" "$existing_active_skill" "$existing_decision_record" "$ts" "$STATE_FILE" "$existing_autonomy_level" "$existing_last_observation_id"
}

get_message_shown() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "false"
        return
    fi
    local shown
    shown=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    print(str(d.get('message_shown', False)).lower())
except Exception:
    print('false')
" "$STATE_FILE" 2>/dev/null)
    echo "${shown:-false}"
}

set_message_shown() {
    if [ ! -f "$STATE_FILE" ]; then
        return
    fi
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    python3 -c "
import json, sys
filepath, ts = sys.argv[1], sys.argv[2]
with open(filepath, 'r') as f:
    d = json.load(f)
d['message_shown'] = True
d['updated'] = ts
with open(filepath, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$STATE_FILE" "$ts"
}

# ---------------------------------------------------------------------------
# Active skill management
# ---------------------------------------------------------------------------

set_active_skill() {
    local name="$1"
    if [ ! -f "$STATE_FILE" ]; then
        return
    fi
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    python3 -c "
import json, sys
name, ts, filepath = sys.argv[1], sys.argv[2], sys.argv[3]
with open(filepath, 'r') as f:
    d = json.load(f)
d['active_skill'] = name
d['updated'] = ts
with open(filepath, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$name" "$ts" "$STATE_FILE"
}

get_active_skill() {
    if [ ! -f "$STATE_FILE" ]; then
        echo ""
        return
    fi
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    print(d.get('active_skill', ''))
except Exception:
    print('')
" "$STATE_FILE" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Decision record management
# ---------------------------------------------------------------------------

set_decision_record() {
    local record_path="$1"
    if [ ! -f "$STATE_FILE" ]; then
        return
    fi
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    python3 -c "
import json, sys
record_path, ts, filepath = sys.argv[1], sys.argv[2], sys.argv[3]
with open(filepath, 'r') as f:
    d = json.load(f)
d['decision_record'] = record_path
d['updated'] = ts
with open(filepath, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$record_path" "$ts" "$STATE_FILE"
}

get_decision_record() {
    if [ ! -f "$STATE_FILE" ]; then
        echo ""
        return
    fi
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    print(d.get('decision_record', ''))
except Exception:
    print('')
" "$STATE_FILE" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Soft gate checks — return warning message or empty string
# ---------------------------------------------------------------------------

check_soft_gate() {
    local target_phase="$1"
    local project_root
    project_root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

    case "$target_phase" in
        implement)
            # Check if any plan file exists
            local plan_files
            plan_files=$(ls "$project_root"/docs/superpowers/plans/*.md "$project_root"/docs/plans/*.md 2>/dev/null)
            if [ -z "$plan_files" ]; then
                echo "No plan exists. The workflow recommends /discuss first. Proceed without a plan?"
                return
            fi
            ;;
        review)
            # Check if there are code changes
            local changes
            changes=$(git diff --name-only main...HEAD 2>/dev/null; git diff --name-only 2>/dev/null)
            if [ -z "$changes" ]; then
                echo "No code changes detected. The review pipeline requires changed files to analyze. Proceed anyway?"
                return
            fi
            ;;
        complete)
            # Check if review findings were acknowledged
            if [ ! -f "$STATE_FILE" ]; then
                echo "Review hasn't been run. The workflow should be followed for best results. Proceed anyway?"
                return
            fi
            local acknowledged
            acknowledged=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    review = d.get('review', {})
    print(str(review.get('findings_acknowledged', False)).lower())
except Exception:
    print('false')
" "$STATE_FILE" 2>/dev/null)
            if [ "$acknowledged" != "true" ]; then
                echo "Review hasn't been run. The workflow should be followed for best results. Proceed anyway?"
                return
            fi
            ;;
    esac

    # No gate triggered — return empty
    echo ""
}

# ---------------------------------------------------------------------------
# Review status helpers
# ---------------------------------------------------------------------------

reset_review_status() {
    if [ ! -f "$STATE_FILE" ]; then
        return
    fi
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    python3 -c "
import json, sys
ts, filepath = sys.argv[1], sys.argv[2]
with open(filepath, 'r') as f:
    d = json.load(f)
d['review'] = {
    'verification_complete': False,
    'agents_dispatched': False,
    'findings_presented': False,
    'findings_acknowledged': False
}
d['updated'] = ts
with open(filepath, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$ts" "$STATE_FILE"
}

get_review_field() {
    local field="$1"
    if [ ! -f "$STATE_FILE" ]; then
        echo ""
        return
    fi
    local value
    value=$(python3 -c "
import json, sys
field = sys.argv[1]
filepath = sys.argv[2]
try:
    with open(filepath) as f:
        d = json.load(f)
    review = d.get('review', {})
    v = review.get(field, '')
    if isinstance(v, bool):
        print(str(v).lower())
    else:
        print(v)
except Exception:
    print('')
" "$field" "$STATE_FILE" 2>/dev/null)
    echo "$value"
}

set_review_field() {
    local field="$1"
    local value="$2"
    if [ ! -f "$STATE_FILE" ]; then
        return
    fi
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    python3 -c "
import json, sys
field, value, ts, filepath = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(filepath, 'r') as f:
    d = json.load(f)
review = d.get('review', {})
if value in ('true', 'false'):
    review[field] = value == 'true'
else:
    review[field] = value
d['review'] = review
d['updated'] = ts
with open(filepath, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$field" "$value" "$ts" "$STATE_FILE"
}

# ---------------------------------------------------------------------------
# Coaching helpers
# ---------------------------------------------------------------------------

increment_coaching_counter() {
    if [ ! -f "$STATE_FILE" ]; then
        return
    fi
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    python3 -c "
import json, sys
ts, filepath = sys.argv[1], sys.argv[2]
with open(filepath, 'r') as f:
    d = json.load(f)
coaching = d.get('coaching', {'tool_calls_since_agent': 0, 'layer2_fired': []})
coaching['tool_calls_since_agent'] = coaching.get('tool_calls_since_agent', 0) + 1
d['coaching'] = coaching
d['updated'] = ts
with open(filepath, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$ts" "$STATE_FILE"
}

reset_coaching_counter() {
    if [ ! -f "$STATE_FILE" ]; then
        return
    fi
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    python3 -c "
import json, sys
ts, filepath = sys.argv[1], sys.argv[2]
with open(filepath, 'r') as f:
    d = json.load(f)
coaching = d.get('coaching', {'tool_calls_since_agent': 0, 'layer2_fired': []})
coaching['tool_calls_since_agent'] = 0
d['coaching'] = coaching
d['updated'] = ts
with open(filepath, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$ts" "$STATE_FILE"
}

add_coaching_fired() {
    local trigger_type="$1"
    if [ ! -f "$STATE_FILE" ]; then
        return
    fi
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    python3 -c "
import json, sys
trigger_type, ts, filepath = sys.argv[1], sys.argv[2], sys.argv[3]
with open(filepath, 'r') as f:
    d = json.load(f)
coaching = d.get('coaching', {'tool_calls_since_agent': 0, 'layer2_fired': []})
fired = coaching.get('layer2_fired', [])
fired.append(trigger_type)
coaching['layer2_fired'] = fired
d['coaching'] = coaching
d['updated'] = ts
with open(filepath, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$trigger_type" "$ts" "$STATE_FILE"
}

has_coaching_fired() {
    local trigger_type="$1"
    if [ ! -f "$STATE_FILE" ]; then
        echo "false"
        return
    fi
    python3 -c "
import json, sys
trigger_type = sys.argv[1]
filepath = sys.argv[2]
try:
    with open(filepath) as f:
        d = json.load(f)
    coaching = d.get('coaching', {})
    fired = coaching.get('layer2_fired', [])
    print('true' if trigger_type in fired else 'false')
except Exception:
    print('false')
" "$trigger_type" "$STATE_FILE" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Pending verify tracking
# ---------------------------------------------------------------------------

set_pending_verify() {
    local count="${1:-0}"
    if [ ! -f "$STATE_FILE" ]; then return; fi
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    python3 -c "
import json, sys
count, ts, filepath = int(sys.argv[1]), sys.argv[2], sys.argv[3]
with open(filepath, 'r') as f:
    d = json.load(f)
coaching = d.get('coaching', {})
coaching['pending_verify'] = count
d['coaching'] = coaching
d['updated'] = ts
with open(filepath, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$count" "$ts" "$STATE_FILE" 2>/dev/null
}

get_pending_verify() {
    if [ ! -f "$STATE_FILE" ]; then echo "0"; return; fi
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    print(d.get('coaching', {}).get('pending_verify', 0))
except Exception:
    print(0)
" "$STATE_FILE" 2>/dev/null
}
