# Public Release Preparation — Implementation Plan

> **Superseded** by `2026-03-20-workflow-rework.md`. This plan was executed but the system was subsequently reworked.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add DEFINE phase with outcome validation, GPL v3 licensing, and community files to prepare the repo for public release.

**Architecture:** New `/define` command guides problem + outcome definition, persisted to `docs/plans/define.json`. Hooks and statusline updated to recognize the DEFINE phase with same edit-blocking as DISCUSS. `/complete` gets a second validation pass checking outcomes. Community files (LICENSE, SECURITY.md, CONTRIBUTING.md, CODE_OF_CONDUCT.md, GitHub templates) added at repo root.

**Tech Stack:** Bash, Python3 (JSON manipulation), Markdown

**Spec:** `docs/superpowers/specs/2026-03-19-public-release-design.md`

---

### Task 1: Add DEFINE phase to workflow-state.sh

**Files:**
- Modify: `.claude/hooks/workflow-state.sh:26-28`
- Test: `tests/run-tests.sh`

- [ ] **Step 1: Write the failing test — set_phase accepts 'define'**

Add after the existing `set_phase accepts 'off' phase` test (around line 185 of `tests/run-tests.sh`):

```bash
# Test: set_phase accepts 'define' phase
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "define"
RESULT=$(source "$TMPDIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "define" "$RESULT" "set_phase accepts 'define' phase"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run-tests.sh 2>&1 | tail -5`
Expected: FAIL — "set_phase accepts 'define' phase" fails because `set_phase` rejects "define" as invalid.

- [ ] **Step 3: Add 'define' to the valid phases case statement**

In `.claude/hooks/workflow-state.sh`, line 27, change:

```bash
        off|discuss|implement|review) ;;
```

to:

```bash
        off|define|discuss|implement|review) ;;
```

And update the error message on line 28:

```bash
        *) echo "ERROR: Invalid phase: $new_phase (valid: off, define, discuss, implement, review)" >&2; return 1 ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run-tests.sh 2>&1 | tail -5`
Expected: PASS — all tests pass including new define test.

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/workflow-state.sh tests/run-tests.sh
git commit -m "feat: add 'define' as valid workflow phase"
```

---

### Task 2: Add DEFINE phase to workflow-gate.sh

**Files:**
- Modify: `.claude/hooks/workflow-gate.sh:2,24,45-52`
- Test: `tests/run-tests.sh`

- [ ] **Step 1: Write the failing tests — gate blocks edits in DEFINE phase**

Add after the existing `allows Write/Edit in OFF phase` test (around line 294 of `tests/run-tests.sh`):

```bash
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | grep -E "FAIL|PASS" | tail -10`
Expected: FAIL — define phase tests fail because gate allows everything in non-discuss phases.

- [ ] **Step 3: Update workflow-gate.sh to block edits in DEFINE phase**

Update the comment on line 2:

```bash
# Workflow Manager: blocks Write/Edit/MultiEdit/NotebookEdit in DISCUSS and DEFINE phases
```

Change line 24 from:

```bash
if [ "$PHASE" != "discuss" ]; then
```

to:

```bash
if [ "$PHASE" != "discuss" ] && [ "$PHASE" != "define" ]; then
```

Update the comment on line 28 (after the change, now the line after `exit 0`):

```bash
# DISCUSS/DEFINE phase: check if the target file is in a whitelisted path
```

Replace the deny message block (lines 45-54, including the trailing `exit 0`) with a phase-aware version:

```bash
# Phase-aware deny message
if [ "$PHASE" = "define" ]; then
    REASON="BLOCKED: Phase is DEFINE. Code changes are not allowed until you define the problem and outcomes. Use /discuss to proceed to discussion."
else
    REASON="BLOCKED: Phase is DISCUSS. Code changes are not allowed until a plan is discussed and approved. Use /approve to proceed to implementation."
fi

REASON="$REASON" python3 -c "
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
exit 0
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -5`
Expected: PASS — all tests pass.

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/workflow-gate.sh tests/run-tests.sh
git commit -m "feat: workflow-gate blocks edits in DEFINE phase with phase-aware deny message"
```

---

### Task 3: Add DEFINE phase to bash-write-guard.sh

**Files:**
- Modify: `.claude/hooks/bash-write-guard.sh:2,4,25`
- Test: `tests/run-tests.sh`

- [ ] **Step 1: Write the failing tests — bash guard blocks writes in DEFINE**

Add after the existing `allows Bash write to docs/plans/` test (around line 385 of `tests/run-tests.sh`):

```bash
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | grep "DEFINE" | head -5`
Expected: FAIL — define phase bash tests fail.

- [ ] **Step 3: Update bash-write-guard.sh to block writes in DEFINE**

Update comment on line 2:

```bash
# Workflow Manager: blocks Bash write operations in DISCUSS and DEFINE phases
```

Change line 25 from:

```bash
if [ "$PHASE" != "discuss" ]; then
```

to:

```bash
if [ "$PHASE" != "discuss" ] && [ "$PHASE" != "define" ]; then
```

Replace the entire deny heredoc block (lines 52-61, from `cat <<'DENY'` through `exit 0`) with a Python-based approach that supports phase-aware messages (same pattern as Task 2):

```bash
    # Phase-aware deny message
    if [ "$PHASE" = "define" ]; then
        REASON="BLOCKED: Bash write operation detected in DEFINE phase. Code changes are not allowed until you define the problem and outcomes. Use /discuss to proceed to discussion."
    else
        REASON="BLOCKED: Bash write operation detected in DISCUSS phase. Code changes are not allowed until a plan is discussed and approved. Use /approve to proceed to implementation."
    fi

    REASON="$REASON" python3 -c "
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
    exit 0
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -5`
Expected: PASS — all tests pass.

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/bash-write-guard.sh tests/run-tests.sh
git commit -m "feat: bash-write-guard blocks writes in DEFINE phase"
```

---

### Task 4: Add DEFINE phase to post-tool-navigator.sh

**Files:**
- Modify: `.claude/hooks/post-tool-navigator.sh:39-52`
- Test: `tests/run-tests.sh`

- [ ] **Step 1: Write the failing test — navigator shows DEFINE message**

Add after the existing `navigator IMPLEMENT message mentions /discuss` test (around line 559 of `tests/run-tests.sh`):

```bash
# Test: shows DEFINE message
setup_test_project
source "$TMPDIR/.claude/hooks/workflow-state.sh" && set_phase "define"
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TMPDIR/.claude/hooks/"
OUTPUT=$(run_navigator "Read")
assert_contains "$OUTPUT" "DEFINE phase" "navigator shows DEFINE message"

# Test: DEFINE message mentions /discuss
assert_contains "$OUTPUT" "/discuss" "navigator DEFINE message mentions /discuss"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | grep "DEFINE" | tail -5`
Expected: FAIL — define navigator tests fail.

- [ ] **Step 3: Add DEFINE case to post-tool-navigator.sh**

In the `case "$PHASE"` block (line 39), add before the `discuss)` case:

```bash
    define)
        MSG="You are in DEFINE phase. Next steps: define the problem statement, outcomes, and success metrics. When definition is complete, use /discuss to proceed to discussion and planning."
        ;;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -5`
Expected: PASS — all tests pass.

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/post-tool-navigator.sh tests/run-tests.sh
git commit -m "feat: post-tool-navigator shows DEFINE phase guidance"
```

---

### Task 5: Add DEFINE phase to statusline

**Files:**
- Modify: `statusline/statusline.sh:101-109`
- Test: `tests/run-tests.sh`

- [ ] **Step 1: Write the failing test — statusline shows DEFINE in blue**

Add after the existing `no skill shown when skill field is empty` test (around line 625 of `tests/run-tests.sh`):

```bash
# Test: shows DEFINE phase in statusline
SL_DEFINE_DIR=$(mktemp -d)
mkdir -p "$SL_DEFINE_DIR/.claude/state" "$SL_DEFINE_DIR/.claude/hooks"
echo '{"phase": "define", "message_shown": false}' > "$SL_DEFINE_DIR/.claude/state/phase.json"
# Create a workflow-gate.sh so Workflow Manager is detected
touch "$SL_DEFINE_DIR/.claude/hooks/workflow-gate.sh"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_DEFINE_DIR\"}")
assert_contains "$OUTPUT" "DEFINE" "statusline shows DEFINE phase label"
assert_contains "$OUTPUT" '\[34m' "statusline uses blue (\\033[34m) for DEFINE phase"
rm -rf "$SL_DEFINE_DIR"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | grep "DEFINE" | tail -5`
Expected: FAIL — statusline tests fail because no DEFINE branch exists.

- [ ] **Step 3: Add DEFINE phase to statusline.sh**

In `statusline/statusline.sh`, add a new `elif` before the `discuss` check (after line 101):

```bash
    if [ "$WM_PHASE" = "off" ]; then
      OUTPUT+=" ${DIM}[OFF]${RESET}"
    elif [ "$WM_PHASE" = "define" ]; then
      OUTPUT+=" ${BLUE}[DEFINE]${RESET}"
    elif [ "$WM_PHASE" = "discuss" ]; then
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -5`
Expected: PASS — all tests pass.

- [ ] **Step 5: Commit**

```bash
git add statusline/statusline.sh tests/run-tests.sh
git commit -m "feat: statusline shows DEFINE phase in blue"
```

---

### Task 6: Create /define command

**Files:**
- Create: `.claude/commands/define.md`

- [ ] **Step 1: Create the define command**

Create `.claude/commands/define.md`:

```markdown
Transition the workflow to DEFINE phase. Run this command:

\`\`\`bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_phase "define" && cat > "$STATE_DIR/active-skill.json" <<'SK'
{"skill": "", "updated": "phase-transition"}
SK
echo "Phase set to DEFINE — code edits are blocked. Define the problem and outcomes first."
\`\`\`

Then confirm to the user that the phase has changed and code edits are blocked.

**You are now in DEFINE phase.** Guide the user through these sections, one at a time. Ask questions conversationally — one question per message, prefer multiple choice when possible.

## Section 1 — Problem Discovery

Understand the problem before trying to solve it:
- Who is affected by this problem?
- What pain or friction are they experiencing?
- What's the current state or workaround?
- Why does this matter now?

## Section 2 — Problem Statement

Synthesize the discovery into a crisp problem statement. Use a "How Might We" framing if appropriate.
Present it to the user: "Is this the right problem?"
Iterate until the user confirms.

## Section 3 — Outcome Definition

Define what success looks like — observable, measurable criteria that can be verified.

For each outcome, capture:
- **Description** — what should be true when we're done
- **Type** — functional, performance, security, reliability, usability, maintainability, compatibility
- **Verification method** — how to demonstrate it (not just prove code exists)
- **Acceptance criteria** — the specific evidence that confirms it

Present diverse examples appropriate to the project type. A CLI tool needs different examples than a web API, a library, or an infrastructure script. Outcomes must be verifiable — expressible as a test that can pass or fail. Verification means exercising the behavior end-to-end, not just proving code exists.

**Success metrics** — quantifiable measures of whether the outcomes collectively solve the problem:
- What to measure, what the target is, how to measure it
- Some metrics are immediately verifiable; others are long-term (flag as "to monitor post-release")
- Not every project needs formal metrics — don't force them when they'd be artificial

## Section 4 — Boundaries

- What's explicitly **in scope**?
- What's explicitly **out of scope** (anti-goals)?
- Any constraints or dependencies?

## Output

After all sections are complete, save the definition to `docs/plans/define.json`. The file must capture:
- The problem statement and who is affected
- All defined outcomes with their type, verification method, and acceptance criteria
- Success metrics with targets and how to measure them (if applicable)
- Linkage between outcomes and the metrics they support
- Scope boundaries (in-scope, out-of-scope, constraints)
- Creation date

Confirm to the user: "Problem and outcomes saved to `docs/plans/define.json`. Use `/discuss` to proceed to discussion and planning."

**Important:** When transitioning, update the active skill tracker:
\`\`\`bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && echo '{"skill": "SKILL_NAME", "updated": "now"}' > "$WF_DIR/.claude/state/active-skill.json"
\`\`\`
```

Note: The escaped backticks (`\`\`\``) above are just to prevent nesting issues in this plan. In the actual file, use normal triple backticks.

- [ ] **Step 2: Verify the file was created correctly**

Run: `head -5 .claude/commands/define.md && echo "---" && wc -l .claude/commands/define.md`
Expected: File exists, starts with "Transition the workflow to DEFINE phase", approximately 70-80 lines.

- [ ] **Step 3: Commit**

```bash
git add .claude/commands/define.md
git commit -m "feat: add /define command for problem and outcome definition"
```

---

### Task 7: Update /override command for DEFINE phase

**Files:**
- Modify: `.claude/commands/override.md`

- [ ] **Step 1: Update override.md to include 'define'**

In `.claude/commands/override.md`, add `define` to all three locations:

Line 3 — valid phases list:
```
Valid phases: `off`, `define`, `discuss`, `implement`, `review`
```

Lines 12-17 — usage block:
```
Valid phases: off, define, discuss, implement, review

  off       — Disable workflow enforcement (normal Claude Code operation)
  define    — Problem and outcome definition (code edits blocked)
  discuss   — Brainstorming and planning (code edits blocked)
  implement — Code implementation (all edits allowed)
  review    — Review pipeline (all edits allowed)
```

- [ ] **Step 2: Verify the changes**

Run: `grep -c "define" .claude/commands/override.md`
Expected: At least 3 occurrences.

- [ ] **Step 3: Commit**

```bash
git add .claude/commands/override.md
git commit -m "feat: add 'define' to /override valid phases"
```

---

### Task 8: Update /complete command for outcome validation

**Files:**
- Modify: `.claude/commands/complete.md:74-104`

- [ ] **Step 1: Add outcome validation to Step 3 of the completion pipeline**

After the existing plan validation section (after line 104, "If no plan file exists: report..."), add:

```markdown
### Step 3b: Outcome Validation

If `docs/plans/define.json` exists, validate that the defined outcomes were achieved:

1. Read `docs/plans/define.json`
2. Extract every outcome and success metric
3. For each outcome, require **behavioral evidence** — demonstrate the behavior, don't just grep for code:
   - Functional outcome? → exercise it and show the result
   - Performance outcome? → measure under realistic conditions
   - Security outcome? → attempt the attack vector, show it's blocked
   - Reliability outcome? → simulate the failure, observe recovery
   - Usability outcome? → exercise the user path
4. For each success metric, check coverage:
   - Immediately verifiable → validate with evidence
   - Long-term metric (cannot verify pre-release) → flag as "TO MONITOR"
   - No outcomes linked to this metric → flag as "WARNING: no outcomes verify this metric"
5. Present the outcome checklist:
   ```
   Outcome Validation:
     [x] <outcome description> — evidence: <what was observed>
     [ ] <outcome description> — FAILED: <what went wrong>

   Success Metrics:
     [x] <metric> <target> — linked to: <outcome(s)> (passed)
     [!] <metric> <target> — TO MONITOR: cannot verify pre-release
     [!] <metric> <target> — WARNING: no outcomes verify this metric
   ```
6. If any outcome fails:
   - Report what failed and ask: "Fix now and re-commit, or proceed anyway?"
   - If fix → make fixes, create new commit, re-validate failed outcomes
   - If proceed → note the gaps in the handover observation

If `docs/plans/define.json` does not exist, report "No outcome definition found — skipping outcome validation" and continue.
```

- [ ] **Step 2: Verify the changes**

Run: `grep -c "define.json" .claude/commands/complete.md`
Expected: At least 2 occurrences (the check and the skip message).

- [ ] **Step 3: Commit**

```bash
git add .claude/commands/complete.md
git commit -m "feat: /complete validates outcomes from define.json"
```

---

### Task 9: Update install.sh and uninstall.sh

**Files:**
- Modify: `install.sh:89-93`
- Modify: `uninstall.sh:19-23`

- [ ] **Step 1: Add define.md to install.sh**

After line 93 (`cp "$SCRIPT_DIR/.claude/commands/override.md" ...`), add:

```bash
cp "$SCRIPT_DIR/.claude/commands/define.md" "$TARGET/.claude/commands/"
```

- [ ] **Step 2: Add define.md to uninstall.sh**

After line 23 (`rm -f "$TARGET/.claude/commands/override.md"`), add:

```bash
rm -f "$TARGET/.claude/commands/define.md"
```

- [ ] **Step 3: Write a failing test for install**

Add after the existing `install creates override.md` test (around line 405 of `tests/run-tests.sh`):

```bash
assert_file_exists "$INSTALL_TARGET/.claude/commands/define.md" "install creates define.md"
```

And add after the existing `uninstall removes override.md` test (around line 480). Note: the uninstall test block uses `$UNINSTALL_TARGET`:

```bash
assert_file_not_exists "$UNINSTALL_TARGET/.claude/commands/define.md" "uninstall removes define.md"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -5`
Expected: PASS — all tests pass.

- [ ] **Step 5: Commit**

```bash
git add install.sh uninstall.sh tests/run-tests.sh
git commit -m "feat: install/uninstall handle define.md command"
```

---

### Task 10: Add GPL v3 LICENSE file

**Files:**
- Create: `LICENSE`

- [ ] **Step 1: Create the GPL v3 LICENSE file**

Download or create the standard GPL v3 license text at the repo root. Use the full text from https://www.gnu.org/licenses/gpl-3.0.txt with the copyright notice:

```
Copyright (C) 2026 azevedo-home-lab

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
```

- [ ] **Step 2: Verify**

Run: `head -5 LICENSE && echo "---" && wc -l LICENSE`
Expected: File exists, contains GPL text, approximately 674 lines.

- [ ] **Step 3: Commit**

```bash
git add LICENSE
git commit -m "feat: add GPL v3 license"
```

---

### Task 11: Add GPL v3 license headers to all source files

**Files:**
- Modify: All `.sh` files and template files

The header to add after the shebang line (for `.sh` files) or at the top (for `.md.template` files):

For shell scripts (after `#!/bin/bash`):
```bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.
```

For markdown templates (at the top, as HTML comment):
```markdown
<!-- Copyright (C) 2026 azevedo-home-lab | SPDX-License-Identifier: GPL-3.0-only -->
```

- [ ] **Step 1: List all files that need headers**

Shell scripts:
- `install.sh`
- `uninstall.sh`
- `.claude/hooks/workflow-state.sh`
- `.claude/hooks/workflow-gate.sh`
- `.claude/hooks/bash-write-guard.sh`
- `.claude/hooks/post-tool-navigator.sh`
- `statusline/statusline.sh`
- `tests/run-tests.sh`
- `tools/iterm-launcher/install.sh`
- `tools/iterm-launcher/launch-claude-iterm.sh`
- `tools/yubikey-setup/install.sh`
- `tools/yubikey-setup/git-ssh-auth.sh`
- `tools/yubikey-setup/git-ssh-sign.sh`
- `tools/yubikey-setup/git-yubikey`
- `tools/yubikey-setup/ssh-askpass-wrapper.sh`

Templates:
- `claude.md.template`
- `docs/reference/SECURITY.md.template`

- [ ] **Step 2: Add headers to each file**

For each `.sh` file: insert the 5-line header block after the `#!/bin/bash` line (before any existing comments).

For `tools/yubikey-setup/git-yubikey`: check if it has a shebang — it does, add after it.

For template files: add the HTML comment at the very first line.

- [ ] **Step 3: Run tests to verify nothing broke**

Run: `bash tests/run-tests.sh 2>&1 | tail -5`
Expected: PASS — all tests pass (headers don't affect behavior).

- [ ] **Step 4: Commit**

```bash
git add install.sh uninstall.sh .claude/hooks/*.sh statusline/statusline.sh tests/run-tests.sh tools/iterm-launcher/*.sh tools/yubikey-setup/*.sh tools/yubikey-setup/git-yubikey claude.md.template docs/reference/SECURITY.md.template
git commit -m "chore: add GPL v3 license headers to all source files"
```

---

### Task 12: Create SECURITY.md

**Files:**
- Create: `SECURITY.md`

- [ ] **Step 1: Create SECURITY.md at repo root**

```markdown
# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Claude Code Workflows, please report it responsibly:

1. **Do NOT open a public issue**
2. Use [GitHub Security Advisories](https://github.com/azevedo-home-lab/claude-code-workflows/security/advisories/new) to report privately
3. Include: description of the vulnerability, steps to reproduce, and potential impact

You should receive a response within 7 days.

## Scope

Claude Code Workflows is a development workflow tool that runs locally. Security issues in scope include:

- **Hook bypass** — ways to circumvent workflow phase enforcement
- **Code injection** — exploiting hook scripts to execute unintended commands
- **Information disclosure** — exposing secrets or credentials through hook output
- **State manipulation** — tampering with workflow state to skip review gates

Out of scope:
- Vulnerabilities in Claude Code itself (report to [Anthropic](https://github.com/anthropics/claude-code/security))
- Vulnerabilities in Superpowers (report to [obra/superpowers](https://github.com/obra/superpowers/security))
- Social engineering or prompt injection (behavioral, not code-level)

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest on `main` | Yes |
| Previous releases | Best effort |
```

- [ ] **Step 2: Commit**

```bash
git add SECURITY.md
git commit -m "docs: add security policy"
```

---

### Task 13: Create CONTRIBUTING.md

**Files:**
- Create: `CONTRIBUTING.md`

- [ ] **Step 1: Create CONTRIBUTING.md at repo root**

```markdown
# Contributing to Claude Code Workflows

Thank you for your interest in contributing.

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/azevedo-home-lab/claude-code-workflows.git
   cd claude-code-workflows
   ```

2. Prerequisites:
   - Bash 4+
   - Python 3 (for JSON manipulation in hooks)
   - Git
   - [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) (for testing the full workflow)

3. Run the test suite:
   ```bash
   bash tests/run-tests.sh
   ```

## Making Changes

1. Fork the repository and create a feature branch
2. Make your changes
3. Ensure all tests pass: `bash tests/run-tests.sh`
4. Add tests for new functionality
5. Add GPL v3 license headers to new source files
6. Submit a pull request

## Code Style

- **Shell scripts**: Use `set -euo pipefail`, quote variables, use `[[ ]]` for tests when possible
- **Markdown**: ATX-style headers (`##`), fenced code blocks with language tags
- **JSON**: 2-space indentation, trailing newline
- **Commits**: Conventional commits (`feat:`, `fix:`, `docs:`, `chore:`)

## Testing

Tests live in `tests/run-tests.sh`. The test suite:
- Creates temporary project directories
- Installs hooks into them
- Tests phase transitions, edit blocking, whitelisting, and statusline output
- Cleans up after itself

When adding new features, add corresponding test cases following the existing patterns.

## Pull Request Process

1. Ensure the test suite passes
2. Update documentation if behavior changes
3. One feature per PR — keep changes focused
4. Describe what and why in the PR description

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating, you agree to uphold this code.

## License

By contributing, you agree that your contributions will be licensed under the GPL v3 license.
```

- [ ] **Step 2: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "docs: add contributing guidelines"
```

---

### Task 14: Create CODE_OF_CONDUCT.md

**Files:**
- Create: `CODE_OF_CONDUCT.md`

- [ ] **Step 1: Create CODE_OF_CONDUCT.md**

Use the standard Contributor Covenant v2.1 text. The full text is available at https://www.contributor-covenant.org/version/2/1/code_of_conduct/

Set the contact method to: GitHub Security Advisories (same as SECURITY.md) or open an issue.

- [ ] **Step 2: Commit**

```bash
git add CODE_OF_CONDUCT.md
git commit -m "docs: add Contributor Covenant code of conduct"
```

---

### Task 15: Create GitHub issue and PR templates

**Files:**
- Create: `.github/ISSUE_TEMPLATE/bug_report.md`
- Create: `.github/ISSUE_TEMPLATE/feature_request.md`
- Create: `.github/PULL_REQUEST_TEMPLATE.md`

- [ ] **Step 1: Create directories**

```bash
mkdir -p .github/ISSUE_TEMPLATE
```

- [ ] **Step 2: Create bug report template**

`.github/ISSUE_TEMPLATE/bug_report.md`:

```markdown
---
name: Bug Report
about: Report a bug in Claude Code Workflows
labels: bug
---

## Description

A clear description of the bug.

## Steps to Reproduce

1.
2.
3.

## Expected Behavior



## Actual Behavior



## Environment

- OS:
- Shell:
- Claude Code version:
- Superpowers version (if applicable):
```

- [ ] **Step 3: Create feature request template**

`.github/ISSUE_TEMPLATE/feature_request.md`:

```markdown
---
name: Feature Request
about: Suggest a new feature or improvement
labels: enhancement
---

## Problem

What problem does this solve?

## Proposed Solution

How should it work?

## Alternatives Considered

What other approaches did you consider?
```

- [ ] **Step 4: Create PR template**

`.github/PULL_REQUEST_TEMPLATE.md`:

```markdown
## Summary



## Related Issue

Closes #

## Test Plan

- [ ] All existing tests pass (`bash tests/run-tests.sh`)
- [ ] New tests added for new functionality
- [ ] Documentation updated (if behavior changed)
- [ ] License headers added to new source files
```

- [ ] **Step 5: Commit**

```bash
git add .github/
git commit -m "docs: add GitHub issue and PR templates"
```

---

### Task 16: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add GPL v3 license badge after the title**

After line 1 (`# Claude Code Workflows`), add:

```markdown
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
```

- [ ] **Step 2: Update "Four-phase workflow" to "Five-phase workflow"**

Line 22, change:
```
Four-phase workflow that prevents cowboy coding.
```
to:
```
Five-phase workflow that prevents cowboy coding. Start by defining the problem and outcomes, then plan, implement, and review.
```

- [ ] **Step 3: Update the phase diagram**

Replace the phase diagram (lines 24-30) with:

```
         ┌──(/define)──> DEFINE ──(/discuss)──┐
OFF ─────┤                                    ├──> DISCUSS ──(/approve)──> IMPLEMENT ──(/review)──> REVIEW ──(/complete)──> OFF
         └──(/discuss)────────────────────────┘         │                      │
                                                        └───── (/discuss) ─────┘

                                    /override <phase>  — jump to any phase directly
```

Note: DEFINE is optional — users can go directly from OFF to DISCUSS via `/discuss`, or start with `/define` for problem + outcome definition first.

- [ ] **Step 4: Update the phase table**

Add DEFINE row to the table (after line 33):

```markdown
| **DEFINE** | Blocked (except specs/plans) | Blocked (except specs/plans) | Define problem, outcomes, success metrics |
```

- [ ] **Step 5: Update commands list**

Add `/define` as the first command (before `/discuss`):

```markdown
- `/define` — define the problem and outcomes (recommended first step, optional)
```

Update `/override`:
```markdown
- `/override <phase>` — jump directly to any phase (off/define/discuss/implement/review)
```

- [ ] **Step 6: Update the Contributing section**

Replace the existing Contributing section (line 176-177) with:

```markdown
## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, code style, and PR process.
```

- [ ] **Step 7: Add License section**

Add at the end of the file:

```markdown
## License

This project is licensed under the GNU General Public License v3.0 — see [LICENSE](LICENSE) for details.
```

- [ ] **Step 8: Commit**

```bash
git add README.md
git commit -m "docs: update README for DEFINE phase, license, and contributing"
```

---

### Task 17: Update architecture and commands docs

**Files:**
- Modify: `docs/reference/architecture.md`
- Modify: `docs/quick-reference/commands.md`

- [ ] **Step 1: Update architecture.md phase diagram**

Replace the phase model (lines 41-49) with:

```
         ┌──(/define)──> DEFINE ──(/discuss)──┐
OFF ─────┤                                    ├──> DISCUSS ──(/approve)──> IMPLEMENT ──(/review)──> REVIEW ──(/complete)──> OFF
         └──(/discuss)────────────────────────┘         │                      │
                                                        └───── (/discuss) ─────┘

DEFINE:     Write/Edit BLOCKED, Bash writes BLOCKED, Read/Grep ALLOWED (optional phase)
DISCUSS:    Write/Edit BLOCKED, Bash writes BLOCKED, Read/Grep ALLOWED
IMPLEMENT:  Everything ALLOWED
REVIEW:     Everything ALLOWED (fixes from review)
```

- [ ] **Step 2: Update architecture.md component responsibilities**

In the "Workflow Manager — Hard Gates" section (line 53), add:
```
- `workflow-gate.sh` — blocks Write/Edit/MultiEdit in DEFINE and DISCUSS phases
- `bash-write-guard.sh` — blocks Bash write operations in DEFINE and DISCUSS phases
```

Add `/define` to the commands listed in the file organization tree.

- [ ] **Step 3: Update architecture.md workflow section**

Add DEFINE phase block before the DISCUSS phase (line 78):

```
DEFINE PHASE (edits blocked, optional):
  /define → guided problem + outcome definition
  Define problem statement, outcomes, success metrics
  Save to docs/plans/define.json

TRANSITION: /discuss → proceed to discussion
```

- [ ] **Step 4: Update architecture.md system overview diagram**

Update the User box (line 10) to include `/define`:
```
│                  /define  /approve  /discuss                   │
```

- [ ] **Step 5: Update commands.md**

Add a "Workflow Manager" section at the top of `docs/quick-reference/commands.md`:

```markdown
## Workflow Manager

| Command | Phase | What It Does |
|---------|-------|-------------|
| `/define` | DEFINE | Guide problem + outcome definition |
| `/discuss` | DISCUSS | Start brainstorming and planning |
| `/approve` | IMPLEMENT | Unlock code edits |
| `/review` | REVIEW | Run multi-agent review pipeline |
| `/complete` | OFF | Verified completion with outcome validation |
| `/override <phase>` | Any | Jump to any phase |
```

Update the Quick Sequence:

```
/define                          → Define problem + outcomes (optional)
/discuss                         → Enter discussion
/superpowers:brainstorm          → Clarify requirements
/superpowers:write-plan          → Generate plan
Review and approve
/superpowers:execute-plan        → Implement with checkpoints
/superpowers:verification-before-completion → Verify
/complete                        → Validate outcomes + commit
```

- [ ] **Step 6: Commit**

```bash
git add docs/reference/architecture.md docs/quick-reference/commands.md
git commit -m "docs: update architecture and commands reference for DEFINE phase"
```

---

### Task 18: Final validation — run all tests

**Files:**
- Test: `tests/run-tests.sh`

- [ ] **Step 1: Run the full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass, 0 failures. The output should show all new DEFINE-related tests passing.

- [ ] **Step 2: Verify all new files exist**

Run: `ls -la LICENSE SECURITY.md CONTRIBUTING.md CODE_OF_CONDUCT.md .github/ISSUE_TEMPLATE/bug_report.md .github/ISSUE_TEMPLATE/feature_request.md .github/PULL_REQUEST_TEMPLATE.md .claude/commands/define.md`
Expected: All files exist.

- [ ] **Step 3: Verify license headers**

Run: `head -7 install.sh && echo "---" && head -7 .claude/hooks/workflow-gate.sh && echo "---" && head -1 claude.md.template`
Expected: All files show the GPL v3 header.

- [ ] **Step 4: Verify no private information**

Run: `grep -rE '(api.?key|password|token|credential|private.?key)' --include='*.sh' --include='*.md' --include='*.json' -l . | grep -v .git | grep -v node_modules || echo "No matches - clean"`
Expected: No matches (or only template references).

- [ ] **Step 5: Verify git status is clean**

Run: `git status`
Expected: Clean working tree, all changes committed.
