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

# Test: get_phase returns "off" when no state file exists
RESULT=$(source "$TMPDIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "off" "$RESULT" "get_phase defaults to 'off' when no state file"

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

# Test: set_phase to review
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "review"
RESULT=$(source "$TMPDIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "review" "$RESULT" "set_phase supports 'review' phase"

# Test: state file contains timestamp
CONTENT=$(cat "$TMPDIR/.claude/state/phase.json")
assert_contains "$CONTENT" "updated" "state file contains timestamp"

# Test: set_phase initializes message_shown to false
assert_contains "$CONTENT" '"message_shown": false' "set_phase initializes message_shown to false"

# Test: get_message_shown returns false initially
RESULT=$(source "$TMPDIR/.claude/hooks/workflow-state.sh" && get_message_shown)
assert_eq "false" "$RESULT" "get_message_shown returns false initially"

# Test: set_message_shown sets flag to true
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_message_shown
RESULT=$(source "$TMPDIR/.claude/hooks/workflow-state.sh" && get_message_shown)
assert_eq "true" "$RESULT" "set_message_shown sets flag to true"

# Test: set_phase resets message_shown to false
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
RESULT=$(source "$TMPDIR/.claude/hooks/workflow-state.sh" && get_message_shown)
assert_eq "false" "$RESULT" "set_phase resets message_shown to false"

# Test: set_phase creates state directory if missing
rm -rf "$TMPDIR/.claude/state"
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
assert_file_exists "$TMPDIR/.claude/state/phase.json" "set_phase creates state dir if missing"

# Test: set_phase rejects invalid phase names
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
OUTPUT=$(source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "invalid_phase" 2>&1 || true)
assert_contains "$OUTPUT" "ERROR" "set_phase rejects invalid phase name"
# Verify phase didn't change
RESULT=$(source "$TMPDIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "implement" "$RESULT" "set_phase keeps previous phase after rejection"

# Test: set_phase accepts 'off' phase
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "off"
RESULT=$(source "$TMPDIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "off" "$RESULT" "set_phase accepts 'off' phase"

# Test: set_phase accepts 'define' phase
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "define"
RESULT=$(source "$TMPDIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "define" "$RESULT" "set_phase accepts 'define' phase"

# Test: set_phase cleans up review-status.json when leaving review
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "review"
source "$TMPDIR/.claude/hooks/workflow-state.sh" && reset_review_status
assert_file_exists "$TMPDIR/.claude/state/review-status.json" "review-status exists in review phase"
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
assert_file_not_exists "$TMPDIR/.claude/state/review-status.json" "set_phase deletes review-status when leaving review"

# Test: set_phase does NOT delete review-status.json when staying in review (re-run)
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "review"
source "$TMPDIR/.claude/hooks/workflow-state.sh" && reset_review_status
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "review"
assert_file_exists "$TMPDIR/.claude/state/review-status.json" "re-entering review keeps review-status"

# Test: reset_review_status creates review-status.json
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && reset_review_status
assert_file_exists "$TMPDIR/.claude/state/review-status.json" "reset_review_status creates file"

# Test: review-status.json has correct initial fields
CONTENT=$(cat "$TMPDIR/.claude/state/review-status.json")
assert_contains "$CONTENT" '"verification_complete": false' "review-status has verification_complete false"
assert_contains "$CONTENT" '"verification_skipped": false' "review-status has verification_skipped false"
assert_contains "$CONTENT" '"agents_dispatched": false' "review-status has agents_dispatched false"
assert_contains "$CONTENT" '"findings_presented": false' "review-status has findings_presented false"
assert_contains "$CONTENT" '"findings_acknowledged": false' "review-status has findings_acknowledged false"

# Test: set_review_field updates a field
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_review_field "verification_complete" "true"
RESULT=$(source "$TMPDIR/.claude/hooks/workflow-state.sh" && get_review_field "verification_complete")
assert_eq "true" "$RESULT" "set_review_field updates verification_complete"

# Test: get_review_field returns false for unset field
RESULT=$(source "$TMPDIR/.claude/hooks/workflow-state.sh" && get_review_field "agents_dispatched")
assert_eq "false" "$RESULT" "get_review_field returns false for unset field"

# Test: get_review_field returns empty when no file
rm -f "$TMPDIR/.claude/state/review-status.json"
RESULT=$(source "$TMPDIR/.claude/hooks/workflow-state.sh" && get_review_field "verification_complete")
assert_eq "" "$RESULT" "get_review_field returns empty when no file"

# ============================================================
# TEST SUITE: workflow-gate.sh
# ============================================================
echo ""
echo "=== workflow-gate.sh ==="

# Helper: run workflow-gate with a file path
run_gate() {
    local file_path="$1"
    echo "{\"tool_input\":{\"file_path\":\"$file_path\"}}" | "$TMPDIR/.claude/hooks/workflow-gate.sh" 2>&1 || true
}

# Test: blocks Write to source files in DISCUSS phase
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
OUTPUT=$(run_gate "/project/src/main.py")
assert_contains "$OUTPUT" "deny" "blocks Write/Edit to source files in DISCUSS phase"
assert_contains "$OUTPUT" "BLOCKED" "shows BLOCKED message in DISCUSS"

# Test: allows Write in IMPLEMENT phase
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
OUTPUT=$(run_gate "/project/src/main.py")
assert_not_contains "$OUTPUT" "deny" "allows Write/Edit in IMPLEMENT phase"

# Test: allows when no state file (first run)
setup_test_project
rm -f "$TMPDIR/.claude/state/phase.json"
OUTPUT=$(run_gate "/project/src/main.py")
assert_not_contains "$OUTPUT" "deny" "allows when no state file (first run)"

# Test: allows Write in REVIEW phase (edits allowed for fixes)
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "review"
OUTPUT=$(run_gate "/project/src/main.py")
assert_not_contains "$OUTPUT" "deny" "allows Write/Edit in REVIEW phase"

# Test: deny message mentions /approve
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
OUTPUT=$(run_gate "/project/src/main.py")
assert_contains "$OUTPUT" "/approve" "deny message mentions /approve command"

# Test: allows Write to .claude/state/ in DISCUSS phase (whitelist)
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
OUTPUT=$(run_gate "/project/.claude/state/phase.json")
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
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "off"
OUTPUT=$(run_gate "/project/src/main.py")
assert_not_contains "$OUTPUT" "deny" "allows Write/Edit in OFF phase"

# Test: blocks Write/Edit in DEFINE phase
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "define"
OUTPUT=$(run_gate "/project/src/main.py")
assert_contains "$OUTPUT" "deny" "blocks Write/Edit to source files in DEFINE phase"
assert_contains "$OUTPUT" "BLOCKED" "shows BLOCKED message in DEFINE"

# Test: allows Write to whitelisted paths in DEFINE phase
OUTPUT=$(run_gate "/project/.claude/state/phase.json")
assert_not_contains "$OUTPUT" "deny" "allows Write to .claude/state/ in DEFINE (whitelist)"

OUTPUT=$(run_gate "/project/docs/superpowers/specs/design.md")
assert_not_contains "$OUTPUT" "deny" "allows Write to docs/superpowers/specs/ in DEFINE (whitelist)"

OUTPUT=$(run_gate "/project/docs/plans/define.json")
assert_not_contains "$OUTPUT" "deny" "allows Write to docs/plans/ in DEFINE (whitelist)"

# Test: deny message in DEFINE mentions /discuss
OUTPUT=$(run_gate "/project/src/main.py")
assert_contains "$OUTPUT" "/discuss" "deny message in DEFINE mentions /discuss"

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

# Test: allows all Bash in REVIEW phase
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "review"
OUTPUT=$(run_bash_guard "echo hello > file.txt")
assert_not_contains "$OUTPUT" "deny" "allows all Bash in REVIEW phase"

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

# Test: allows all Bash in OFF phase
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "off"
OUTPUT=$(run_bash_guard "echo hello > file.txt")
assert_not_contains "$OUTPUT" "deny" "allows all Bash in OFF phase"

# Test: allows when no state file
setup_test_project
rm -f "$TMPDIR/.claude/state/phase.json"
OUTPUT=$(run_bash_guard "echo hello > file.txt")
assert_not_contains "$OUTPUT" "deny" "allows Bash writes when no state file (first run)"

# Test: allows writes to .claude/state/ in DISCUSS phase (whitelist)
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
OUTPUT=$(run_bash_guard "echo '{\"phase\":\"implement\"}' > .claude/state/phase.json")
assert_not_contains "$OUTPUT" "deny" "allows Bash write to .claude/state/ in DISCUSS (whitelist)"

# Test: allows writes to docs/superpowers/specs/ in DISCUSS phase (whitelist)
OUTPUT=$(run_bash_guard "cat > docs/superpowers/specs/design.md << EOF")
assert_not_contains "$OUTPUT" "deny" "allows Bash write to docs/superpowers/specs/ in DISCUSS (whitelist)"

# Test: allows writes to docs/plans/ in DISCUSS phase (whitelist)
OUTPUT=$(run_bash_guard "echo 'plan content' > docs/plans/plan.md")
assert_not_contains "$OUTPUT" "deny" "allows Bash write to docs/plans/ in DISCUSS (whitelist)"

# Test: blocks Bash redirect in DEFINE phase
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "define"
OUTPUT=$(run_bash_guard "echo hello > file.txt")
assert_contains "$OUTPUT" "deny" "blocks 'echo hello > file.txt' in DEFINE"

# Test: allows read-only Bash in DEFINE phase
OUTPUT=$(run_bash_guard "cat file.txt")
assert_not_contains "$OUTPUT" "deny" "allows 'cat file.txt' in DEFINE"

# Test: allows writes to whitelisted paths in DEFINE
OUTPUT=$(run_bash_guard "echo '{\"phase\":\"discuss\"}' > .claude/state/phase.json")
assert_not_contains "$OUTPUT" "deny" "allows Bash write to .claude/state/ in DEFINE (whitelist)"

OUTPUT=$(run_bash_guard "echo 'plan' > docs/plans/define.json")
assert_not_contains "$OUTPUT" "deny" "allows Bash write to docs/plans/ in DEFINE (whitelist)"

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
assert_file_exists "$INSTALL_TARGET/.claude/commands/approve.md" "install creates approve.md"
assert_file_exists "$INSTALL_TARGET/.claude/commands/discuss.md" "install creates discuss.md"
assert_file_exists "$INSTALL_TARGET/.claude/commands/review.md" "install creates review.md"
assert_file_exists "$INSTALL_TARGET/.claude/commands/complete.md" "install creates complete.md"
assert_file_exists "$INSTALL_TARGET/.claude/commands/override.md" "install creates override.md"
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
assert_file_not_exists "$UNINSTALL_TARGET/.claude/commands/approve.md" "uninstall removes approve.md"
assert_file_not_exists "$UNINSTALL_TARGET/.claude/commands/discuss.md" "uninstall removes discuss.md"
assert_file_not_exists "$UNINSTALL_TARGET/.claude/commands/review.md" "uninstall removes review.md"
assert_file_not_exists "$UNINSTALL_TARGET/.claude/commands/complete.md" "uninstall removes complete.md"
assert_file_not_exists "$UNINSTALL_TARGET/.claude/commands/override.md" "uninstall removes override.md"
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
    echo "{\"tool_name\":\"$tool\"}" | "$TMPDIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true
}

# Test: shows message in IMPLEMENT phase on first Write
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TMPDIR/.claude/hooks/"
OUTPUT=$(run_navigator "Write")
assert_contains "$OUTPUT" "IMPLEMENT phase" "navigator shows IMPLEMENT message on Write"

# Test: silent on second tool use (message_shown = true)
OUTPUT=$(run_navigator "Edit")
assert_not_contains "$OUTPUT" "IMPLEMENT" "navigator silent after first message shown"

# Test: phase change resets message_shown
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "review"
OUTPUT=$(run_navigator "Read")
assert_contains "$OUTPUT" "REVIEW phase" "navigator shows REVIEW message after phase change"

# Test: silent on Read/Grep in IMPLEMENT phase
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TMPDIR/.claude/hooks/"
OUTPUT=$(run_navigator "Read")
assert_not_contains "$OUTPUT" "IMPLEMENT" "navigator silent on Read in IMPLEMENT"

OUTPUT=$(run_navigator "Grep")
assert_not_contains "$OUTPUT" "IMPLEMENT" "navigator silent on Grep in IMPLEMENT"

# Test: shows DISCUSS message
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TMPDIR/.claude/hooks/"
OUTPUT=$(run_navigator "Read")
assert_contains "$OUTPUT" "DISCUSS phase" "navigator shows DISCUSS message"

# Test: no message when no state file
setup_test_project
rm -f "$TMPDIR/.claude/state/phase.json"
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TMPDIR/.claude/hooks/"
OUTPUT=$(run_navigator "Write")
assert_not_contains "$OUTPUT" "phase" "navigator silent when no state file"

# Test: REVIEW message mentions /complete
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "review"
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TMPDIR/.claude/hooks/"
OUTPUT=$(run_navigator "Bash")
assert_contains "$OUTPUT" "/complete" "navigator REVIEW message mentions /complete"

# Test: IMPLEMENT message mentions /review
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TMPDIR/.claude/hooks/"
OUTPUT=$(run_navigator "Write")
assert_contains "$OUTPUT" "/review" "navigator IMPLEMENT message mentions /review"

# Test: all messages mention /discuss
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TMPDIR/.claude/hooks/"
OUTPUT=$(run_navigator "Write")
assert_contains "$OUTPUT" "/discuss" "navigator IMPLEMENT message mentions /discuss"

# Test: shows DEFINE message
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "define"
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TMPDIR/.claude/hooks/"
OUTPUT=$(run_navigator "Read")
assert_contains "$OUTPUT" "DEFINE phase" "navigator shows DEFINE message"

# Test: DEFINE message mentions /discuss
assert_contains "$OUTPUT" "/discuss" "navigator DEFINE message mentions /discuss"

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

# Test: shows active skill in statusline
SL_TEST_DIR=$(mktemp -d)
mkdir -p "$SL_TEST_DIR/.claude/state"
echo '{"skill": "brainstorming", "updated": "test"}' > "$SL_TEST_DIR/.claude/state/active-skill.json"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_TEST_DIR\"}")
assert_contains "$OUTPUT" "brainstorming" "statusline shows active skill name"
rm -rf "$SL_TEST_DIR"

# Test: no skill shown when skill field is empty
SL_TEST_DIR2=$(mktemp -d)
mkdir -p "$SL_TEST_DIR2/.claude/state"
echo '{"skill": "", "updated": "test"}' > "$SL_TEST_DIR2/.claude/state/active-skill.json"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_TEST_DIR2\"}")
# Strip ANSI codes and check for empty brackets like "[]"
CLEAN_OUTPUT=$(echo "$OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
assert_not_contains "$CLEAN_OUTPUT" "\[\]" "statusline hides empty skill brackets"
rm -rf "$SL_TEST_DIR2"

# Test: shows DEFINE phase in statusline
SL_DEFINE_DIR=$(mktemp -d)
mkdir -p "$SL_DEFINE_DIR/.claude/state" "$SL_DEFINE_DIR/.claude/hooks"
echo '{"phase": "define", "message_shown": false}' > "$SL_DEFINE_DIR/.claude/state/phase.json"
touch "$SL_DEFINE_DIR/.claude/hooks/workflow-gate.sh"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_DEFINE_DIR\"}")
assert_contains "$OUTPUT" "DEFINE" "statusline shows DEFINE phase label"
assert_contains "$OUTPUT" '\[34m' "statusline uses blue (\\033[34m) for DEFINE phase"
rm -rf "$SL_DEFINE_DIR"

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
