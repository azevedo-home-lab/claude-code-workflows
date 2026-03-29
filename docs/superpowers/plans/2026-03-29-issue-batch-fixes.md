# Issue Batch Fixes (#21, #22, #23, #11) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 4 independent issues — jq injection (#21), path traversal (#21), lock stat DoS (#22), missing reconciliation milestone (#23), and stale statusLine on migration (#11).

**Architecture:** Each fix is a self-contained change to 1-2 files. No new patterns introduced. All fixes harden existing code by closing known gaps.

**Tech Stack:** Bash, jq

**GitHub Issues:** #21, #22, #23, #11

---

## File Map

| File | Change | Issue |
|------|--------|-------|
| `cl-plugin/scripts/evolve.sh` | Remove dead `--update` flag; fix lock stat fallback | #21a, #22 |
| `plugin/scripts/workflow-gate.sh` | Replace literal `..` check with `realpath` canonicalization | #21b |
| `plugin/scripts/workflow-state.sh` | Add `issues_reconciled` to `reset_completion_status` and exit gate | #23 |
| `plugin/commands/complete.md` | Add `issues_reconciled` milestone set after reconciliation | #23 |
| `install.sh` | Add `statusLine` removal from project settings during migration | #11 |

---

### Task 1: Remove `--update` jq injection vector (#21a)

**Files:**
- Modify: `cl-plugin/scripts/evolve.sh:47-50` (remove `update_state` function)
- Modify: `cl-plugin/scripts/evolve.sh:101-103` (update `reset_counter` to use inline jq)
- Modify: `cl-plugin/scripts/evolve.sh:124-126` (remove `--update` case)
- Modify: `cl-plugin/scripts/evolve.sh:140` (remove `--update` from usage string)

**Context:** The `--update` flag passes raw jq expressions to `jq "$updates"` with no validation. The architecture doc (`cl-plugin/docs/architecture.md:55`) already notes this was bypassed — evolve.md Step 5 writes state directly via `jq --argjson`. No runtime code calls `--update`. The `update_state` function is also used by `reset_counter`, which needs to be updated to use inline jq instead.

- [ ] **Step 1: Remove `update_state` function and `--update` CLI case**

Replace the `update_state` function (lines 47-50) with nothing. Update `reset_counter` (lines 101-103) to use inline jq directly:

```bash
reset_counter() {
  jq '.completion_count = 0' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
}
```

Remove the `--update` case from the CLI dispatch (lines 124-126):

```bash
  --update)
    update_state "${2:-.}"
    ;;
```

Update the usage string (line 140) to remove `--update <jq-expr>`:

```bash
echo "Usage: evolve.sh --trigger=complete | --init | --read <field> | --lock | --unlock | --reset-counter | --check-threshold" >&2
```

- [ ] **Step 2: Verify evolve.sh still works**

Run:
```bash
bash cl-plugin/scripts/evolve.sh --init
bash cl-plugin/scripts/evolve.sh --read version
bash cl-plugin/scripts/evolve.sh --reset-counter
bash cl-plugin/scripts/evolve.sh --read completion_count
```

Expected: version prints `0.1.0`, completion_count prints `0` after reset.

- [ ] **Step 3: Verify `--update` is rejected**

Run:
```bash
bash cl-plugin/scripts/evolve.sh --update '.foo = "bar"' 2>&1
```

Expected: Prints usage message and exits with code 1.

- [ ] **Step 4: Commit**

```bash
git add cl-plugin/scripts/evolve.sh
git commit -m "security: remove dead --update jq injection vector from evolve.sh (#21)"
```

---

### Task 2: Fix path traversal check with realpath (#21b)

**Files:**
- Modify: `plugin/scripts/workflow-gate.sh:39-42`

**Context:** The current check uses `grep -qE '\.\.'` which only catches literal `..`. We need to canonicalize the path to catch traversal via symlinks or encoded components. If the canonicalized path doesn't start with the project root, it's a traversal attempt. macOS `realpath` doesn't support `-m` (no-exist mode), so we use `python3` which is already a dependency (used in `install.sh`).

- [ ] **Step 1: Replace literal `..` check with python3-based path canonicalization**

Replace lines 39-42:

```bash
# Reject path traversal attempts
if [ -n "$FILE_PATH" ] && echo "$FILE_PATH" | grep -qE '\.\.'; then
    FILE_PATH=""  # Force deny — traversal paths are never whitelisted
fi
```

With:

```bash
# Reject path traversal attempts — canonicalize to catch encoded/symlinked traversal
# Uses python3 (already a dependency) because macOS realpath lacks -m (no-exist) flag
if [ -n "$FILE_PATH" ]; then
    CANONICAL_PATH=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$FILE_PATH" 2>/dev/null || echo "")
    CANONICAL_ROOT=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$PROJECT_ROOT" 2>/dev/null || echo "$PROJECT_ROOT")
    if [ -z "$CANONICAL_PATH" ] || [ "${CANONICAL_PATH#"$CANONICAL_ROOT"/}" = "$CANONICAL_PATH" ]; then
        FILE_PATH=""  # Force deny — path resolves outside project root
    fi
fi
```

Note: `os.path.realpath()` handles non-existent paths (returns the resolved absolute path without requiring existence). The prefix-strip check `${CANONICAL_PATH#"$CANONICAL_ROOT"/} = $CANONICAL_PATH` is true when the prefix didn't match — meaning the path is outside the project root.

- [ ] **Step 2: Verify traversal is blocked**

Test by running the hook manually with crafted input. The script requires a workflow state file with an active phase (it exits early if phase is `off`), so ensure the WFM is in an active phase first:

```bash
export CLAUDE_PROJECT_DIR="$(pwd)"
echo '{"tool_input":{"file_path":"'"$(pwd)"'/../../../etc/passwd"}}' | bash plugin/scripts/workflow-gate.sh
```

Expected: The script should exit 0 (deny emitted or path forced empty). No "ALLOW" in debug output.

- [ ] **Step 3: Verify normal paths still work**

```bash
export CLAUDE_PROJECT_DIR="$(pwd)"
echo '{"tool_input":{"file_path":"'"$(pwd)"'/docs/superpowers/plans/test.md"}}' | bash plugin/scripts/workflow-gate.sh
```

Expected: Exits 0 with no deny (path is within project root and on whitelist for discuss phase).

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/workflow-gate.sh
git commit -m "security: use realpath canonicalization for path traversal check (#21)"
```

---

### Task 3: Fix lock stat fallback causing stuck pipeline (#22)

**Files:**
- Modify: `cl-plugin/scripts/evolve.sh:58-66`

**Context:** When `stat` fails on the lock file, the fallback `date +%s` makes `lock_age=0`, which the `< 600` check treats as "fresh lock" — blocking the pipeline permanently. The fix: separate stat into its own variable with explicit error handling.

- [ ] **Step 1: Replace silent stat fallback with explicit error handler**

Replace lines 58-66 in `acquire_lock`:

```bash
  if [ -f "$LOCK_FILE" ]; then
    local lock_age
    lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK_FILE" 2>/dev/null || stat -c %Y "$LOCK_FILE" 2>/dev/null || date +%s) ))
    if [ "$lock_age" -lt 600 ]; then
      echo "CL: Pipeline already running (lock is ${lock_age}s old). Exiting." >&2
      exit 0
    fi
    echo "CL: Stale lock found (${lock_age}s old). Removing." >&2
    rm -f "$LOCK_FILE"
  fi
```

With:

```bash
  if [ -f "$LOCK_FILE" ]; then
    local mtime lock_age
    mtime=$(stat -f %m "$LOCK_FILE" 2>/dev/null || stat -c %Y "$LOCK_FILE" 2>/dev/null) || {
      echo "CL: ERROR — cannot stat lock file. Remove manually: rm $LOCK_FILE" >&2
      exit 1
    }
    lock_age=$(( $(date +%s) - mtime ))
    if [ "$lock_age" -lt 600 ]; then
      echo "CL: Pipeline already running (lock is ${lock_age}s old). Exiting." >&2
      exit 0
    fi
    echo "CL: Stale lock found (${lock_age}s old). Removing." >&2
    rm -f "$LOCK_FILE"
  fi
```

- [ ] **Step 2: Verify lock acquisition works normally**

```bash
bash cl-plugin/scripts/evolve.sh --init
bash cl-plugin/scripts/evolve.sh --lock
ls -la .claude/state/cl-state.lock
bash cl-plugin/scripts/evolve.sh --unlock
```

Expected: Lock created with PID, then removed.

- [ ] **Step 3: Verify stale lock is cleaned up**

```bash
bash cl-plugin/scripts/evolve.sh --init
touch -t 202501010000 .claude/state/cl-state.lock  # Set mtime to old date
bash cl-plugin/scripts/evolve.sh --lock 2>&1
```

Expected: "CL: Stale lock found" message, lock replaced.

- [ ] **Step 4: Commit**

```bash
git add cl-plugin/scripts/evolve.sh
git commit -m "fix: explicit error on lock stat failure instead of silent DoS (#22)"
```

---

### Task 4: Add `issues_reconciled` milestone to COMPLETE gate (#23)

**Files:**
- Modify: `plugin/scripts/workflow-state.sh:637` (add to `reset_completion_status`)
- Modify: `plugin/scripts/workflow-state.sh:319` (add to exit gate check)
- Modify: `plugin/commands/complete.md:369` (add milestone set after reconciliation summary)

**Context:** The COMPLETE exit gate checks 8 milestones but not `issues_reconciled`. Step 7 includes GitHub Issue Reconciliation but there's no enforcement that it ran. The milestone should be set after the reconciliation summary is presented (line 369 in complete.md).

- [ ] **Step 1: Add `issues_reconciled` to `reset_completion_status`**

In `plugin/scripts/workflow-state.sh`, line 637, change:

```bash
reset_completion_status() { _reset_section "completion" "plan_validated" "outcomes_validated" "results_presented" "docs_checked" "committed" "pushed" "tech_debt_audited" "handover_saved"; }
```

To:

```bash
reset_completion_status() { _reset_section "completion" "plan_validated" "outcomes_validated" "results_presented" "docs_checked" "committed" "pushed" "issues_reconciled" "tech_debt_audited" "handover_saved"; }
```

Note: `issues_reconciled` goes before `tech_debt_audited` to match the pipeline step order (reconciliation happens during Step 7, before the tech debt review gate).

- [ ] **Step 2: Add `issues_reconciled` to exit gate check**

In `plugin/scripts/workflow-state.sh`, line 319, change:

```bash
missing=$(_check_milestones "completion" "plan_validated" "outcomes_validated" "results_presented" "docs_checked" "committed" "pushed" "tech_debt_audited" "handover_saved")
```

To:

```bash
missing=$(_check_milestones "completion" "plan_validated" "outcomes_validated" "results_presented" "docs_checked" "committed" "pushed" "issues_reconciled" "tech_debt_audited" "handover_saved")
```

- [ ] **Step 3: Add milestone set in complete.md after reconciliation**

In `plugin/commands/complete.md`, after line 369 (the reconciliation summary line), add:

```markdown

Mark reconciliation milestone:
```bash
.claude/hooks/workflow-cmd.sh set_completion_field "issues_reconciled" "true"
```
```

This goes after: `Present summary: "GitHub reconciliation: [N issues closed..."` and before `#### Collect and Categorize Findings`.

- [ ] **Step 4: Verify milestone is in reset and gate**

```bash
grep -c "issues_reconciled" plugin/scripts/workflow-state.sh
```

Expected: At least 2 matches (reset + gate).

- [ ] **Step 5: Commit**

```bash
git add plugin/scripts/workflow-state.sh plugin/commands/complete.md
git commit -m "fix: add issues_reconciled milestone to COMPLETE exit gate (#23)"
```

---

### Task 5: Remove stale statusLine during migration (#11)

**Files:**
- Modify: `install.sh:62-84`

**Context:** The migration script removes `hooks` from project `.claude/settings.json` but not `statusLine`. If a previous installation wrote a `statusLine` entry pointing to a now-deleted file, it persists and overrides the plugin's global statusline. The fix: extend the existing Python cleanup to also delete `statusLine`.

- [ ] **Step 1: Add statusLine removal to the Python cleanup block**

In `install.sh`, replace the Python block (lines 64-79):

```python
        python3 -c "
import json, sys

settings_path = sys.argv[1]
with open(settings_path) as f:
    settings = json.load(f)

if 'hooks' in settings:
    del settings['hooks']
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
    print('removed')
else:
    print('none')
" "$OLD_SETTINGS"
```

With:

```python
        python3 -c "
import json, sys

settings_path = sys.argv[1]
with open(settings_path) as f:
    settings = json.load(f)

changed = False
for key in ['hooks', 'statusLine']:
    if key in settings:
        del settings[key]
        changed = True

if changed:
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
    print('removed')
else:
    print('none')
" "$OLD_SETTINGS"
```

- [ ] **Step 2: Update the success message**

In `install.sh`, line 82, change:

```bash
            ok "Removed hook entries from .claude/settings.json"
```

To:

```bash
            ok "Removed stale entries (hooks, statusLine) from .claude/settings.json"
```

- [ ] **Step 3: Verify with a test settings file**

```bash
mkdir -p /tmp/test-migration/.claude
echo '{"hooks":{"PreToolUse":[]},"statusLine":"sessions/statusline.js","other":"keep"}' > /tmp/test-migration/.claude/settings.json
mkdir -p /tmp/test-migration/.claude/hooks
touch /tmp/test-migration/.claude/hooks/workflow-gate.sh
bash install.sh /tmp/test-migration
cat /tmp/test-migration/.claude/settings.json
rm -rf /tmp/test-migration
```

Expected: Output should show `{"other": "keep"}` — both `hooks` and `statusLine` removed, `other` preserved.

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "fix: remove stale statusLine from project settings during migration (#11)"
```
