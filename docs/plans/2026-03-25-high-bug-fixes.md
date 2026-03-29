# Design Spec: 3 HIGH Bug Fixes

**Date:** 2026-03-25
**Status:** Draft
**Scope:** BUG-1, BUG-2, BUG-3 from master bug list (#3792)

---

## Problem

Three HIGH-priority bugs undermine workflow enforcement reliability:

1. **BUG-1:** `/autonomy 3` silently fails — user believes autonomy was set but state retains previous value.
2. **BUG-2:** Phase transition commands print success even when `set_phase` fails, misleading both user and Claude.
3. **BUG-3:** Claude can bypass workflow enforcement by calling `set_phase` directly via Bash, circumventing all phase gates.

Together, these bugs mean the workflow enforcement system cannot be trusted. BUG-3 is the most critical — it renders the entire phase gate system advisory rather than enforced.

---

## BUG-1: `/autonomy 3` silently fails

### Root Cause

`set_autonomy_level()` in `workflow-state.sh` validates against `off|ask|auto` only. The `/autonomy` command (`autonomy.md`) passes `$ARGUMENTS` raw. Old numeric values (`1`, `2`, `3`) hit the validation error, but the echo on the next line prints success anyway (compounds with BUG-2 pattern).

### Fix

**Backward-compat mapping in both places (defense-in-depth):**

#### `autonomy.md` (command template)

Add input normalization before the `set_autonomy_level` call:

```bash
# Normalize legacy numeric values
LEVEL="$ARGUMENTS"
case "$LEVEL" in
    1) LEVEL="off" ;;
    2) LEVEL="ask" ;;
    3) LEVEL="auto" ;;
esac
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_autonomy_level "$LEVEL" && echo "Autonomy level set to $LEVEL"
```

Note: the `echo` is also chained with `&&` — this fixes the BUG-2 pattern in this file too.

#### `set_autonomy_level()` in `workflow-state.sh`

Add fallback mapping before the case validation, **plus token authorization** (defense-in-depth against BUG-3 — prevents Claude from escalating autonomy to `auto` and then using forward-only auto-transition to bypass phase token requirements):

```bash
set_autonomy_level() {
    local level="$1"
    # Backward-compat: map legacy numeric values
    case "$level" in
        1) level="off" ;;
        2) level="ask" ;;
        3) level="auto" ;;
    esac
    case "$level" in
        off|ask|auto) ;;
        *) echo "ERROR: Invalid autonomy level: $level (valid: off, ask, auto)" >&2; return 1 ;;
    esac

    # Authorization: require token from UserPromptSubmit hook
    # The /autonomy command generates an "autonomy" token via the same hook
    if ! _check_autonomy_token "$level"; then
        echo "BLOCKED: Autonomy level change requires user authorization. Use /autonomy $level." >&2
        return 1
    fi

    # ... rest unchanged
```

The `_check_autonomy_token()` helper follows the same pattern as the phase token check — looks for a token with `{"target": "autonomy:<level>", ...}` in the token directory and consumes it.

### Files Modified

- `plugin/commands/autonomy.md`
- `plugin/scripts/workflow-state.sh`

### Effort

S (small)

---

## BUG-2: Phase echo false positive in all 5 commands

### Root Cause

In all 5 phase command templates, the confirmation `echo` is on a separate line from `set_phase`. When `set_phase` returns non-zero (hard gate), the echo still runs because it's not chained with `&&`.

Current pattern in `define.md` and `discuss.md`:
```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_phase "define" && "$WF" set_active_skill ""
echo "Phase set to DEFINE — ..."
```

Current pattern in `implement.md`, `review.md`, `complete.md` (each includes a phase-specific reset call — `reset_implement_status`, `reset_review_status`, `reset_completion_status` respectively):
```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_phase "implement" && "$WF" reset_implement_status && "$WF" set_active_skill ""
echo "Phase set to IMPLEMENT — ..."
```

In both patterns the `echo` is a separate statement — not chained to the `set_phase` call.

### Fix

Chain the echo with `&&` in all 5 files so it only runs on success:

#### `define.md`
```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_phase "define" && "$WF" set_active_skill "" && echo "Phase set to DEFINE — code edits are blocked. Define the problem and outcomes first."
```

#### `discuss.md`
```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_phase "discuss" && "$WF" set_active_skill "" && echo "Phase set to DISCUSS — code edits are now blocked until plan is ready."
```

#### `implement.md`
```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_phase "implement" && "$WF" reset_implement_status && "$WF" set_active_skill "" && echo "Phase set to IMPLEMENT — code edits are now allowed."
```

#### `review.md`
```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_phase "review" && "$WF" reset_review_status && "$WF" set_active_skill "review-pipeline" && echo "Phase set to REVIEW — running review pipeline."
```

#### `complete.md`
```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_phase "complete" && "$WF" reset_completion_status && "$WF" set_active_skill "completion-pipeline" && echo "Phase set to COMPLETE — running completion pipeline. Code edits blocked, doc updates allowed."
```

### Files Modified

- `plugin/commands/define.md`
- `plugin/commands/discuss.md`
- `plugin/commands/implement.md`
- `plugin/commands/review.md`
- `plugin/commands/complete.md`

### Effort

S (small)

---

## BUG-3: Claude can bypass `set_phase` directly

### Root Cause

`set_phase()` has no concept of caller identity. Claude can run `workflow-cmd.sh set_phase "off"` via the Bash tool to disable all enforcement. The bash-write-guard hook doesn't detect this because `workflow-cmd.sh set_phase` performs no file I/O patterns (no redirections, `sed -i`, etc.) visible to the write-pattern regex — it passes through as a non-write Bash command. The workflow gate (PreToolUse on Write/Edit) is irrelevant because Claude uses Bash, not Write.

### Security Model

- **Only the user can set the phase.** Claude suggests transitions but cannot execute them.
- **Autonomy `auto` exception:** Claude can auto-transition **forward only** (higher phase ordinal). Never backward, never to OFF.
- **OFF is always user-only.** OFF means abandoning the workflow.
- **The workflow is a one-way pipeline:** DEFINE → DISCUSS → IMPLEMENT → REVIEW → COMPLETE. Claude moves forward toward COMPLETE.

### Fix: UserPromptSubmit One-Time Token System

Based on Anthropic's officially documented UserPromptSubmit hook event (see [Hooks Reference](https://code.claude.com/docs/en/hooks)):

- UserPromptSubmit fires on every user prompt submission, before Claude processes it.
- Claude cannot trigger this hook — it only fires on actual user input.
- The hook receives the user's prompt text via stdin JSON (`prompt` field).
- Exit code 2 blocks the prompt; exit code 0 allows it.
- Stdout can inject additional context for Claude.

#### Architecture

```
User types /review
    │
    ▼
UserPromptSubmit hook fires
    │ Detects "/review" in prompt
    │ Writes one-time token file:
    │   $CLAUDE_PLUGIN_DATA/.phase-tokens/<random>
    │   Content: {"target": "review", "ts": <epoch>, "nonce": "<random>"}
    │ Exits 0 (allow prompt through)
    │
    ▼
Claude processes /review skill
    │ Skill template runs set_phase("review")
    │
    ▼
set_phase() checks authorization:
    │
    ├─ Token found & valid? → Consume token, allow transition
    ├─ No token, but autonomy=auto & forward transition? → Allow
    └─ No token, backward/OFF/no auto? → BLOCK (return 1)
```

#### Component 1: `plugin/scripts/user-phase-token.sh`

New UserPromptSubmit hook script. Placed in `scripts/` per existing convention (all executable hook scripts live in `plugin/scripts/`, while `plugin/hooks/` contains only `hooks.json` configuration).

**Input:** stdin JSON with `prompt` field.

**Logic:**
1. Parse `prompt` from stdin JSON using `jq`.
2. Pattern-match for phase commands: `/define`, `/discuss`, `/implement`, `/review`, `/complete`, and also bare `set_phase` calls (for the user running them directly via `!`).
3. Pattern-match for autonomy commands: `/autonomy <level>` and bare `set_autonomy_level` calls.
4. Extract target (phase name or `autonomy:<level>`) from the matched command.
5. Generate a random nonce (e.g., `openssl rand -hex 16` or `uuidgen`).
6. Write token file to `$CLAUDE_PLUGIN_DATA/.phase-tokens/<nonce>`:
   ```json
   {"target": "<phase-or-autonomy:level>", "ts": <epoch_seconds>, "nonce": "<nonce>"}
   ```
7. Clean up any expired tokens (older than 60 seconds) in the same directory.
8. Exit 0 (allow prompt to proceed).

If prompt doesn't match a phase or autonomy command, exit 0 immediately (no-op).

**Token directory:** `$CLAUDE_PLUGIN_DATA/.phase-tokens/`. Created on first use. Plugin data directory is managed by Claude Code and persists across sessions.

#### Component 2: Modified `set_phase()` in `workflow-state.sh`

Add token verification after phase name validation and before state write:

```bash
set_phase() {
    local new_phase="$1"

    # Phase name validation (unchanged)
    case "$new_phase" in
        off|define|discuss|implement|review|complete) ;;
        *) echo "ERROR: Invalid phase: $new_phase" >&2; return 1 ;;
    esac

    # --- NEW: Authorization check ---
    local authorized=false

    # Check 1: Valid one-time token
    local token_dir="${CLAUDE_PLUGIN_DATA:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/.claude/plugin-data}/.phase-tokens"
    if [ -d "$token_dir" ]; then
        local now
        now=$(date +%s)
        for token_file in "$token_dir"/*; do
            [ -f "$token_file" ] || continue
            local target ts
            target=$(jq -r '.target // ""' "$token_file" 2>/dev/null)
            ts=$(jq -r '.ts // 0' "$token_file" 2>/dev/null)
            # Token must match target phase and be < 60 seconds old
            if [ "$target" = "$new_phase" ] && [ $((now - ts)) -lt 60 ]; then
                rm -f "$token_file"  # Consume token (one-time use)
                authorized=true
                break
            fi
        done
    fi

    # Check 2: Forward-only auto-transition (no token needed)
    if [ "$authorized" = false ]; then
        local current_autonomy
        current_autonomy=$(get_autonomy_level)
        if [ "$current_autonomy" = "auto" ]; then
            local current_ordinal new_ordinal
            current_ordinal=$(_phase_ordinal "$(get_phase)")
            new_ordinal=$(_phase_ordinal "$new_phase")
            if [ "$new_ordinal" -gt "$current_ordinal" ] && [ "$new_phase" != "off" ]; then
                authorized=true
            fi
        fi
    fi

    if [ "$authorized" = false ]; then
        echo "BLOCKED: Phase transition to '$new_phase' requires user authorization. Only the user can change the workflow phase." >&2
        return 1
    fi
    # --- END authorization check ---

    # ... rest of set_phase unchanged (mkdir, gate checks, state write)
```

#### Component 3: Phase ordinal helper

New helper function in `workflow-state.sh`:

```bash
_phase_ordinal() {
    case "$1" in
        off)       echo 0 ;;
        define)    echo 1 ;;
        discuss)   echo 2 ;;
        implement) echo 3 ;;
        review)    echo 4 ;;
        complete)  echo 5 ;;
        *)         echo 0 ;;
    esac
}
```

#### Component 4: Hook registration in `hooks.json`

Add UserPromptSubmit entry under the existing `"hooks"` key in `plugin/hooks/hooks.json`. The full merged file becomes:

```json
{
  "description": "Workflow Manager enforcement hooks",
  "hooks": {
    "Setup": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/user-phase-token.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-gate.sh"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/bash-write-guard.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/post-tool-navigator.sh"
          }
        ]
      }
    ]
  }
}
```

Note: UserPromptSubmit does not support matchers (per Anthropic docs), so no `matcher` field is included in the UserPromptSubmit entry. Existing entries with matchers are unchanged.

### Security Properties

| Property | Guarantee |
|----------|-----------|
| Claude cannot forge tokens | UserPromptSubmit only fires on user input — Claude has no way to trigger it |
| Tokens are single-use | Consumed (deleted) on verification |
| Tokens expire | 60-second TTL prevents stale token accumulation |
| Forward-only auto | Phase ordinals enforce pipeline direction; OFF always requires token |
| Backward transitions require user | Any transition to a lower ordinal or to OFF requires a valid token |
| Autonomy changes require user | `set_autonomy_level` also requires a token — prevents Claude from escalating to `auto` to exploit forward-only bypass |
| Existing gate checks preserved | Hard gates (`_check_phase_gates`) still run after authorization |

### Edge Cases

1. **User runs `set_phase` via `!` prefix:** The `!` prefix runs commands in the user's shell, which also triggers UserPromptSubmit. The hook detects `set_phase` in the prompt text and generates a token. Works correctly.
2. **Token cleanup:** Expired tokens (>60s) are cleaned up each time the hook fires. No accumulation risk.
3. **No `CLAUDE_PLUGIN_DATA`:** Fallback uses `CLAUDE_PROJECT_DIR` or `git rev-parse --show-toplevel` for reliable absolute path resolution, consistent with `STATE_DIR` pattern in `workflow-state.sh`. This shouldn't happen in practice — Claude Code always sets this env var for plugins.
4. **Race condition:** Two rapid phase commands could theoretically create two tokens. Each `set_phase` call consumes only the matching token, so this works correctly. Duplicate tokens for the same phase are harmless (`set_phase` is idempotent).
5. **`/autonomy` command:** Also protected by the token system. The UserPromptSubmit hook generates `autonomy:<level>` tokens for `/autonomy` commands, and `set_autonomy_level()` verifies and consumes them. This closes the escalation vector where Claude could set autonomy to `auto` and then use forward-only transitions.

### Files Modified

- `plugin/hooks/hooks.json` (add UserPromptSubmit entry)
- `plugin/scripts/workflow-state.sh` (add `_phase_ordinal`, `_check_autonomy_token`, modify `set_phase` and `set_autonomy_level`)

### Files Created

- `plugin/scripts/user-phase-token.sh` (new hook script)

### Effort

M (medium)

---

## Dependency Order

BUG-2 should be fixed first (it's the simplest and affects the most files). BUG-1 second (also simple, compounds with BUG-2 pattern in autonomy.md). BUG-3 last (most complex, builds on the now-reliable `set_phase` error reporting from BUG-2 fix).

1. **BUG-2** → Fix echo chaining in all 5 phase commands (NOT autonomy.md — see below)
2. **BUG-1** → Add backward-compat mapping in autonomy.md and workflow-state.sh. Note: BUG-1's fix to `autonomy.md` already incorporates the BUG-2 echo-chaining fix, so `autonomy.md` only needs to be touched once (during BUG-1).
3. **BUG-3** → Implement UserPromptSubmit token system (covers both `set_phase` and `set_autonomy_level`)

---

## Testing Strategy

### BUG-1 Tests
- `/autonomy 1` sets level to `off`
- `/autonomy 2` sets level to `ask`
- `/autonomy 3` sets level to `auto`
- `/autonomy off|ask|auto` still works (no regression)
- `/autonomy invalid` shows error, does not set level

### BUG-2 Tests
- Simulate `set_phase` failure (e.g., hard gate blocks transition) — verify echo does NOT print
- Successful transition — verify echo DOES print

### BUG-3 Tests
- Direct `set_phase` call via Bash without token → blocked
- Phase command via slash command (token generated) → allowed
- Forward auto-transition in `auto` mode → allowed without token
- Backward transition in `auto` mode → blocked without token
- Transition to OFF in `auto` mode → blocked without token
- Token expiry (>60s) → rejected
- Token consumed → second call with same phase blocked
- Direct `set_autonomy_level` call via Bash without token → blocked
- `/autonomy auto` via slash command (token generated) → allowed
- Escalation attack: set autonomy to auto then forward-transition → blocked (autonomy change requires token)

---

## Files Summary

| File | Action | Bug |
|------|--------|-----|
| `plugin/commands/autonomy.md` | Modify | BUG-1, BUG-2 |
| `plugin/commands/define.md` | Modify | BUG-2 |
| `plugin/commands/discuss.md` | Modify | BUG-2 |
| `plugin/commands/implement.md` | Modify | BUG-2 |
| `plugin/commands/review.md` | Modify | BUG-2 |
| `plugin/commands/complete.md` | Modify | BUG-2 |
| `plugin/scripts/workflow-state.sh` | Modify | BUG-1, BUG-3 |
| `plugin/hooks/hooks.json` | Modify | BUG-3 |
| `plugin/scripts/user-phase-token.sh` | Create | BUG-3 |
