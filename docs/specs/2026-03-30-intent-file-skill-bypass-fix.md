# Intent File Authorization for user-set-phase.sh and set_autonomy_level

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Close the Skill tool bypass (issue #26) by adding intent file verification to `user-set-phase.sh` and `set_autonomy_level()`, while preserving the existing path separation architecture.

**Problem:** `disable-model-invocation: true` is not enforced for plugin commands (upstream bug anthropics/claude-code#22345). Claude can call `Skill("off")` which triggers backtick preprocessing, executing `user-set-phase.sh "off"` and disabling workflow enforcement. The same vulnerability exists for `Skill("autonomy auto")` which could escalate autonomy via `workflow-cmd.sh set_autonomy_level`, enabling `agent_set_phase()` to advance phases freely. Both empirically verified in session 2026-03-30.

**Architecture:** Two layers working together:
1. **Path separation** (existing, v1.12.0): `user-set-phase.sh` for user transitions, `agent_set_phase()` for agent transitions. Separate code paths, separate files, no shared bypass.
2. **Intent file verification** (new): `UserPromptSubmit` hook writes `phase-intent.json` / `autonomy-intent.json` before the slash command runs. `user-set-phase.sh` and `set_autonomy_level()` verify the intent file exists and matches before transitioning.

**Why both layers:**
- Path separation keeps the code auditable — you can trace who called what
- Intent files close the Skill tool hole — even if Claude reaches these paths via Skill backtick, no intent file exists (UserPromptSubmit didn't fire), so the transition is rejected

**Tech Stack:** Bash, jq (for intent checks only — not in the hook), shell builtins

**History:** Original intent file spec designed March 25, implemented March 28, then removed in v1.12.0 in favor of path separation alone. This spec reintroduces intent files as a complement to path separation after discovering the Skill tool bypass.

**Ordering guarantee:** `UserPromptSubmit` hooks complete before any tool invocation or backtick preprocessing begins. This is part of the Claude Code hook lifecycle — the intent file is always written before `user-set-phase.sh` runs.

**Fail-closed design:** The hook uses grep/sed (not jq) to extract the prompt from stdin JSON. If extraction fails (malformed JSON, encoding issues), no intent file is written, and `user-set-phase.sh` blocks all transitions. This is immediately visible to the user and debuggable.

**Issue:** [#26](https://github.com/azevedo-home-lab/claude-code-workflows/issues/26)

---

### Task 1: Create intent file hook (`user-phase-gate.sh`)

**Files:**
- Create: `plugin/scripts/user-phase-gate.sh`

- [ ] **Step 1: Write the hook script**

```bash
#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# UserPromptSubmit hook: writes intent files for phase and autonomy commands.
# Intent files are consumed by user-set-phase.sh and set_autonomy_level().
# Claude cannot trigger this hook — it only fires on actual user input.
#
# Fail-closed: if prompt extraction fails, no intent file is written,
# and user-set-phase.sh / set_autonomy_level() will block the transition.
# This is immediately visible to the user and debuggable.
#
# Security model: Only explicit slash commands generate intent files.
# No bare set_phase/set_autonomy_level matching — prevents false positives.
# Uses printf (shell builtin) — no jq, no openssl, no PATH dependencies.

set -euo pipefail

# Read stdin JSON — extract prompt using shell builtins + grep/sed
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | grep -o '"prompt"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"prompt"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || PROMPT=""
[ -z "$PROMPT" ] && exit 0

# Resolve STATE_DIR (same logic as workflow-state.sh)
STATE_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/.claude/state"

# Detect phase commands: explicit slash commands only
# Regex: ^\s*/<command>(\s|$) — anchored to line start, must start with /
TARGET=""
if echo "$PROMPT" | grep -qE '^\s*/define(\s|$)'; then
    TARGET="define"
elif echo "$PROMPT" | grep -qE '^\s*/discuss(\s|$)'; then
    TARGET="discuss"
elif echo "$PROMPT" | grep -qE '^\s*/implement(\s|$)'; then
    TARGET="implement"
elif echo "$PROMPT" | grep -qE '^\s*/review(\s|$)'; then
    TARGET="review"
elif echo "$PROMPT" | grep -qE '^\s*/complete(\s|$)'; then
    TARGET="complete"
elif echo "$PROMPT" | grep -qE '^\s*/off(\s|$)'; then
    TARGET="off"
fi

# Detect autonomy commands: /autonomy <level>
AUTONOMY_TARGET=""
if echo "$PROMPT" | grep -qE '^\s*/autonomy\s+'; then
    RAW_LEVEL=$(echo "$PROMPT" | grep -oE '/autonomy\s+\S+' | head -1 | awk '{print $2}')
    case "$RAW_LEVEL" in
        1|off) AUTONOMY_TARGET="autonomy:off" ;;
        2|ask) AUTONOMY_TARGET="autonomy:ask" ;;
        3|auto) AUTONOMY_TARGET="autonomy:auto" ;;
    esac
fi

# No matching command — exit silently
[ -z "$TARGET" ] && [ -z "$AUTONOMY_TARGET" ] && exit 0

# Write phase intent file
if [ -n "$TARGET" ]; then
    printf '{"intent":"%s"}\n' "$TARGET" > "$STATE_DIR/phase-intent.json"
    if [ ! -s "$STATE_DIR/phase-intent.json" ]; then
        echo "ERROR: Failed to write phase intent file" >&2
    fi
fi

# Write autonomy intent file (separate file — prevents overwrite when both in same prompt)
if [ -n "$AUTONOMY_TARGET" ]; then
    printf '{"intent":"%s"}\n' "$AUTONOMY_TARGET" > "$STATE_DIR/autonomy-intent.json"
    if [ ! -s "$STATE_DIR/autonomy-intent.json" ]; then
        echo "ERROR: Failed to write autonomy intent file" >&2
    fi
fi

exit 0
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x plugin/scripts/user-phase-gate.sh`

- [ ] **Step 3: Verify hook runs with test input**

Run: `echo '{"prompt": "/discuss some args"}' | CLAUDE_PROJECT_DIR="$(pwd)" bash plugin/scripts/user-phase-gate.sh && echo "exit: $?"`

Expected: exit 0, file `.claude/state/phase-intent.json` containing `{"intent":"discuss"}`

- [ ] **Step 4: Clean up test artifact**

Run: `rm -f .claude/state/phase-intent.json .claude/state/autonomy-intent.json`

- [ ] **Step 5: Commit**

---

### Task 2: Add intent verification to `user-set-phase.sh`

**Files:**
- Modify: `plugin/scripts/user-set-phase.sh`

The key change: `user-set-phase.sh` currently trusts that it was called from a user's slash command. After this change, it verifies by checking for a matching intent file.

- [ ] **Step 1: Add `_check_phase_intent` function**

After `source "$SCRIPT_DIR/workflow-state.sh"` (line 21), before `new_phase="${1:-}"` (line 23), add:

```bash
# Check for a valid phase intent file. Consumes the intent on success.
# Returns 0 if authorized, 1 if blocked.
# Intent files are written by user-phase-gate.sh (UserPromptSubmit hook).
_check_phase_intent() {
    local target_phase="$1"
    local intent_file="$STATE_DIR/phase-intent.json"
    [ -s "$intent_file" ] || return 1
    local intent
    intent=$(jq -r '.intent // ""' "$intent_file" 2>/dev/null) || return 1
    if [ "$intent" = "$target_phase" ]; then
        rm -f "$intent_file"
        return 0
    fi
    return 1
}
```

- [ ] **Step 2: Add intent verification after phase validation**

After the `case "$new_phase"` block (after line 28), add:

```bash
# Intent file verification — closes Skill tool bypass (issue #26).
# UserPromptSubmit writes the intent file before this script runs.
# If called via Skill tool, no UserPromptSubmit fired, so no intent file exists.
if ! _check_phase_intent "$new_phase"; then
    echo "BLOCKED: No valid intent file for phase '$new_phase'." >&2
    echo "  Intent files are generated by the UserPromptSubmit hook when you type a slash command." >&2
    echo "  If you see this error, the transition was not initiated by a user slash command." >&2
    exit 1
fi
```

- [ ] **Step 3: Update script header comments**

Replace lines 8-14 with:
```bash
# USER PHASE TRANSITION — called from !backtick in command files.
# Verifies a matching intent file exists (written by UserPromptSubmit hook)
# before transitioning. This closes the Skill tool bypass (issue #26):
# even if Claude invokes a command via Skill tool (which runs backtick
# preprocessing), no intent file exists because UserPromptSubmit only
# fires on actual user input.
#
# SECURITY: Two layers protect this path:
# 1. Intent file verification (this script) — rejects without matching intent
# 2. bash-write-guard.sh — blocks direct Bash tool execution of this script
```

- [ ] **Step 4: Verify manually**

```bash
# Without intent file — should fail
CLAUDE_PROJECT_DIR="$(pwd)" bash plugin/scripts/user-set-phase.sh "discuss" 2>&1
# Expected: BLOCKED: No valid intent file for phase 'discuss'.

# With intent file — should succeed
printf '{"intent":"discuss"}\n' > .claude/state/phase-intent.json
CLAUDE_PROJECT_DIR="$(pwd)" bash plugin/scripts/user-set-phase.sh "discuss" 2>&1
# Expected: Phase set to discuss.

# Intent file should be consumed
ls .claude/state/phase-intent.json 2>/dev/null || echo "Consumed"
# Expected: Consumed
```

- [ ] **Step 5: Commit**

---

### Task 2b: Add autonomy intent verification to `set_autonomy_level()`

**Files:**
- Modify: `plugin/scripts/workflow-state.sh` (add intent check to `set_autonomy_level`)

The same Skill tool bypass affects `/autonomy auto` — Claude could call `Skill("autonomy auto")` which runs `workflow-cmd.sh set_autonomy_level "auto"` via backtick. Once autonomy is "auto", `agent_set_phase()` can advance phases freely. This task closes that gap.

- [ ] **Step 1: Add `_check_autonomy_intent` function**

In `plugin/scripts/workflow-state.sh`, before the `set_autonomy_level()` function (before line 130), add:

```bash
# Check for a valid autonomy intent file. Consumes the intent on success.
# Returns 0 if authorized, 1 if blocked.
# Intent files are written by user-phase-gate.sh (UserPromptSubmit hook).
_check_autonomy_intent() {
    local level="$1"
    local intent_file="$STATE_DIR/autonomy-intent.json"
    [ -s "$intent_file" ] || return 1
    local intent
    intent=$(jq -r '.intent // ""' "$intent_file" 2>/dev/null) || return 1
    if [ "$intent" = "autonomy:$level" ]; then
        rm -f "$intent_file"
        return 0
    fi
    return 1
}
```

- [ ] **Step 2: Add intent verification to `set_autonomy_level()`**

In `set_autonomy_level()`, replace lines 142-143:
```bash
    # set_autonomy_level is always user-initiated — called from !backtick in autonomy.md.
    # No authorization check needed here; the user's slash command is the authorization.
```

With:
```bash
    # Intent file verification — closes Skill tool bypass (issue #26).
    # UserPromptSubmit writes the intent file before this function runs.
    # If called via Skill tool, no UserPromptSubmit fired, so no intent file exists.
    if ! _check_autonomy_intent "$level"; then
        echo "BLOCKED: No valid intent file for autonomy level '$level'." >&2
        echo "  Intent files are generated by the UserPromptSubmit hook when you type /autonomy." >&2
        echo "  If you see this error, the change was not initiated by a user slash command." >&2
        return 1
    fi
```

- [ ] **Step 3: Verify manually**

```bash
# Without intent file — should fail
source plugin/scripts/workflow-state.sh && set_autonomy_level "auto" 2>&1
# Expected: BLOCKED: No valid intent file for autonomy level 'auto'.

# With intent file — should succeed
printf '{"intent":"autonomy:auto"}\n' > .claude/state/autonomy-intent.json
source plugin/scripts/workflow-state.sh && set_autonomy_level "auto" 2>&1
# Expected: (no error, autonomy updated)

# Intent file should be consumed
ls .claude/state/autonomy-intent.json 2>/dev/null || echo "Consumed"
# Expected: Consumed
```

- [ ] **Step 4: Commit**

---

### Task 3: Register UserPromptSubmit hook and update guards

**Files:**
- Modify: `plugin/hooks/hooks.json` (add UserPromptSubmit section)
- Modify: `plugin/scripts/bash-write-guard.sh:177` (add autonomy-intent.json)
- Modify: `plugin/scripts/setup.sh:148` (add symlink for user-phase-gate.sh)
- Modify: `plugin/scripts/setup.sh:156-172` (add UserPromptSubmit registration in settings.json)

- [ ] **Step 1: Add UserPromptSubmit to hooks.json**

After the `PreToolUse` block (after line 37), before `PostToolUse`, add:

```json
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/user-phase-gate.sh",
            "timeout": 5
          }
        ]
      }
    ],
```

- [ ] **Step 2: Add `autonomy-intent.json` to state file guard**

In `plugin/scripts/bash-write-guard.sh`, line 177, replace:
```
STATE_FILE_PATTERN='\.claude/(state/workflow\.json|state/phase-intent\.json)'
```
With:
```
STATE_FILE_PATTERN='\.claude/(state/workflow\.json|state/phase-intent\.json|state/autonomy-intent\.json)'
```

- [ ] **Step 3: Add `user-phase-gate.sh` to setup.sh symlink loop**

In `plugin/scripts/setup.sh`, line 148, add `user-phase-gate.sh` to the script list:

Replace:
```bash
for script in user-set-phase.sh workflow-gate.sh bash-write-guard.sh post-tool-navigator.sh workflow-state.sh workflow-cmd.sh; do
```
With:
```bash
for script in user-set-phase.sh user-phase-gate.sh workflow-gate.sh bash-write-guard.sh post-tool-navigator.sh workflow-state.sh workflow-cmd.sh; do
```

- [ ] **Step 4: Add UserPromptSubmit registration to setup.sh settings.json**

In `plugin/scripts/setup.sh`, after the PostToolUse registration block (after line 172, after `fi || true`), add:

```bash
  # Ensure UserPromptSubmit hook exists
  HAS_UPS=$(jq 'has("hooks") and (.hooks | has("UserPromptSubmit"))' "$PROJECT_SETTINGS" 2>/dev/null)
  if [ "$HAS_UPS" != "true" ]; then
    jq '.hooks.UserPromptSubmit = [{"hooks": [{"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/user-phase-gate.sh", "timeout": 5}]}]' \
      "$PROJECT_SETTINGS" > "$PROJECT_SETTINGS.tmp" && mv "$PROJECT_SETTINGS.tmp" "$PROJECT_SETTINGS" || true
  fi
```

Note: this must be added BEFORE the `fi || true` that closes the `if [ -f "$PROJECT_SETTINGS" ]` block (line 173). Insert at line 172, before that closing block.

- [ ] **Step 5: Commit**

---

### Task 4: Add stale intent file cleanup to setup.sh

**Files:**
- Modify: `plugin/scripts/setup.sh:41`

- [ ] **Step 1: Add cleanup after stale temp file cleanup**

After line 41 (`find "$STATE_DIR" -name '*.tmp.*' ...`), add:

```bash
# Clean up stale intent files from previous sessions
rm -f "$STATE_DIR/phase-intent.json" "$STATE_DIR/autonomy-intent.json"
```

- [ ] **Step 2: Commit**

---

### Task 5: End-to-end validation

**Files:** None (validation only)

- [ ] **Step 1: Verify full flow — user path (happy path)**

```bash
# Simulate UserPromptSubmit for /implement
echo '{"prompt": "/implement"}' | CLAUDE_PROJECT_DIR="$(pwd)" bash plugin/scripts/user-phase-gate.sh
cat .claude/state/phase-intent.json
# Expected: {"intent":"implement"}

# Run user-set-phase.sh (simulating backtick)
CLAUDE_PROJECT_DIR="$(pwd)" bash plugin/scripts/user-set-phase.sh "implement"
# Expected: Phase set to implement.

# Verify intent file was consumed
ls .claude/state/phase-intent.json 2>/dev/null || echo "Intent file consumed"
# Expected: Intent file consumed
```

- [ ] **Step 2: Verify Skill tool bypass is closed**

```bash
# Set up active phase
printf '{"intent":"discuss"}\n' > .claude/state/phase-intent.json
CLAUDE_PROJECT_DIR="$(pwd)" bash plugin/scripts/user-set-phase.sh "discuss"

# Simulate Skill tool calling /off (no UserPromptSubmit fires — no intent file)
CLAUDE_PROJECT_DIR="$(pwd)" bash plugin/scripts/user-set-phase.sh "off" 2>&1
# Expected: BLOCKED: No valid intent file for phase 'off'.

# Verify phase unchanged
source plugin/scripts/workflow-state.sh && get_phase
# Expected: discuss
```

- [ ] **Step 3: Verify autonomy Skill tool bypass is closed**

```bash
# Set up active phase with ask autonomy
printf '{"intent":"implement"}\n' > .claude/state/phase-intent.json
CLAUDE_PROJECT_DIR="$(pwd)" bash plugin/scripts/user-set-phase.sh "implement"

# Simulate Skill tool calling /autonomy auto (no UserPromptSubmit fires)
source plugin/scripts/workflow-state.sh && set_autonomy_level "auto" 2>&1
# Expected: BLOCKED: No valid intent file for autonomy level 'auto'.

# Verify autonomy unchanged
source plugin/scripts/workflow-state.sh && get_autonomy_level
# Expected: ask
```

- [ ] **Step 4: Verify agent path still works**

```bash
# agent_set_phase uses its own checks (forward-only, auto autonomy, milestone gates)
# It does NOT check intent files — that's user path only
# No changes needed to agent path
```

- [ ] **Step 6: Verify bash-write-guard blocks intent file forgery**

```bash
echo '{"tool_input":{"command":"printf x > .claude/state/phase-intent.json"}}' | CLAUDE_PROJECT_DIR="$(pwd)" bash plugin/scripts/bash-write-guard.sh 2>&1
# Expected: output contains "deny"

echo '{"tool_input":{"command":"echo x > .claude/state/autonomy-intent.json"}}' | CLAUDE_PROJECT_DIR="$(pwd)" bash plugin/scripts/bash-write-guard.sh 2>&1
# Expected: output contains "deny"
```

- [ ] **Step 7: Verify hooks.json is valid JSON**

```bash
jq . plugin/hooks/hooks.json > /dev/null && echo "Valid JSON"
```

- [ ] **Step 8: Verify git status is clean**

Run: `git status`

---

## Security Model Summary

### Phase transitions

```
User types /off
        |
        v
+----------------------------+
|  UserPromptSubmit           |  <-- Platform guarantee: user-only
|  (user-phase-gate.sh)       |      Claude CANNOT trigger this hook
|                             |
|  Writes phase-intent.json   |
|  {"intent":"off"}           |
+-------------+--------------+
              |
              v
+----------------------------+
|  Backtick preprocessing     |  <-- Runs for BOTH /off AND Skill("off")
|  (off.md)                   |      This is the vulnerability we're closing
|                             |
|  Calls user-set-phase.sh    |
+-------------+--------------+
              |
              v
+----------------------------+
|  user-set-phase.sh          |  <-- Intent verification (NEW)
|                             |
|  Reads phase-intent.json    |
|  Match? -> transition       |
|  No match? -> BLOCKED       |  <-- Skill tool path dies here
+----------------------------+
```

### Autonomy escalation

```
User types /autonomy auto
        |
        v
+----------------------------+
|  UserPromptSubmit           |  <-- Platform guarantee: user-only
|  (user-phase-gate.sh)       |
|                             |
|  Writes autonomy-intent.json|
|  {"intent":"autonomy:auto"} |
+-------------+--------------+
              |
              v
+----------------------------+
|  Backtick preprocessing     |  <-- Runs for BOTH /autonomy AND Skill("autonomy auto")
|  (autonomy.md)              |
|                             |
|  Calls workflow-cmd.sh      |
|  set_autonomy_level "auto"  |
+-------------+--------------+
              |
              v
+----------------------------+
|  set_autonomy_level()       |  <-- Intent verification (NEW)
|  (workflow-state.sh)        |
|                             |
|  Reads autonomy-intent.json |
|  Match? -> update           |
|  No match? -> BLOCKED       |  <-- Skill tool path dies here
+----------------------------+
```

### Defense-in-depth layers

```
1. UserPromptSubmit (platform guarantee) — only user input creates intent files
2. user-set-phase.sh (intent check) — rejects phase change without matching intent
3. set_autonomy_level() (intent check) — rejects autonomy change without matching intent
4. bash-write-guard.sh (state file guard) — blocks intent file forgery via Bash
5. bash-write-guard.sh (execution guard) — blocks user-set-phase.sh via Bash tool
```

## What This Does NOT Change

- `agent_set_phase()` in `workflow-state.sh` — untouched. Agent path has its own guards.
- `workflow-cmd.sh` dispatch list — untouched.
- Path separation architecture — preserved.
- Command files (`off.md`, `implement.md`, etc.) — untouched. Still call `user-set-phase.sh` via backtick.
