# Autonomy Off Redesign, /complete Push, /wf: Aliases — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make autonomy `off` usable (supervised not read-only), ensure `/complete` pushes, and add `/wf:` command aliases with observation management commands.

**Architecture:** Remove the autonomy `off` write-block from both hook guards so `off` follows phase rules like `ask`. Add step-by-step instructions to command files. Split `/complete` push into explicit sub-step. Create symlinks for `/wf:` aliases and new observation commands.

**Tech Stack:** Bash (hooks, tests), Markdown (commands, docs), symlinks

---

### Task 1: Remove autonomy `off` block from workflow-gate.sh

**Files:**
- Modify: `plugin/scripts/workflow-gate.sh:32-38` (remove block), `:42` (update comment)

- [ ] **Step 1: Write the failing test — off allows Write in IMPLEMENT**

In `tests/run-tests.sh`, find the test at line 620-625 ("Level 1 blocks Write in IMPLEMENT phase"). Change it to expect the opposite:

```bash
# Test: Level 1 allows Write in IMPLEMENT phase (same as ask — supervised, not read-only)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level off
OUTPUT=$(run_gate "/project/src/main.py")
assert_not_contains "$OUTPUT" "deny" "Level 1 allows Write in IMPLEMENT (supervised, not read-only)"
```

Also delete the "Level 1 denial message mentions /autonomy" test at lines 627-632 (no longer relevant — no denial).

- [ ] **Step 2: Write the failing test — off blocks Write in DISCUSS (phase gate preserved)**

Add after the existing Level tests (after line 667):

```bash
# Test: Level 1 blocks Write in DISCUSS (phase gate preserved, same as ask)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level off
OUTPUT=$(run_gate "/project/src/main.py")
assert_contains "$OUTPUT" "deny" "Level 1 blocks Write in DISCUSS (phase gate, same as ask)"
```

- [ ] **Step 3: Run tests to verify new tests fail**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: The "Level 1 allows Write in IMPLEMENT" test FAILS (because the block still exists).

- [ ] **Step 4: Remove the autonomy off block from workflow-gate.sh**

In `plugin/scripts/workflow-gate.sh`, remove lines 32-38:

```bash
# Autonomy off: block ALL writes regardless of phase
AUTONOMY_LEVEL=$(get_autonomy_level)
if [ "$AUTONOMY_LEVEL" = "off" ]; then
    cat > /dev/null  # consume stdin
    emit_deny "BLOCKED: ▶ Supervised (off) — read-only mode. No file writes allowed. Run /autonomy ask to enable writes."
    exit 0
fi
```

Also update the comment on what is now the early-exit line for implement/review (was line 42, now ~line 35 after deletion). Change:

```bash
# Allow everything in implement and review phases (ask/auto only reach here)
```

To:

```bash
# Allow everything in implement and review phases
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: ALL PASS including the new tests.

- [ ] **Step 6: Commit**

```bash
git add plugin/scripts/workflow-gate.sh tests/run-tests.sh
git commit -m "feat: autonomy off allows writes in implement/review (same as ask)"
```

---

### Task 2: Remove autonomy `off` block from bash-write-guard.sh

**Files:**
- Modify: `plugin/scripts/bash-write-guard.sh:104-115` (remove block), `:137` (update comment)
- Modify: `tests/run-tests.sh` (update 4 tests)

- [ ] **Step 1: Update tests for new off behavior**

In `tests/run-tests.sh`:

**a)** Lines 824-829 — Change "Level 1 blocks Bash write in IMPLEMENT phase":
```bash
# Test: Level 1 allows Bash write in IMPLEMENT phase (same as ask)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level off
OUTPUT=$(run_bash_guard 'echo data > output.txt')
assert_not_contains "$OUTPUT" "deny" "Level 1 allows Bash write in IMPLEMENT (supervised, not read-only)"
```

**b)** Lines 831-832 — Delete "Level 1 denial message mentions /autonomy" test.

**c)** Lines 862-867 — Change "Level 1 rejects chained workflow-state command (bypass attempt)". Move to DISCUSS phase so chain detection still fires:
```bash
# Test: Level 1 rejects chained workflow-state command in DISCUSS (bypass attempt)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level off
OUTPUT=$(run_bash_guard 'source .claude/hooks/workflow-state.sh && echo pwned > evil.txt')
assert_contains "$OUTPUT" "deny" "Level 1 blocks chained workflow-state bypass in DISCUSS"
```

**d)** Lines 1027-1031 — Change "python3 write blocked at Level 1 in IMPLEMENT":
```bash
# Level 1 in IMPLEMENT now allows python writes (same as ask)
jq '.autonomy_level = "off"' "$TEST_DIR/.claude/state/workflow.json" > "$TEST_DIR/.claude/state/workflow.json.tmp" && mv "$TEST_DIR/.claude/state/workflow.json.tmp" "$TEST_DIR/.claude/state/workflow.json"
RESULT=$(printf '{"tool_input":{"command":"python3 -c \\\"\\nwith open('"'"'f'"'"','"'"'w'"'"') as fh:\\n  fh.write('"'"'x'"'"')\\n\\\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_eq "" "$RESULT" "bash-guard: python3 write allowed at Level 1 in IMPLEMENT"
```

**e)** Add new test — "Level 1 blocks Bash write in DISCUSS (phase gate preserved)":
```bash
# Test: Level 1 blocks Bash write in DISCUSS (phase gate preserved, same as ask)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level off
OUTPUT=$(run_bash_guard 'echo data > output.txt')
assert_contains "$OUTPUT" "deny" "Level 1 blocks Bash write in DISCUSS (phase gate, same as ask)"
```

- [ ] **Step 2: Run tests to verify new assertions fail**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: "Level 1 allows Bash write in IMPLEMENT" FAILS.

- [ ] **Step 3: Remove the autonomy off block from bash-write-guard.sh**

In `plugin/scripts/bash-write-guard.sh`, remove lines 103-115:

```bash
# ---------------------------------------------------------------------------
# Autonomy "off": block ALL Bash write commands regardless of phase
# ---------------------------------------------------------------------------

AUTONOMY_LEVEL=$(get_autonomy_level)
if [ "$AUTONOMY_LEVEL" = "off" ]; then
    if echo "$CLEAN_CMD" | grep -qE "$WRITE_PATTERN" || [ "$PYTHON_WRITE" = "true" ]; then
        emit_deny "BLOCKED: ▶ Supervised (off) — read-only mode. No Bash write operations allowed. Run /autonomy ask to enable writes."
        exit 0
    fi
    # Read-only Bash commands allowed at autonomy off
    exit 0
fi
```

Also update the comment that was at line 136 (now ~line 123 after deletion):

```bash
# Allow everything in implement and review phases (ask/auto only reach here)
```

To:

```bash
# Allow everything in implement and review phases
```

- [ ] **Step 4: Run tests to verify all pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add plugin/scripts/bash-write-guard.sh tests/run-tests.sh
git commit -m "feat: autonomy off follows phase rules for bash writes (same as ask)"
```

---

### Task 3: Update autonomy.md and command files for off behavior

**Files:**
- Modify: `plugin/commands/autonomy.md`
- Modify: `plugin/commands/define.md`
- Modify: `plugin/commands/discuss.md`
- Modify: `plugin/commands/implement.md`
- Modify: `plugin/commands/review.md`
- Modify: `plugin/commands/complete.md`

- [ ] **Step 1: Update autonomy.md — remove EnterPlanMode**

Change the `off` response from:
```markdown
- **off**: Call `EnterPlanMode`. Say: "▶ **Supervised** — read-only mode."
```

To:
```markdown
- **off**: Say: "▶ **Supervised** — step-by-step mode. I'll work within phase rules and pause after each plan step for your review."
```

- [ ] **Step 2: Update implement.md — add off behavior**

Find the existing autonomy-aware section:
```markdown
**Autonomy-aware behavior:**
- **auto (▶▶▶):** Use `superpowers:subagent-driven-development` ...
- **off/ask:** Ask the user which execution approach ...
```

Replace with three-level:
```markdown
**Autonomy-aware behavior:**
- **auto (▶▶▶):** Use `superpowers:subagent-driven-development` (recommended execution mode) without asking. Make operational decisions (execution approach, model selection, task ordering) autonomously. Only stop for genuine blockers.
- **ask (▶▶):** Ask the user which execution approach they prefer if multiple options exist. Work freely within the phase, committing after each task.
- **off (▶):** Work within phase rules. After completing each plan step, present the change (files modified, key diff summary), and wait for the user's explicit approval before proceeding to the next step. Never batch multiple steps. Never auto-commit — ask before each commit.
```

- [ ] **Step 3: Update define.md — add off behavior**

Find:
```markdown
**Auto-transition:** If autonomy is auto, invoke `/discuss` now. Do not wait for the user.
```

Add before that line:
```markdown
**Autonomy-aware behavior:**
- **auto (▶▶▶):** Auto-transition to `/discuss` after problem is defined.
- **ask (▶▶):** Present the decision record and wait for the user to run `/discuss`.
- **off (▶):** After each problem discovery exchange, summarize what was learned and wait for the user's direction before proceeding. Present the decision record and wait for explicit approval before any transition.

```

- [ ] **Step 4: Update discuss.md — add off behavior**

Find the existing autonomy section near the end:
```markdown
**Autonomy-aware behavior:**
- **off/ask:** When the plan is ready and the user approves, they will run `/implement` to proceed.
```

Replace with:
```markdown
**Autonomy-aware behavior:**
- **off (▶):** After each design decision or research finding, present the result and wait for explicit user approval before proceeding. Never batch diverge/converge phases. Present the plan section by section, waiting for approval after each.
- **ask (▶▶):** When the plan is ready and the user approves, they will run `/implement` to proceed.
```

- [ ] **Step 5: Update review.md — add off behavior**

Find the auto-transition section at the end. Add `off` behavior before it:
```markdown
**Autonomy-aware behavior:**
- **off (▶):** After each review agent returns, present its findings individually and wait for user review before dispatching the next agent. Do not batch all 5 agents in parallel — dispatch one at a time, presenting results between each.
- **ask (▶▶):** Dispatch all 5 agents in parallel, present consolidated findings, wait for user response.
```

- [ ] **Step 6: Update complete.md — add off behavior**

Find the existing autonomy section:
```markdown
**Autonomy-aware behavior:**
- **auto (▶▶▶):** Make operational decisions autonomously...
- **off/ask:** Ask the user at each decision point...
```

Replace with:
```markdown
**Autonomy-aware behavior:**
- **auto (▶▶▶):** Make operational decisions autonomously: auto-commit, auto-update docs (yes), auto-select recommended options. Only stop for git push (always requires confirmation) and validation failures that need user judgment.
- **ask (▶▶):** Ask the user at each decision point (doc updates, commit, push, tech debt actions).
- **off (▶):** After each pipeline step (validation, docs, commit, push, tech debt, handover), present the result and wait for explicit approval before proceeding to the next step. Never batch steps.
```

- [ ] **Step 7: Run tests to verify nothing broke**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: ALL PASS (command file changes don't affect hook tests).

- [ ] **Step 8: Commit**

```bash
git add plugin/commands/autonomy.md plugin/commands/define.md plugin/commands/discuss.md plugin/commands/implement.md plugin/commands/review.md plugin/commands/complete.md
git commit -m "feat: autonomy off = step-by-step supervised mode in all phase commands"
```

---

### Task 4: Split /complete push into explicit sub-step

**Files:**
- Modify: `plugin/commands/complete.md`

- [ ] **Step 1: Add explicit push sub-step after Step 5 commit section**

In `plugin/commands/complete.md`, after Step 5's commit instructions (after the commit message format and before the Step 5 Review Gate), add a push sub-section:

```markdown
#### Push to Remote

After committing, push to the remote:

1. Check if there are commits to push:
\`\`\`bash
AHEAD=$(git rev-list --count @{u}..HEAD 2>/dev/null || git rev-list --count origin/$(git symbolic-ref --short HEAD)..HEAD 2>/dev/null || echo "unknown")
echo "Commits ahead of remote: $AHEAD"
\`\`\`

2. If ahead > 0, ask: "Push to remote? (yes / no)"
   - At **all autonomy levels**: always ask before pushing. Push is never automatic.
   - If **yes**: warn about YubiKey, then push:
     \`\`\`
     ========== YUBIKEY: TOUCH NOW FOR GIT PUSH ==========
     \`\`\`
     \`\`\`bash
     git push origin HEAD
     \`\`\`
   - If **no**: note "Push deferred — run `git push` manually when ready."

3. If no upstream or unknown: skip push, note "No remote tracking branch — push skipped."

4. After push (or skip), mark informational milestone:
\`\`\`bash
.claude/hooks/workflow-cmd.sh set_completion_field "pushed" "true"
\`\`\`
This is NOT an exit gate — just tracks whether push happened.
```

- [ ] **Step 2: Verify the existing push instructions in Step 5 are replaced**

Read the current Step 5 to confirm the old push instruction (item 5 in the numbered list) is replaced by the new sub-section. Remove the old "Ask: Push to remote?" line if it exists as a numbered item.

- [ ] **Step 3: Run tests to verify nothing broke**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: ALL PASS.

- [ ] **Step 4: Commit**

```bash
git add plugin/commands/complete.md
git commit -m "feat: explicit push sub-step in /complete with confirmation at all levels"
```

---

### Task 5: Verify git commit works in DISCUSS phase (#4194.1)

**Files:**
- Modify: `tests/run-tests.sh` (add verification test if needed)

- [ ] **Step 1: Run manual verification**

```bash
# Set up test environment
cd $(mktemp -d)
git init && git commit --allow-empty -m "init"
mkdir -p .claude/state .claude/hooks
# Copy workflow scripts
cp /Users/pedroazevedo/Documents/GDrive/Projects/ClaudeWorkflows/plugin/scripts/workflow-state.sh .claude/hooks/
cp /Users/pedroazevedo/Documents/GDrive/Projects/ClaudeWorkflows/plugin/scripts/bash-write-guard.sh .claude/hooks/
# Set up DISCUSS phase with ask autonomy
source .claude/hooks/workflow-state.sh && WF_SKIP_AUTH=1 set_phase "discuss" && set_autonomy_level ask
# Test git add
echo '{"tool_input":{"command":"git add README.md"}}' | CLAUDE_PROJECT_DIR="$(pwd)" bash .claude/hooks/bash-write-guard.sh 2>/dev/null
echo "git add result: $?"
# Test git commit
echo '{"tool_input":{"command":"git commit -m \"docs: test spec\""}}' | CLAUDE_PROJECT_DIR="$(pwd)" bash .claude/hooks/bash-write-guard.sh 2>/dev/null
echo "git commit result: $?"
```

Expected: Both commands produce empty output (allowed, no deny).

- [ ] **Step 2: Assess result**

If both pass → #4194.1 is working-as-intended. The git commit allowlist and git add passthrough work correctly. Note this in the decision record.

If either fails → investigate and fix. Add the fix to bash-write-guard.sh and a regression test.

- [ ] **Step 3: Commit if any changes made**

```bash
# Only if changes were needed
git add tests/run-tests.sh
git commit -m "test: verify git commit/add allowed in DISCUSS phase"
```

---

### Task 6: Create /wf: alias symlinks

**Files:**
- Create: `plugin/commands/wf:define.md` (symlink)
- Create: `plugin/commands/wf:discuss.md` (symlink)
- Create: `plugin/commands/wf:implement.md` (symlink)
- Create: `plugin/commands/wf:review.md` (symlink)
- Create: `plugin/commands/wf:complete.md` (symlink)
- Create: `plugin/commands/wf:off.md` (symlink)
- Create: `plugin/commands/wf:autonomy.md` (symlink)
- Create: `plugin/commands/wf:proposals.md` (symlink)

- [ ] **Step 1: Create symlinks in plugin/commands/**

```bash
cd plugin/commands
for cmd in define discuss implement review complete off autonomy proposals; do
  ln -sf "$cmd.md" "wf:$cmd.md"
done
```

- [ ] **Step 2: Verify symlinks**

```bash
ls -la plugin/commands/wf:* | head -10
```

Expected: 8 symlinks, each pointing to their short-name counterpart.

- [ ] **Step 3: Write test for alias symlinks**

Add to `tests/run-tests.sh` in a new section after the existing test suites:

```bash
# ============================================================
# TEST SUITE: /wf: aliases
# ============================================================
echo ""
echo "=== /wf: aliases ==="

PLUGIN_COMMANDS="$SCRIPT_DIR/../plugin/commands"

# Test: all 8 wf: aliases exist as symlinks
for cmd in define discuss implement review complete off autonomy proposals; do
  if [ -L "$PLUGIN_COMMANDS/wf:$cmd.md" ]; then
    PASS=$((PASS + 1))
    echo -e "  ${GREEN}PASS${NC} wf:$cmd.md symlink exists"
  else
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}FAIL${NC} wf:$cmd.md symlink missing"
    ERRORS="$ERRORS\n  FAIL: wf:$cmd.md symlink missing"
  fi
done

# Test: wf: aliases resolve to correct targets
for cmd in define discuss implement review complete off autonomy proposals; do
  TARGET=$(readlink "$PLUGIN_COMMANDS/wf:$cmd.md")
  assert_eq "$cmd.md" "$TARGET" "wf:$cmd.md points to $cmd.md"
done
```

- [ ] **Step 4: Run tests**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add plugin/commands/wf:*.md tests/run-tests.sh
git commit -m "feat: add /wf: prefix aliases for all WFM commands"
```

---

### Task 7: Create observation management commands

**Files:**
- Create: `plugin/commands/wf:obs-read.md`
- Create: `plugin/commands/wf:obs-track.md`
- Create: `plugin/commands/wf:obs-untrack.md`

- [ ] **Step 1: Create wf:obs-read.md**

```markdown
---
description: Read an observation by ID from claude-mem
---
Read observation #$ARGUMENTS from claude-mem and display it.

Use the `get_observations` MCP tool with IDs: [$ARGUMENTS]. Present the observation's title, type, date, and narrative to the user in a readable format.

If $ARGUMENTS is empty, say: "Usage: /wf:obs-read <observation-id>"
```

- [ ] **Step 2: Create wf:obs-track.md**

```markdown
---
description: Track an observation ID in the workflow status line
---
!`.claude/hooks/workflow-cmd.sh add_tracked_observation $ARGUMENTS && echo "Now tracking observation #$ARGUMENTS"`

Confirm to the user that observation #$ARGUMENTS is now tracked and will appear in the status line.

If the output shows an error, report it. If $ARGUMENTS is empty, say: "Usage: /wf:obs-track <observation-id>"
```

- [ ] **Step 3: Create wf:obs-untrack.md**

```markdown
---
description: Stop tracking an observation ID in the workflow status line
---
!`.claude/hooks/workflow-cmd.sh remove_tracked_observation $ARGUMENTS && echo "Stopped tracking observation #$ARGUMENTS"`

Confirm to the user that observation #$ARGUMENTS is no longer tracked.

If the output shows an error, report it. If $ARGUMENTS is empty, say: "Usage: /wf:obs-untrack <observation-id>"
```

- [ ] **Step 4: Run tests**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: ALL PASS (observation commands are thin wrappers — the underlying functions are already tested).

- [ ] **Step 5: Commit**

```bash
git add plugin/commands/wf:obs-read.md plugin/commands/wf:obs-track.md plugin/commands/wf:obs-untrack.md
git commit -m "feat: add /wf:obs-read, /wf:obs-track, /wf:obs-untrack commands"
```

---

### Task 8: Update setup.sh to install command symlinks

**Files:**
- Modify: `plugin/scripts/setup.sh`
- Modify: `tests/run-tests.sh` (add setup test)

- [ ] **Step 1: Add command symlink section to setup.sh**

After section D (Project hooks), add a new section E (renumber existing E to F):

```bash
# ─────────────────────────────────────────────────────────────────────────────
# E. Project commands — symlink plugin commands to .claude/commands/
# ─────────────────────────────────────────────────────────────────────────────

COMMANDS_DIR="$PROJECT_DIR/.claude/commands"
mkdir -p "$COMMANDS_DIR"

# Install all plugin command files as symlinks (idempotent)
for cmd_file in "$PLUGIN_ROOT/commands/"*.md; do
  [ -f "$cmd_file" ] || continue
  cmd_name=$(basename "$cmd_file")
  if [ ! -e "$COMMANDS_DIR/$cmd_name" ]; then
    ln -s "../../plugin/commands/$cmd_name" "$COMMANDS_DIR/$cmd_name"
  fi
done
```

Renumber existing section E (permissions) to F with updated comment.

- [ ] **Step 2: Add setup.sh test for command symlinks**

Add to the setup.sh test section in `tests/run-tests.sh`:

```bash
# Test: setup.sh creates command symlinks
SETUP_DIR=$(mktemp -d)
mkdir -p "$SETUP_DIR/.claude" "$SETUP_DIR/plugin/commands" "$SETUP_DIR/plugin/scripts"
# Create minimal plugin structure
echo '---' > "$SETUP_DIR/plugin/commands/define.md"
echo '---' > "$SETUP_DIR/plugin/commands/wf:define.md"
# Create minimal setup.sh dependencies
touch "$SETUP_DIR/plugin/scripts/setup.sh"
git -C "$SETUP_DIR" init -q && git -C "$SETUP_DIR" commit --allow-empty -m init -q
# Run setup
PLUGIN_ROOT="$SETUP_DIR/plugin" PROJECT_DIR="$SETUP_DIR" CLAUDE_PROJECT_DIR="$SETUP_DIR" bash "$SCRIPT_DIR/../plugin/scripts/setup.sh" 2>/dev/null
# Verify
if [ -L "$SETUP_DIR/.claude/commands/define.md" ]; then
  assert_eq "true" "true" "setup.sh creates command symlink for define.md"
else
  assert_eq "true" "false" "setup.sh creates command symlink for define.md"
fi
if [ -L "$SETUP_DIR/.claude/commands/wf:define.md" ]; then
  assert_eq "true" "true" "setup.sh creates command symlink for wf:define.md"
else
  assert_eq "true" "false" "setup.sh creates command symlink for wf:define.md"
fi
rm -rf "$SETUP_DIR"
```

- [ ] **Step 3: Run tests**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: ALL PASS.

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/setup.sh tests/run-tests.sh
git commit -m "feat: setup.sh installs plugin commands as symlinks to .claude/commands/"
```

---

### Task 9: Update documentation

**Files:**
- Modify: `docs/reference/hooks.md:211-213` (remove bug note)
- Modify: `docs/reference/architecture.md:184` (update enforcement description)

- [ ] **Step 1: Remove the bug note from hooks.md**

In `docs/reference/hooks.md`, delete lines 213:
```markdown
> **Note:** The hook code currently has an extra gate that blocks all writes when autonomy is `off` regardless of phase. This is a known bug — `off` should follow phase rules like `ask` and `auto`. See issue #4228.
```

- [ ] **Step 2: Update architecture.md enforcement description**

In `docs/reference/architecture.md`, line 184, change:
```markdown
**Enforcement**: Hooks (`workflow-gate.sh`, `bash-write-guard.sh`) are the single source of truth and apply the autonomy check before the phase gate.
```

To:
```markdown
**Enforcement**: Hooks (`workflow-gate.sh`, `bash-write-guard.sh`) are the single source of truth for write permissions. All autonomy levels follow the same phase-based rules — the difference is checkpoint granularity (instructional), not enforcement.
```

- [ ] **Step 3: Run tests**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: ALL PASS.

- [ ] **Step 4: Commit**

```bash
git add docs/reference/hooks.md docs/reference/architecture.md
git commit -m "docs: remove autonomy off bug note, update enforcement description"
```

---

### Task 10: Install new symlinks in local .claude/commands/

**Files:**
- Create: `.claude/commands/wf:*.md` (symlinks — 11 total: 8 aliases + 3 obs commands)

- [ ] **Step 1: Install wf: aliases**

```bash
cd .claude/commands
for cmd in define discuss implement review complete off autonomy proposals; do
  ln -sf "../../plugin/commands/wf:$cmd.md" "wf:$cmd.md"
done
```

- [ ] **Step 2: Install observation commands**

```bash
cd .claude/commands
for cmd in wf:obs-read wf:obs-track wf:obs-untrack; do
  ln -sf "../../plugin/commands/$cmd.md" "$cmd.md"
done
```

- [ ] **Step 3: Verify all symlinks**

```bash
ls -la .claude/commands/ | grep "wf:"
```

Expected: 11 symlinks (8 aliases + 3 obs commands).

- [ ] **Step 4: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1 | tail -5`
Expected: ALL PASS, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add .claude/commands/wf:*.md
git commit -m "feat: install /wf: aliases and observation commands in project"
```

---

### Task 11: Version bump

**Files:**
- Modify: `.claude-plugin/marketplace.json`
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Determine version bump**

Current version: read from `.claude-plugin/marketplace.json`. This is a feature release (new commands, behavior change) → minor bump.

- [ ] **Step 2: Apply version bump**

```bash
python3 -c "
import json, sys
new_version = sys.argv[1]
for path in ['.claude-plugin/marketplace.json', '.claude-plugin/plugin.json']:
    with open(path) as f:
        data = json.load(f)
    if 'plugins' in data:
        data['plugins'][0]['version'] = new_version
    else:
        data['version'] = new_version
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
" "1.7.0"
```

- [ ] **Step 3: Verify version sync**

Run: `bash scripts/check-version-sync.sh`
Expected: Versions match.

- [ ] **Step 4: Run full test suite one final time**

Run: `bash tests/run-tests.sh 2>&1 | tail -5`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/marketplace.json .claude-plugin/plugin.json
git commit -m "chore: bump version to 1.7.0"
```
