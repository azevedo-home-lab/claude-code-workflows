# Tech Debt Cleanup + README Overhaul

**Date:** 2026-03-23
**Status:** Draft
**Scope:** 7 bug fixes/improvements + README restructure

## Problem

Five tech debt items accumulated during the autonomy levels and claude-mem integration work (session handover #3165). A sixth bug was discovered during this session: observation IDs not tracked when workflow phase is OFF. A seventh was discovered when a multi-line `python3 -c` command bypassed the bash-write-guard, revealing a class of pattern-matching weaknesses. Additionally, the README has several accuracy and structure issues identified during review.

### Tech Debt Items

1. `.claude/commands/` not in COMPLETE phase whitelist — blocks editing command templates during completion pipeline
2. bash-write-guard HEREDOC false positive — `git commit -m "$(cat <<'EOF'...)"` triggers `>[^&]` and `cat[[:space:]].*<<` patterns, blocking normal git workflow
3. ~~Level 1 WebFetch/WebSearch no hook fallback~~ — **CLOSED (won't fix)**: WebFetch/WebSearch are read-only operations; blocking them at Level 1 contradicts "read-only mode"
4. Coaching context-eviction — Layer 1 coaching fires once at phase entry then gets evicted from context in long sessions; critical instructions stop being reinforced
5. post-tool-navigator HEREDOC extraction fragile — current extraction code is actually well-structured (per code review); reduce to minimal hardening
6. Observation ID not tracked when phase is OFF — `post-tool-navigator.sh` early-exits before reaching the observation extraction block; `set_last_observation_id` silently discards when no state file exists
7. bash-write-guard multi-line and wrapper bypasses — security audit revealed a class of pattern-matching weaknesses: multi-line python3 commands, `eval`/`bash -c`/`sh -c` wrappers, `^`-anchored patterns bypassed by chaining, missing heredoc variants, and missing write commands

### README Issues

1. Workflow Manager description ("hooks that block code edits until you have a plan") is inaccurate
2. Install section should be further down
3. "Informed By" should be "Sources:" with claude-mem sources added
4. YubiKey and iTerm Launcher presented as core tools but are optional helpers
5. General structure and accuracy need review

## Approaches Considered

### Item 2: bash-write-guard HEREDOC false positive

**Approach A (rejected): Strip HEREDOC content before pattern matching.** Remove `$(cat <<...EOF...EOF)` blocks from CLEAN_CMD before applying WRITE_PATTERN. Risk: could hide legitimate write detection inside HEREDOCs (e.g., `$(cat << EOF > /etc/passwd)`). The `cat[[:space:]].*<<` pattern exists precisely to catch heredoc-based writes — stripping conflicts with this.

**Approach B (chosen): Allowlist `git commit` directly.** Git commit writes to the git object store, not arbitrary files. Layer 3 already monitors commit message quality. Simpler, no risk of hiding real writes. Also allows `git commit` at Level 1 — committing is state preservation, not a destructive write.

### Item 3: Level 1 WebFetch/WebSearch

**Approach A (rejected): New PreToolUse hook script.** Would block web tools at Level 1.

**Decision: Won't fix.** WebFetch/WebSearch are read-only operations. Level 1 is "read-only mode." Blocking reads contradicts the label. These tools are already in `permissions.allow` in `settings.json`. Blocking via hook would create a confusing contradiction.

### Item 4: Coaching context-eviction

**Approach A (rejected): Per-trigger counter re-firing.** Change `has_coaching_fired`/`add_coaching_fired` to track counter per trigger, re-fire after N calls. Too noisy — in a 200-call session, ~10 messages per trigger type. Per-trigger counters also require schema migration (array → dict).

**Approach B (chosen): Global silence counter.** Single `last_layer2_at` field tracking the tool-call count when any Layer 2 last fired. After 30 tool calls of Layer 2 silence, clear `layer2_fired` array to re-enable all triggers. Simpler state, less noisy (~5-6 re-fires per session), backward compatible (additive field). Validated by context engineering research: progressive disclosure over context bombardment (source: https://docs.claude-mem.ai/context-engineering).

### Item 6: Observation ID tracking

**Approach A (rejected): Move block above early exits, only track when state file exists.** Leaves a gap when no state file exists at all (first-ever session before any `/define` or `/discuss`).

**Approach B (chosen): Move block above early exits AND create state file if needed.** `set_last_observation_id` creates a minimal state file (`{"phase": "off", "last_observation_id": N}`) when none exists. Observation IDs are always tracked regardless of phase or state file existence.

### Item 8: bash-write-guard multi-line and wrapper bypasses

Security audit (triggered by discovering the multi-line python3 bypass in this session) revealed multiple weaknesses in `bash-write-guard.sh` WRITE_PATTERN matching:

**Findings (all HIGH severity):**

| # | Bypass | Root Cause |
|---|--------|-----------|
| 1 | Multi-line `python3 -c` splits trigger from payload across lines | `grep -qE` matches line-by-line; compound pattern requires both parts on same line |
| 2 | `eval "rm file"`, `bash -c "cp src dst"`, `sh -c "mv a b"` | No patterns for command wrappers |
| 3 | `cd /tmp && cp src dst`, `VAR=x rm file`, `command cp src dst` | `^[[:space:]]*` anchoring on `cp`/`mv`/`rm`/`install`/`patch`/`ln` only matches at line start |
| 4 | `bash << EOF` / `sh << EOF` / `python3 << EOF` heredocs | Only `cat[[:space:]].*<<` is caught |
| 5 | `$()` subshells and backtick substitutions containing writes | Write commands not at line start |

**Additional MEDIUM findings:**

| # | Gap | Impact |
|---|-----|--------|
| 6 | Missing write commands: `truncate`, `touch`, `perl -i`, `ruby -i`, `tar -x`, `unzip`, `rsync`, `sponge` | Uncovered write operations |
| 7 | `python3 -c` with `os.system`, `subprocess.run`, `shutil.copy` bypasses `.write`/`.open` check | Python can write without using `open()` |

**Approach A (rejected): Collapse multi-line commands.** Replace newlines with spaces in `CLEAN_CMD` before matching. Breaks `^`-anchored patterns (they'd never match except at command start). Also changes behavior of all patterns globally.

**Approach B (rejected): grep -z for null-delimited matching.** Same `^` anchor problem. Changes ALL pattern semantics.

**Approach B+ (chosen): Multi-layered fix.** Address each bypass class with targeted changes:

1. **Two-pass python3 check** with extended indicators — separate from WRITE_PATTERN
2. **Remove `^` anchoring** from command patterns — use word-boundary-like matching instead
3. **Add wrapper detection** — `eval`, `bash -c`, `sh -c` treated as potential writes
4. **Extend heredoc detection** — `bash <<`, `sh <<`, `python3 <<`
5. **Add missing write commands** to WRITE_PATTERN
6. **Extend python3 indicators** — `os.system`, `subprocess`, `shutil`

**Trade-offs:**
- Dropping `^` anchoring increases false positive surface. E.g., `echo "cp"` would match. Mitigated by: (a) this only applies in DEFINE/DISCUSS/COMPLETE phases where bash writes are genuinely unwanted, (b) IMPLEMENT/REVIEW phases exit early before pattern matching.
- Blocking `eval`/`bash -c` is aggressive — legitimate uses like `bash -c "echo hello"` would be blocked. Acceptable because these wrappers are rarely needed in non-IMPLEMENT phases, and they represent a fundamental bypass vector.
- Read-only `python3 -c` with `open()` for reading will be blocked. Acceptable — fail-closed is the right posture for a security guard. User can switch to IMPLEMENT phase.

## Decision

All approaches chosen above. Item 3 closed as won't-fix.

**Rationale:** Each chosen approach is the simplest correct fix for its problem. The reviewer validated Items 1 and 5 as sound, revised Items 2, 4, and 6 to simpler approaches, and recommended closing Item 3 entirely. Item 8 addresses a class of bypass vulnerabilities discovered during the session — defense-in-depth posture means these are worth fixing even though Claude Code is the "threat actor" and unlikely to deliberately construct obfuscated commands.

**Trade-offs accepted:**
- Item 2: `git commit` is unconditionally allowed, even in restrictive phases. This is acceptable because commits don't write to the working tree — they snapshot it.
- Item 4: N=30 is a guess without telemetry. May need tuning after real-world use.
- Item 6: `set_last_observation_id` can now create state files as a side effect. This is a deliberate choice — observation tracking should work unconditionally.
- Item 8: Dropping `^` anchoring and blocking `eval`/`bash -c` increases false positives for legitimate read-only bash commands in DEFINE/DISCUSS/COMPLETE. Acceptable because: (a) these phases genuinely should not have bash writes, (b) IMPLEMENT/REVIEW exit early before pattern matching, (c) fail-closed is the correct security posture.

**Risks:**
- Item 4 state schema change is additive but code must handle missing `last_layer2_at` field gracefully (default to 0).
- Item 6 restructure moves `INPUT=$(cat)` to top of `post-tool-navigator.sh` — must verify no other code path depends on stdin being unconsumed at that point (verified: only one `cat` consumer exists).
- Item 8: WRITE_PATTERN changes affect all phases simultaneously. Must verify IMPLEMENT/REVIEW still exit early (line 83-85) before any pattern matching occurs. Regression tests critical.

**Tech debt acknowledged:**
- Future opportunity: compaction-aware coaching — shorter messages on refresh vs first fire (from context engineering patterns, observation #3184).
- Future opportunity: progressive disclosure of professional standards — load phase-relevant subset instead of all.

## Detailed Design

### Item 1: COMPLETE whitelist update

**File:** `.claude/hooks/workflow-state.sh` line 20

**Change:**
```bash
# Before
COMPLETE_WRITE_WHITELIST='(\.claude/state/|docs/|^[^/]*\.md$)'

# After
COMPLETE_WRITE_WHITELIST='(\.claude/state/|\.claude/commands/|docs/|^[^/]*\.md$)'
```

Both `workflow-gate.sh` and `bash-write-guard.sh` reference `$COMPLETE_WRITE_WHITELIST` from `workflow-state.sh`. Single change propagates to both guards.

**Security:** `.claude/hooks/` remains excluded. `.claude/commands/` contains Markdown templates, not executable enforcement code.

**Tests:**
- Write to `.claude/commands/foo.md` → allowed in COMPLETE phase
- Write to `.claude/commands/foo.md` → blocked in DISCUSS phase
- Write to `.claude/hooks/foo.sh` → still blocked in COMPLETE phase

### Item 2: git commit allowlist

**File:** `.claude/hooks/bash-write-guard.sh`

**Change:** Add early-exit for `git commit` after the `source workflow-state.sh` chain check (line 58) and before the CLEAN_CMD construction (line 62):

```bash
# Allow git commit — writes to git object store, not arbitrary files.
# Commit message quality monitored by Layer 3 coaching.
# Chain guard: only allow if git commit is the sole command (no &&, ||, ;, |).
if echo "$COMMAND" | grep -qE '^[[:space:]]*git[[:space:]]+commit\b'; then
    if ! echo "$COMMAND" | grep -qE '(&&|\|\||;|\|)'; then
        exit 0
    fi
fi
```

Placed before the Level 1 autonomy check so `git commit` is allowed at all autonomy levels including Level 1. The chain guard prevents bypass via `git commit && evil_command` — same pattern used for the `source workflow-state.sh` allowlist.

**Tests:**
- `git commit -m "$(cat <<'EOF'\nfeat: something\nEOF\n)"` → allowed in DISCUSS/COMPLETE
- `git commit -m "msg" && rm -rf /` → blocked (chained command)
- `git commit -m "short msg"` → allowed (already works, regression test)
- `cat << EOF > file.txt` → still blocked
- `git commit` at Level 1 → allowed

### Item 4: Global coaching silence counter

**File:** `.claude/hooks/workflow-state.sh`

**New function:** No stdout output — mutates state file silently to avoid corrupting hook JSON output.
```bash
check_coaching_refresh() {
    if [ ! -f "$STATE_FILE" ]; then return; fi
    python3 -c "
import json, sys
filepath = sys.argv[1]
with open(filepath, 'r') as f:
    d = json.load(f)
coaching = d.get('coaching', {})
current = coaching.get('tool_calls_since_agent', 0)
last_l2 = coaching.get('last_layer2_at', 0)
if current - last_l2 >= 30:
    coaching['layer2_fired'] = []
    coaching['last_layer2_at'] = current
    d['coaching'] = coaching
    from datetime import datetime, timezone
    d['updated'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    with open(filepath, 'w') as f:
        json.dump(d, f, indent=2)
        f.write('\n')
" "$STATE_FILE" 2>/dev/null
}
```

**Modified function:** `add_coaching_fired` — also record `last_layer2_at`:
```bash
add_coaching_fired() {
    local trigger_type="$1"
    if [ ! -f "$STATE_FILE" ]; then return; fi
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    python3 -c "
import json, sys
trigger_type, ts, filepath = sys.argv[1], sys.argv[2], sys.argv[3]
with open(filepath, 'r') as f:
    d = json.load(f)
coaching = d.get('coaching', {'tool_calls_since_agent': 0, 'layer2_fired': []})
fired = coaching.get('layer2_fired', [])
fired.append(trigger_type)
coaching['layer2_fired'] = fired
coaching['last_layer2_at'] = coaching.get('tool_calls_since_agent', 0)
d['coaching'] = coaching
d['updated'] = ts
with open(filepath, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$trigger_type" "$ts" "$STATE_FILE"
}
```

**File:** `.claude/hooks/post-tool-navigator.sh`

**Change:** Inside the `if [ "$(get_message_shown)" = "true" ]` block, after `increment_coaching_counter` (line 179) and before `TRIGGER=""` (line 182), add:
```bash
# Refresh Layer 2 triggers after 30 calls of silence
check_coaching_refresh
```

**State schema:** Additive. New `last_layer2_at` integer in `coaching` object. Old state files without it default to 0 via `.get('last_layer2_at', 0)`.

**Tests:**
- Layer 2 trigger fires → `last_layer2_at` updated
- Same trigger at call +29 → does NOT re-fire
- Same trigger at call +30 → re-fires (layer2_fired cleared)
- State file without `last_layer2_at` field → defaults to 0, no crash

### Item 5: Observation extraction hardening

**File:** `tests/run-tests.sh`

**Change:** Add test for malformed `tool_response`:
- Empty `content` array → extraction returns empty string
- Non-JSON `text` block → extraction returns empty string
- Missing `id` field → extraction returns empty string

No changes to `post-tool-navigator.sh` — existing code already handles these cases.

### Item 6: Observation ID tracking regardless of phase

**File:** `.claude/hooks/post-tool-navigator.sh`

**Restructure:** Move `INPUT=$(cat)` and `TOOL_NAME` extraction to the very top (after `source workflow-state.sh`), then the observation ID block, then the early exits, then coaching logic.

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workflow-state.sh"

# Read tool input from stdin — consumed once, used by all layers
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "..." 2>/dev/null || echo "")

# ── Observation ID tracking (runs regardless of phase) ──────────
if echo "$TOOL_NAME" | grep -qE 'mcp.*(save_observation|get_observations)'; then
    # ... existing extraction logic ...
    if [[ "$OBS_ID" =~ ^[0-9]+$ ]]; then
        set_last_observation_id "$OBS_ID"
    fi
fi

# ── Early exits ─────────────────────────────────────────────────
if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

PHASE=$(get_phase)

if [ "$PHASE" = "off" ]; then
    exit 0
fi

# ... rest of coaching logic unchanged ...
```

**File:** `.claude/hooks/workflow-state.sh`

**Change:** `set_last_observation_id` creates state file if missing:

```bash
set_last_observation_id() {
    local obs_id="$1"
    mkdir -p "$STATE_DIR"
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [ ! -f "$STATE_FILE" ]; then
        python3 -c "
import json, sys
obs_id, ts, filepath = sys.argv[1], sys.argv[2], sys.argv[3]
state = {'phase': 'off', 'last_observation_id': int(obs_id) if obs_id else '', 'updated': ts}
with open(filepath, 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
" "$obs_id" "$ts" "$STATE_FILE"
        return
    fi
    # existing update-in-place logic
    python3 -c "
import json, sys
obs_id, ts, filepath = sys.argv[1], sys.argv[2], sys.argv[3]
with open(filepath, 'r') as f:
    d = json.load(f)
d['last_observation_id'] = int(obs_id) if obs_id else ''
d['updated'] = ts
with open(filepath, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$obs_id" "$ts" "$STATE_FILE"
}
```

**Tests:**
- `get_observations` with phase OFF + state file exists → ID captured
- `save_observation` with no state file → state file created with observation ID
- `save_observation` with phase OFF → ID captured
- `get_observations` with active phase → ID captured (regression)

### Item 7: README overhaul

**File:** `README.md`

**Structure (new order):**
1. Title + tagline + badges
2. Four core tools (with corrected descriptions)
3. Workflow phases table
4. Autonomy levels
5. Tools table (core tools only)
6. Optional Tools section (YubiKey, iTerm — clearly marked as opt-in, require flags)
7. Docs links
8. Install (moved down — user understands what they're installing first)
9. Sources (renamed from "Informed By")
10. Contributing
11. License

**Specific changes:**

1. Workflow Manager description → "Phase-based workflow enforcement with coaching and edit gates"

2. Install section moved after Docs

3. "Informed By" → "Sources:" with additions:
   - [claude-mem](https://github.com/thedotmack/claude-mem) — cross-session memory MCP server
   - [Context Engineering for AI Agents](https://docs.claude-mem.ai/context-engineering) — context rot, progressive disclosure, agentic memory
   - (existing Anthropic links preserved)

4. Tools table split:
   ```markdown
   ## Tools

   | Tool | What it does | Docs |
   |------|-------------|------|
   | Workflow Manager | Phase-based enforcement + coaching | [Hooks](docs/reference/hooks.md) |
   | Superpowers | Auto-activated development skills | [Guide](docs/guides/integration-guide.md) |
   | claude-mem | Cross-session memory via MCP | [Guide](docs/guides/claude-mem-guide.md) |
   | Status Line | Context, branch, phase at a glance | [Guide](docs/guides/statusline-guide.md) |

   ### Optional Tools

   Installed separately with `--iterm` or `--yubikey` flags:

   | Tool | What it does | Docs |
   |------|-------------|------|
   | YubiKey signing | FIDO2 commit signing + push auth | [Setup](tools/yubikey-setup/) |
   | iTerm Launcher | Dedicated Claude Code window | [Launcher](tools/iterm-launcher/) |
   ```

5. Verify install.sh: Confirmed — YubiKey and iTerm require `--yubikey`/`--iterm` flags (lines 19-20, 31-35). Not installed by default.

### Item 8: bash-write-guard comprehensive hardening

**File:** `.claude/hooks/bash-write-guard.sh`

Six changes to the write detection logic. All changes are in the section between COMMAND extraction and the deny message output.

#### 8a. Restructure WRITE_PATTERN — remove python3, fix anchoring, add missing commands

**Before (line 24):**
```bash
WRITE_PATTERN='(>[^&]|>>|sed[[:space:]]+-i|tee[[:space:]]|cat[[:space:]].*<<|python[3]?[[:space:]]+-c.*\.(write|open)|echo[[:space:]].*>|^[[:space:]]*cp[[:space:]]|^[[:space:]]*mv[[:space:]]|^[[:space:]]*rm[[:space:]]|^[[:space:]]*install[[:space:]]|curl[[:space:]].*-o[[:space:]]|wget[[:space:]].*-O[[:space:]]|dd[[:space:]].*of=|^[[:space:]]*patch[[:space:]]|^[[:space:]]*ln[[:space:]])'
```

**After:**
```bash
# Write pattern — detects file-writing operations
# Groups:
#   1. Redirections: >, >>, echo >
#   2. In-place editors: sed -i, perl -i, ruby -i
#   3. Stream writers: tee
#   4. Heredocs: cat <<, bash <<, sh <<, python3 <<
#   5. File operations (no ^ anchor — catches mid-command): cp, mv, rm, install, patch, ln, touch, truncate
#   6. Network downloads: curl -o, wget -O
#   7. Archive extraction: tar -x, tar x, unzip
#   8. Block devices: dd of=
#   9. Sync: rsync
WRITE_PATTERN='(>[^&]|>>|sed[[:space:]]+-i|perl[[:space:]]+-i|ruby[[:space:]]+-i|tee[[:space:]]|cat[[:space:]].*<<|bash[[:space:]].*<<|sh[[:space:]].*<<|python[3]?[[:space:]].*<<|echo[[:space:]].*>|cp[[:space:]]|mv[[:space:]]|rm[[:space:]]|install[[:space:]]|curl[[:space:]].*-o[[:space:]]|wget[[:space:]].*-O[[:space:]]|dd[[:space:]].*of=|patch[[:space:]]|ln[[:space:]]|touch[[:space:]]|truncate[[:space:]]|tar[[:space:]].*-?x|unzip[[:space:]]|rsync[[:space:]])'
```

**Key changes:**
- Removed `python[3]?[[:space:]]+-c.*\.(write|open)` — handled separately in 8b
- Removed `^[[:space:]]*` anchoring from `cp`, `mv`, `rm`, `install`, `patch`, `ln` — now matches anywhere in command
- Added `perl -i`, `ruby -i` (in-place editing like sed -i)
- Added `bash <<`, `sh <<`, `python3 <<` (heredoc-to-interpreter)
- Added `touch`, `truncate`, `tar -x`/`tar x`, `unzip`, `rsync`

#### 8b. Two-pass python3 write detection (multi-line safe)

Add after the `git commit` allowlist check and before the CLEAN_CMD construction. This replaces the python3 sub-pattern that was removed from WRITE_PATTERN.

```bash
# Multi-line python3/python write detection — separate from WRITE_PATTERN
# because the compound pattern (python -c + write indicator) can span lines.
# Extended indicators cover file I/O, subprocess, and shutil operations.
if echo "$COMMAND" | grep -qE 'python[3]?[[:space:]]+-c'; then
    if echo "$COMMAND" | grep -qiE '\.(write|open|read_text|write_text)|os\.(system|remove|rename|unlink|makedirs)|subprocess\.(run|call|Popen|check_call|check_output)|shutil\.(copy|move|rmtree|copytree)'; then
        # Check whitelist for known safe targets before blocking
        WRITE_TARGET=""  # python3 -c targets are too complex to extract — always block
        case "$PHASE" in
            define|discuss) REASON="BLOCKED: Python file write detected in ${PHASE^^} phase. Code changes are not allowed." ;;
            complete)       REASON="BLOCKED: Python file write detected in COMPLETE phase. Only documentation updates are permitted." ;;
            *)              REASON="BLOCKED: Python file write detected in $PHASE phase." ;;
        esac
        emit_deny "$REASON"
        exit 0
    fi
fi
```

**Placement:** The python3 check cannot be a standalone early-exit block because it needs to work at both Level 1 (all phases) and Level 2/3 (phase-gated). Using a standalone block placed after IMPLEMENT/REVIEW exit would miss Level 1 enforcement. Placing it before IMPLEMENT/REVIEW exit would block python in IMPLEMENT phase.

**Solution: `PYTHON_WRITE` flag.** Compute a boolean after CLEAN_CMD construction (line 62), then reference it in both the Level 1 check and the phase-gated check. DRY, correct ordering, no phase confusion.

```bash
# After CLEAN_CMD construction (line 62), detect python3 writes across lines
PYTHON_WRITE=false
if echo "$COMMAND" | grep -qE 'python[3]?[[:space:]]+-c'; then
    if echo "$COMMAND" | grep -qiE '\.(write|open|read_text|write_text)|os\.(system|remove|rename|unlink|makedirs)|subprocess\.(run|call|Popen|check_call|check_output)|shutil\.(copy|move|rmtree|copytree)'; then
        PYTHON_WRITE=true
    fi
fi
```

Then in the Level 1 check (line 70):
```bash
if [ "$AUTONOMY_LEVEL" = "1" ]; then
    if echo "$CLEAN_CMD" | grep -qE "$WRITE_PATTERN" || [ "$PYTHON_WRITE" = "true" ]; then
        emit_deny "BLOCKED: ▶ Level 1 (supervised) — read-only mode. No Bash write operations allowed."
        exit 0
    fi
    exit 0
fi
```

And in the phase-gated check (line 94):
```bash
if echo "$CLEAN_CMD" | grep -qE "$WRITE_PATTERN" || [ "$PYTHON_WRITE" = "true" ]; then
    # ... whitelist check and deny ...
fi
```

**Known limitation:** `git commit -m "$(python3 -c 'open(\"f\",\"w\").write(\"x\")')"` bypasses because the git commit allowlist (Item 2) exits before PYTHON_WRITE is computed. Acceptable — Claude wouldn't generate this, and the subshell executes at shell evaluation time, not within git commit.

#### 8c. Command wrapper detection

Add `eval`, `bash -c`, `sh -c` as write indicators. These can wrap arbitrary commands, making pattern-based detection of the inner command unreliable. Block them in restrictive phases.

Add to WRITE_PATTERN:
```
eval[[:space:]]|bash[[:space:]]+-c|sh[[:space:]]+-c
```

**Updated WRITE_PATTERN (final):**
```bash
WRITE_PATTERN='(>[^&]|>>|sed[[:space:]]+-i|perl[[:space:]]+-i|ruby[[:space:]]+-i|tee[[:space:]]|cat[[:space:]].*<<|bash[[:space:]].*<<|sh[[:space:]].*<<|python[3]?[[:space:]].*<<|echo[[:space:]].*>|cp[[:space:]]|mv[[:space:]]|rm[[:space:]]|install[[:space:]]|curl[[:space:]].*-o[[:space:]]|wget[[:space:]].*-O[[:space:]]|dd[[:space:]].*of=|patch[[:space:]]|ln[[:space:]]|touch[[:space:]]|truncate[[:space:]]|tar[[:space:]].*-?x|unzip[[:space:]]|rsync[[:space:]]|eval[[:space:]]|bash[[:space:]]+-c|sh[[:space:]]+-c)'
```

#### 8d. Write target extraction update

The write target extractor (lines 98-112) currently handles redirects and `cp`/`mv`/`install` last argument. With `^` anchoring removed, the extractor still works — it matches on redirect targets or last arguments regardless of position. No change needed to the extractor itself.

However, the newly added commands (`touch`, `truncate`, `rsync`, `tar`, `unzip`, `eval`, `bash -c`, `sh -c`) have no target extraction. This means `WRITE_TARGET` is empty for them, so whitelist checking is skipped and the write is **always blocked** (fail-closed). This is the correct behavior — these commands are too complex for path extraction, and blocking them entirely in restrictive phases is safe.

#### 8e. Summary of file changes

All changes in `.claude/hooks/bash-write-guard.sh`:

1. **Line 24:** Replace WRITE_PATTERN with expanded version (8a + 8c)
2. **After line 58 (chain check):** Add git commit allowlist (Item 2)
3. **After line 62 (CLEAN_CMD):** Add `PYTHON_WRITE` detection flag (8b)
4. **Line 70:** Update Level 1 check to include `|| [ "$PYTHON_WRITE" = "true" ]`
5. **Line 94:** Update phase-gated check to include `|| [ "$PYTHON_WRITE" = "true" ]`

#### 8f. Tests

**Multi-line python3 bypasses:**
- `python3 -c "\nimport json\nwith open('f','w') as fh:\n  fh.write('x')\n"` → blocked in DISCUSS
- `python3 -c "\nimport shutil\nshutil.copy('a','b')\n"` → blocked in DISCUSS
- `python3 -c "\nimport subprocess\nsubprocess.run(['cp','a','b'])\n"` → blocked in DISCUSS
- `python3 -c "\nimport os\nos.system('rm file')\n"` → blocked in DISCUSS
- `python3 -c "print('hello')"` → allowed (no write indicators)
- `python3 -c "\nwith open('f') as fh:\n  print(fh.read())\n"` → blocked (false positive, acceptable — fail-closed)

**Wrapper bypasses:**
- `eval "echo data > file.txt"` → blocked in DISCUSS
- `bash -c "cp src dst"` → blocked in DISCUSS
- `sh -c "mv a b"` → blocked in DISCUSS
- `eval "echo hello"` → blocked (false positive, acceptable)

**Anchoring bypasses:**
- `cd /tmp && cp src dst` → blocked in DISCUSS (cp no longer needs `^`)
- `VAR=x rm file` → blocked in DISCUSS
- `command cp src dst` → blocked in DISCUSS
- `true && mv a b` → blocked in DISCUSS

**Heredoc variants:**
- `bash << EOF` → blocked in DISCUSS
- `sh << 'EOF'` → blocked in DISCUSS
- `python3 << EOF` → blocked in DISCUSS
- `cat << EOF > file` → still blocked (regression)

**Missing commands:**
- `touch newfile.txt` → blocked in DISCUSS
- `truncate -s 0 file` → blocked in DISCUSS
- `perl -i -pe 's/old/new/' file` → blocked in DISCUSS
- `ruby -i -pe 'gsub(/old/,"new")' file` → blocked in DISCUSS
- `tar xf archive.tar` → blocked in DISCUSS
- `unzip archive.zip` → blocked in DISCUSS
- `rsync -av src/ dst/` → blocked in DISCUSS

**Regression — IMPLEMENT/REVIEW unaffected:**
- All above commands → allowed in IMPLEMENT phase (early exit at line 83-85)
- All above commands → allowed in REVIEW phase

**Regression — Level 1 catches new patterns:**
- `python3 -c "\nwith open('f','w')..."` → blocked at Level 1
- `python3 -c "\nwith open('f','w')..."` in IMPLEMENT + Level 1 → blocked (Level 1 runs before IMPLEMENT exit)
- `eval "rm file"` → blocked at Level 1
- `bash -c "cp a b"` → blocked at Level 1

**Whitelist still works:**
- `cp file.md .claude/state/backup.json` → allowed in COMPLETE (`.claude/state/` whitelisted)
- `echo data > docs/notes.md` → allowed in COMPLETE (`docs/` whitelisted)

## Future Opportunities (out of scope)

From context engineering research (observation #3184, source: https://docs.claude-mem.ai/context-engineering):

- **Compaction-aware coaching** — shorter refreshed messages vs verbose first-fire messages
- **Progressive disclosure of professional standards** — load phase-relevant subset, not full document
- **JIT tool descriptions** — load phase-specific tool guidance only when needed

## Test Plan

| Item | New Tests | Regression Tests |
|------|-----------|-----------------|
| 1. Whitelist | Write to `.claude/commands/` allowed in COMPLETE, blocked in DISCUSS, `.claude/hooks/` still blocked | Existing whitelist tests |
| 2. git commit | HEREDOC-style commit allowed, chained commit blocked, Level 1 commit allowed | Existing bash guard tests |
| 4. Silence counter | Refresh at 30 calls, no refresh at 29, backward compat with missing field | Existing coaching tests |
| 5. Extraction | Malformed response graceful degradation (3 variants) | Existing observation ID tests |
| 6. OFF tracking | Phase OFF + state file, no state file, active phase | Existing observation tests |
| 7. README | Manual review | N/A |
| 8. Write guard | Multi-line python3 (6 tests), wrappers (4 tests), anchoring (4 tests), heredocs (4 tests), missing commands (7 tests), Level 1 (4 tests), whitelist (2 tests) | IMPLEMENT/REVIEW still allows all commands, existing pattern tests pass |
