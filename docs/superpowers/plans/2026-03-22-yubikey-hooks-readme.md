# YubiKey Tiered Touch, Hook Fixes, Review Gap, README Rewrite — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix YubiKey touch UX (tiered touch policy), fix two workflow hook bugs, add negative test coverage to review pipeline, and rewrite README to be concise.

**Architecture:** Four independent changes sharing a single branch. Task B (hook fixes) should go first since the bugs affect the current session. Tasks A, C, D are independent of each other.

**Tech Stack:** Bash, shell hooks, ykman CLI, ssh-keygen, markdown

**Spec:** `docs/superpowers/specs/2026-03-22-yubikey-hooks-readme-design.md`

---

### Task 1: Fix PostToolUse coaching hook errors on irrelevant tools

**Files:**
- Modify: `.claude/hooks/post-tool-navigator.sh:88-101` (add early exit after Layer 1)
- Test: `tests/run-tests.sh` (add new test cases)

- [ ] **Step 1: Write failing tests for irrelevant tool types**

Add these tests to the `post-tool-navigator.sh` test suite section in `tests/run-tests.sh`, after the existing Layer 1 tests:

```bash
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run-tests.sh`
Expected: new tests FAIL (hook currently crashes or increments counter for irrelevant tools)

- [ ] **Step 3: Add early exit for irrelevant tools after Layer 1**

In `post-tool-navigator.sh`, after the Layer 1 block (after the `fi` that closes the `FIRE_LAYER1` check, around line 88), add:

```bash
# Early exit for tools that don't participate in Layer 2/3
# These tools don't need coaching evaluation or counter tracking
case "$TOOL_NAME" in
    Agent|Write|Edit|MultiEdit|NotebookEdit|Bash|AskUserQuestion) ;;
    mcp*save_observation) ;;
    *) # Tool is irrelevant to coaching — output any Layer 1 message and exit
        if [ -n "$MESSAGES" ]; then
            MESSAGES="$MESSAGES" python3 -c "
import json, os
output = {
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'systemMessage': os.environ['MESSAGES']
    }
}
print(json.dumps(output))
"
        fi
        exit 0
        ;;
esac
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run-tests.sh`
Expected: all tests PASS including new ones

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/post-tool-navigator.sh tests/run-tests.sh
git commit -m "fix: add early exit in PostToolUse hook for irrelevant tool types

Hook was firing increment_coaching_counter on every tool call (Read, Glob,
TaskCreate, etc.) causing errors with set -euo pipefail. Now exits cleanly
after Layer 1 for tools that don't participate in Layer 2/3 coaching."
```

---

### Task 2: Fix bash write guard false positive on `2>/dev/null`

**Files:**
- Modify: `.claude/hooks/bash-write-guard.sh:75-76` (strip safe redirects before pattern match)
- Test: `tests/run-tests.sh` (add new test cases)

- [ ] **Step 1: Write failing tests for stderr redirects**

Add these tests to the `bash-write-guard.sh` test suite section in `tests/run-tests.sh`, after the existing read-only tests:

```bash
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run-tests.sh`
Expected: the "allows" tests FAIL (guard currently blocks these), the "blocks" tests PASS

- [ ] **Step 3: Strip safe redirect patterns before write detection**

In `bash-write-guard.sh`, after the `COMMAND` extraction (around line 44) and before the `WRITE_PATTERN` check (line 75), add:

```bash
# Strip safe redirects before checking write patterns
# 2>/dev/null, 2>&1, 1>&2 etc. are not file writes
CLEAN_CMD=$(echo "$COMMAND" | sed -E 's/[0-9]+>\/dev\/null//g; s/[0-9]*>&[0-9]+//g')
```

Then change line 76 from:
```bash
if echo "$COMMAND" | grep -qE "$WRITE_PATTERN"; then
```
to:
```bash
if echo "$CLEAN_CMD" | grep -qE "$WRITE_PATTERN"; then
```

Keep the original `$COMMAND` for the write-target extraction inside the block (it still uses `$COMMAND` to find paths).

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run-tests.sh`
Expected: all tests PASS including new ones

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/bash-write-guard.sh tests/run-tests.sh
git commit -m "fix: bash write guard false positive on stderr redirects

2>/dev/null and 2>&1 were matching the >[^&] write pattern. Now strips
safe fd redirects before applying write detection. Real writes with
stderr redirects are still caught."
```

---

### Task 3: Add negative test coverage check to review pipeline

**Files:**
- Modify: `.claude/commands/review.md:66` (add directive to Code Quality agent prompt)
- Modify: `docs/reference/professional-standards.md:86` (add REVIEW standard)
- Test: manual — verify the text appears in the correct location

- [ ] **Step 1: Add test coverage directive to Code Quality agent prompt**

In `.claude/commands/review.md`, append to the end of the Agent 1 — Code Quality Reviewer prompt string (line 66), before the closing `"`):

Add this sentence after "...limit to 2000 tokens.":

```
Also check: are there tests for unhappy paths and edge cases? For every conditional branch, error path, or input validation in the changed code, verify a test exercises the failure case. If tests only cover happy paths, flag as WARNING with specific untested scenarios.
```

- [ ] **Step 2: Add professional standard to REVIEW Phase Standards**

In `docs/reference/professional-standards.md`, add after the last REVIEW standard ("Quantify the cost of not fixing."):

```markdown

**Review test coverage for unhappy paths.** Happy-path tests prove the feature works when everything goes right. Unhappy-path tests prove it doesn't break when things go wrong. If the test suite only verifies positive cases, flag it. Every conditional branch implies at least one negative case that needs a test. "It works on my inputs" is not coverage.
```

- [ ] **Step 3: Verify changes are in the right locations**

Read both files and confirm the new text appears in the correct sections.

- [ ] **Step 4: Commit**

```bash
git add .claude/commands/review.md docs/reference/professional-standards.md
git commit -m "feat: add negative test coverage check to review pipeline

Code Quality agent now flags missing unhappy-path tests. New professional
standard: every conditional branch needs a failure test. Addresses gap
that allowed hook bugs to ship with only positive test coverage."
```

---

### Task 4: Rewrite `git-yubikey` with tiered touch and presence check

**Files:**
- Modify: `tools/yubikey-setup/git-yubikey` (full rewrite)
- Test: `tests/run-tests.sh` (add git-yubikey test suite)

- [ ] **Step 1: Write tests for the new git-yubikey behavior**

Add a new test suite section to `tests/run-tests.sh`:

```bash
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
OUTPUT=$(echo "n" | YKMAN_CMD="$MOCK_BIN/ykman-present" GIT_CMD="$MOCK_BIN/mock-git" "$GIT_YUBIKEY" push --force origin main 2>&1)
assert_contains "$OUTPUT" "DESTRUCTIVE" "shows DESTRUCTIVE warning for push --force"
assert_not_contains "$OUTPUT" "MOCK_GIT_CALLED" "aborts when user says no"

OUTPUT=$(echo "n" | YKMAN_CMD="$MOCK_BIN/ykman-present" GIT_CMD="$MOCK_BIN/mock-git" "$GIT_YUBIKEY" push --delete origin feature 2>&1)
assert_contains "$OUTPUT" "DESTRUCTIVE" "shows DESTRUCTIVE warning for push --delete"

OUTPUT=$(echo "n" | YKMAN_CMD="$MOCK_BIN/ykman-present" GIT_CMD="$MOCK_BIN/mock-git" "$GIT_YUBIKEY" branch -D feature 2>&1)
assert_contains "$OUTPUT" "DESTRUCTIVE" "shows DESTRUCTIVE warning for branch -D"

OUTPUT=$(echo "n" | YKMAN_CMD="$MOCK_BIN/ykman-present" GIT_CMD="$MOCK_BIN/mock-git" "$GIT_YUBIKEY" push -f origin main 2>&1)
assert_contains "$OUTPUT" "DESTRUCTIVE" "shows DESTRUCTIVE warning for push -f"

# Test: dangerous command proceeds when user confirms
OUTPUT=$(echo "y" | YKMAN_CMD="$MOCK_BIN/ykman-present" GIT_CMD="$MOCK_BIN/mock-git" "$GIT_YUBIKEY" push --force origin main 2>&1)
assert_contains "$OUTPUT" "MOCK_GIT_CALLED" "proceeds when user confirms dangerous command"

rm -rf "$MOCK_BIN"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run-tests.sh`
Expected: new git-yubikey tests FAIL (current wrapper has no presence check or dangerous command detection)

- [ ] **Step 3: Rewrite git-yubikey**

Replace the contents of `tools/yubikey-setup/git-yubikey` with:

```bash
#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Git wrapper with tiered YubiKey enforcement:
#   1. YubiKey must be plugged in — all git blocked if absent
#   2. Safe commands pass through (no touch, no confirmation)
#   3. Dangerous commands require explicit confirmation before proceeding
#
# Usage: use 'git-yubikey' anywhere you'd use 'git'.
#
# Environment overrides (for testing):
#   YKMAN_CMD  — path to ykman binary (default: ykman)
#   GIT_CMD    — path to git binary (default: /usr/bin/git)

YKMAN="${YKMAN_CMD:-ykman}"
GIT="${GIT_CMD:-/usr/bin/git}"

# --- Step 1: Check YubiKey presence ---
if ! "$YKMAN" list --serials 2>/dev/null | grep -q '[0-9]'; then
    echo ""
    echo "========================================"
    echo "  YubiKey not detected."
    echo "  Git operations require YubiKey."
    echo "========================================"
    echo ""
    exit 1
fi

# --- Step 2: Classify command ---
# Note: tag -d is local-only (recoverable via reflog). Remote tag deletion
# is done via 'push --delete origin <tag>', which IS caught below.
is_dangerous() {
    local args=("$@")
    local subcmd="${args[0]:-}"

    case "$subcmd" in
        push)
            for arg in "${args[@]:1}"; do
                case "$arg" in
                    --force|--force-with-lease|-f|--delete) return 0 ;;
                esac
            done
            ;;
        branch)
            for arg in "${args[@]:1}"; do
                case "$arg" in
                    -D|-M) return 0 ;;
                esac
            done
            ;;
    esac
    return 1
}

# --- Step 3: Gate dangerous commands ---
if is_dangerous "$@"; then
    echo ""
    echo "========================================"
    echo "  DESTRUCTIVE: git $*"
    echo "  This cannot be undone on the remote."
    echo "========================================"
    read -p "  Confirm? (y/N) " -n 1 -r REPLY
    echo ""
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# --- Step 4: Execute ---
exec "$GIT" "$@"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run-tests.sh`
Expected: all tests PASS including new git-yubikey tests

- [ ] **Step 5: Commit**

```bash
git add tools/yubikey-setup/git-yubikey tests/run-tests.sh
git commit -m "feat: rewrite git-yubikey with tiered touch enforcement

Three tiers: blocked when YubiKey absent, pass-through for safe commands,
confirmation prompt for destructive commands (push --force, push --delete,
branch -D/-M). Supports YKMAN_CMD and GIT_CMD env vars for testing."
```

---

### Task 5: Update YubiKey SSH wrappers and documentation

**Files:**
- Modify: `tools/yubikey-setup/git-ssh-auth.sh:19` (update default key path)
- Modify: `tools/yubikey-setup/CLAUDE.md.snippet` (reflect new behavior)
- Modify: `tools/yubikey-setup/README.md` (document new tiered behavior)

- [ ] **Step 1: Update default key path in git-ssh-auth.sh**

In `tools/yubikey-setup/git-ssh-auth.sh`, line 19, update the default key path to reference the new no-touch key. Change:

```bash
YUBIKEY_SSH_KEY="${YUBIKEY_SSH_KEY:-$HOME/.ssh/id_ed25519_sk}"
```

to:

```bash
YUBIKEY_SSH_KEY="${YUBIKEY_SSH_KEY:-$HOME/.ssh/id_ed25519_sk_no_touch}"
```

Also update the comment on line 17 to say "CUSTOMIZE: Change the -i path to your no-touch ed25519-sk key file."

Note: The actual key filename will depend on what the user names it during generation. The README Key Setup section documents this. Use a sensible default.

- [ ] **Step 2: Update CLAUDE.md.snippet**

Replace the contents of `tools/yubikey-setup/CLAUDE.md.snippet` with:

```markdown
## YubiKey Git Signing & Auth

**All git commits are signed and all GitHub pushes are authenticated via YubiKey FIDO2. The YubiKey must be plugged in for any git operation.**

### Rules for Claude Code Sessions

1. **Use `git-yubikey` instead of `git`** for all git commands. It checks YubiKey presence and gates destructive operations.
2. **Safe commands** (commit, push, pull, fetch, tag): no touch needed — YubiKey presence is enough.
3. **Destructive commands** (push --force, push --delete, branch -D/-M): require explicit confirmation.
4. **If YubiKey is unplugged**: all git operations are blocked. Ask user to insert YubiKey.
5. **NEVER use `commit.gpgsign=false`** or `--no-gpg-sign` — YubiKey signing is a security requirement.

### How It Works

| Wrapper | Purpose | Git Config |
|---------|---------|------------|
| `/usr/local/bin/git-ssh-sign` | Commit signing | `gpg.ssh.program` |
| `/usr/local/bin/git-ssh-auth` | Push/pull auth | `core.sshCommand` |
| `/usr/local/bin/ssh-askpass-wrapper` | Popup filter | `SSH_ASKPASS` in `~/.zshenv` |
| `~/bin/git-yubikey` | Presence check + destructive gate | Used directly |

### Reinstall (if wrappers are lost)

```bash
curl -fsSL https://raw.githubusercontent.com/azevedo-home-lab/claude-code-workflows/main/tools/yubikey-setup/install.sh | bash
```
```

- [ ] **Step 2: Update YubiKey README**

In `tools/yubikey-setup/README.md`, update the "What It Does" section to reflect the new tiered behavior:

Replace the `git-yubikey` bullet with:
```markdown
- **git-yubikey**: Git wrapper with tiered YubiKey enforcement. Checks presence (blocks all git if absent), passes safe commands through silently, and requires confirmation for destructive operations (push --force, push --delete, branch -D/-M).
```

Add a new section after "Quick Install":

```markdown
## Key Setup

The no-touch-required SSH key allows YubiKey presence to authorize safe operations without physical tap.

```bash
# Generate no-touch key (one-time)
ssh-keygen -t ed25519-sk -O no-touch-required -O resident -C "yubikey-no-touch"

# Then register on GitHub:
# 1. Add the .pub as a signing key
# 2. Add the .pub as an authentication key
# 3. Update ~/.ssh/allowed_signers
# 4. Update git config: git config --global user.signingkey ~/.ssh/<new-key>.pub
```
```

- [ ] **Step 3: Verify changes read correctly**

Read both files and confirm the documentation is accurate and concise.

- [ ] **Step 4: Commit**

```bash
git add tools/yubikey-setup/git-ssh-auth.sh tools/yubikey-setup/CLAUDE.md.snippet tools/yubikey-setup/README.md
git commit -m "feat: update YubiKey wrappers and docs for tiered touch

git-ssh-auth.sh default key path updated to no-touch key.
CLAUDE.md.snippet reflects new three-tier model. README documents
no-touch key generation and updated git-yubikey behavior."
```

---

### Task 6: Rewrite README

**Files:**
- Modify: `README.md` (rewrite)
- Modify: `docs/reference/architecture.md` (add mermaid diagram)

- [ ] **Step 1: Move mermaid diagram to architecture doc**

In `docs/reference/architecture.md`, add the mermaid diagram from the current README after the existing "Phase Model" section (after line 53). Add a heading `### Detailed Workflow Diagram` and paste the mermaid block.

- [ ] **Step 2: Rewrite README**

Replace `README.md` with a concise version. Target ~80-100 lines:

```markdown
# Claude Code Workflows

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

Structured development with Claude Code. Think before coding, review before shipping.

Four tools that work together:

- **Workflow Manager** — hooks that block code edits until you have a plan
- **Superpowers** — skills for brainstorming, TDD, planning, debugging, code review
- **claude-mem** — cross-session memory via MCP server
- **Status Line** — context usage, git branch, workflow phase at a glance

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/azevedo-home-lab/claude-code-workflows/main/install.sh | bash
```

Or clone and install manually:

```bash
git clone https://github.com/azevedo-home-lab/claude-code-workflows.git
./claude-code-workflows/install.sh /path/to/your/project
```

Uninstall: `./uninstall.sh`

If your project has a `CLAUDE.md`, review [`claude.md.template`](claude.md.template) and merge any relevant sections.

## Workflow

Six phases. Code edits are blocked until you discuss and approve a plan.

| Phase | Edits | What happens |
|-------|-------|--------------|
| **OFF** | Allowed | No enforcement |
| **DEFINE** | Blocked | Frame the problem, define outcomes |
| **DISCUSS** | Blocked | Research approaches, write plan |
| **IMPLEMENT** | Allowed | Execute plan with TDD |
| **REVIEW** | Allowed | 3 parallel review agents + verification |
| **COMPLETE** | Blocked | Validate outcomes, docs, handover |

Commands: `/define` `/discuss` `/implement` `/review` `/complete`

Any command can jump to any phase. Soft gates warn when skipping steps.

Each cycle produces a **decision record** tracking problem, approaches, rationale, findings, and outcomes.

## Tools

| Tool | What it does | Docs |
|------|-------------|------|
| Workflow Manager | Phase-based edit gates + coaching system | [Hooks reference](docs/reference/hooks.md) |
| Superpowers | Auto-activated development skills | [Integration guide](docs/guides/integration-guide.md) |
| claude-mem | Persistent cross-session observations | [Memory guide](docs/guides/claude-mem-guide.md) |
| Status Line | Color-coded status bar | [Setup guide](docs/guides/statusline-guide.md) |
| YubiKey signing | FIDO2 commit signing + push auth | [YubiKey setup](tools/yubikey-setup/) |
| iTerm Launcher | Dedicated Claude Code window | [Launcher](tools/iterm-launcher/) |

## Docs

- [Getting Started](docs/guides/getting-started.md) — installation and first workflow
- [Architecture](docs/reference/architecture.md) — how the pieces fit together
- [Command Reference](docs/quick-reference/commands.md) — all commands
- [Professional Standards](docs/reference/professional-standards.md) — behavioral expectations per phase

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[GPL v3](LICENSE)
```

- [ ] **Step 3: Verify line count and readability**

Read the new README. Confirm it's under 100 lines and links to the right docs.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/reference/architecture.md
git commit -m "docs: rewrite README — concise, human-readable

Cut from ~296 to ~80 lines. Moved mermaid diagram and pipeline details
to architecture doc. README now focuses on what it is, how to install,
and where to find details."
```

---

### Task 7: Run full test suite and verify

- [ ] **Step 1: Run the full test suite**

Run: `./tests/run-tests.sh`
Expected: all tests PASS

- [ ] **Step 2: Verify no regressions in hook behavior**

Manually check: set phase to discuss, verify that Read/Glob don't produce hook errors. Verify that bash commands with `2>/dev/null` are allowed.

- [ ] **Step 3: Final commit if any fixups needed**

If any test failures or issues found, fix and commit.
