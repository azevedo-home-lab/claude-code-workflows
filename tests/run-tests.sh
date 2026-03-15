#!/bin/bash
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
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$REPO_DIR/.claude/hooks"

# Create a fake project structure in TMPDIR
setup_test_project() {
    rm -rf "$TMPDIR"
    TMPDIR=$(mktemp -d)
    mkdir -p "$TMPDIR/.claude/hooks" "$TMPDIR/.claude/state" "$TMPDIR/.claude/commands"
    cp "$HOOKS_DIR/workflow-state.sh" "$TMPDIR/.claude/hooks/"
    cp "$HOOKS_DIR/workflow-gate.sh" "$TMPDIR/.claude/hooks/"
    cp "$HOOKS_DIR/bash-write-guard.sh" "$TMPDIR/.claude/hooks/"
    # Set CLAUDE_PROJECT_DIR for hooks
    export CLAUDE_PROJECT_DIR="$TMPDIR"
}

# ============================================================
# TEST SUITE: workflow-state.sh
# ============================================================
echo ""
echo "=== workflow-state.sh ==="

setup_test_project

# Test: get_phase returns "discuss" when no state file exists
RESULT=$(source "$TMPDIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "discuss" "$RESULT" "get_phase defaults to 'discuss' when no state file"

# Test: set_phase creates state file with correct phase
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
assert_file_exists "$TMPDIR/.claude/state/phase.json" "set_phase creates phase.json"

# Test: get_phase returns "implement" after set_phase
RESULT=$(source "$TMPDIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "implement" "$RESULT" "get_phase returns 'implement' after set_phase"

# Test: set_phase back to discuss
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
RESULT=$(source "$TMPDIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "discuss" "$RESULT" "set_phase can change back to 'discuss'"

# Test: state file contains timestamp
CONTENT=$(cat "$TMPDIR/.claude/state/phase.json")
assert_contains "$CONTENT" "updated" "state file contains timestamp"

# Test: set_phase creates state directory if missing
rm -rf "$TMPDIR/.claude/state"
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
assert_file_exists "$TMPDIR/.claude/state/phase.json" "set_phase creates state dir if missing"

# ============================================================
# TEST SUITE: workflow-gate.sh
# ============================================================
echo ""
echo "=== workflow-gate.sh ==="

# Test: blocks Write in DISCUSS phase
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
OUTPUT=$("$TMPDIR/.claude/hooks/workflow-gate.sh" 2>&1 || true)
assert_contains "$OUTPUT" "deny" "blocks Write/Edit in DISCUSS phase"
assert_contains "$OUTPUT" "BLOCKED" "shows BLOCKED message in DISCUSS"

# Test: allows Write in IMPLEMENT phase
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
OUTPUT=$("$TMPDIR/.claude/hooks/workflow-gate.sh" 2>&1 || true)
assert_not_contains "$OUTPUT" "deny" "allows Write/Edit in IMPLEMENT phase"

# Test: allows when no state file (first run)
setup_test_project
rm -f "$TMPDIR/.claude/state/phase.json"
OUTPUT=$("$TMPDIR/.claude/hooks/workflow-gate.sh" 2>&1 || true)
assert_not_contains "$OUTPUT" "deny" "allows when no state file (first run)"

# Test: deny message mentions /approve
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
OUTPUT=$("$TMPDIR/.claude/hooks/workflow-gate.sh" 2>&1 || true)
assert_contains "$OUTPUT" "/approve" "deny message mentions /approve command"

# ============================================================
# TEST SUITE: bash-write-guard.sh
# ============================================================
echo ""
echo "=== bash-write-guard.sh ==="

# Helper: run bash-write-guard with a command
run_bash_guard() {
    local cmd="$1"
    echo "{\"tool_input\":{\"command\":\"$cmd\"}}" | "$TMPDIR/.claude/hooks/bash-write-guard.sh" 2>&1 || true
}

# Test: allows all Bash in IMPLEMENT phase
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
OUTPUT=$(run_bash_guard "echo hello > file.txt")
assert_not_contains "$OUTPUT" "deny" "allows all Bash in IMPLEMENT phase"

# Test: allows read-only Bash in DISCUSS phase
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
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
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
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
OUTPUT=$(echo '{"tool_input":{"command":"python3 -c \"open('"'"'f'"'"','"'"'w'"'"').write('"'"'x'"'"')\""}}' | "$TMPDIR/.claude/hooks/bash-write-guard.sh" 2>&1 || true)
assert_contains "$OUTPUT" "deny" "blocks python3 -c file write in DISCUSS"

# Test: allows when no state file
setup_test_project
rm -f "$TMPDIR/.claude/state/phase.json"
OUTPUT=$(run_bash_guard "echo hello > file.txt")
assert_not_contains "$OUTPUT" "deny" "allows Bash writes when no state file (first run)"

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
assert_file_exists "$INSTALL_TARGET/.claude/commands/approve.md" "install creates approve.md"
assert_file_exists "$INSTALL_TARGET/.claude/commands/discuss.md" "install creates discuss.md"
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

# Test: auto-initializes phase.json to "discuss"
assert_file_exists "$INSTALL_TARGET/.claude/state/phase.json" "install auto-creates phase.json"
INIT_PHASE=$(grep -o '"phase"[[:space:]]*:[[:space:]]*"[^"]*"' "$INSTALL_TARGET/.claude/state/phase.json" | grep -o '"[^"]*"$' | tr -d '"')
assert_eq "discuss" "$INIT_PHASE" "install sets initial phase to discuss"

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
assert_file_not_exists "$UNINSTALL_TARGET/.claude/commands/approve.md" "uninstall removes approve.md"
assert_file_not_exists "$UNINSTALL_TARGET/.claude/commands/discuss.md" "uninstall removes discuss.md"
assert_file_not_exists "$UNINSTALL_TARGET/.claude/state" "uninstall removes state directory"

# Test: settings.json preserved (not deleted by uninstall)
assert_file_exists "$UNINSTALL_TARGET/.claude/settings.json" "uninstall preserves settings.json"

rm -rf "$UNINSTALL_TARGET"

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
