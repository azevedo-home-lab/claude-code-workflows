# Implementation Plan: Tech Debt Cleanup + GitHub Issue Sync

**Decision Record:** `docs/plans/2026-03-26-tech-debt-github-sync-decisions.md`
**Approach:** C — GitHub issues with OSC 8 graceful degradation

## Stream A: Tech Debt Fixes (6 items)

### Step 1: Fix git commit chain detection in bash-write-guard.sh

**File:** `plugin/scripts/bash-write-guard.sh` lines 81-93

**Problem:** The regex `^[[:space:]]*(git|...)` only matches when `git commit` is the FIRST command. When chained as `git add X && git commit -m "msg"`, the line starts with `git add`, not `git commit`, so the commit-allow block is never entered. The command then falls through to the general write-pattern detection which blocks it.

**Fix:** The grep checks if the command starts with `git commit`. For `git add && git commit`, the initial grep fails because it starts with `git add`. Add a second check: if the command contains `git commit` AND the only "dangerous" commands in the chain are `git add`/`git status`/`git diff` (safe read-only git ops), allow it.

After line 93, add a new block:
```bash
# Allow safe git chains: git add ... && git commit ...
# Only permit when ALL commands before git commit are safe git read/stage ops
if echo "$COMMAND" | grep -qE '(git|/usr/bin/git|/usr/local/bin/git)[[:space:]]+commit\b'; then
    # Split on chain operators, check each segment before the commit
    SAFE=true
    while IFS= read -r segment; do
        segment=$(echo "$segment" | sed 's/^[[:space:]]*//')
        # Skip the git commit segment itself
        echo "$segment" | grep -qE '^(git|/usr/bin/git|/usr/local/bin/git)[[:space:]]+commit\b' && continue
        # Allow: git add, git status, git diff, git stash, echo, true
        if ! echo "$segment" | grep -qE '^(git|/usr/bin/git|/usr/local/bin/git)[[:space:]]+(add|status|diff|stash|log|show)\b' && \
           ! echo "$segment" | grep -qE '^(echo|true|printf)\b'; then
            SAFE=false
            break
        fi
    done < <(echo "$COMMAND" | sed 's/&&/\n/g; s/||/\n/g; s/;/\n/g')
    if [ "$SAFE" = true ]; then
        if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] Bash ALLOW: safe git chain with commit" >&2; fi
        exit 0
    fi
fi
```

**Tests:** Add tests for:
- `git add file.txt && git commit -m "msg"` → ALLOW
- `git add -A && git commit -m "msg"` → ALLOW
- `git status && git add . && git commit -m "msg"` → ALLOW
- `git commit -m "msg" && rm -rf /` → DENY (existing behavior)
- `echo hi && git commit -m "msg"` → ALLOW (echo is safe)

### Step 2: Fix printf '%b' newline injection in statusline

**File:** `plugin/statusline/statusline.sh` line 211

**Problem:** `printf '%b'` interprets escape sequences in the output variable, including `\n`, `\t`, `\\`. If any field from CC session JSON contains these sequences, they'd be interpreted.

**Fix:** Change `printf '%b' "$OUTPUT"` to `echo -e "$OUTPUT"`. Actually both have the same issue. The real fix is to use `printf '%s'` for the final output and pre-process escape sequences ourselves. But since we intentionally use ANSI escape codes in `$OUTPUT`, we need `%b`.

Better fix: sanitize the untrusted inputs (CWD, WORKTREE_NAME, WORKTREE_BRANCH) by escaping backslashes before they're interpolated into OUTPUT:
```bash
SHORT_CWD=$(echo "$SHORT_CWD" | sed 's/\\/\\\\/g')
```

Apply to: `SHORT_CWD`, `WORKTREE_NAME`, `WORKTREE_BRANCH`, `BRANCH`.

**Tests:** Add test with a CWD containing `\n` in the JSON input.

### Step 3: Fix used_percentage bounds check in statusline

**File:** `plugin/statusline/statusline.sh` lines 39-61

**Fix:** After parsing, clamp USED_PCT:
```bash
# Bounds-check percentage
[ "$USED_PCT" -lt 0 ] 2>/dev/null && USED_PCT=0
[ "$USED_PCT" -gt 100 ] 2>/dev/null && USED_PCT=100
```

**Tests:** Add tests for USED_PCT=0, USED_PCT=100, USED_PCT=150 (clamped to 100), USED_PCT=-5 (clamped to 0).

### Step 4: Add `pushed` to COMPLETE exit gate

**File:** `plugin/scripts/workflow-state.sh` line 294

**Fix:** Add `"pushed"` to the milestone list:
```bash
missing=$(_check_milestones "completion" "plan_validated" "outcomes_validated" "results_presented" "docs_checked" "committed" "pushed" "tech_debt_audited" "handover_saved")
```

**Tests:** Add test that COMPLETE exit gate fails when `pushed` is not set.

### Step 5: Deduplicate _plugin_version in test suite

**File:** `tests/run-tests.sh` ~line 2375

**Fix:** Replace the duplicate function with a source of the statusline script's function. Since sourcing the whole statusline.sh would execute it, instead extract `_plugin_version` into a shared file: `plugin/scripts/statusline-utils.sh`. Source it from both `statusline.sh` and `run-tests.sh`.

Actually simpler: the test suite only uses `_plugin_version` in the statusline tests section. Keep the duplication but add a comment with the canonical source and a test that verifies the two implementations produce identical output for the same input. This avoids creating a new file for a single function.

**Fix (simpler):** Add a test that sources both functions and asserts they produce the same output for the plugin cache directory. Add a comment `# SYNC: must match plugin/statusline/statusline.sh:_plugin_version`.

**Tests:** Comparison test between the two implementations.

### Step 6: Add jq filter security comment (no code change)

**File:** `plugin/scripts/workflow-state.sh` lines 43-45

The security note already exists and is accurate. The mitigation is architectural (all callers are internal). No code change needed — this item is resolved by the existing documentation. Skip.

## Stream B: GitHub Issue Sync + Statusline Links

### Step 7: Add issue mapping state helpers

**File:** `plugin/scripts/workflow-state.sh`

Add new state helpers for the observation→GitHub issue mapping:
```bash
# Store mapping: observation_id → github_issue_url
set_issue_mapping() {
    local obs_id="$1" issue_url="$2"
    _update_state '.issue_mappings = ((.issue_mappings // {}) + {($obs_id): $url})' \
        --arg obs_id "$obs_id" --arg url "$issue_url"
}

get_issue_mappings() {
    if [ ! -f "$STATE_FILE" ]; then echo "{}"; return; fi
    jq -r '.issue_mappings // {} | to_entries | map("\(.key)=\(.value)") | join("\n")' "$STATE_FILE" 2>/dev/null
}

get_issue_url() {
    local obs_id="$1"
    if [ ! -f "$STATE_FILE" ]; then echo ""; return; fi
    jq -r --arg id "$obs_id" '.issue_mappings[$id] // ""' "$STATE_FILE" 2>/dev/null
}
```

Add to `workflow-cmd.sh` allowlist: `set_issue_mapping`, `get_issue_mappings`, `get_issue_url`.

Preserve `issue_mappings` across phase transitions (same as `tracked_observations`).

**Tests:** set/get round-trip, get nonexistent, preserve across phase transition.

### Step 8: Add GitHub issue creation helper

**File:** `plugin/scripts/workflow-cmd.sh` (new function)

```bash
create_github_issue() {
    local title="$1" body="$2" labels="${3:-}"
    # Check gh is available
    if ! command -v gh &>/dev/null; then
        echo "ERROR: gh CLI not found" >&2; return 1
    fi
    # Check gh is authenticated
    if ! gh auth status &>/dev/null 2>&1; then
        echo "ERROR: gh not authenticated" >&2; return 1
    fi
    local label_args=""
    [ -n "$labels" ] && label_args="--label $labels"
    gh issue create --title "$title" --body "$body" $label_args 2>&1
}
```

**Tests:** Test with gh unavailable (mock), test output parsing.

### Step 9: Update complete.md Step 7 for issue creation

**File:** `plugin/commands/complete.md` around line 341

After the tech debt table is presented, add:

```markdown
#### GitHub Issue Creation (opt-in)

After the tech debt review gate passes, offer to create GitHub issues for tech debt items:

- **auto (▶▶▶):** Create issues for all High/Medium priority items without prompting. Skip Low items unless user configured otherwise.
- **ask (▶▶):** Present each item and ask "Create GitHub issue? (y/n)"
- **off (▶):** Present each item individually, wait for explicit yes/no.

For each issue created:
1. Run: `gh issue create --title "[Tech Debt] <item>" --body "<details from table>" --label "tech-debt"`
2. Capture the issue URL from output
3. Store mapping: `.claude/hooks/workflow-cmd.sh set_issue_mapping "<obs_id>" "<issue_url>"`
4. Report: "Created issue #N: <url>"

If `gh` is not available or not authenticated, skip gracefully: "Skipping GitHub issue creation — gh CLI not available/authenticated."
```

### Step 10: Update statusline for OSC 8 hyperlinks

**File:** `plugin/statusline/statusline.sh` lines 202-205

Replace the tracked observations rendering with OSC 8 links:

```bash
# Tracked observations with OSC 8 hyperlinks (graceful degradation)
CM_TRACKED_IDS=$(jq -r '.tracked_observations // [] | .[]' "$WM_STATE_FILE" 2>/dev/null)
if [ -n "$CM_TRACKED_IDS" ]; then
  LINKS=""
  for OBS_ID in $CM_TRACKED_IDS; do
    [ -n "$LINKS" ] && LINKS+=","
    # Check for GitHub issue URL mapping
    ISSUE_URL=$(jq -r --arg id "$OBS_ID" '.issue_mappings[$id] // ""' "$WM_STATE_FILE" 2>/dev/null)
    if [ -n "$ISSUE_URL" ]; then
      # OSC 8 hyperlink: clickable in VS Code, plain text elsewhere
      LINKS+="\033]8;;${ISSUE_URL}\a#${OBS_ID}\033]8;;\a"
    else
      LINKS+="#${OBS_ID}"
    fi
  done
  CM_SUFFIX+=" ${DIM}Open:[${LINKS}]${RESET}"
fi
```

**Tests:**
- Tracked obs with no issue mapping → plain `#1234`
- Tracked obs with issue mapping → contains OSC 8 escape sequence
- Mixed: some with mapping, some without

### Step 11: Version bump and tests

- Bump version in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` from 1.8.0 → 1.9.0 (minor — new feature)
- Run full test suite, verify all pass
- Commit, push

## Commit Strategy

- **Commit 1:** Stream A tech debt fixes (steps 1-5)
- **Commit 2:** Stream B state helpers + issue creation (steps 7-8)
- **Commit 3:** Stream B complete.md + statusline updates (steps 9-10)
- **Commit 4:** Version bump (step 11)

Or fewer commits if the changes are small enough to be cohesive.
