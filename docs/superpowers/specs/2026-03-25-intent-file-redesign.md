# Design: Phase Intent File Redesign

**Date:** 2026-03-25
**Supersedes:** [2026-03-25-bug3-redesign-design.md](2026-03-25-bug3-redesign-design.md)
**ADR:** [2026-03-25-phase-token-security-model.md](2026-03-25-phase-token-security-model.md) (platform research still valid; approach selection superseded)
**Also fixes:** #3907 — version bump blocked in COMPLETE phase

## Problem

The BUG-3 phase token system (commit `b410d79`) was designed for HMAC-signed tokens, but HMAC proved impossible (CLAUDE_ENV_FILE is SessionStart-only). The implementation pivoted to unsigned file-tokens but kept all the HMAC-era infrastructure: nonce-named files in a dedicated directory, iteration-based consumption, directory guards, openssl for nonce generation, jq for token JSON. This adds ~150 lines of complexity with zero security benefit over a simpler approach — the unsigned tokens are just as forgeable as writing directly to the state file.

**Evidence:** In the current session, Claude forged a phase token via Bash (`printf '{"target":"discuss",...}' > .phase-tokens/<nonce>`) and used it to transition from OFF to DISCUSS. The defense-in-depth guard didn't fire because the workflow was in OFF phase (no enforcement). The token system is security theater.

**Separate bug discovered:** The `jq` command in `user-phase-token.sh` produces 0-byte token files because `/opt/homebrew/bin` is not on the hook's PATH. This silently breaks all phase transitions.

**Separate issue (#3907):** Version bump in COMPLETE Step 5 writes to `.claude-plugin/` files, which aren't in COMPLETE_WRITE_WHITELIST. The bump is structurally impossible during COMPLETE.

## Why Tokens Exist (And Why They Must Be Something)

The phase token system exists to answer one question: **did the user type this command?**

Without proof-of-user-action, `set_phase("discuss")` cannot distinguish:
- The user typed `/discuss` → UserPromptSubmit fired → legitimate
- Claude called `set_phase("discuss")` on its own → no hook fired → illegitimate

The UserPromptSubmit hook is the only platform-guaranteed user-only boundary. Claude cannot trigger it. But `set_phase()` runs *after* the hook, in Claude's execution context. It needs an artifact — created by the hook, checked by `set_phase()` — to verify that the user initiated the transition.

This artifact must be:
- **Writable by UserPromptSubmit** — the hook creates it
- **Readable by `set_phase()`** — the function checks it
- **Not forgeable without Bash** — Claude's primary tool for file manipulation

No file-based artifact is cryptographically secure against same-UID access. The security rests on the UserPromptSubmit platform guarantee plus a defense-in-depth speed bump (bash-write-guard) that blocks the obvious forgery path. This is the same model as [cc-sessions](https://github.com/GWUDCAP/cc-sessions).

**The question is not whether to have an artifact, but how simple it can be.**

## Approaches Considered

### Approach A: Token Files (Current — Rejected)

Nonce-named files in a `.phase-tokens/` directory. Each transition creates a new file, consumption iterates the directory, atomic mv prevents double-use.

- **Complexity:** ~150 lines across 3 files
- **Dependencies:** jq (broken in hook PATH), openssl (for nonce generation)
- **Failure modes:** 0-byte files from jq failure, orphaned tokens, directory iteration race conditions, directory must be created/guarded
- **Security:** Same as all approaches — UserPromptSubmit is the real boundary

### Approach B: Direct State Write by Hook (Rejected)

UserPromptSubmit hook writes phase directly to `workflow-state.json`. No intermediate artifact.

- **Complexity:** ~30 lines in hook, but hook must: read current state, validate gates, compute new state, write atomically
- **Dependencies:** jq or equivalent for JSON mutation in the hook
- **Failure modes:** Hook becomes complex — gate validation logic duplicated between hook and `set_phase()`. Silent hook failure leaves state unchanged with no diagnostic. Hook tightly coupled to state file format.
- **Why rejected:** Moves validation complexity into the hook, which runs in a restricted environment with limited debugging. The hook should be as dumb as possible.

### Approach C: Intent File (Chosen)

Single fixed-path file written by UserPromptSubmit using `printf` (shell builtin). `set_phase()` reads the intent, validates gates, writes the full state, deletes the intent file.

- **Complexity:** ~25 lines in hook, ~15 lines changed in `set_phase()`
- **Dependencies:** `printf` (shell builtin — always available, no PATH issues)
- **Failure modes:** Minimal — `printf` can't fail unless disk is full. Hook self-validates after write.
- **Security:** Same as all approaches — but nothing to forge except one known file path (guarded by bash-write-guard)

## Decision

**Chosen approach: C — Intent File.**

### Rationale

The intent file is the **minimum viable proof-of-user-action**. It preserves the security property (UserPromptSubmit creates the artifact, `set_phase()` checks it) while eliminating all unnecessary complexity:

| Aspect | Tokens (current) | Intent file (proposed) |
|---|---|---|
| Files per transition | 1 nonce-named file in a directory | 1 fixed-path file (overwritten) |
| Hook dependencies | jq, openssl, mkdir | printf (shell builtin) |
| Hook lines | 77 | ~25 |
| Consumption logic | Iterate directory, read-before-consume, atomic mv, cleanup | Read fixed file, validate, delete |
| Orphan cleanup needed | Yes (stale tokens accumulate) | No (single file, overwritten on next command) |
| Guard target | Directory name (`.phase-tokens`) | File name (`phase-intent.json`) |
| Validation location | Split (hook generates, set_phase validates format + gates) | Hook writes intent only, set_phase does all validation |
| Autonomy handling | Separate nonce file per autonomy command | Same intent file, `autonomy:` prefix on target |
| jq in hook | Yes (broken — 0-byte files) | No |
| State format coupling | Token format independent of state | Intent format independent of state |

### Trade-offs Accepted

- **Intent file forgery is possible** via Bash during IMPLEMENT/REVIEW — same risk as tokens, same risk as cc-sessions. Accepted because UserPromptSubmit is the real boundary.
- **Single intent file means rapid successive commands overwrite** — e.g., `/discuss` immediately followed by `/implement` before the first processes. Acceptable: only the last command's intent survives, which matches user expectation.

### Risks Identified

- If the hook fails silently (disk full, permissions), no intent file exists and `set_phase()` blocks with a diagnostic message. This is the same failure mode as tokens but with better diagnostics.
- If Anthropic changes UserPromptSubmit behavior, the entire model breaks (same as all hook-based enforcement).

## Design

### Section 1: Intent File Hook (`plugin/scripts/user-phase-gate.sh`)

Replaces `user-phase-token.sh`. New name reflects new purpose.

**Intent file location:** `$STATE_DIR/phase-intent.json` (same directory as `workflow.json`)

**Intent file format:**
```json
{"intent":"discuss"}
```

For autonomy commands:
```json
{"intent":"autonomy:ask"}
```

**Hook logic (~25 lines):**

```
1. Read stdin JSON, extract .prompt
2. Match slash commands (same regex as current: ^\s*/<command>(\s|$))
3. Determine TARGET (phase name) and/or AUTONOMY_TARGET
4. Resolve STATE_DIR (same logic as workflow-state.sh)
5. Write intent file using printf:
     printf '{"intent":"%s"}\n' "$TARGET" > "$STATE_DIR/phase-intent.json"
6. Validate write: [ -s "$STATE_DIR/phase-intent.json" ] or exit 1 with stderr error
7. If autonomy command also detected, write second intent:
     printf '{"intent":"%s"}\n' "$AUTONOMY_TARGET" > "$STATE_DIR/autonomy-intent.json"
```

**Key properties:**
- `printf` is a shell builtin — no PATH dependency, cannot fail unless disk is full
- Self-validates after write (file must be non-empty)
- Errors go to stderr (logged by Claude Code)
- No jq, no openssl, no mkdir (STATE_DIR already exists from setup.sh)
- Two separate intent files for phase vs autonomy (prevents overwrite when both are in same prompt)

**Removed entirely:**
- Token directory (`.phase-tokens/`)
- Nonce generation
- jq dependency in hook
- mkdir in hook

### Section 2: `set_phase()` Changes (`plugin/scripts/workflow-state.sh`)

**Delete:**
- `_check_phase_token()` function (lines 103-123)
- `_check_autonomy_token()` function (lines 125-130)
- Token authorization logic in `set_phase()` (lines 334-355)

**Add:** `_check_phase_intent()` function:

```
_check_phase_intent(target_phase):
  1. INTENT_FILE="$STATE_DIR/phase-intent.json"
  2. If file doesn't exist or is empty → return 1
  3. Read intent field: grep + sed (no jq dependency for reading simple JSON)
     Or: use jq if available, printf-parsed fallback if not
  4. If intent matches target_phase:
     a. Delete intent file (consumed)
     b. Return 0 (authorized)
  5. Return 1 (no match)
```

**`set_phase()` authorization flow (same structure, new check):**
1. Check 1: `_check_phase_intent "$new_phase"` — intent file from UserPromptSubmit
2. Check 2: Forward-only auto-transition (autonomy=auto, new > current, not OFF) — unchanged
3. If neither: BLOCKED with diagnostic message explaining why

**`_check_autonomy_intent()` — same pattern:**

```
_check_autonomy_intent(level):
  1. INTENT_FILE="$STATE_DIR/autonomy-intent.json"
  2. Same read/match/consume logic as _check_phase_intent
  3. Match against "autonomy:$level"
```

**`set_autonomy_level()` updated** to call `_check_autonomy_intent()` instead of `_check_autonomy_token()`.

**`WF_SKIP_AUTH=1` bypass preserved** for test infrastructure.

### Section 3: bash-write-guard Changes (`plugin/scripts/bash-write-guard.sh`)

**Replace** the `.phase-tokens` directory guard (lines 117-126) with an intent file guard:

```bash
# Defense-in-depth: block direct writes to phase intent and workflow state files
if echo "$COMMAND" | grep -qE 'phase-intent\.json|autonomy-intent\.json|workflow\.json'; then
    emit_deny "BLOCKED: Direct writes to workflow state files are not allowed."
    exit 0
fi
```

**Same placement** — before the implement/review early-exit. Same speed-bump caveat.

**Also guards `workflow.json`** — the state file itself. Previously unguarded because tokens were the authorization mechanism. With the simpler model, guarding the state file directly is belt-and-suspenders.

### Section 4: hooks.json Update

**UserPromptSubmit entry changes:**

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
]
```

Only the script name changes. Timeout stays at 5s (actual execution <100ms with printf).

### Section 5: Command File Updates

All 6 command files (`define.md`, `discuss.md`, `implement.md`, `review.md`, `complete.md`, `off.md`) keep calling `set_phase` through `workflow-cmd.sh` — the interface is unchanged. The difference is internal: `set_phase()` now checks an intent file instead of iterating token files.

No command file changes needed for the token→intent migration.

### Section 6: Version Bump Fix (#3907)

**Problem:** COMPLETE Step 5 runs the versioning agent to bump `.claude-plugin/` files, but those paths aren't in `COMPLETE_WRITE_WHITELIST`. The bump is structurally blocked.

**Fix — move bump to IMPLEMENT, verify at COMPLETE:**

**`implement.md` changes:**
Add a new step between step 4 (all_tasks_complete) and step 5 (tests_passing):

```
4b. Version bump: Dispatch a Versioning agent (same prompt as current complete.md Step 5 2b).
    Apply the bump to all 3 files. Run scripts/check-version-sync.sh.
    This runs during IMPLEMENT where all writes are allowed.
```

**`complete.md` Step 5 changes:**
Replace the versioning agent dispatch (lines 226-258) with verification only:

```
2b. Version verification: Run scripts/check-version-sync.sh. Verify all 3 files
    have the same version and it is greater than the previous release tag.
    If version bump was not done during IMPLEMENT, flag as validation failure
    and instruct user to loop back to /implement.
```

### Section 7: Cleanup

**Delete:**
- `plugin/scripts/user-phase-token.sh` — replaced by `user-phase-gate.sh`
- `.claude/plugin-data/.phase-tokens/` directory — no longer used
- Adversarial test scripts from `docs/superpowers/specs/`: `adversarial-test-runner.sh`, `adversarial-followup.sh`

**Create:**
- `plugin/scripts/user-phase-gate.sh` — new intent file hook

### Section 8: Test Changes (`tests/run-tests.sh`)

**Delete BUG-3 token tests:**
- Token format assertions (nonce, target field checks)
- Token consumption/iteration tests
- Two-token coexistence test
- Token directory guard test
- Integration test (hook → token → set_phase)

**Replace with intent file tests:**

| Test | What it verifies |
|---|---|
| set_phase blocked without intent file | Authorization enforced |
| set_phase allowed with valid intent file | Intent consumed, phase changes |
| intent file deleted after consumption | One-time use |
| wrong intent target rejected | Only matching intent authorizes |
| forward auto-transition without intent | Autonomy=auto still works |
| backward transition blocked in auto mode | Only forward allowed |
| OFF blocked in auto mode | OFF always requires user |
| autonomy intent consumed correctly | Separate intent file works |
| phase + autonomy intents coexist | Independent files, independent consumption |
| intent file guard in bash-write-guard | `phase-intent.json` in command → BLOCKED |
| workflow.json guard in bash-write-guard | `workflow.json` in command → BLOCKED |
| hook writes valid intent (integration) | Simulate hook → check file content |
| hook self-validates write | Zero-byte file → hook exits 1 |

**Unchanged:**
- `WF_SKIP_AUTH=1` bypass for non-auth tests
- `run_with_auth` helper pattern (adapted for intent files)
- Forward-only auto-transition logic tests
- Gate check tests (milestones)

## Files Modified

| File | Action | Est. Lines |
|------|--------|-----------|
| `plugin/scripts/user-phase-gate.sh` | **NEW** (replaces user-phase-token.sh) | ~25 |
| `plugin/scripts/user-phase-token.sh` | **DELETE** | -77 |
| `plugin/scripts/workflow-state.sh` | Replace token functions with intent functions | ~40 changed |
| `plugin/scripts/bash-write-guard.sh` | Replace .phase-tokens guard with intent+state guard | ~5 changed |
| `plugin/hooks/hooks.json` | Update UserPromptSubmit script path | 1 changed |
| `plugin/commands/implement.md` | Add version bump step | ~15 added |
| `plugin/commands/complete.md` | Replace version bump with verification | ~20 changed |
| `tests/run-tests.sh` | Replace BUG-3 token tests with intent tests | ~80 changed |
| `docs/superpowers/specs/adversarial-test-runner.sh` | **DELETE** | cleanup |
| `docs/superpowers/specs/adversarial-followup.sh` | **DELETE** | cleanup |

## Non-Goals

- HMAC signing (deferred — platform constraints unchanged, see ADR)
- CLAUDE_ENV_FILE integration (SessionStart-only, multiple open bugs)
- PreToolUse exit code 2 migration (unreliable per documented bugs)
- Changes to BUG-1 (autonomy mapping) or BUG-2 (echo chaining) fixes — both are solid
- Whitelisting `.claude-plugin/` in COMPLETE phase (principle: COMPLETE should not write config)
