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
HOOKS_DIR="$REPO_DIR/.claude/hooks"

# Create a fake project structure in TEST_DIR
setup_test_project() {
    rm -rf "$TEST_DIR"
    TEST_DIR=$(mktemp -d)
    mkdir -p "$TEST_DIR/.claude/hooks" "$TEST_DIR/.claude/state" "$TEST_DIR/.claude/commands"
    cp "$HOOKS_DIR/workflow-state.sh" "$TEST_DIR/.claude/hooks/"
    cp "$HOOKS_DIR/workflow-gate.sh" "$TEST_DIR/.claude/hooks/"
    cp "$HOOKS_DIR/bash-write-guard.sh" "$TEST_DIR/.claude/hooks/"
    # Set CLAUDE_PROJECT_DIR for hooks
    export CLAUDE_PROJECT_DIR="$TEST_DIR"
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

# Test: get_autonomy_level returns default 2 when no state file
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "2" "$RESULT" "get_autonomy_level defaults to 2 when no state file"

# Test: get_autonomy_level returns default 2 for old-format workflow.json (backward compat)
setup_test_project
# Create a workflow.json WITHOUT autonomy_level (simulates pre-feature state file)
echo '{"phase": "implement", "message_shown": true, "active_skill": "", "decision_record": "", "coaching": {"tool_calls_since_agent": 0, "layer2_fired": []}, "updated": "2026-03-22T00:00:00Z"}' > "$TEST_DIR/.claude/state/workflow.json"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "2" "$RESULT" "get_autonomy_level defaults to 2 for old-format state file (backward compat)"

# Test: set_autonomy_level accepts valid values
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 1
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "1" "$RESULT" "set_autonomy_level sets level to 1"

source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 2
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "2" "$RESULT" "set_autonomy_level sets level to 2"

source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 3
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "3" "$RESULT" "set_autonomy_level sets level to 3"

# Test: set_autonomy_level rejects invalid values
OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 0 2>&1 || true)
assert_contains "$OUTPUT" "ERROR" "set_autonomy_level rejects 0"

OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 4 2>&1 || true)
assert_contains "$OUTPUT" "ERROR" "set_autonomy_level rejects 4"

OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level abc 2>&1 || true)
assert_contains "$OUTPUT" "ERROR" "set_autonomy_level rejects non-numeric input"

# Test: autonomy_level preserved across set_phase transitions
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 3
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "3" "$RESULT" "autonomy_level preserved across phase transitions"

# Test: set_phase from OFF initializes autonomy_level to 2
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "define"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "2" "$RESULT" "set_phase from OFF initializes autonomy_level to 2"

# Test: set_phase("off") clears autonomy_level
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 3
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "2" "$RESULT" "set_phase off clears autonomy_level (returns default 2)"

# Test: set_autonomy_level warns and returns 1 when no state file
setup_test_project
rm -f "$TEST_DIR/.claude/state/workflow.json"
OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 2 2>&1 || true)
assert_contains "$OUTPUT" "WARNING" "set_autonomy_level warns when no state file"
assert_file_not_exists "$TEST_DIR/.claude/state/workflow.json" "set_autonomy_level does not create state file"

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

# Test: set_phase("off") clears last_observation_id
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_last_observation_id)
assert_eq "" "$RESULT" "set_phase off clears last_observation_id"

# --- Hard gates: phase transition enforcement ---

# Test: hard gate blocks leaving IMPLEMENT without milestones
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && reset_implement_status
OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review" 2>&1 || true)
assert_contains "$OUTPUT" "HARD GATE" "hard gate blocks leaving IMPLEMENT without milestones"

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

# Test: corrupt state file does not crash set_phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
echo "NOT VALID JSON" > "$TEST_DIR/.claude/state/workflow.json"
OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review" 2>&1 || true)
# Should not crash — python3 try/except handles corrupt JSON
assert_not_contains "$OUTPUT" "Traceback" "corrupt state file does not produce python traceback"

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
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 1
OUTPUT=$(run_gate "/project/src/main.py")
assert_contains "$OUTPUT" "deny" "Level 1 blocks Write in IMPLEMENT phase"

# Test: Level 1 denial message mentions /autonomy
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 1
OUTPUT=$(run_gate "/project/src/main.py")
assert_contains "$OUTPUT" "/autonomy" "Level 1 deny message mentions /autonomy command"

# Test: Level 1 does NOT block writes when phase is OFF
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
python3 -c "
import json
with open('$TEST_DIR/.claude/state/workflow.json', 'r') as f:
    d = json.load(f)
d['autonomy_level'] = 1
with open('$TEST_DIR/.claude/state/workflow.json', 'w') as f:
    json.dump(d, f, indent=2)
"
OUTPUT=$(run_gate "/project/src/main.py")
assert_not_contains "$OUTPUT" "deny" "Level 1 does NOT block writes when phase is OFF"

# Test: Level 2 allows writes in IMPLEMENT (current behavior)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 2
OUTPUT=$(run_gate "/project/src/main.py")
assert_not_contains "$OUTPUT" "deny" "Level 2 allows writes in IMPLEMENT"

# Test: Level 3 allows writes in IMPLEMENT (current behavior)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 3
OUTPUT=$(run_gate "/project/src/main.py")
assert_not_contains "$OUTPUT" "deny" "Level 3 allows writes in IMPLEMENT"

# Test: Level 2 still blocks writes in DISCUSS (phase gate preserved)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 2
OUTPUT=$(run_gate "/project/src/main.py")
assert_contains "$OUTPUT" "deny" "Level 2 blocks writes in DISCUSS (phase gate)"

# Test: Level 3 still blocks writes in DISCUSS (phase gate preserved)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 3
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
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 1
OUTPUT=$(run_bash_guard 'echo data > output.txt')
assert_contains "$OUTPUT" "deny" "Level 1 blocks Bash write in IMPLEMENT phase"

# Test: Level 1 denial message mentions /autonomy
assert_contains "$OUTPUT" "/autonomy" "Level 1 bash deny message mentions /autonomy"

# Test: Level 2 allows Bash write in IMPLEMENT
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 2
OUTPUT=$(run_bash_guard 'echo data > output.txt')
assert_not_contains "$OUTPUT" "deny" "Level 2 allows Bash write in IMPLEMENT"

# Test: Level 3 allows Bash write in IMPLEMENT
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 3
OUTPUT=$(run_bash_guard 'echo data > output.txt')
assert_not_contains "$OUTPUT" "deny" "Level 3 allows Bash write in IMPLEMENT"

# Test: Level 2 still blocks Bash write in DISCUSS (phase gate preserved)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 2
OUTPUT=$(run_bash_guard 'echo data > output.txt')
assert_contains "$OUTPUT" "deny" "Level 2 blocks Bash write in DISCUSS (phase gate)"

# Test: Level 1 allows read-only Bash commands in IMPLEMENT
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 1
OUTPUT=$(run_bash_guard 'ls -la')
assert_not_contains "$OUTPUT" "deny" "Level 1 allows read-only Bash in IMPLEMENT"

# Test: Level 1 rejects chained workflow-state command (bypass attempt)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 1
OUTPUT=$(run_bash_guard 'source .claude/hooks/workflow-state.sh && echo pwned > evil.txt')
assert_contains "$OUTPUT" "deny" "Level 1 blocks chained workflow-state bypass"

# ============================================================
# TEST SUITE: install.sh
# ============================================================
echo ""
echo "=== install.sh ==="

# Test: installs into a git project
INSTALL_TARGET=$(mktemp -d)
git -C "$INSTALL_TARGET" init --quiet
"$REPO_DIR/install.sh" "$INSTALL_TARGET" > /dev/null 2>&1
assert_file_exists "$INSTALL_TARGET/.claude/hooks/workflow-gate.sh" "install creates workflow-gate.sh"
assert_file_exists "$INSTALL_TARGET/.claude/hooks/bash-write-guard.sh" "install creates bash-write-guard.sh"
assert_file_exists "$INSTALL_TARGET/.claude/hooks/workflow-state.sh" "install creates workflow-state.sh"
assert_file_exists "$INSTALL_TARGET/.claude/hooks/post-tool-navigator.sh" "install creates post-tool-navigator.sh"
assert_file_exists "$INSTALL_TARGET/.claude/commands/implement.md" "install creates implement.md"
assert_file_exists "$INSTALL_TARGET/.claude/commands/discuss.md" "install creates discuss.md"
assert_file_exists "$INSTALL_TARGET/.claude/commands/review.md" "install creates review.md"
assert_file_exists "$INSTALL_TARGET/.claude/commands/complete.md" "install creates complete.md"
assert_file_exists "$INSTALL_TARGET/.claude/commands/define.md" "install creates define.md"
assert_file_exists "$INSTALL_TARGET/.claude/settings.json" "install creates settings.json"

# Test: hooks are executable
if [ -x "$INSTALL_TARGET/.claude/hooks/workflow-gate.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} installed hooks are executable"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} installed hooks are executable"
    FAIL=$((FAIL + 1))
fi

# Test: .gitignore updated with .claude/state/
assert_contains "$(cat "$INSTALL_TARGET/.gitignore")" ".claude/state/" "install adds .claude/state/ to .gitignore"

# Test: settings.json contains hook config
SETTINGS=$(cat "$INSTALL_TARGET/.claude/settings.json")
assert_contains "$SETTINGS" "workflow-gate.sh" "settings.json references workflow-gate.sh"
assert_contains "$SETTINGS" "bash-write-guard.sh" "settings.json references bash-write-guard.sh"

# Test: auto-initializes workflow.json to "discuss"
assert_file_exists "$INSTALL_TARGET/.claude/state/workflow.json" "install auto-creates workflow.json"
INIT_PHASE=$(grep -o '"phase"[[:space:]]*:[[:space:]]*"[^"]*"' "$INSTALL_TARGET/.claude/state/workflow.json" | grep -o '"[^"]*"$' | tr -d '"')
assert_eq "off" "$INIT_PHASE" "install sets initial phase to off"

# Test: installs statusline globally
assert_file_exists "$HOME/.claude/statusline.sh" "install creates global statusline.sh"
if [ -x "$HOME/.claude/statusline.sh" ]; then
    echo -e "  ${GREEN}PASS${NC} global statusline is executable"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} global statusline is executable"
    FAIL=$((FAIL + 1))
fi

# Test: global settings.json contains statusLine config
if [ -f "$HOME/.claude/settings.json" ]; then
    GLOBAL_SETTINGS=$(cat "$HOME/.claude/settings.json")
    assert_contains "$GLOBAL_SETTINGS" "statusline.sh" "global settings references statusline.sh"
else
    echo -e "  ${RED}FAIL${NC} global settings references statusline.sh"
    echo "    ~/.claude/settings.json not found"
    FAIL=$((FAIL + 1))
fi

# Test: refuses non-git directory
NON_GIT=$(mktemp -d)
INSTALL_OUTPUT=$("$REPO_DIR/install.sh" "$NON_GIT" 2>&1 || true)
assert_contains "$INSTALL_OUTPUT" "not a git repository" "refuses install in non-git directory"

# Test: skips settings.json if hooks already configured
SECOND_OUTPUT=$("$REPO_DIR/install.sh" "$INSTALL_TARGET" 2>&1 || true)
assert_contains "$SECOND_OUTPUT" "already configured" "skips settings.json on re-install"

rm -rf "$INSTALL_TARGET" "$NON_GIT"

# ============================================================
# TEST SUITE: uninstall.sh
# ============================================================
echo ""
echo "=== uninstall.sh ==="

# Test: removes hooks and commands
UNINSTALL_TARGET=$(mktemp -d)
git -C "$UNINSTALL_TARGET" init --quiet
"$REPO_DIR/install.sh" "$UNINSTALL_TARGET" > /dev/null 2>&1
"$REPO_DIR/uninstall.sh" "$UNINSTALL_TARGET" > /dev/null 2>&1
assert_file_not_exists "$UNINSTALL_TARGET/.claude/hooks/workflow-gate.sh" "uninstall removes workflow-gate.sh"
assert_file_not_exists "$UNINSTALL_TARGET/.claude/hooks/bash-write-guard.sh" "uninstall removes bash-write-guard.sh"
assert_file_not_exists "$UNINSTALL_TARGET/.claude/hooks/workflow-state.sh" "uninstall removes workflow-state.sh"
assert_file_not_exists "$UNINSTALL_TARGET/.claude/hooks/post-tool-navigator.sh" "uninstall removes post-tool-navigator.sh"
assert_file_not_exists "$UNINSTALL_TARGET/.claude/commands/implement.md" "uninstall removes implement.md"
assert_file_not_exists "$UNINSTALL_TARGET/.claude/commands/discuss.md" "uninstall removes discuss.md"
assert_file_not_exists "$UNINSTALL_TARGET/.claude/commands/review.md" "uninstall removes review.md"
assert_file_not_exists "$UNINSTALL_TARGET/.claude/commands/complete.md" "uninstall removes complete.md"
assert_file_not_exists "$UNINSTALL_TARGET/.claude/commands/define.md" "uninstall removes define.md"
assert_file_not_exists "$UNINSTALL_TARGET/.claude/state" "uninstall removes state directory"

# Test: settings.json preserved (not deleted by uninstall)
assert_file_exists "$UNINSTALL_TARGET/.claude/settings.json" "uninstall preserves settings.json"

rm -rf "$UNINSTALL_TARGET"

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
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
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
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(run_navigator "Read")
assert_not_contains "$OUTPUT" "Workflow Coach" "Layer 1 silent on Read in IMPLEMENT"

OUTPUT=$(run_navigator "Grep")
assert_not_contains "$OUTPUT" "Workflow Coach" "Layer 1 silent on Grep in IMPLEMENT"

# Test: Layer 1 shows DISCUSS coaching message
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(run_navigator "Read")
assert_contains "$OUTPUT" "Workflow Coach.*DISCUSS" "Layer 1 shows DISCUSS coaching message"

# Test: no message when no state file
setup_test_project
rm -f "$TEST_DIR/.claude/state/workflow.json"
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(run_navigator "Write")
assert_not_contains "$OUTPUT" "Workflow Coach" "coach silent when no state file"

# Test: Layer 1 shows DEFINE coaching message
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "define"
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(run_navigator "Read")
assert_contains "$OUTPUT" "Workflow Coach.*DEFINE" "Layer 1 shows DEFINE coaching message"

# Test: Layer 1 shows COMPLETE coaching message
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(run_navigator "Read")
assert_contains "$OUTPUT" "Workflow Coach.*COMPLETE" "Layer 1 shows COMPLETE coaching message"

# Test: Layer 1 silent in OFF phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(run_navigator "Read")
assert_not_contains "$OUTPUT" "Workflow Coach" "Layer 1 silent in OFF phase"

# Test: hook exits cleanly (exit 0) for irrelevant tool types in active phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"

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
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
echo '{"tool_name":"Read"}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
echo '{"tool_name":"Glob"}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
echo '{"tool_name":"Grep"}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
CONTENT=$(cat "$TEST_DIR/.claude/state/workflow.json")
assert_contains "$CONTENT" '"tool_calls_since_agent": 0' "irrelevant tools don't increment coaching counter"

# Test: Layer 3 Check 1 — short agent prompt warning
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(echo '{"tool_name":"Agent","tool_input":{"prompt":"short"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "Agent prompts must be detailed" "Layer 3 fires for short agent prompt"

# Test: Layer 3 Check 1 — long agent prompt no warning
OUTPUT=$(echo '{"tool_name":"Agent","tool_input":{"prompt":"This is a sufficiently long prompt that exceeds the 150 character threshold and should not trigger the short agent prompt coaching warning from the Layer 3 anti-laziness check system"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_not_contains "$OUTPUT" "Agent prompts must be detailed" "Layer 3 silent for long agent prompt"

# Test: Layer 3 Check 2 — short commit message warning
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fix\""}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "Commit messages must explain why" "Layer 3 fires for short commit message"

# Test: Layer 3 Check 5 — skipping research (counter > 10)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
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
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(echo '{"tool_name":"Agent","tool_input":{"prompt":"This is a sufficiently long agent prompt that exceeds one hundred and fifty characters so that it does not trigger the short prompt warning from Layer 3 checks"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "Every approach must have stated downsides" "Layer 2 fires on Agent return in DISCUSS"

# Test: Layer 2 — agent return fires only once per phase
OUTPUT=$(echo '{"tool_name":"Agent","tool_input":{"prompt":"This is a sufficiently long agent prompt that exceeds one hundred and fifty characters so that it does not trigger the short prompt warning from Layer 3 checks"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_not_contains "$OUTPUT" "Every approach must have stated downsides" "Layer 2 silent on second Agent return in DISCUSS"

# Test: Layer 3 Check 2 — short HEREDOC commit message warning
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"$(cat <<'"'"'EOF'"'"'\\nfix\\n\\nCo-Authored-By: Claude\\nEOF\\n)\""}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "Commit messages must explain why" "Layer 3 fires for short HEREDOC commit message"

# Test: Layer 3 Check 2 — long HEREDOC commit message no warning
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"$(cat <<'"'"'EOF'"'"'\\nfeat: add comprehensive hallucination reduction standards from Anthropic docs\\n\\nCo-Authored-By: Claude\\nEOF\\n)\""}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_not_contains "$OUTPUT" "Commit messages must explain why" "Layer 3 silent for long HEREDOC commit message"

# Test: Layer 3 — no verify after code change
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
for i in $(seq 1 6); do
    echo '{"tool_name":"Write","tool_input":{"file_path":"src/main.py"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
done
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"src/main.py"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "haven.t run tests" "Layer 3 fires after source edits without verify"

# Test: verify clears the flag
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
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
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"docs/plans/decisions.md"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "Challenge vague problem statements" "Layer 2 fires on decision record write in DEFINE"

# Test: Layer 2 — test run in COMPLETE triggers coaching
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"./tests/run-tests.sh"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "specific about validation failures" "Layer 2 fires on test run in COMPLETE"

# --- Autonomy level coaching ---

# Test: Level 3 coaching includes auto-transition guidance
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 3
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
python3 -c "
import json
with open('$TEST_DIR/.claude/state/workflow.json', 'r') as f:
    d = json.load(f)
d['message_shown'] = False
with open('$TEST_DIR/.claude/state/workflow.json', 'w') as f:
    json.dump(d, f, indent=2)
"
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"/project/src/main.py"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "Level 3" "Level 3 coaching mentions Level 3 in phase entry"
assert_contains "$OUTPUT" "proceed" "Level 3 coaching includes auto-transition guidance"

# Test: Level 2 coaching does NOT include auto-transition guidance
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 2
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
python3 -c "
import json
with open('$TEST_DIR/.claude/state/workflow.json', 'r') as f:
    d = json.load(f)
d['message_shown'] = False
with open('$TEST_DIR/.claude/state/workflow.json', 'w') as f:
    json.dump(d, f, indent=2)
"
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"/project/src/main.py"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_not_contains "$OUTPUT" "Level 3" "Level 2 coaching does not mention Level 3"

# --- Claude-mem project enforcement ---

# Test: coaching fires when save_observation has no project field
setup_test_project
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
OUTPUT=$(echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__save_observation","tool_input":{"text":"some observation"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "without project" "coaching fires when save_observation missing project field"

# Test: coaching does NOT fire when save_observation has project field
setup_test_project
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
OUTPUT=$(echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__save_observation","tool_input":{"text":"some observation","project":"claude-code-workflows"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_not_contains "$OUTPUT" "without project" "no coaching when save_observation has project field"

# --- Observation ID capture ---

# Test: hook captures observation ID from save_observation response
setup_test_project
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__save_observation","tool_input":{"text":"test","project":"test"},"tool_response":{"content":[{"type":"text","text":"{\"success\":true,\"id\":4242,\"title\":\"test\",\"project\":\"test\",\"message\":\"Memory saved as observation #4242\"}"}]}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_last_observation_id)
assert_eq "4242" "$RESULT" "hook captures observation ID from save_observation"

# Test: hook captures observation ID from get_observations response
setup_test_project
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__get_observations","tool_input":{"ids":[1234]},"tool_response":{"content":[{"type":"text","text":"[{\"id\":1234,\"title\":\"test obs\"}]"}]}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_last_observation_id)
assert_eq "1234" "$RESULT" "hook captures observation ID from get_observations"

# ============================================================
# TEST SUITE: statusline.sh
# ============================================================
echo ""
echo "=== statusline.sh ==="

STATUSLINE="$REPO_DIR/statusline/statusline.sh"

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
mkdir -p "$SL_TEST_DIR/.claude/state" "$SL_TEST_DIR/.claude/hooks"
echo '{"phase": "discuss", "message_shown": false, "active_skill": "brainstorming"}' > "$SL_TEST_DIR/.claude/state/workflow.json"
touch "$SL_TEST_DIR/.claude/hooks/workflow-gate.sh"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_TEST_DIR\"}")
assert_contains "$OUTPUT" "brainstorming" "statusline shows active skill name from workflow.json"
rm -rf "$SL_TEST_DIR"

# Test: no skill shown when active_skill field is empty
SL_TEST_DIR2=$(mktemp -d)
mkdir -p "$SL_TEST_DIR2/.claude/state" "$SL_TEST_DIR2/.claude/hooks"
echo '{"phase": "off", "message_shown": false, "active_skill": ""}' > "$SL_TEST_DIR2/.claude/state/workflow.json"
touch "$SL_TEST_DIR2/.claude/hooks/workflow-gate.sh"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_TEST_DIR2\"}")
CLEAN_OUTPUT=$(echo "$OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
assert_not_contains "$CLEAN_OUTPUT" "\[\]" "statusline hides empty skill brackets"
rm -rf "$SL_TEST_DIR2"

# Test: shows DEFINE phase in statusline
SL_DEFINE_DIR=$(mktemp -d)
mkdir -p "$SL_DEFINE_DIR/.claude/state" "$SL_DEFINE_DIR/.claude/hooks"
echo '{"phase": "define", "message_shown": false, "active_skill": ""}' > "$SL_DEFINE_DIR/.claude/state/workflow.json"
touch "$SL_DEFINE_DIR/.claude/hooks/workflow-gate.sh"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_DEFINE_DIR\"}")
assert_contains "$OUTPUT" "DEFINE" "statusline shows DEFINE phase label"
assert_contains "$OUTPUT" '\[34m' "statusline uses blue (\\033[34m) for DEFINE phase"
rm -rf "$SL_DEFINE_DIR"

# Test: shows COMPLETE phase in statusline with magenta
SL_COMPLETE_DIR=$(mktemp -d)
mkdir -p "$SL_COMPLETE_DIR/.claude/state" "$SL_COMPLETE_DIR/.claude/hooks"
echo '{"phase": "complete", "message_shown": false, "active_skill": ""}' > "$SL_COMPLETE_DIR/.claude/state/workflow.json"
touch "$SL_COMPLETE_DIR/.claude/hooks/workflow-gate.sh"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_COMPLETE_DIR\"}")
assert_contains "$OUTPUT" "COMPLETE" "statusline shows COMPLETE phase label"
assert_contains "$OUTPUT" '\[35m' "statusline uses magenta (\\033[35m) for COMPLETE phase"
rm -rf "$SL_COMPLETE_DIR"

# --- Autonomy level symbols ---

# Test: Level 1 renders ▶ before phase
SL_AUTO1_DIR=$(mktemp -d)
mkdir -p "$SL_AUTO1_DIR/.claude/state" "$SL_AUTO1_DIR/.claude/hooks"
echo '{"phase": "implement", "autonomy_level": 1, "message_shown": false, "active_skill": ""}' > "$SL_AUTO1_DIR/.claude/state/workflow.json"
touch "$SL_AUTO1_DIR/.claude/hooks/workflow-gate.sh"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_AUTO1_DIR\"}")
assert_contains "$OUTPUT" "▶ " "statusline shows ▶ for Level 1"
assert_contains "$OUTPUT" "IMPLEMENT" "statusline still shows phase at Level 1"
rm -rf "$SL_AUTO1_DIR"

# Test: Level 2 renders ▶▶ before phase
SL_AUTO2_DIR=$(mktemp -d)
mkdir -p "$SL_AUTO2_DIR/.claude/state" "$SL_AUTO2_DIR/.claude/hooks"
echo '{"phase": "discuss", "autonomy_level": 2, "message_shown": false, "active_skill": ""}' > "$SL_AUTO2_DIR/.claude/state/workflow.json"
touch "$SL_AUTO2_DIR/.claude/hooks/workflow-gate.sh"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_AUTO2_DIR\"}")
assert_contains "$OUTPUT" "▶▶ " "statusline shows ▶▶ for Level 2"
rm -rf "$SL_AUTO2_DIR"

# Test: Level 3 renders ▶▶▶ before phase
SL_AUTO3_DIR=$(mktemp -d)
mkdir -p "$SL_AUTO3_DIR/.claude/state" "$SL_AUTO3_DIR/.claude/hooks"
echo '{"phase": "review", "autonomy_level": 3, "message_shown": false, "active_skill": ""}' > "$SL_AUTO3_DIR/.claude/state/workflow.json"
touch "$SL_AUTO3_DIR/.claude/hooks/workflow-gate.sh"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_AUTO3_DIR\"}")
assert_contains "$OUTPUT" "▶▶▶ " "statusline shows ▶▶▶ for Level 3"
rm -rf "$SL_AUTO3_DIR"

# Test: No symbol when workflow is OFF
SL_AUTOOFF_DIR=$(mktemp -d)
mkdir -p "$SL_AUTOOFF_DIR/.claude/state" "$SL_AUTOOFF_DIR/.claude/hooks"
echo '{"phase": "off", "message_shown": false, "active_skill": ""}' > "$SL_AUTOOFF_DIR/.claude/state/workflow.json"
touch "$SL_AUTOOFF_DIR/.claude/hooks/workflow-gate.sh"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_AUTOOFF_DIR\"}")
CLEAN_OUTPUT=$(echo "$OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
assert_not_contains "$CLEAN_OUTPUT" "▶" "statusline shows no autonomy symbol when OFF"
rm -rf "$SL_AUTOOFF_DIR"

# Test: No symbol when autonomy_level field absent
SL_AUTOABS_DIR=$(mktemp -d)
mkdir -p "$SL_AUTOABS_DIR/.claude/state" "$SL_AUTOABS_DIR/.claude/hooks"
echo '{"phase": "implement", "message_shown": false, "active_skill": ""}' > "$SL_AUTOABS_DIR/.claude/state/workflow.json"
touch "$SL_AUTOABS_DIR/.claude/hooks/workflow-gate.sh"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_AUTOABS_DIR\"}")
CLEAN_OUTPUT=$(echo "$OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
assert_not_contains "$CLEAN_OUTPUT" "▶" "statusline shows no autonomy symbol when field absent"
rm -rf "$SL_AUTOABS_DIR"

# --- Claude-Mem observation ID in statusline ---

# Test: statusline shows observation ID when present
SL_OBS_DIR=$(mktemp -d)
mkdir -p "$SL_OBS_DIR/.claude/state" "$SL_OBS_DIR/.claude/hooks"
echo '{"phase": "implement", "autonomy_level": 2, "last_observation_id": 3007, "message_shown": true, "active_skill": ""}' > "$SL_OBS_DIR/.claude/state/workflow.json"
touch "$SL_OBS_DIR/.claude/hooks/workflow-gate.sh"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_OBS_DIR\",\"mcp_servers\":[\"claude-mem\"]}")
assert_contains "$OUTPUT" "#3007" "statusline shows observation ID when present"
assert_contains "$OUTPUT" "Claude-Mem" "statusline still shows Claude-Mem label"
rm -rf "$SL_OBS_DIR"

# Test: statusline shows no ID when field absent
SL_NOOBS_DIR=$(mktemp -d)
mkdir -p "$SL_NOOBS_DIR/.claude/state" "$SL_NOOBS_DIR/.claude/hooks"
echo '{"phase": "implement", "message_shown": true, "active_skill": ""}' > "$SL_NOOBS_DIR/.claude/state/workflow.json"
touch "$SL_NOOBS_DIR/.claude/hooks/workflow-gate.sh"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_NOOBS_DIR\",\"mcp_servers\":[\"claude-mem\"]}")
CLEAN_OUTPUT=$(echo "$OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
assert_not_contains "$CLEAN_OUTPUT" "#[0-9]" "statusline shows no observation ID when field absent"
rm -rf "$SL_NOOBS_DIR"

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
