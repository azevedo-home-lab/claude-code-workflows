#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Simple bash test runner for workflow enforcement hooks
# Usage: ./tests/run-tests.sh

set -euo pipefail

PASS=0
FAIL=0
ERRORS=""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

assert_eq() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    if [ "$expected" = "$actual" ]; then
        echo -e "  ${GREEN}PASS${NC} $test_name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $test_name"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
        FAIL=$((FAIL + 1))
        ERRORS="$ERRORS\n  FAIL: $test_name"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    if echo "$haystack" | grep -q "$needle"; then
        echo -e "  ${GREEN}PASS${NC} $test_name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $test_name"
        echo "    '$needle' not found in output"
        FAIL=$((FAIL + 1))
        ERRORS="$ERRORS\n  FAIL: $test_name"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    if echo "$haystack" | grep -q "$needle"; then
        echo -e "  ${RED}FAIL${NC} $test_name"
        echo "    '$needle' was found but should not be"
        FAIL=$((FAIL + 1))
        ERRORS="$ERRORS\n  FAIL: $test_name"
    else
        echo -e "  ${GREEN}PASS${NC} $test_name"
        PASS=$((PASS + 1))
    fi
}

assert_file_exists() {
    local path="$1"
    local test_name="$2"
    if [ -e "$path" ]; then
        echo -e "  ${GREEN}PASS${NC} $test_name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $test_name"
        echo "    file not found: $path"
        FAIL=$((FAIL + 1))
        ERRORS="$ERRORS\n  FAIL: $test_name"
    fi
}

assert_file_not_exists() {
    local path="$1"
    local test_name="$2"
    if [ ! -e "$path" ]; then
        echo -e "  ${GREEN}PASS${NC} $test_name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $test_name"
        echo "    file exists but shouldn't: $path"
        FAIL=$((FAIL + 1))
        ERRORS="$ERRORS\n  FAIL: $test_name"
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    assert_eq "$expected" "$actual" "$test_name"
}

# Setup: create a temporary project directory for testing
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$REPO_DIR/plugin/scripts"

# Create a fake project structure in TEST_DIR
setup_test_project() {
    rm -rf "$TEST_DIR"
    TEST_DIR=$(mktemp -d)
    mkdir -p "$TEST_DIR/.claude/hooks" "$TEST_DIR/.claude/state" "$TEST_DIR/.claude/commands"
    cp "$HOOKS_DIR/workflow-state.sh" "$TEST_DIR/.claude/hooks/"
    cp "$HOOKS_DIR/workflow-cmd.sh" "$TEST_DIR/.claude/hooks/"
    cp "$HOOKS_DIR/workflow-gate.sh" "$TEST_DIR/.claude/hooks/"
    cp "$HOOKS_DIR/bash-write-guard.sh" "$TEST_DIR/.claude/hooks/"
    # Set CLAUDE_PROJECT_DIR for hooks
    export CLAUDE_PROJECT_DIR="$TEST_DIR"
    # Skip token auth for existing tests (BUG-3 tests explicitly unset this via run_with_auth)
    export WF_SKIP_AUTH=1
}

# Run a workflow-state.sh function with auth enforcement enabled (no WF_SKIP_AUTH bypass).
# Uses a subshell so the unset doesn't leak into the parent environment.
# Usage: run_with_auth set_phase "review"
#        run_with_auth set_autonomy_level "auto"
run_with_auth() {
    (unset WF_SKIP_AUTH; export CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-$TEST_DIR/.claude/plugin-data}"; source "$TEST_DIR/.claude/hooks/workflow-state.sh" && "$@")
}

# ============================================================
# TEST SUITE: workflow-state.sh
# ============================================================
echo ""
echo "=== workflow-state.sh ==="

setup_test_project

# Test: get_phase returns "off" when no state file exists
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "off" "$RESULT" "get_phase defaults to 'off' when no state file"

# Test: set_phase creates state file with correct phase
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
assert_file_exists "$TEST_DIR/.claude/state/workflow.json" "set_phase creates workflow.json"

# Test: get_phase returns "implement" after set_phase
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "implement" "$RESULT" "get_phase returns 'implement' after set_phase"

# Test: set_phase back to discuss
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "discuss" "$RESULT" "set_phase can change back to 'discuss'"

# Test: set_phase to review
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "review" "$RESULT" "set_phase supports 'review' phase"

# Test: state file contains timestamp
CONTENT=$(cat "$TEST_DIR/.claude/state/workflow.json")
assert_contains "$CONTENT" "updated" "state file contains timestamp"

# Test: set_phase initializes message_shown to false
assert_contains "$CONTENT" '"message_shown": false' "set_phase initializes message_shown to false"

# Test: get_message_shown returns false initially
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_message_shown)
assert_eq "false" "$RESULT" "get_message_shown returns false initially"

# Test: set_message_shown sets flag to true
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_message_shown)
assert_eq "true" "$RESULT" "set_message_shown sets flag to true"

# Test: set_phase resets message_shown to false
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_message_shown)
assert_eq "false" "$RESULT" "set_phase resets message_shown to false"

# Test: set_phase creates state directory if missing
rm -rf "$TEST_DIR/.claude/state"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
assert_file_exists "$TEST_DIR/.claude/state/workflow.json" "set_phase creates state dir if missing"

# Test: set_phase rejects invalid phase names
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "invalid_phase" 2>&1 || true)
assert_contains "$OUTPUT" "ERROR" "set_phase rejects invalid phase name"
# Verify phase didn't change
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "implement" "$RESULT" "set_phase keeps previous phase after rejection"

# Test: set_phase accepts 'off' phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "off" "$RESULT" "set_phase accepts 'off' phase"

# Test: set_phase accepts 'define' phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "define"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "define" "$RESULT" "set_phase accepts 'define' phase"

# Test: set_phase cleans up review sub-object when leaving review
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && reset_review_status
CONTENT=$(cat "$TEST_DIR/.claude/state/workflow.json")
assert_contains "$CONTENT" '"review"' "review sub-object exists in review phase"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
CONTENT=$(cat "$TEST_DIR/.claude/state/workflow.json")
assert_not_contains "$CONTENT" '"verification_complete"' "set_phase removes review sub-object when leaving review"

# Test: reset_review_status creates review sub-object in workflow.json
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && reset_review_status
CONTENT=$(cat "$TEST_DIR/.claude/state/workflow.json")
assert_contains "$CONTENT" '"verification_complete": false' "review sub-object has verification_complete false"
assert_contains "$CONTENT" '"agents_dispatched": false' "review sub-object has agents_dispatched false"
assert_contains "$CONTENT" '"findings_presented": false' "review sub-object has findings_presented false"
assert_contains "$CONTENT" '"findings_acknowledged": false' "review sub-object has findings_acknowledged false"

# Test: set_phase accepts 'complete' phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "complete" "$RESULT" "set_phase accepts 'complete' phase"

# Test: set_review_field updates a field (requires review sub-object)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && reset_review_status
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_review_field "verification_complete" "true"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_review_field "verification_complete")
assert_eq "true" "$RESULT" "set_review_field updates verification_complete"

# Test: get_review_field returns false for unset field
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_review_field "agents_dispatched")
assert_eq "false" "$RESULT" "get_review_field returns false for unset field"

# Test: get_review_field returns empty when no file
rm -f "$TEST_DIR/.claude/state/workflow.json"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_review_field "verification_complete")
assert_eq "" "$RESULT" "get_review_field returns empty when no file"

# --- Autonomy level management ---

# Test: get_autonomy_level returns default "ask" when no state file
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "ask" "$RESULT" "get_autonomy_level defaults to ask when no state file"

# Test: get_autonomy_level returns default "ask" for old-format workflow.json (backward compat)
setup_test_project
# Create a workflow.json WITHOUT autonomy_level (simulates pre-feature state file)
echo '{"phase": "implement", "message_shown": true, "active_skill": "", "decision_record": "", "coaching": {"tool_calls_since_agent": 0, "layer2_fired": []}, "updated": "2026-03-22T00:00:00Z"}' > "$TEST_DIR/.claude/state/workflow.json"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "ask" "$RESULT" "get_autonomy_level defaults to ask for old-format state file (backward compat)"

# Test: set_autonomy_level accepts valid values
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level off
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "off" "$RESULT" "set_autonomy_level sets level to off"

source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level ask
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "ask" "$RESULT" "set_autonomy_level sets level to ask"

source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level auto
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "auto" "$RESULT" "set_autonomy_level sets level to auto"

# Test: set_autonomy_level rejects invalid values
OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 0 2>&1 || true)
assert_contains "$OUTPUT" "ERROR" "set_autonomy_level rejects 0"

OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 4 2>&1 || true)
assert_contains "$OUTPUT" "ERROR" "set_autonomy_level rejects 4"

OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level abc 2>&1 || true)
assert_contains "$OUTPUT" "ERROR" "set_autonomy_level rejects invalid input"

# Test: autonomy_level preserved across set_phase transitions
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level auto
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "auto" "$RESULT" "autonomy_level preserved across phase transitions"

# Test: set_phase from OFF initializes autonomy_level to ask
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "define"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "ask" "$RESULT" "set_phase from OFF initializes autonomy_level to ask"

# Test: set_phase("off") clears autonomy_level
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level auto
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "ask" "$RESULT" "set_phase off clears autonomy_level (returns default ask)"

# Test: set_autonomy_level warns and returns 1 when no state file
setup_test_project
rm -f "$TEST_DIR/.claude/state/workflow.json"
OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level ask 2>&1 || true)
assert_contains "$OUTPUT" "WARNING" "set_autonomy_level warns when no state file"
assert_file_not_exists "$TEST_DIR/.claude/state/workflow.json" "set_autonomy_level does not create state file"

# --- BUG-1: Backward-compat numeric autonomy values ---

# Test: set_autonomy_level maps numeric 1 to off
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 1
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "off" "$RESULT" "set_autonomy_level maps 1 to off"

# Test: set_autonomy_level maps numeric 2 to ask
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 2
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "ask" "$RESULT" "set_autonomy_level maps 2 to ask"

# Test: set_autonomy_level maps numeric 3 to auto
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 3
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "auto" "$RESULT" "set_autonomy_level maps 3 to auto"

# Test: set_autonomy_level still rejects truly invalid values
OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 4 2>&1 || true)
assert_contains "$OUTPUT" "ERROR" "set_autonomy_level still rejects 4 after backward-compat"

OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level abc 2>&1 || true)
assert_contains "$OUTPUT" "ERROR" "set_autonomy_level still rejects abc after backward-compat"

# --- BUG-2: Echo chaining verification ---

# Test: echo suppressed when set_phase fails (hard gate)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && reset_implement_status
# set_phase should fail (hard gate: implement milestones incomplete), && echo should NOT fire
WF="$TEST_DIR/.claude/hooks/workflow-cmd.sh"
OUTPUT=$("$WF" set_phase "review" && echo "Phase set to REVIEW" 2>&1 || true)
assert_not_contains "$OUTPUT" "Phase set to REVIEW" "BUG-2: echo suppressed when set_phase fails (hard gate)"

# Test: echo fires when set_phase succeeds
setup_test_project
WF="$TEST_DIR/.claude/hooks/workflow-cmd.sh"
OUTPUT=$("$WF" set_phase "implement" && echo "Phase set to IMPLEMENT" 2>&1)
assert_contains "$OUTPUT" "Phase set to IMPLEMENT" "BUG-2: echo fires when set_phase succeeds"

# --- Last observation ID tracking ---

# Test: get_last_observation_id returns empty when no state file
setup_test_project
rm -f "$TEST_DIR/.claude/state/workflow.json"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_last_observation_id)
assert_eq "" "$RESULT" "get_last_observation_id returns empty when no state file"

# Test: set and get last_observation_id
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_last_observation_id 3007
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_last_observation_id)
assert_eq "3007" "$RESULT" "set/get_last_observation_id roundtrip"

# Test: last_observation_id preserved across phase transitions
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_last_observation_id)
assert_eq "3007" "$RESULT" "last_observation_id preserved across phase transitions"

# Test: set_phase("off") preserves last_observation_id (useful in statusline when workflow is OFF)
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_last_observation_id)
assert_eq "3007" "$RESULT" "set_phase off preserves last_observation_id"

# --- Hard gates: phase transition enforcement ---

# Test: hard gate blocks leaving IMPLEMENT without milestones
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && reset_implement_status
OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review" 2>&1 || true)
assert_contains "$OUTPUT" "HARD GATE" "hard gate blocks leaving IMPLEMENT without milestones"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "implement" "$RESULT" "phase remains implement after gate blocks"

# Test: hard gate allows leaving IMPLEMENT when all milestones complete
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && reset_implement_status
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_implement_field "plan_read" "true"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_implement_field "tests_passing" "true"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_implement_field "all_tasks_complete" "true"
OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review" 2>&1)
assert_not_contains "$OUTPUT" "HARD GATE" "hard gate allows leaving IMPLEMENT when milestones complete"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "review" "$RESULT" "phase transitions to review after milestones complete"

# Test: hard gate blocks set_phase off from COMPLETE without milestones
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && reset_completion_status
OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off" 2>&1 || true)
assert_contains "$OUTPUT" "HARD GATE" "hard gate blocks leaving COMPLETE without milestones"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "complete" "$RESULT" "phase remains complete after gate blocks"

# Test: hard gate allows set_phase off when all completion milestones done
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && reset_completion_status
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_completion_field "plan_validated" "true"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_completion_field "outcomes_validated" "true"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_completion_field "results_presented" "true"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_completion_field "docs_checked" "true"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_completion_field "committed" "true"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_completion_field "tech_debt_audited" "true"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_completion_field "handover_saved" "true"
OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off" 2>&1)
assert_not_contains "$OUTPUT" "HARD GATE" "hard gate allows leaving COMPLETE when milestones complete"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "off" "$RESULT" "phase transitions to off after completion milestones"

# Test: hard gate message lists missing milestones
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && reset_implement_status
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_implement_field "plan_read" "true"
OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review" 2>&1 || true)
assert_contains "$OUTPUT" "tests_passing" "hard gate message lists specific missing milestone"
assert_contains "$OUTPUT" "all_tasks_complete" "hard gate message lists all missing milestones"
assert_not_contains "$OUTPUT" "plan_read" "hard gate message does not list completed milestones"

# Test: backward compat — set_phase without reset_implement_status succeeds (no gate)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review" 2>&1)
assert_not_contains "$OUTPUT" "HARD GATE" "no gate when reset_implement_status was never called"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "review" "$RESULT" "phase transitions without implement status object"

# Test: backward compat — set_phase off from complete without reset_completion_status succeeds
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off" 2>&1)
assert_not_contains "$OUTPUT" "HARD GATE" "no gate when reset_completion_status was never called"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "off" "$RESULT" "phase transitions without completion status object"

# Test: COMPLETE hard gate blocks ALL exits (not just complete->off)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && reset_completion_status
OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement" 2>&1 || true)
assert_contains "$OUTPUT" "HARD GATE" "COMPLETE gate blocks complete->implement with incomplete milestones"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "complete" "$RESULT" "phase remains complete after complete→implement gate block"

# Test: corrupt state file does not crash set_phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
echo "NOT VALID JSON" > "$TEST_DIR/.claude/state/workflow.json"
OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review" 2>&1 || true)
# Should not crash — jq handles corrupt JSON gracefully via fallback defaults
assert_not_contains "$OUTPUT" "HARD GATE" "corrupt state file does not trigger false gate block"

# ============================================================
# TEST SUITE: workflow-gate.sh
# ============================================================
echo ""
echo "=== workflow-gate.sh ==="

# Helper: run workflow-gate with a file path
run_gate() {
    local file_path="$1"
    echo "{\"tool_input\":{\"file_path\":\"$file_path\"}}" | "$TEST_DIR/.claude/hooks/workflow-gate.sh" 2>&1 || true
}

# Test: blocks Write to source files in DISCUSS phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
OUTPUT=$(run_gate "/project/src/main.py")
assert_contains "$OUTPUT" "deny" "blocks Write/Edit to source files in DISCUSS phase"
assert_contains "$OUTPUT" "BLOCKED" "shows BLOCKED message in DISCUSS"

# Test: allows Write in IMPLEMENT phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
OUTPUT=$(run_gate "/project/src/main.py")
assert_not_contains "$OUTPUT" "deny" "allows Write/Edit in IMPLEMENT phase"

# Test: allows when no state file (first run)
setup_test_project
rm -f "$TEST_DIR/.claude/state/workflow.json"
OUTPUT=$(run_gate "/project/src/main.py")
assert_not_contains "$OUTPUT" "deny" "allows when no state file (first run)"

# Test: allows Write in REVIEW phase (edits allowed for fixes)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review"
OUTPUT=$(run_gate "/project/src/main.py")
assert_not_contains "$OUTPUT" "deny" "allows Write/Edit in REVIEW phase"

# Test: deny message mentions /implement
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
OUTPUT=$(run_gate "/project/src/main.py")
assert_contains "$OUTPUT" "/implement" "deny message mentions /implement command"

# Test: allows Write to .claude/state/ in DISCUSS phase (whitelist)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
OUTPUT=$(run_gate "/project/.claude/state/workflow.json")
assert_not_contains "$OUTPUT" "deny" "allows Write to .claude/state/ in DISCUSS (whitelist)"

# Test: allows Write to docs/superpowers/specs/ in DISCUSS phase (whitelist)
OUTPUT=$(run_gate "/project/docs/superpowers/specs/2026-03-16-design.md")
assert_not_contains "$OUTPUT" "deny" "allows Write to docs/superpowers/specs/ in DISCUSS (whitelist)"

# Test: allows Write to docs/plans/ in DISCUSS phase (whitelist)
OUTPUT=$(run_gate "/project/docs/plans/2026-03-16-plan.md")
assert_not_contains "$OUTPUT" "deny" "allows Write to docs/plans/ in DISCUSS (whitelist)"

# Test: still blocks non-whitelisted paths in DISCUSS phase
OUTPUT=$(run_gate "/project/src/app.js")
assert_contains "$OUTPUT" "deny" "blocks Write to non-whitelisted path in DISCUSS"

# Test: allows Write in OFF phase (no enforcement)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
OUTPUT=$(run_gate "/project/src/main.py")
assert_not_contains "$OUTPUT" "deny" "allows Write/Edit in OFF phase"

# Test: blocks Write/Edit in DEFINE phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "define"
OUTPUT=$(run_gate "/project/src/main.py")
assert_contains "$OUTPUT" "deny" "blocks Write/Edit to source files in DEFINE phase"
assert_contains "$OUTPUT" "BLOCKED" "shows BLOCKED message in DEFINE"

# Test: allows Write to whitelisted paths in DEFINE phase
OUTPUT=$(run_gate "/project/.claude/state/workflow.json")
assert_not_contains "$OUTPUT" "deny" "allows Write to .claude/state/ in DEFINE (whitelist)"

OUTPUT=$(run_gate "/project/docs/superpowers/specs/design.md")
assert_not_contains "$OUTPUT" "deny" "allows Write to docs/superpowers/specs/ in DEFINE (whitelist)"

OUTPUT=$(run_gate "/project/docs/plans/2026-01-01-test-decisions.md")
assert_not_contains "$OUTPUT" "deny" "allows Write to docs/plans/ in DEFINE (whitelist)"

# Test: deny message in DEFINE mentions problem definition
OUTPUT=$(run_gate "/project/src/main.py")
assert_contains "$OUTPUT" "define the problem" "deny message in DEFINE mentions problem definition"

# Test: path traversal rejection in DISCUSS phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
OUTPUT=$(run_gate "../../etc/passwd")
assert_contains "$OUTPUT" "deny" "blocks path traversal in Write target (workflow-gate)"

OUTPUT=$(run_gate "/project/.claude/state/../hooks/evil.sh")
assert_contains "$OUTPUT" "deny" "blocks path traversal via ../ in normalized path (workflow-gate)"

# --- Autonomy level enforcement ---

# Test: Level 1 blocks Write in IMPLEMENT phase (normally allowed)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level off
OUTPUT=$(run_gate "/project/src/main.py")
assert_contains "$OUTPUT" "deny" "Level 1 blocks Write in IMPLEMENT phase"

# Test: Level 1 denial message mentions /autonomy
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level off
OUTPUT=$(run_gate "/project/src/main.py")
assert_contains "$OUTPUT" "/autonomy" "Level 1 deny message mentions /autonomy command"

# Test: Level 1 does NOT block writes when phase is OFF
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
jq '.autonomy_level = "off"' "$TEST_DIR/.claude/state/workflow.json" > "$TEST_DIR/.claude/state/workflow.json.tmp" && mv "$TEST_DIR/.claude/state/workflow.json.tmp" "$TEST_DIR/.claude/state/workflow.json"
OUTPUT=$(run_gate "/project/src/main.py")
assert_not_contains "$OUTPUT" "deny" "Level 1 does NOT block writes when phase is OFF"

# Test: Level 2 allows writes in IMPLEMENT (current behavior)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level ask
OUTPUT=$(run_gate "/project/src/main.py")
assert_not_contains "$OUTPUT" "deny" "Level 2 allows writes in IMPLEMENT"

# Test: Level 3 allows writes in IMPLEMENT (current behavior)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level auto
OUTPUT=$(run_gate "/project/src/main.py")
assert_not_contains "$OUTPUT" "deny" "Level 3 allows writes in IMPLEMENT"

# Test: Level 2 still blocks writes in DISCUSS (phase gate preserved)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level ask
OUTPUT=$(run_gate "/project/src/main.py")
assert_contains "$OUTPUT" "deny" "Level 2 blocks writes in DISCUSS (phase gate)"

# Test: Level 3 still blocks writes in DISCUSS (phase gate preserved)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level auto
OUTPUT=$(run_gate "/project/src/main.py")
assert_contains "$OUTPUT" "deny" "Level 3 blocks writes in DISCUSS (phase gate)"

# ============================================================
# TEST SUITE: bash-write-guard.sh
# ============================================================
echo ""
echo "=== bash-write-guard.sh ==="

# Helper: run bash-write-guard with a command
run_bash_guard() {
    local cmd="$1"
    echo "{\"tool_input\":{\"command\":\"$cmd\"}}" | "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>&1 || true
}

# Test: allows all Bash in IMPLEMENT phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
OUTPUT=$(run_bash_guard "echo hello > file.txt")
assert_not_contains "$OUTPUT" "deny" "allows all Bash in IMPLEMENT phase"

# Test: allows all Bash in REVIEW phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review"
OUTPUT=$(run_bash_guard "echo hello > file.txt")
assert_not_contains "$OUTPUT" "deny" "allows all Bash in REVIEW phase"

# Test: allows read-only Bash in DISCUSS phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
OUTPUT=$(run_bash_guard "cat file.txt")
assert_not_contains "$OUTPUT" "deny" "allows 'cat file.txt' in DISCUSS"

OUTPUT=$(run_bash_guard "ls -la")
assert_not_contains "$OUTPUT" "deny" "allows 'ls -la' in DISCUSS"

OUTPUT=$(run_bash_guard "git status")
assert_not_contains "$OUTPUT" "deny" "allows 'git status' in DISCUSS"

OUTPUT=$(run_bash_guard "grep -r pattern .")
assert_not_contains "$OUTPUT" "deny" "allows 'grep -r pattern .' in DISCUSS"

# Test: blocks redirect in DISCUSS phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
OUTPUT=$(run_bash_guard "echo hello > file.txt")
assert_contains "$OUTPUT" "deny" "blocks 'echo hello > file.txt' in DISCUSS"

# Test: blocks append redirect in DISCUSS phase
OUTPUT=$(run_bash_guard "echo hello >> file.txt")
assert_contains "$OUTPUT" "deny" "blocks 'echo hello >> file.txt' in DISCUSS"

# Test: blocks sed -i in DISCUSS phase
OUTPUT=$(run_bash_guard "sed -i 's/old/new/' file.txt")
assert_contains "$OUTPUT" "deny" "blocks 'sed -i' in DISCUSS"

# Test: blocks tee in DISCUSS phase
OUTPUT=$(run_bash_guard "echo hello | tee file.txt")
assert_contains "$OUTPUT" "deny" "blocks 'tee' in DISCUSS"

# Test: blocks heredoc in DISCUSS phase
OUTPUT=$(run_bash_guard "cat > file.txt << EOF")
assert_contains "$OUTPUT" "deny" "blocks 'cat > file.txt << EOF' in DISCUSS"

# Test: blocks python file write in DISCUSS phase
OUTPUT=$(echo '{"tool_input":{"command":"python3 -c \"open('"'"'f'"'"','"'"'w'"'"').write('"'"'x'"'"')\""}}' | "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>&1 || true)
assert_contains "$OUTPUT" "deny" "blocks python3 -c file write in DISCUSS"

# Test: allows all Bash in OFF phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
OUTPUT=$(run_bash_guard "echo hello > file.txt")
assert_not_contains "$OUTPUT" "deny" "allows all Bash in OFF phase"

# Test: allows when no state file
setup_test_project
rm -f "$TEST_DIR/.claude/state/workflow.json"
OUTPUT=$(run_bash_guard "echo hello > file.txt")
assert_not_contains "$OUTPUT" "deny" "allows Bash writes when no state file (first run)"

# Test: allows writes to .claude/state/ in DISCUSS phase (whitelist)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
OUTPUT=$(run_bash_guard "echo test > .claude/state/workflow.json")
assert_not_contains "$OUTPUT" "deny" "allows Bash write to .claude/state/ in DISCUSS (whitelist)"

# Test: allows writes to docs/superpowers/specs/ in DISCUSS phase (whitelist)
OUTPUT=$(run_bash_guard "cat > docs/superpowers/specs/design.md << EOF")
assert_not_contains "$OUTPUT" "deny" "allows Bash write to docs/superpowers/specs/ in DISCUSS (whitelist)"

# Test: allows writes to docs/plans/ in DISCUSS phase (whitelist)
OUTPUT=$(run_bash_guard "echo 'plan content' > docs/plans/plan.md")
assert_not_contains "$OUTPUT" "deny" "allows Bash write to docs/plans/ in DISCUSS (whitelist)"

# Test: blocks Bash redirect in DEFINE phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "define"
OUTPUT=$(run_bash_guard "echo hello > file.txt")
assert_contains "$OUTPUT" "deny" "blocks 'echo hello > file.txt' in DEFINE"

# Test: allows read-only Bash in DEFINE phase
OUTPUT=$(run_bash_guard "cat file.txt")
assert_not_contains "$OUTPUT" "deny" "allows 'cat file.txt' in DEFINE"

# Test: allows writes to whitelisted paths in DEFINE
OUTPUT=$(run_bash_guard "echo test > .claude/state/workflow.json")
assert_not_contains "$OUTPUT" "deny" "allows Bash write to .claude/state/ in DEFINE (whitelist)"

OUTPUT=$(run_bash_guard "echo 'plan' > docs/plans/decisions.md")
assert_not_contains "$OUTPUT" "deny" "allows Bash write to docs/plans/ in DEFINE (whitelist)"

# Test: allows commands with 2>/dev/null in DISCUSS phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
OUTPUT=$(run_bash_guard "ssh-keygen -l -f key.pub 2>/dev/null")
assert_not_contains "$OUTPUT" "deny" "allows 'ssh-keygen -l 2>/dev/null' in DISCUSS"

OUTPUT=$(run_bash_guard "git config --list 2>&1")
assert_not_contains "$OUTPUT" "deny" "allows 'git config --list 2>&1' in DISCUSS"

OUTPUT=$(run_bash_guard "ykman list --serials 2>/dev/null")
assert_not_contains "$OUTPUT" "deny" "allows 'ykman list 2>/dev/null' in DISCUSS"

OUTPUT=$(run_bash_guard "some_cmd 2>/dev/null | grep pattern")
assert_not_contains "$OUTPUT" "deny" "allows 'cmd 2>/dev/null | grep' in DISCUSS"

# Test: still blocks real writes that also have 2>/dev/null
OUTPUT=$(run_bash_guard "echo x > file.txt 2>/dev/null")
assert_contains "$OUTPUT" "deny" "blocks 'echo x > file.txt 2>/dev/null' in DISCUSS"

OUTPUT=$(run_bash_guard "cat data >> output.txt 2>&1")
assert_contains "$OUTPUT" "deny" "blocks 'cat data >> output.txt 2>&1' in DISCUSS"

# Test: blocks rm in DISCUSS phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
OUTPUT=$(run_bash_guard "rm -rf src/")
assert_contains "$OUTPUT" "deny" "blocks 'rm -rf src/' in DISCUSS"

OUTPUT=$(run_bash_guard "rm file.txt")
assert_contains "$OUTPUT" "deny" "blocks 'rm file.txt' in DISCUSS"

# Test: fail-closed on empty/malformed command
OUTPUT=$(echo '{"tool_input":{}}' | "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>&1 || true)
assert_contains "$OUTPUT" "deny" "fail-closed on missing command field"

OUTPUT=$(echo '{}' | "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>&1 || true)
assert_contains "$OUTPUT" "deny" "fail-closed on empty JSON"

# Test: path traversal rejection
OUTPUT=$(run_bash_guard "echo x > ../../etc/passwd")
assert_contains "$OUTPUT" "deny" "blocks path traversal in write target"

OUTPUT=$(run_bash_guard "cp evil.sh ../../../outside")
assert_contains "$OUTPUT" "deny" "blocks path traversal in cp target"

# --- Autonomy level enforcement ---

# Test: Level 1 blocks Bash write in IMPLEMENT phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level off
OUTPUT=$(run_bash_guard 'echo data > output.txt')
assert_contains "$OUTPUT" "deny" "Level 1 blocks Bash write in IMPLEMENT phase"

# Test: Level 1 denial message mentions /autonomy
assert_contains "$OUTPUT" "/autonomy" "Level 1 bash deny message mentions /autonomy"

# Test: Level 2 allows Bash write in IMPLEMENT
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level ask
OUTPUT=$(run_bash_guard 'echo data > output.txt')
assert_not_contains "$OUTPUT" "deny" "Level 2 allows Bash write in IMPLEMENT"

# Test: Level 3 allows Bash write in IMPLEMENT
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level auto
OUTPUT=$(run_bash_guard 'echo data > output.txt')
assert_not_contains "$OUTPUT" "deny" "Level 3 allows Bash write in IMPLEMENT"

# Test: Level 2 still blocks Bash write in DISCUSS (phase gate preserved)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level ask
OUTPUT=$(run_bash_guard 'echo data > output.txt')
assert_contains "$OUTPUT" "deny" "Level 2 blocks Bash write in DISCUSS (phase gate)"

# Test: Level 1 allows read-only Bash commands in IMPLEMENT
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level off
OUTPUT=$(run_bash_guard 'ls -la')
assert_not_contains "$OUTPUT" "deny" "Level 1 allows read-only Bash in IMPLEMENT"

# Test: Level 1 rejects chained workflow-state command (bypass attempt)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level off
OUTPUT=$(run_bash_guard 'source .claude/hooks/workflow-state.sh && echo pwned > evil.txt')
assert_contains "$OUTPUT" "deny" "Level 1 blocks chained workflow-state bypass"

# --- git commit allowlist ---

# Test: git commit with HEREDOC allowed in DISCUSS
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level ask
RESULT=$(echo '{"tool_input":{"command":"git commit -m \"$(cat <<'"'"'EOF'"'"'\nfeat: something\nEOF\n)\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_eq "" "$RESULT" "bash-guard: git commit with HEREDOC allowed in DISCUSS"

# Test: git commit with simple message allowed in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"git commit -m \"feat: add feature\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_eq "" "$RESULT" "bash-guard: git commit with simple message allowed in DISCUSS"

# Test: git commit chained with destructive command blocked
RESULT=$(echo '{"tool_input":{"command":"git commit -m \"msg\" && rm -rf /"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: git commit && rm blocked"

# Test: git commit allowed at Level 1
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level off
RESULT=$(echo '{"tool_input":{"command":"git commit -m \"feat: something\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_eq "" "$RESULT" "bash-guard: git commit allowed at Level 1"

# Test: /usr/bin/git commit allowed (full path)
jq '.autonomy_level = "ask"' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
RESULT=$(echo '{"tool_input":{"command":"/usr/bin/git commit -m \"docs: test\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_eq "" "$RESULT" "bash-guard: /usr/bin/git commit allowed (full path)"

# --- Item 8: Write guard hardening ---

# Ensure we're in discuss phase for these tests
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
jq '.autonomy_level = "ask"' "$TEST_DIR/.claude/state/workflow.json" > "$TEST_DIR/.claude/state/workflow.json.tmp" && mv "$TEST_DIR/.claude/state/workflow.json.tmp" "$TEST_DIR/.claude/state/workflow.json"

# Test: multi-line python3 with open() blocked in DISCUSS
RESULT=$(printf '{"tool_input":{"command":"python3 -c \\\"\\nimport json\\nwith open('"'"'f'"'"','"'"'w'"'"') as fh:\\n  fh.write('"'"'x'"'"')\\n\\\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: multi-line python3 open() blocked in DISCUSS"

# Test: multi-line python3 with shutil blocked
RESULT=$(printf '{"tool_input":{"command":"python3 -c \\\"\\nimport shutil\\nshutil.copy('"'"'a'"'"','"'"'b'"'"')\\n\\\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: multi-line python3 shutil blocked"

# Test: multi-line python3 with subprocess blocked
RESULT=$(printf '{"tool_input":{"command":"python3 -c \\\"\\nimport subprocess\\nsubprocess.run(['"'"'cp'"'"','"'"'a'"'"','"'"'b'"'"'])\\n\\\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: multi-line python3 subprocess blocked"

# Test: multi-line python3 with os.system blocked
RESULT=$(printf '{"tool_input":{"command":"python3 -c \\\"\\nimport os\\nos.system('"'"'rm file'"'"')\\n\\\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: multi-line python3 os.system blocked"

# Test: harmless python3 -c allowed
RESULT=$(echo '{"tool_input":{"command":"python3 -c \"print('"'"'hello'"'"')\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_eq "" "$RESULT" "bash-guard: harmless python3 -c allowed in DISCUSS"

# Test: eval blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"eval \"echo data > file.txt\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: eval blocked in DISCUSS"

# Test: bash -c blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"bash -c \"cp src dst\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: bash -c blocked in DISCUSS"

# Test: sh -c blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"sh -c \"mv a b\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: sh -c blocked in DISCUSS"

# Test: chained cp (no ^ anchor) blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"cd /tmp && cp src dst"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: chained cp blocked in DISCUSS"

# Test: prefixed rm blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"VAR=x rm file"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: prefixed rm blocked in DISCUSS"

# Test: command cp blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"command cp src dst"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: command cp blocked in DISCUSS"

# Test: bash heredoc blocked
RESULT=$(echo '{"tool_input":{"command":"bash << EOF\necho hello\nEOF"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: bash heredoc blocked in DISCUSS"

# Test: python3 heredoc blocked
RESULT=$(echo '{"tool_input":{"command":"python3 << EOF\nprint(1)\nEOF"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: python3 heredoc blocked in DISCUSS"

# Test: sh heredoc blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"sh << EOF\necho hello\nEOF"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: sh heredoc blocked in DISCUSS"

# Test: touch blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"touch newfile.txt"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: touch blocked in DISCUSS"

# Test: truncate blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"truncate -s 0 file"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: truncate blocked in DISCUSS"

# Test: perl -i blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"perl -i -pe '"'"'s/old/new/'"'"' file"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: perl -i blocked in DISCUSS"

# Test: ruby -i blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"ruby -i -pe '\''gsub(/old/,\"new\")'\'' file"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: ruby -i blocked in DISCUSS"

# Test: tar xf blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"tar xf archive.tar"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: tar xf blocked in DISCUSS"

# Test: unzip blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"unzip archive.zip"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: unzip blocked in DISCUSS"

# Test: rsync blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"rsync -av src/ dst/"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: rsync blocked in DISCUSS"

# Regression: all new patterns allowed in IMPLEMENT
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
jq '.autonomy_level = "ask"' "$TEST_DIR/.claude/state/workflow.json" > "$TEST_DIR/.claude/state/workflow.json.tmp" && mv "$TEST_DIR/.claude/state/workflow.json.tmp" "$TEST_DIR/.claude/state/workflow.json"
RESULT=$(echo '{"tool_input":{"command":"eval \"echo hello\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_eq "" "$RESULT" "bash-guard: eval allowed in IMPLEMENT"

RESULT=$(echo '{"tool_input":{"command":"touch newfile.txt"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_eq "" "$RESULT" "bash-guard: touch allowed in IMPLEMENT"

# Regression: multi-line python3 blocked at Level 1 even in IMPLEMENT
jq '.autonomy_level = "off"' "$TEST_DIR/.claude/state/workflow.json" > "$TEST_DIR/.claude/state/workflow.json.tmp" && mv "$TEST_DIR/.claude/state/workflow.json.tmp" "$TEST_DIR/.claude/state/workflow.json"
RESULT=$(printf '{"tool_input":{"command":"python3 -c \\\"\\nwith open('"'"'f'"'"','"'"'w'"'"') as fh:\\n  fh.write('"'"'x'"'"')\\n\\\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: python3 write blocked at Level 1 in IMPLEMENT"

# Reset state
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"

# ============================================================
# TEST SUITE: install.sh (migration tool)
# ============================================================
echo ""
echo "=== install.sh (migration tool) ==="

# Test: detects and cleans old-style installation
MIGRATE_DIR=$(mktemp -d)
mkdir -p "$MIGRATE_DIR/.claude/hooks" "$MIGRATE_DIR/.claude"
# Create fake old-style hook files (regular files, not symlinks)
touch "$MIGRATE_DIR/.claude/hooks/workflow-gate.sh"
touch "$MIGRATE_DIR/.claude/hooks/bash-write-guard.sh"
touch "$MIGRATE_DIR/.claude/hooks/post-tool-navigator.sh"
touch "$MIGRATE_DIR/.claude/hooks/workflow-cmd.sh"
touch "$MIGRATE_DIR/.claude/hooks/workflow-state.sh"
cat > "$MIGRATE_DIR/.claude/settings.json" <<'OLDSETTINGS'
{
  "permissions": {"allow": ["Bash"]},
  "hooks": {
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "test"}]}]
  }
}
OLDSETTINGS
MIGRATE_OUTPUT=$(bash "$REPO_DIR/install.sh" "$MIGRATE_DIR" 2>&1 || true)
assert_contains "$MIGRATE_OUTPUT" "Old hook-based installation detected" "migration detects old installation"
assert_file_not_exists "$MIGRATE_DIR/.claude/hooks/workflow-gate.sh" "migration removes old workflow-gate.sh"
assert_file_not_exists "$MIGRATE_DIR/.claude/hooks/bash-write-guard.sh" "migration removes old bash-write-guard.sh"
# Verify hooks key removed from settings.json but permissions preserved
MIGRATED_HOOKS=$(jq -r 'if has("hooks") then "false" else "true" end' "$MIGRATE_DIR/.claude/settings.json")
assert_eq "true" "$MIGRATED_HOOKS" "migration removes hooks from settings.json"
MIGRATED_PERMS=$(jq -r 'if (.permissions.allow // [] | index("Bash")) != null then "true" else "false" end' "$MIGRATE_DIR/.claude/settings.json")
assert_eq "true" "$MIGRATED_PERMS" "migration preserves permissions in settings.json"
rm -rf "$MIGRATE_DIR"

# Test: no old installation prints plugin instructions
CLEAN_DIR=$(mktemp -d)
CLEAN_OUTPUT=$(bash "$REPO_DIR/install.sh" "$CLEAN_DIR" 2>&1 || true)
assert_contains "$CLEAN_OUTPUT" "plugin" "migration shows plugin install instructions"
rm -rf "$CLEAN_DIR"

# Test: does not remove symlinks (only regular files)
SYMLINK_DIR=$(mktemp -d)
mkdir -p "$SYMLINK_DIR/.claude/hooks"
ln -s /dev/null "$SYMLINK_DIR/.claude/hooks/workflow-gate.sh"
bash "$REPO_DIR/install.sh" "$SYMLINK_DIR" 2>&1 || true
if [ -L "$SYMLINK_DIR/.claude/hooks/workflow-gate.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} migration preserves symlinks"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} migration preserves symlinks"
    FAIL=$((FAIL + 1))
fi
rm -rf "$SYMLINK_DIR"

# ============================================================
# TEST SUITE: post-tool-navigator.sh
# ============================================================
echo ""
echo "=== post-tool-navigator.sh ==="

# Helper: run navigator with a tool name
run_navigator() {
    local tool="$1"
    echo "{\"tool_name\":\"$tool\"}" | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true
}

# Test: Layer 1 shows coaching message in IMPLEMENT phase on first Write
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(run_navigator "Write")
assert_contains "$OUTPUT" "Workflow Coach.*IMPLEMENT" "Layer 1 shows IMPLEMENT coaching message on Write"

# Test: Layer 1 silent on second tool use (message_shown = true)
OUTPUT=$(run_navigator "Edit")
assert_not_contains "$OUTPUT" "Workflow Coach.*IMPLEMENT" "Layer 1 silent after first message shown"

# Test: phase change resets message_shown
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review"
OUTPUT=$(run_navigator "Read")
assert_contains "$OUTPUT" "Workflow Coach.*REVIEW" "Layer 1 shows REVIEW message after phase change"

# Test: Layer 1 silent on Read/Grep in IMPLEMENT phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(run_navigator "Read")
assert_not_contains "$OUTPUT" "Workflow Coach" "Layer 1 silent on Read in IMPLEMENT"

OUTPUT=$(run_navigator "Grep")
assert_not_contains "$OUTPUT" "Workflow Coach" "Layer 1 silent on Grep in IMPLEMENT"

# Test: Layer 1 shows DISCUSS coaching message
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(run_navigator "Read")
assert_contains "$OUTPUT" "Workflow Coach.*DISCUSS" "Layer 1 shows DISCUSS coaching message"

# Test: no message when no state file
setup_test_project
rm -f "$TEST_DIR/.claude/state/workflow.json"
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(run_navigator "Write")
assert_not_contains "$OUTPUT" "Workflow Coach" "coach silent when no state file"

# Test: Layer 1 shows DEFINE coaching message
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "define"
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(run_navigator "Read")
assert_contains "$OUTPUT" "Workflow Coach.*DEFINE" "Layer 1 shows DEFINE coaching message"

# Test: Layer 1 shows COMPLETE coaching message
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(run_navigator "Read")
assert_contains "$OUTPUT" "Workflow Coach.*COMPLETE" "Layer 1 shows COMPLETE coaching message"

# Test: Layer 1 silent in OFF phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(run_navigator "Read")
assert_not_contains "$OUTPUT" "Workflow Coach" "Layer 1 silent in OFF phase"

# Test: hook exits cleanly (exit 0) for irrelevant tool types in active phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"

# These tools should exit cleanly with no output and exit code 0
for TOOL in Read Glob Grep TaskCreate TaskUpdate Skill ToolSearch; do
    EXIT_CODE=0
    OUTPUT=$(echo "{\"tool_name\":\"$TOOL\"}" | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1) || EXIT_CODE=$?
    assert_eq "0" "$EXIT_CODE" "hook exits 0 for $TOOL in DISCUSS"
    assert_not_contains "$OUTPUT" "Workflow Coach" "no coaching for $TOOL in DISCUSS"
done

# Test: irrelevant tools don't increment coaching counter
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
echo '{"tool_name":"Read"}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
echo '{"tool_name":"Glob"}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
echo '{"tool_name":"Grep"}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
CONTENT=$(cat "$TEST_DIR/.claude/state/workflow.json")
assert_contains "$CONTENT" '"tool_calls_since_agent": 0' "irrelevant tools don't increment coaching counter"

# Test: Layer 3 Check 1 — short agent prompt warning
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(echo '{"tool_name":"Agent","tool_input":{"prompt":"short"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "Agent prompts must be detailed" "Layer 3 fires for short agent prompt"

# Test: Layer 3 Check 1 — long agent prompt no warning
OUTPUT=$(echo '{"tool_name":"Agent","tool_input":{"prompt":"This is a sufficiently long prompt that exceeds the 150 character threshold and should not trigger the short agent prompt coaching warning from the Layer 3 anti-laziness check system"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_not_contains "$OUTPUT" "Agent prompts must be detailed" "Layer 3 silent for long agent prompt"

# Test: Layer 3 Check 2 — short commit message warning
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fix\""}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "Commit messages must explain why" "Layer 3 fires for short commit message"

# Test: Layer 3 Check 5 — skipping research (counter > 10)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
# Increment counter past 10
for i in $(seq 1 11); do
    source "$TEST_DIR/.claude/hooks/workflow-state.sh" && increment_coaching_counter
done
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"docs/superpowers/specs/test.md"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "haven.t dispatched background agents" "Layer 3 fires when counter > 10 in DISCUSS"

# Test: Layer 2 — agent return in DISCUSS triggers coaching
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(echo '{"tool_name":"Agent","tool_input":{"prompt":"This is a sufficiently long agent prompt that exceeds one hundred and fifty characters so that it does not trigger the short prompt warning from Layer 3 checks"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "Every approach must have stated downsides" "Layer 2 fires on Agent return in DISCUSS"

# Test: Layer 2 — agent return fires only once per phase
OUTPUT=$(echo '{"tool_name":"Agent","tool_input":{"prompt":"This is a sufficiently long agent prompt that exceeds one hundred and fifty characters so that it does not trigger the short prompt warning from Layer 3 checks"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_not_contains "$OUTPUT" "Every approach must have stated downsides" "Layer 2 silent on second Agent return in DISCUSS"

# Test: Layer 3 Check 2 — short HEREDOC commit message warning
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"$(cat <<'"'"'EOF'"'"'\\nfix\\n\\nCo-Authored-By: Claude\\nEOF\\n)\""}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "Commit messages must explain why" "Layer 3 fires for short HEREDOC commit message"

# Test: Layer 3 Check 2 — long HEREDOC commit message no warning
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"$(cat <<'"'"'EOF'"'"'\\nfeat: add comprehensive hallucination reduction standards from Anthropic docs\\n\\nCo-Authored-By: Claude\\nEOF\\n)\""}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_not_contains "$OUTPUT" "Commit messages must explain why" "Layer 3 silent for long HEREDOC commit message"

# Test: Layer 3 — no verify after code change
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
# Pre-fire Layer 2 source_edit trigger so it doesn't consume the first write
jq '.coaching.layer2_fired = ["source_edit"]' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
for i in $(seq 1 4); do
    echo '{"tool_name":"Write","tool_input":{"file_path":"src/main.py"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
done
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"src/main.py"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "haven.t run tests" "Layer 3 fires after source edits without verify"

# Test: verify clears the flag
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
echo '{"tool_name":"Write","tool_input":{"file_path":"src/main.py"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
echo '{"tool_name":"Write","tool_input":{"file_path":"src/main.py"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
echo '{"tool_name":"Bash","tool_input":{"command":"npm test"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
for i in $(seq 1 3); do
    echo '{"tool_name":"Write","tool_input":{"file_path":"src/other.py"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
done
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"src/other.py"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_not_contains "$OUTPUT" "haven.t run tests" "verify clears the pending_verify flag"

# Test: Layer 2 — decision record write in DEFINE triggers coaching
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "define"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"docs/plans/decisions.md"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "Challenge vague problem statements" "Layer 2 fires on decision record write in DEFINE"

# Test: Layer 2 — test run in COMPLETE triggers coaching
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"./tests/run-tests.sh"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "specific about validation failures" "Layer 2 fires on test run in COMPLETE"

# --- Autonomy level coaching ---

# Test: auto coaching includes auto-transition guidance
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level auto
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
jq '.message_shown = false' "$TEST_DIR/.claude/state/workflow.json" > "$TEST_DIR/.claude/state/workflow.json.tmp" && mv "$TEST_DIR/.claude/state/workflow.json.tmp" "$TEST_DIR/.claude/state/workflow.json"
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"/project/src/main.py"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "Unattended" "auto coaching mentions Unattended in phase entry"
assert_contains "$OUTPUT" "proceed" "auto coaching includes auto-transition guidance"

# Test: ask coaching does NOT include auto-transition guidance
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level ask
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
jq '.message_shown = false' "$TEST_DIR/.claude/state/workflow.json" > "$TEST_DIR/.claude/state/workflow.json.tmp" && mv "$TEST_DIR/.claude/state/workflow.json.tmp" "$TEST_DIR/.claude/state/workflow.json"
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"/project/src/main.py"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_not_contains "$OUTPUT" "Level 3" "Level 2 coaching does not mention Level 3"

# --- Claude-mem project enforcement ---

# Test: coaching fires when save_observation has no project field
setup_test_project
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
OUTPUT=$(echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__save_observation","tool_input":{"text":"some observation"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "without project" "coaching fires when save_observation missing project field"

# Test: coaching does NOT fire when save_observation has project field
setup_test_project
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
OUTPUT=$(echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__save_observation","tool_input":{"text":"some observation","project":"claude-code-workflows"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_not_contains "$OUTPUT" "without project" "no coaching when save_observation has project field"

# --- Observation ID capture ---

# Test: hook captures observation ID from save_observation response
setup_test_project
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__save_observation","tool_input":{"text":"test","project":"test"},"tool_response":{"content":[{"type":"text","text":"{\"success\":true,\"id\":4242,\"title\":\"test\",\"project\":\"test\",\"message\":\"Memory saved as observation #4242\"}"}]}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_last_observation_id)
assert_eq "4242" "$RESULT" "hook captures observation ID from save_observation"

# Test: hook captures observation ID from get_observations response
setup_test_project
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__get_observations","tool_input":{"ids":[1234]},"tool_response":{"content":[{"type":"text","text":"[{\"id\":1234,\"title\":\"test obs\"}]"}]}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_last_observation_id)
assert_eq "1234" "$RESULT" "hook captures observation ID from get_observations"

# --- Observation ID tracking in OFF phase ---

# Test: observation ID captured when phase is OFF + state file exists
jq -n '{"phase":"off","message_shown":false,"active_skill":"","decision_record":"","coaching":{"tool_calls_since_agent":0,"layer2_fired":[]},"autonomy_level":2}' > "$STATE_FILE"
echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__save_observation","tool_input":{"text":"test"},"tool_response":{"content":[{"type":"text","text":"{\"id\":9999,\"success\":true}"}]}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1
OBS_ID=$(jq -r '.last_observation_id // ""' "$STATE_FILE")
assert_eq "9999" "$OBS_ID" "obs-tracking: ID captured when phase is OFF"

# Test: observation ID captured when no state file exists
rm -f "$STATE_FILE"
echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__save_observation","tool_input":{"text":"test"},"tool_response":{"content":[{"type":"text","text":"{\"id\":8888,\"success\":true}"}]}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1
if [ -f "$STATE_FILE" ]; then
    OBS_ID=$(jq -r '.last_observation_id // ""' "$STATE_FILE")
    assert_eq "8888" "$OBS_ID" "obs-tracking: ID captured and state file created"
else
    assert_eq "exists" "missing" "obs-tracking: state file should have been created"
fi

# Test: observation ID still works in active phase (regression)
jq -n '{"phase":"discuss","message_shown":true,"active_skill":"","decision_record":"","coaching":{"tool_calls_since_agent":0,"layer2_fired":[]},"autonomy_level":2}' > "$STATE_FILE"
echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__get_observations","tool_input":{"ids":[1]},"tool_response":{"content":[{"type":"text","text":"[{\"id\":7777}]"}]}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1
OBS_ID=$(jq -r '.last_observation_id // ""' "$STATE_FILE")
assert_eq "7777" "$OBS_ID" "obs-tracking: ID captured in active phase (regression)"

# --- Coaching refresh tests ---

# Test: Layer 2 trigger fires normally (baseline)
jq -n '{"phase":"discuss","message_shown":true,"active_skill":"","decision_record":"","coaching":{"tool_calls_since_agent":0,"layer2_fired":[]},"autonomy_level":2}' > "$STATE_FILE"
echo '{"tool_name":"Agent","tool_input":{"prompt":"This is a test prompt with enough characters to avoid the short prompt check which requires at least 150 characters of content in the prompt field here"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
FIRED=$(jq -r '.coaching.layer2_fired // []' "$STATE_FILE")
assert_contains "$FIRED" "agent_return_discuss" "coaching: Layer 2 trigger fires on Agent return"

# Test: last_layer2_at is updated when trigger fires
L2_AT=$(jq -r '.coaching.last_layer2_at // "NOT_SET"' "$STATE_FILE")
assert_eq "0" "$L2_AT" "coaching: last_layer2_at set when trigger fires"

# Test: after 30 calls of silence, trigger can re-fire
jq '.coaching.tool_calls_since_agent = 31 | .coaching.last_layer2_at = 0' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
echo '{"tool_name":"Agent","tool_input":{"prompt":"This is another test prompt with enough characters to avoid the short prompt check which requires at least 150 characters of content in the prompt field here"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
FIRED_COUNT=$(jq -r '[.coaching.layer2_fired[]? | select(. == "agent_return_discuss")] | length' "$STATE_FILE")
assert_eq "1" "$FIRED_COUNT" "coaching: trigger re-fires after 30 calls of silence"
REFRESHED_AT=$(jq -r '.coaching.last_layer2_at // "NOT_SET"' "$STATE_FILE")
assert_eq "0" "$REFRESHED_AT" "coaching: last_layer2_at reset after refresh and re-fire"

# Test: backward compat — state file without last_layer2_at field
jq -n '{"phase":"discuss","message_shown":true,"active_skill":"","decision_record":"","coaching":{"tool_calls_since_agent":5,"layer2_fired":[]},"autonomy_level":2}' > "$STATE_FILE"
echo '{"tool_name":"Agent","tool_input":{"prompt":"This is a backward compat test prompt with enough characters to avoid the short prompt check which requires at least 150 characters of content here"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
RESULT=$?
assert_eq "0" "$RESULT" "coaching: no crash without last_layer2_at field"

# --- Observation extraction edge cases ---

# Setup for edge case tests
setup_test_project
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
STATE_FILE="$TEST_DIR/.claude/state/workflow.json"

# Set up state with a known observation ID
jq -n '{"phase":"discuss","message_shown":true,"active_skill":"","decision_record":"","coaching":{"tool_calls_since_agent":0,"layer2_fired":[]},"autonomy_level":2,"last_observation_id":1234}' > "$STATE_FILE"

# Test: empty content array — preserves existing ID
echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__save_observation","tool_input":{"text":"test"},"tool_response":{"content":[]}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
OBS_ID=$(jq -r '.last_observation_id // ""' "$STATE_FILE")
assert_eq "1234" "$OBS_ID" "obs-extraction: empty content preserves existing ID"

# Test: non-JSON text block — preserves existing ID
echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__save_observation","tool_input":{"text":"test"},"tool_response":{"content":[{"type":"text","text":"not valid json"}]}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
OBS_ID=$(jq -r '.last_observation_id // ""' "$STATE_FILE")
assert_eq "1234" "$OBS_ID" "obs-extraction: non-JSON preserves existing ID"

# Test: missing id field — preserves existing ID
echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__save_observation","tool_input":{"text":"test"},"tool_response":{"content":[{"type":"text","text":"{\"success\":true}"}]}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
OBS_ID=$(jq -r '.last_observation_id // ""' "$STATE_FILE")
assert_eq "1234" "$OBS_ID" "obs-extraction: missing id preserves existing ID"

# --- Layer 3 Check 3: all findings downgraded ---
setup_test_project
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
STATE_FILE="$TEST_DIR/.claude/state/workflow.json"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review"
jq '.message_shown = true' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

# Create a decisions.md with only Suggestions
DECISIONS_FILE="$TEST_DIR/docs/decisions.md"
mkdir -p "$(dirname "$DECISIONS_FILE")"
cat > "$DECISIONS_FILE" << 'DECFILE'
## Review Findings
### Suggestions
- Some minor thing
DECFILE

RESULT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$DECISIONS_FILE"'"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>/dev/null)
assert_contains "$RESULT" "downgrad" "coaching L3: warns when all findings are suggestions only"
rm -f "$DECISIONS_FILE"

# --- Layer 3 Check 4a: minimal handover ---
setup_test_project
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
STATE_FILE="$TEST_DIR/.claude/state/workflow.json"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
jq '.message_shown = true' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

RESULT=$(echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__save_observation","tool_input":{"text":"short","project":"test"},"tool_response":{"content":[{"type":"text","text":"{\"id\":1,\"success\":true}"}]}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>/dev/null)
assert_contains "$RESULT" "handover" "coaching L3: warns on minimal handover in COMPLETE"

# --- Layer 3 Check 6: options without recommendation ---
setup_test_project
cp "$HOOKS_DIR/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
STATE_FILE="$TEST_DIR/.claude/state/workflow.json"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
jq '.message_shown = true | .coaching.layer2_fired = ["agent_return_discuss"]' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

RESULT=$(echo '{"tool_name":"AskUserQuestion","tool_input":{"question":"which option?"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$RESULT" "recommend" "coaching L3: warns about options without recommendation"

# ============================================================
# TEST SUITE: statusline.sh
# ============================================================
echo ""
echo "=== statusline.sh ==="

STATUSLINE="$REPO_DIR/plugin/statusline/statusline.sh"

# Setup: ensure Workflow Manager plugin cache exists for statusline detection
WM_CACHE_DIR="$HOME/.claude/plugins/cache/azevedo-home-lab/workflow-manager"
WM_CACHE_EXISTED=false
if [ -d "$WM_CACHE_DIR" ]; then
    WM_CACHE_EXISTED=true
fi
mkdir -p "$WM_CACHE_DIR/1.0.0"

# Helper: run statusline with mock JSON
run_statusline() {
    echo "$1" | "$STATUSLINE" 2>/dev/null || true
}

# Test: parses model name
OUTPUT=$(run_statusline '{"model":{"display_name":"Opus 4.6"},"context_window":{"used_percentage":25,"context_window_size":200000,"current_usage":{"input_tokens":50000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cwd":"/tmp/test"}')
assert_contains "$OUTPUT" "Opus 4.6" "statusline shows model name"

# Test: shows percentage
assert_contains "$OUTPUT" "25%" "statusline shows context percentage"

# Test: shows token counts
assert_contains "$OUTPUT" "50k/200k" "statusline shows token counts (Xk/Yk)"

# Test: blue bar color for <50%
assert_contains "$OUTPUT" '\[34m' "statusline uses blue for <50% usage"

# Test: yellow bar for 50-80%
OUTPUT=$(run_statusline '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":65,"context_window_size":200000,"current_usage":{"input_tokens":130000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cwd":"/tmp/test"}')
assert_contains "$OUTPUT" '\[33m' "statusline uses yellow for 50-80% usage"

# Test: red bar for >80%
OUTPUT=$(run_statusline '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":90,"context_window_size":200000,"current_usage":{"input_tokens":180000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cwd":"/tmp/test"}')
assert_contains "$OUTPUT" '\[31m' "statusline uses red for >80% usage"

# Test: shows Workflow Manager ✗ when not installed
OUTPUT=$(run_statusline '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":10,"context_window_size":200000,"current_usage":{"input_tokens":20000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cwd":"/tmp/nonexistent"}')
assert_contains "$OUTPUT" "Workflow Manager" "statusline shows Workflow Manager label"

# Test: handles missing token data gracefully
OUTPUT=$(run_statusline '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":0},"cwd":"/tmp/test"}')
assert_contains "$OUTPUT" "0%" "statusline handles missing token data"

# Test: shows Superpowers ✓ when plugin installed
if [ -d "$HOME/.claude/plugins/cache/superpowers-marketplace" ]; then
    OUTPUT=$(run_statusline '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":10,"context_window_size":200000,"current_usage":{"input_tokens":20000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cwd":"/tmp/test"}')
    assert_contains "$OUTPUT" "Superpowers" "statusline shows Superpowers label"
fi

# Test: shows active skill in statusline (from workflow.json)
SL_TEST_DIR=$(mktemp -d)
mkdir -p "$SL_TEST_DIR/.claude/state"
echo '{"phase": "discuss", "message_shown": false, "active_skill": "brainstorming"}' > "$SL_TEST_DIR/.claude/state/workflow.json"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_TEST_DIR\"}")
assert_contains "$OUTPUT" "brainstorming" "statusline shows active skill name from workflow.json"
rm -rf "$SL_TEST_DIR"

# Test: no skill shown when active_skill field is empty
SL_TEST_DIR2=$(mktemp -d)
mkdir -p "$SL_TEST_DIR2/.claude/state"
echo '{"phase": "off", "message_shown": false, "active_skill": ""}' > "$SL_TEST_DIR2/.claude/state/workflow.json"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_TEST_DIR2\"}")
CLEAN_OUTPUT=$(echo "$OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
assert_not_contains "$CLEAN_OUTPUT" "\[\]" "statusline hides empty skill brackets"
rm -rf "$SL_TEST_DIR2"

# Test: shows DEFINE phase in statusline
SL_DEFINE_DIR=$(mktemp -d)
mkdir -p "$SL_DEFINE_DIR/.claude/state"
echo '{"phase": "define", "message_shown": false, "active_skill": ""}' > "$SL_DEFINE_DIR/.claude/state/workflow.json"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_DEFINE_DIR\"}")
assert_contains "$OUTPUT" "DEFINE" "statusline shows DEFINE phase label"
assert_contains "$OUTPUT" '\[34m' "statusline uses blue (\\033[34m) for DEFINE phase"
rm -rf "$SL_DEFINE_DIR"

# Test: shows COMPLETE phase in statusline with magenta
SL_COMPLETE_DIR=$(mktemp -d)
mkdir -p "$SL_COMPLETE_DIR/.claude/state"
echo '{"phase": "complete", "message_shown": false, "active_skill": ""}' > "$SL_COMPLETE_DIR/.claude/state/workflow.json"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_COMPLETE_DIR\"}")
assert_contains "$OUTPUT" "COMPLETE" "statusline shows COMPLETE phase label"
assert_contains "$OUTPUT" '\[35m' "statusline uses magenta (\\033[35m) for COMPLETE phase"
rm -rf "$SL_COMPLETE_DIR"

# --- Autonomy level symbols ---

# Test: Level 1 renders ▶ before phase
SL_AUTO1_DIR=$(mktemp -d)
mkdir -p "$SL_AUTO1_DIR/.claude/state"
echo '{"phase": "implement", "autonomy_level": "off", "message_shown": false, "active_skill": ""}' > "$SL_AUTO1_DIR/.claude/state/workflow.json"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_AUTO1_DIR\"}")
assert_contains "$OUTPUT" "▶ " "statusline shows ▶ for Level 1"
assert_contains "$OUTPUT" "IMPLEMENT" "statusline still shows phase at Level 1"
rm -rf "$SL_AUTO1_DIR"

# Test: Level 2 renders ▶▶ before phase
SL_AUTO2_DIR=$(mktemp -d)
mkdir -p "$SL_AUTO2_DIR/.claude/state"
echo '{"phase": "discuss", "autonomy_level": "ask", "message_shown": false, "active_skill": ""}' > "$SL_AUTO2_DIR/.claude/state/workflow.json"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_AUTO2_DIR\"}")
assert_contains "$OUTPUT" "▶▶ " "statusline shows ▶▶ for Level 2"
rm -rf "$SL_AUTO2_DIR"

# Test: Level 3 renders ▶▶▶ before phase
SL_AUTO3_DIR=$(mktemp -d)
mkdir -p "$SL_AUTO3_DIR/.claude/state"
echo '{"phase": "review", "autonomy_level": "auto", "message_shown": false, "active_skill": ""}' > "$SL_AUTO3_DIR/.claude/state/workflow.json"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_AUTO3_DIR\"}")
assert_contains "$OUTPUT" "▶▶▶ " "statusline shows ▶▶▶ for Level 3"
rm -rf "$SL_AUTO3_DIR"

# Test: No symbol when workflow is OFF
SL_AUTOOFF_DIR=$(mktemp -d)
mkdir -p "$SL_AUTOOFF_DIR/.claude/state"
echo '{"phase": "off", "message_shown": false, "active_skill": ""}' > "$SL_AUTOOFF_DIR/.claude/state/workflow.json"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_AUTOOFF_DIR\"}")
CLEAN_OUTPUT=$(echo "$OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
assert_not_contains "$CLEAN_OUTPUT" "▶" "statusline shows no autonomy symbol when OFF"
rm -rf "$SL_AUTOOFF_DIR"

# Test: No symbol when autonomy_level field absent
SL_AUTOABS_DIR=$(mktemp -d)
mkdir -p "$SL_AUTOABS_DIR/.claude/state"
echo '{"phase": "implement", "message_shown": false, "active_skill": ""}' > "$SL_AUTOABS_DIR/.claude/state/workflow.json"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_AUTOABS_DIR\"}")
CLEAN_OUTPUT=$(echo "$OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
assert_not_contains "$CLEAN_OUTPUT" "▶" "statusline shows no autonomy symbol when field absent"
rm -rf "$SL_AUTOABS_DIR"

# --- Claude-Mem observation ID in statusline ---

# Test: statusline shows observation ID when present
SL_OBS_DIR=$(mktemp -d)
mkdir -p "$SL_OBS_DIR/.claude/state"
echo '{"phase": "implement", "autonomy_level": "ask", "last_observation_id": 3007, "message_shown": true, "active_skill": ""}' > "$SL_OBS_DIR/.claude/state/workflow.json"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_OBS_DIR\",\"mcp_servers\":[\"claude-mem\"]}")
assert_contains "$OUTPUT" "[#3007]" "statusline shows observation ID in brackets when present"
assert_contains "$OUTPUT" "Claude-Mem" "statusline still shows Claude-Mem label"
rm -rf "$SL_OBS_DIR"

# Test: statusline shows no ID when field absent
SL_NOOBS_DIR=$(mktemp -d)
mkdir -p "$SL_NOOBS_DIR/.claude/state"
echo '{"phase": "implement", "message_shown": true, "active_skill": ""}' > "$SL_NOOBS_DIR/.claude/state/workflow.json"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_NOOBS_DIR\",\"mcp_servers\":[\"claude-mem\"]}")
CLEAN_OUTPUT=$(echo "$OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
assert_not_contains "$CLEAN_OUTPUT" "#[0-9]" "statusline shows no observation ID when field absent"
rm -rf "$SL_NOOBS_DIR"

# Teardown: clean up Workflow Manager plugin cache if we created it
if [ "$WM_CACHE_EXISTED" = "false" ]; then
    rm -rf "$HOME/.claude/plugins/cache/azevedo-home-lab"
fi

# ============================================================
# TEST SUITE: COMPLETE phase edit-blocking
# ============================================================
echo ""
echo "=== COMPLETE phase edit-blocking ==="

# Test: blocks Write to source code in COMPLETE phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
OUTPUT=$(run_gate "/project/src/main.py")
assert_contains "$OUTPUT" "deny" "blocks Write to source code in COMPLETE phase"
assert_contains "$OUTPUT" "COMPLETE" "shows COMPLETE in deny message"

# Test: allows Write to docs/ in COMPLETE phase
OUTPUT=$(run_gate "/project/docs/reference/architecture.md")
assert_not_contains "$OUTPUT" "deny" "allows Write to docs/ in COMPLETE phase"

# Test: allows Write to root-level *.md in COMPLETE phase
OUTPUT=$(run_gate "README.md")
assert_not_contains "$OUTPUT" "deny" "allows Write to README.md in COMPLETE phase"

OUTPUT=$(run_gate "CONTRIBUTING.md")
assert_not_contains "$OUTPUT" "deny" "allows Write to CONTRIBUTING.md in COMPLETE phase"

# Test: allows Write to .claude/state/ in COMPLETE phase
OUTPUT=$(run_gate "/project/.claude/state/workflow.json")
assert_not_contains "$OUTPUT" "deny" "allows Write to .claude/state/ in COMPLETE phase"

# Test: blocks Write to .claude/hooks/ in COMPLETE phase (security)
OUTPUT=$(run_gate "/project/.claude/hooks/workflow-gate.sh")
assert_contains "$OUTPUT" "deny" "blocks Write to .claude/hooks/ in COMPLETE phase (security)"

# Test: blocks Bash writes in COMPLETE phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
OUTPUT=$(run_bash_guard "echo hello > src/main.py")
assert_contains "$OUTPUT" "deny" "blocks Bash write to source in COMPLETE phase"

# Test: allows Bash writes to docs/ in COMPLETE phase
OUTPUT=$(run_bash_guard "echo content > docs/guide.md")
assert_not_contains "$OUTPUT" "deny" "allows Bash write to docs/ in COMPLETE phase"

# Test: .claude/commands/ writable in COMPLETE phase (workflow-gate)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
OUTPUT=$(run_gate "$TEST_DIR/.claude/commands/foo.md")
assert_not_contains "$OUTPUT" "deny" "allows Write to .claude/commands/ in COMPLETE phase"

# Test: .claude/commands/ blocked in DISCUSS phase (workflow-gate)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
OUTPUT=$(run_gate "$TEST_DIR/.claude/commands/foo.md")
assert_contains "$OUTPUT" "deny" ".claude/commands/ blocked in DISCUSS phase"

# Test: .claude/hooks/ still blocked in COMPLETE phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
OUTPUT=$(run_gate "$TEST_DIR/.claude/hooks/foo.sh")
assert_contains "$OUTPUT" "deny" ".claude/hooks/ still blocked in COMPLETE phase"

# ============================================================
# TEST SUITE: Whitelist security
# ============================================================
echo ""
echo "=== Whitelist security ==="

# Test: .claude/hooks/ blocked in DEFINE phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "define"
OUTPUT=$(run_gate "/project/.claude/hooks/workflow-gate.sh")
assert_contains "$OUTPUT" "deny" "blocks Write to .claude/hooks/ in DEFINE phase (security)"

# Test: .claude/hooks/ blocked in DISCUSS phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
OUTPUT=$(run_gate "/project/.claude/hooks/workflow-gate.sh")
assert_contains "$OUTPUT" "deny" "blocks Write to .claude/hooks/ in DISCUSS phase (security)"

# ============================================================
# TEST SUITE: Soft gate checks
# ============================================================
echo ""
echo "=== Soft gate checks ==="

# Test: implement gate warns when no plan file
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && check_soft_gate "implement")
assert_contains "$RESULT" "No plan" "implement gate warns when no plan exists"

# Test: implement gate silent when plan file exists
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
mkdir -p "$TEST_DIR/docs/superpowers/plans"
echo "# Plan" > "$TEST_DIR/docs/superpowers/plans/2026-01-01-test.md"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && check_soft_gate "implement")
assert_eq "" "$RESULT" "implement gate silent when plan exists"

# Test: complete gate warns when review not done
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && check_soft_gate "complete")
assert_contains "$RESULT" "Review" "complete gate warns when review not done"

# Test: complete gate silent when review acknowledged
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && reset_review_status
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_review_field "findings_acknowledged" "true"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && check_soft_gate "complete")
assert_eq "" "$RESULT" "complete gate silent when review acknowledged"

# Test: discuss gate has no warning
setup_test_project
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && check_soft_gate "discuss")
assert_eq "" "$RESULT" "discuss gate has no warning"

# Test: define gate has no warning
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && check_soft_gate "define")
assert_eq "" "$RESULT" "define gate has no warning"

# ============================================================
# TEST SUITE: workflow.json new API functions
# ============================================================
echo ""
echo "=== workflow.json API ==="

# Test: set_active_skill / get_active_skill round-trip
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_active_skill "brainstorming"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_active_skill)
assert_eq "brainstorming" "$RESULT" "set/get_active_skill round-trip"

# Test: set_decision_record / get_decision_record round-trip
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_decision_record "docs/plans/2026-01-01-test-decisions.md"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_decision_record)
assert_eq "docs/plans/2026-01-01-test-decisions.md" "$RESULT" "set/get_decision_record round-trip"

# Test: coaching sub-object resets on phase change
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "define"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && increment_coaching_counter
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && increment_coaching_counter
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
CONTENT=$(cat "$TEST_DIR/.claude/state/workflow.json")
assert_contains "$CONTENT" '"tool_calls_since_agent": 0' "coaching counter resets on phase change"

# Test: coaching counter increments
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "define"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && increment_coaching_counter
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && increment_coaching_counter
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && increment_coaching_counter
CONTENT=$(cat "$TEST_DIR/.claude/state/workflow.json")
assert_contains "$CONTENT" '"tool_calls_since_agent": 3' "coaching counter increments to 3"

# Test: coaching counter resets on Agent dispatch
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && reset_coaching_counter
CONTENT=$(cat "$TEST_DIR/.claude/state/workflow.json")
assert_contains "$CONTENT" '"tool_calls_since_agent": 0' "coaching counter resets to 0"

# Test: has_coaching_fired / add_coaching_fired tracking
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "define"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && has_coaching_fired "agent_return")
assert_eq "false" "$RESULT" "has_coaching_fired returns false initially"

source "$TEST_DIR/.claude/hooks/workflow-state.sh" && add_coaching_fired "agent_return"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && has_coaching_fired "agent_return")
assert_eq "true" "$RESULT" "has_coaching_fired returns true after adding"

RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && has_coaching_fired "plan_write")
assert_eq "false" "$RESULT" "has_coaching_fired tracks types independently"

# ============================================================
# TEST SUITE: git-yubikey
# ============================================================
echo ""
echo "=== git-yubikey ==="

GIT_YUBIKEY="$REPO_DIR/tools/yubikey-setup/git-yubikey"

# Helper: run git-yubikey with mock ykman and capture output
# We mock ykman and git to test the wrapper logic without real hardware
MOCK_BIN=$(mktemp -d)

# Mock ykman that reports YubiKey present
cat > "$MOCK_BIN/ykman-present" << 'MOCKEOF'
#!/bin/bash
echo "12345678"
MOCKEOF
chmod +x "$MOCK_BIN/ykman-present"

# Mock ykman that reports YubiKey absent
cat > "$MOCK_BIN/ykman-absent" << 'MOCKEOF'
#!/bin/bash
exit 1
MOCKEOF
chmod +x "$MOCK_BIN/ykman-absent"

# Mock git that just echoes what it would do
cat > "$MOCK_BIN/mock-git" << 'MOCKEOF'
#!/bin/bash
echo "MOCK_GIT_CALLED: $*"
MOCKEOF
chmod +x "$MOCK_BIN/mock-git"

# Test: blocks all git when YubiKey is absent
OUTPUT=$(YKMAN_CMD="$MOCK_BIN/ykman-absent" GIT_CMD="$MOCK_BIN/mock-git" "$GIT_YUBIKEY" status 2>&1) || true
assert_contains "$OUTPUT" "YubiKey" "shows YubiKey error when absent"
assert_not_contains "$OUTPUT" "MOCK_GIT_CALLED" "does not call git when YubiKey absent"

# Test: allows safe commands when YubiKey present (no confirmation)
OUTPUT=$(YKMAN_CMD="$MOCK_BIN/ykman-present" GIT_CMD="$MOCK_BIN/mock-git" "$GIT_YUBIKEY" status 2>&1)
assert_contains "$OUTPUT" "MOCK_GIT_CALLED: status" "passes safe command through"

OUTPUT=$(YKMAN_CMD="$MOCK_BIN/ykman-present" GIT_CMD="$MOCK_BIN/mock-git" "$GIT_YUBIKEY" commit -m "test" 2>&1)
assert_contains "$OUTPUT" "MOCK_GIT_CALLED: commit -m test" "passes commit through without confirmation"

OUTPUT=$(YKMAN_CMD="$MOCK_BIN/ykman-present" GIT_CMD="$MOCK_BIN/mock-git" "$GIT_YUBIKEY" push origin main 2>&1)
assert_contains "$OUTPUT" "MOCK_GIT_CALLED: push origin main" "passes normal push through"

# Test: dangerous commands show confirmation prompt
OUTPUT=$(echo "n" | YKMAN_CMD="$MOCK_BIN/ykman-present" GIT_CMD="$MOCK_BIN/mock-git" "$GIT_YUBIKEY" push --force origin main 2>&1) || true
assert_contains "$OUTPUT" "DESTRUCTIVE" "shows DESTRUCTIVE warning for push --force"
assert_not_contains "$OUTPUT" "MOCK_GIT_CALLED" "aborts when user says no"

OUTPUT=$(echo "n" | YKMAN_CMD="$MOCK_BIN/ykman-present" GIT_CMD="$MOCK_BIN/mock-git" "$GIT_YUBIKEY" push --delete origin feature 2>&1) || true
assert_contains "$OUTPUT" "DESTRUCTIVE" "shows DESTRUCTIVE warning for push --delete"

OUTPUT=$(echo "n" | YKMAN_CMD="$MOCK_BIN/ykman-present" GIT_CMD="$MOCK_BIN/mock-git" "$GIT_YUBIKEY" branch -D feature 2>&1) || true
assert_contains "$OUTPUT" "DESTRUCTIVE" "shows DESTRUCTIVE warning for branch -D"

OUTPUT=$(echo "n" | YKMAN_CMD="$MOCK_BIN/ykman-present" GIT_CMD="$MOCK_BIN/mock-git" "$GIT_YUBIKEY" push -f origin main 2>&1) || true
assert_contains "$OUTPUT" "DESTRUCTIVE" "shows DESTRUCTIVE warning for push -f"

# Test: dangerous command proceeds when user confirms
OUTPUT=$(echo "y" | YKMAN_CMD="$MOCK_BIN/ykman-present" GIT_CMD="$MOCK_BIN/mock-git" "$GIT_YUBIKEY" push --force origin main 2>&1)
assert_contains "$OUTPUT" "MOCK_GIT_CALLED" "proceeds when user confirms dangerous command"

# Test: dangerous command --force-with-lease
OUTPUT=$(echo "n" | YKMAN_CMD="$MOCK_BIN/ykman-present" GIT_CMD="$MOCK_BIN/mock-git" "$GIT_YUBIKEY" push --force-with-lease origin main 2>&1) || true
assert_contains "$OUTPUT" "DESTRUCTIVE" "shows DESTRUCTIVE warning for push --force-with-lease"

# Test: dangerous command branch -M
OUTPUT=$(echo "n" | YKMAN_CMD="$MOCK_BIN/ykman-present" GIT_CMD="$MOCK_BIN/mock-git" "$GIT_YUBIKEY" branch -M main new-main 2>&1) || true
assert_contains "$OUTPUT" "DESTRUCTIVE" "shows DESTRUCTIVE warning for branch -M"

# Test: exit code 1 when YubiKey absent
EXIT_CODE=0
YKMAN_CMD="$MOCK_BIN/ykman-absent" GIT_CMD="$MOCK_BIN/mock-git" "$GIT_YUBIKEY" status 2>&1 || EXIT_CODE=$?
assert_eq "1" "$EXIT_CODE" "exit code 1 when YubiKey absent"

# Test: exit code 1 when user aborts dangerous command
EXIT_CODE=0
echo "n" | YKMAN_CMD="$MOCK_BIN/ykman-present" GIT_CMD="$MOCK_BIN/mock-git" "$GIT_YUBIKEY" push --force origin main 2>&1 || EXIT_CODE=$?
assert_eq "1" "$EXIT_CODE" "exit code 1 when user aborts dangerous command"

rm -rf "$MOCK_BIN"

# ============================================================
# TEST SUITE: Plugin Structure
# ============================================================
echo ""
echo "=== Plugin Structure ==="

# Verify all required plugin files exist
assert_file_exists "$REPO_DIR/plugin/.claude-plugin/plugin.json" "plugin/.claude-plugin/plugin.json exists"
assert_file_exists "$REPO_DIR/.claude-plugin/marketplace.json" ".claude-plugin/marketplace.json exists"
assert_file_exists "$REPO_DIR/.claude-plugin/plugin.json" ".claude-plugin/plugin.json exists"
assert_file_exists "$REPO_DIR/plugin/hooks/hooks.json" "plugin/hooks/hooks.json exists"
assert_file_exists "$REPO_DIR/plugin/scripts/setup.sh" "plugin/scripts/setup.sh exists"
assert_file_exists "$REPO_DIR/plugin/statusline/statusline.sh" "plugin/statusline/statusline.sh exists"
assert_file_exists "$REPO_DIR/plugin/docs/reference/professional-standards.md" "plugin/docs/reference/professional-standards.md exists"

# Verify all 6 commands exist in plugin
for cmd in define discuss implement review complete autonomy; do
    assert_file_exists "$REPO_DIR/plugin/commands/$cmd.md" "plugin/commands/$cmd.md exists"
done

# Verify all 5 scripts exist in plugin (plus setup.sh)
for script in workflow-state.sh workflow-cmd.sh workflow-gate.sh bash-write-guard.sh post-tool-navigator.sh; do
    assert_file_exists "$REPO_DIR/plugin/scripts/$script" "plugin/scripts/$script exists"
done

# Verify symlinks in .claude/hooks/ point to plugin/scripts/
for script in workflow-state.sh workflow-cmd.sh workflow-gate.sh bash-write-guard.sh post-tool-navigator.sh; do
    if [ -L "$REPO_DIR/.claude/hooks/$script" ]; then
        echo -e "  ${GREEN}PASS${NC} .claude/hooks/$script is a symlink"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} .claude/hooks/$script is a symlink"
        FAIL=$((FAIL + 1))
        ERRORS="$ERRORS\n  FAIL: .claude/hooks/$script is a symlink"
    fi
done

# Verify symlinks in .claude/commands/ point to plugin/commands/
for cmd in define discuss implement review complete autonomy; do
    if [ -L "$REPO_DIR/.claude/commands/$cmd.md" ]; then
        echo -e "  ${GREEN}PASS${NC} .claude/commands/$cmd.md is a symlink"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} .claude/commands/$cmd.md is a symlink"
        FAIL=$((FAIL + 1))
        ERRORS="$ERRORS\n  FAIL: .claude/commands/$cmd.md is a symlink"
    fi
done

# Verify commands no longer contain WF_DIR boilerplate
for cmd in define discuss implement review complete autonomy; do
    if grep -q 'CLAUDE_PROJECT_DIR.*git rev-parse' "$REPO_DIR/plugin/commands/$cmd.md" 2>/dev/null; then
        echo -e "  ${RED}FAIL${NC} plugin/commands/$cmd.md has no WF_DIR boilerplate"
        FAIL=$((FAIL + 1))
        ERRORS="$ERRORS\n  FAIL: plugin/commands/$cmd.md has no WF_DIR boilerplate"
    else
        echo -e "  ${GREEN}PASS${NC} plugin/commands/$cmd.md has no WF_DIR boilerplate"
        PASS=$((PASS + 1))
    fi
done

# Verify hooks.json references CLAUDE_PLUGIN_ROOT
assert_contains "$(cat "$REPO_DIR/plugin/hooks/hooks.json")" "CLAUDE_PLUGIN_ROOT" "hooks.json uses CLAUDE_PLUGIN_ROOT"

# ============================================================
# TEST SUITE: Version Sync
# ============================================================
echo ""
echo "=== Version Sync ==="

SYNC_OUTPUT=$(bash "$REPO_DIR/scripts/check-version-sync.sh" 2>&1)
SYNC_EXIT=$?
assert_eq "0" "$SYNC_EXIT" "Version sync check passes"
assert_contains "$SYNC_OUTPUT" "All versions in sync" "Version sync reports success"

# Test version mismatch detection
ORIG_VERSION=$(jq -r '.version' "$REPO_DIR/plugin/.claude-plugin/plugin.json")
jq '.version = "99.99.99"' "$REPO_DIR/plugin/.claude-plugin/plugin.json" > "$REPO_DIR/plugin/.claude-plugin/plugin.json.tmp" && mv "$REPO_DIR/plugin/.claude-plugin/plugin.json.tmp" "$REPO_DIR/plugin/.claude-plugin/plugin.json"
MISMATCH_OUTPUT=$(bash "$REPO_DIR/scripts/check-version-sync.sh" 2>&1) && MISMATCH_EXIT=0 || MISMATCH_EXIT=$?
jq --arg v "$ORIG_VERSION" '.version = $v' "$REPO_DIR/plugin/.claude-plugin/plugin.json" > "$REPO_DIR/plugin/.claude-plugin/plugin.json.tmp" && mv "$REPO_DIR/plugin/.claude-plugin/plugin.json.tmp" "$REPO_DIR/plugin/.claude-plugin/plugin.json"
assert_eq "1" "$MISMATCH_EXIT" "Version sync detects mismatch"
assert_contains "$MISMATCH_OUTPUT" "mismatch" "Version sync reports mismatch"

# Test field mismatch detection (name differs between plugin.json files)
ORIG_NAME=$(jq -r '.name' "$REPO_DIR/plugin/.claude-plugin/plugin.json")
jq '.name = "wrong-name"' "$REPO_DIR/plugin/.claude-plugin/plugin.json" > "$REPO_DIR/plugin/.claude-plugin/plugin.json.tmp" && mv "$REPO_DIR/plugin/.claude-plugin/plugin.json.tmp" "$REPO_DIR/plugin/.claude-plugin/plugin.json"
FIELD_OUTPUT=$(bash "$REPO_DIR/scripts/check-version-sync.sh" 2>&1) && FIELD_EXIT=0 || FIELD_EXIT=$?
jq --arg n "$ORIG_NAME" '.name = $n' "$REPO_DIR/plugin/.claude-plugin/plugin.json" > "$REPO_DIR/plugin/.claude-plugin/plugin.json.tmp" && mv "$REPO_DIR/plugin/.claude-plugin/plugin.json.tmp" "$REPO_DIR/plugin/.claude-plugin/plugin.json"
assert_eq "1" "$FIELD_EXIT" "Version sync detects field mismatch"
assert_contains "$FIELD_OUTPUT" "Field" "Version sync reports field mismatch"

# ============================================================
# TEST SUITE: Tracked Observations Lifecycle
# ============================================================
echo ""
echo "=== Tracked Observations Lifecycle ==="

setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh"

# Test: add_tracked_observation adds to empty list
set_phase "off"
jq 'del(.tracked_observations)' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
add_tracked_observation 100
assert_eq "100" "$(get_tracked_observations)" "add_tracked_observation adds to empty list"

# Test: add_tracked_observation appends
add_tracked_observation 200
assert_eq "100,200" "$(get_tracked_observations)" "add_tracked_observation appends to list"

# Test: add_tracked_observation is idempotent
add_tracked_observation 100
assert_eq "100,200" "$(get_tracked_observations)" "add_tracked_observation is idempotent"

# Test: remove_tracked_observation removes single item
remove_tracked_observation 100
assert_eq "200" "$(get_tracked_observations)" "remove_tracked_observation removes single item"

# Test: set_tracked_observations replaces entire list
set_tracked_observations "500,600,700"
assert_eq "500,600,700" "$(get_tracked_observations)" "set_tracked_observations replaces entire list"

# Test: get_tracked_observations returns empty string for no list
jq 'del(.tracked_observations)' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
assert_eq "" "$(get_tracked_observations)" "get_tracked_observations returns empty for missing field"

# Test: set_tracked_observations with empty string clears list
set_tracked_observations "100,200"
set_tracked_observations ""
assert_eq "" "$(get_tracked_observations)" "set_tracked_observations with empty string clears list"

# Test: tracked observations preserved across phase transitions
set_tracked_observations "3416"
set_phase "define"
assert_eq "3416" "$(get_tracked_observations)" "tracked observations preserved: off → define"
set_phase "implement"
assert_eq "3416" "$(get_tracked_observations)" "tracked observations preserved: define → implement"
set_phase "off"
assert_eq "3416" "$(get_tracked_observations)" "tracked observations preserved: implement → off"

# Test: set_tracked_observations skips non-numeric CSV elements
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh"
set_phase "implement"
set_tracked_observations "1,abc,3"
RESULT=$(get_tracked_observations)
assert_eq "1,3" "$RESULT" "set_tracked_observations skips non-numeric CSV elements"

# ============================================================
# TEST SUITE: _update_state Safety Guards
# ============================================================
echo ""
echo "=== _update_state Safety Guards ==="

setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh"
set_phase "off"

# Test: 10KB size guard rejects oversized writes
OVERSIZE_ERR=$(_update_state '.bloat = ("x" * 12000)' 2>&1) && OVERSIZE_EXIT=0 || OVERSIZE_EXIT=$?
assert_eq "1" "$OVERSIZE_EXIT" "size guard: rejects write exceeding 10KB"
assert_contains "$OVERSIZE_ERR" "10KB" "size guard: error message mentions 10KB"
# Verify original state file is unchanged (phase still "off")
PHASE_AFTER=$(jq -r '.phase' "$STATE_FILE")
assert_eq "off" "$PHASE_AFTER" "size guard: state file unchanged after rejection"

# Test: temp file cleaned up on jq failure
INVALID_ERR=$(_update_state 'INVALID_SYNTAX!!!' 2>&1) && INVALID_EXIT=0 || INVALID_EXIT=$?
assert_eq "1" "$INVALID_EXIT" "jq failure: returns non-zero"
TMP_FILES=$(find "$STATE_DIR" -name '*.tmp.*' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "0" "$TMP_FILES" "jq failure: no temp files left behind"
PHASE_AFTER=$(jq -r '.phase' "$STATE_FILE")
assert_eq "off" "$PHASE_AFTER" "jq failure: state file unchanged"

# Test: zero-byte state file returns safe defaults (not empty string)
: > "$STATE_FILE"
PHASE_ZERO=$(get_phase)
assert_eq "off" "$PHASE_ZERO" "zero-byte state: get_phase returns off"
LEVEL_ZERO=$(get_autonomy_level)
assert_eq "ask" "$LEVEL_ZERO" "zero-byte state: get_autonomy_level returns ask"
MSG_ZERO=$(get_message_shown)
assert_eq "false" "$MSG_ZERO" "zero-byte state: get_message_shown returns false"

# Test: _safe_write rejects oversized input
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh"
set_phase "off"
OVERSIZE_SW_ERR=$(printf '%0.sx' $(seq 1 12000) | _safe_write 2>&1) && OVERSIZE_SW_EXIT=0 || OVERSIZE_SW_EXIT=$?
assert_eq "1" "$OVERSIZE_SW_EXIT" "_safe_write: rejects oversized input"
assert_contains "$OVERSIZE_SW_ERR" "10KB" "_safe_write: error message mentions 10KB"
TMP_FILES=$(find "$STATE_DIR" -name '*.tmp.*' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "0" "$TMP_FILES" "_safe_write: no temp files left after oversized rejection"

# Test: _safe_write rejects zero-byte input
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh"
set_phase "off"
ORIGINAL=$(cat "$STATE_FILE")
ZERO_SW_ERR=$(printf '' | _safe_write 2>&1) && ZERO_SW_EXIT=0 || ZERO_SW_EXIT=$?
assert_eq "1" "$ZERO_SW_EXIT" "_safe_write: rejects zero-byte input"
assert_contains "$ZERO_SW_ERR" "zero bytes" "_safe_write: zero-byte error message"
TMP_FILES=$(find "$STATE_DIR" -name '*.tmp.*' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "0" "$TMP_FILES" "_safe_write: no temp files left after zero-byte rejection"
AFTER=$(cat "$STATE_FILE")
assert_eq "$ORIGINAL" "$AFTER" "_safe_write: state file unchanged after zero-byte rejection"

# Test: initial-creation via _safe_write produces valid JSON
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh"
rm -f "$STATE_FILE"
set_last_observation_id 9999
VALID=$(jq -e '.last_observation_id' "$STATE_FILE" 2>/dev/null) && VALID_EXIT=0 || VALID_EXIT=$?
assert_eq "0" "$VALID_EXIT" "initial creation: produces valid JSON via _safe_write"
assert_eq "9999" "$VALID" "initial creation: contains expected observation ID"

# Test: get_phase returns "off" for unknown phase string (enum guard)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh"
set_phase "off"
jq '.phase = "bogus"' "$STATE_FILE" > "$STATE_FILE.tmp.test" && mv "$STATE_FILE.tmp.test" "$STATE_FILE"
RESULT=$(get_phase)
assert_eq "off" "$RESULT" "phase enum guard: unknown phase string returns off"

# Test: get_phase returns "off" for null phase (enum guard)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh"
set_phase "off"
jq '.phase = null' "$STATE_FILE" > "$STATE_FILE.tmp.test" && mv "$STATE_FILE.tmp.test" "$STATE_FILE"
RESULT=$(get_phase)
assert_eq "off" "$RESULT" "phase enum guard: null phase returns off"

# Test: _update_state failure propagates through callers
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh"
set_phase "off"
chmod 000 "$STATE_DIR"
SET_ERR=$(set_autonomy_level auto 2>&1) && SET_EXIT=0 || SET_EXIT=$?
chmod 755 "$STATE_DIR"
assert_eq "1" "$SET_EXIT" "failure propagation: set_autonomy_level returns non-zero on write failure"

# ============================================================
# TEST SUITE: Completion Snapshot (Loop-back Exception)
# ============================================================
echo ""
echo "=== Completion Snapshot ==="

setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh"

# Test: has_completion_snapshot returns false when no snapshot
set_phase "complete"
assert_eq "false" "$(has_completion_snapshot)" "has_completion_snapshot false when no snapshot"

# Test: save/restore cycle
reset_completion_status
set_completion_field "plan_validated" "true"
set_completion_field "outcomes_validated" "true"
save_completion_snapshot
assert_eq "true" "$(has_completion_snapshot)" "has_completion_snapshot true after save"

# Test: snapshot survives phase transition to implement
# Complete all milestones so the hard gate allows leaving COMPLETE
set_completion_field "results_presented" "true"
set_completion_field "docs_checked" "true"
set_completion_field "committed" "true"
set_completion_field "tech_debt_audited" "true"
set_completion_field "handover_saved" "true"
set_phase "implement"
assert_eq "true" "$(has_completion_snapshot)" "snapshot survives transition to implement"

# Test: restore_completion_snapshot restores milestones
set_phase "complete"
reset_completion_status
assert_eq "false" "$(get_completion_field plan_validated)" "milestones reset before restore"
restore_completion_snapshot
assert_eq "true" "$(get_completion_field plan_validated)" "plan_validated restored from snapshot"
assert_eq "true" "$(get_completion_field outcomes_validated)" "outcomes_validated restored from snapshot"
assert_eq "false" "$(has_completion_snapshot)" "snapshot cleared after restore"

# ============================================================
# TEST SUITE: workflow-cmd.sh Allowlist
# ============================================================
echo ""
echo "=== workflow-cmd.sh Allowlist ==="

setup_test_project

# Test: public function succeeds
RESULT=$(CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/workflow-cmd.sh" get_phase 2>&1)
assert_eq "off" "$RESULT" "allowlist: get_phase succeeds"

# Test: private _reset_section blocked
RESULT=$(CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/workflow-cmd.sh" _reset_section test 2>&1 || true)
assert_contains "$RESULT" "ERROR: Unknown command" "allowlist: _reset_section blocked"

# Test: unknown function blocked
RESULT=$(CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/workflow-cmd.sh" nonexistent_func 2>&1 || true)
assert_contains "$RESULT" "ERROR: Unknown command" "allowlist: unknown function blocked"

# ============================================================
# TEST SUITE: setup.sh Functional Tests
# ============================================================
echo ""
echo "=== setup.sh Functional Tests ==="

# Create a clean test environment for setup.sh
SETUP_TEST_DIR=$(mktemp -d)
mkdir -p "$SETUP_TEST_DIR/.claude"
# Create minimal settings.json with just Bash permission
jq -n '{"permissions":{"allow":["Bash"]}}' > "$SETUP_TEST_DIR/.claude/settings.json"

# Run setup.sh
CLAUDE_PROJECT_DIR="$SETUP_TEST_DIR" bash "$REPO_DIR/plugin/scripts/setup.sh" 2>/dev/null

# Test: state directory created
if [ -d "$SETUP_TEST_DIR/.claude/state" ]; then
    echo -e "  ${GREEN}PASS${NC} setup.sh creates state directory"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} setup.sh creates state directory"
    FAIL=$((FAIL + 1))
    ERRORS="$ERRORS\n  FAIL: setup.sh creates state directory"
fi

# Test: workflow.json created
if [ -f "$SETUP_TEST_DIR/.claude/state/workflow.json" ]; then
    echo -e "  ${GREEN}PASS${NC} setup.sh creates workflow.json"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} setup.sh creates workflow.json"
    FAIL=$((FAIL + 1))
    ERRORS="$ERRORS\n  FAIL: setup.sh creates workflow.json"
fi

# Test: .gitignore updated
assert_contains "$(cat "$SETUP_TEST_DIR/.gitignore" 2>/dev/null)" ".claude/state/" "setup.sh adds .claude/state/ to .gitignore"

# Test: permissions updated with Read, Agent, Glob, Grep
SETTINGS_CONTENT=$(cat "$SETUP_TEST_DIR/.claude/settings.json")
assert_contains "$SETTINGS_CONTENT" "Read" "setup.sh adds Read permission"
assert_contains "$SETTINGS_CONTENT" "Agent" "setup.sh adds Agent permission"
assert_contains "$SETTINGS_CONTENT" "Glob" "setup.sh adds Glob permission"
assert_contains "$SETTINGS_CONTENT" "Grep" "setup.sh adds Grep permission"
# Original Bash permission preserved
assert_contains "$SETTINGS_CONTENT" "Bash" "setup.sh preserves existing Bash permission"

# Test: idempotency (run twice, no duplication)
CLAUDE_PROJECT_DIR="$SETUP_TEST_DIR" bash "$REPO_DIR/plugin/scripts/setup.sh" 2>/dev/null
READ_COUNT=$(jq -r '[.permissions.allow[]? | select(. == "Read")] | length' "$SETUP_TEST_DIR/.claude/settings.json")
assert_eq "1" "$READ_COUNT" "setup.sh is idempotent (no duplicate permissions)"

# Test: .gitignore idempotency
GITIGNORE_COUNT=$(grep -c '.claude/state/' "$SETUP_TEST_DIR/.gitignore" 2>/dev/null || echo "0")
assert_eq "1" "$GITIGNORE_COUNT" "setup.sh .gitignore is idempotent"

rm -rf "$SETUP_TEST_DIR"

# ============================================================
# TEST SUITE: Statusline Version Detection
# ============================================================
echo ""
echo "=== Statusline Version Detection ==="

# _plugin_version helper (mirrors statusline.sh)
_plugin_version() {
  local plugin_dir="$1"
  local latest_dir
  latest_dir=$(ls -1 "$plugin_dir" 2>/dev/null | sort -V | tail -1)
  [ -z "$latest_dir" ] && return 1
  local pjson="$plugin_dir/$latest_dir/.claude-plugin/plugin.json"
  if [ -f "$pjson" ]; then
    jq -r '.version // "?"' "$pjson" 2>/dev/null
  else
    echo "$latest_dir"
  fi
}

# Create mock plugin cache for testing
MOCK_CACHE=$(mktemp -d)

# Test: empty directory returns "?"
MOCK_EMPTY="$MOCK_CACHE/empty-plugin"
mkdir -p "$MOCK_EMPTY"
VERSION=$(_plugin_version "$MOCK_EMPTY" || true)
VERSION="${VERSION:-?}"
assert_eq "?" "$VERSION" "version detection: empty dir returns ?"

# Test: version read from plugin.json
MOCK_SINGLE="$MOCK_CACHE/single-plugin"
mkdir -p "$MOCK_SINGLE/1.0.0/.claude-plugin"
echo '{"version":"1.2.3"}' > "$MOCK_SINGLE/1.0.0/.claude-plugin/plugin.json"
VERSION=$(_plugin_version "$MOCK_SINGLE")
assert_eq "1.2.3" "$VERSION" "version detection: reads from plugin.json"

# Test: falls back to directory name when no plugin.json
MOCK_FALLBACK="$MOCK_CACHE/fallback-plugin"
mkdir -p "$MOCK_FALLBACK/3.0.0"
VERSION=$(_plugin_version "$MOCK_FALLBACK")
assert_eq "3.0.0" "$VERSION" "version detection: falls back to dir name"

# Test: highest of multiple versions picked, reads plugin.json
MOCK_MULTI="$MOCK_CACHE/multi-plugin"
mkdir -p "$MOCK_MULTI/1.0.0" "$MOCK_MULTI/1.1.0/.claude-plugin" "$MOCK_MULTI/2.0.0/.claude-plugin" "$MOCK_MULTI/1.9.9"
echo '{"version":"2.0.0"}' > "$MOCK_MULTI/2.0.0/.claude-plugin/plugin.json"
echo '{"version":"1.1.0"}' > "$MOCK_MULTI/1.1.0/.claude-plugin/plugin.json"
VERSION=$(_plugin_version "$MOCK_MULTI")
assert_eq "2.0.0" "$VERSION" "version detection: highest version picked from multiple"

rm -rf "$MOCK_CACHE"

# ============================================================
# TEST SUITE: BUG-3 — Phase token authorization
# ============================================================
echo ""
echo "=== BUG-3: Phase token authorization ==="

# Test: set_phase blocked without token (when WF_SKIP_AUTH is unset)
setup_test_project
# First create state via authorized path
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
# Now try to change phase with auth enforced
OUTPUT=$(run_with_auth set_phase "review" 2>&1) || true
assert_contains "$OUTPUT" "BLOCKED" "set_phase blocked without token when auth enforced"
# Phase should not have changed
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "implement" "$RESULT" "phase unchanged after blocked set_phase"

# Test: set_phase allowed with valid token
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
# Create a valid token
TOKEN_DIR="$TEST_DIR/.claude/plugin-data/.phase-tokens"
mkdir -p "$TOKEN_DIR"
NOW=$(date +%s)
NONCE="test-token-123"
jq -n --arg target "review" --argjson ts "$NOW" --arg nonce "$NONCE" \
    '{"target": $target, "ts": $ts, "nonce": $nonce}' > "$TOKEN_DIR/$NONCE"
export CLAUDE_PLUGIN_DATA="$TEST_DIR/.claude/plugin-data"
run_with_auth set_phase "review"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "review" "$RESULT" "set_phase allowed with valid token"
# Token should be consumed
assert_file_not_exists "$TOKEN_DIR/$NONCE" "token consumed after use"

# Test: second set_phase blocked after token consumed
OUTPUT=$(run_with_auth set_phase "review" 2>&1) || true
assert_contains "$OUTPUT" "BLOCKED" "second set_phase blocked after token consumed"

# Test: set_phase blocked with expired token (>60s)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
TOKEN_DIR="$TEST_DIR/.claude/plugin-data/.phase-tokens"
mkdir -p "$TOKEN_DIR"
EXPIRED_TS=$(($(date +%s) - 120))
jq -n --arg target "review" --argjson ts "$EXPIRED_TS" --arg nonce "expired-token" \
    '{"target": $target, "ts": $ts, "nonce": $nonce}' > "$TOKEN_DIR/expired-token"
export CLAUDE_PLUGIN_DATA="$TEST_DIR/.claude/plugin-data"
OUTPUT=$(run_with_auth set_phase "review" 2>&1) || true
assert_contains "$OUTPUT" "BLOCKED" "set_phase blocked with expired token"

# Test: forward auto-transition allowed without token when autonomy=auto
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level "auto"
run_with_auth set_phase "review"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "review" "$RESULT" "forward auto-transition allowed in auto mode"

# Test: backward transition blocked even in auto mode
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level "auto"
OUTPUT=$(run_with_auth set_phase "implement" 2>&1) || true
assert_contains "$OUTPUT" "BLOCKED" "backward transition blocked in auto mode"

# Test: transition to OFF blocked even in auto mode
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level "auto"
OUTPUT=$(run_with_auth set_phase "off" 2>&1) || true
assert_contains "$OUTPUT" "BLOCKED" "transition to OFF blocked in auto mode"

# Test: set_autonomy_level blocked without token (when WF_SKIP_AUTH is unset)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level "ask"
OUTPUT=$(run_with_auth set_autonomy_level "auto" 2>&1) || true
assert_contains "$OUTPUT" "BLOCKED" "set_autonomy_level blocked without token"

# Test: set_autonomy_level allowed with valid autonomy token
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
TOKEN_DIR="$TEST_DIR/.claude/plugin-data/.phase-tokens"
mkdir -p "$TOKEN_DIR"
NOW=$(date +%s)
jq -n --arg target "autonomy:auto" --argjson ts "$NOW" --arg nonce "auto-token" \
    '{"target": $target, "ts": $ts, "nonce": $nonce}' > "$TOKEN_DIR/auto-token"
export CLAUDE_PLUGIN_DATA="$TEST_DIR/.claude/plugin-data"
run_with_auth set_autonomy_level "auto"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "auto" "$RESULT" "set_autonomy_level allowed with valid autonomy token"
assert_file_not_exists "$TOKEN_DIR/auto-token" "autonomy token consumed after use"

# ============================================================
# RESULTS
# ============================================================
echo ""
echo "=========================================="
echo -e "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
if [ $FAIL -gt 0 ]; then
    echo -e "\nFailures:$ERRORS"
    echo ""
    exit 1
fi
echo "=========================================="
