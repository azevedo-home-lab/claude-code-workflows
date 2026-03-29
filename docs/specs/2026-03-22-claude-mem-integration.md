# Claude-Mem Integration Improvements Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce project-scoped claude-mem usage via GitHub repo name and show last observation ID in the status line.

**Architecture:** Commands instruct agents to derive the repo name from `git remote` and pass it as `project`. A Layer 3 coaching check catches `save_observation` calls missing the `project` field. The PostToolUse hook captures observation IDs from `tool_response` and writes to `workflow.json`. The status line reads and displays the ID.

**Tech Stack:** Bash, Python 3 (inline in hooks), jq (statusline), Claude Code hooks API

**Spec:** `docs/superpowers/specs/2026-03-22-claude-mem-integration.md`

---

### Task 1: Enforce `project` parameter in commands

**Files:**
- Modify: `.claude/commands/define.md:34`
- Modify: `.claude/commands/discuss.md:43`
- Modify: `.claude/commands/complete.md:235`

- [ ] **Step 1: Add project derivation instruction to `define.md`**

Find line 34 (`2. **Context gatherer** — Search project history for prior discussions, related decisions, failed attempts. Tools: claude-mem search, git log, Grep.`).

Replace the agent description to include the project scoping instruction. Change from:

```
2. **Context gatherer** — Search project history for prior discussions, related decisions, failed attempts. Tools: claude-mem search, git log, Grep.
```

To:

```
2. **Context gatherer** — Search project history for prior discussions, related decisions, failed attempts. Tools: claude-mem search, git log, Grep. **Always pass `project` parameter to claude-mem tools.** Derive repo name: `git remote get-url origin 2>/dev/null | sed 's/.*[:/]\([^/]*\)\.git$/\1/' | sed 's/.*[:/]\([^/]*\)$/\1/'`
```

- [ ] **Step 2: Add project derivation instruction to `discuss.md`**

Find line 43 (`3. **Prior art scanner** — Search project history and codebase for previous related implementations or decisions. Tools: claude-mem search, git log, Grep, Read.`).

Change to:

```
3. **Prior art scanner** — Search project history and codebase for previous related implementations or decisions. Tools: claude-mem search, git log, Grep, Read. **Always pass `project` parameter to claude-mem tools.** Derive repo name: `git remote get-url origin 2>/dev/null | sed 's/.*[:/]\([^/]*\)\.git$/\1/' | sed 's/.*[:/]\([^/]*\)$/\1/'`
```

- [ ] **Step 3: Make `complete.md` project instruction explicit**

Find line 235 (`Save via the \`save_observation\` MCP tool. Set \`project\` to match the current project.`).

Change to:

```
Save via the `save_observation` MCP tool. **Set `project` to the GitHub repo name.** Derive it: `git remote get-url origin 2>/dev/null | sed 's/.*[:/]\([^/]*\)\.git$/\1/' | sed 's/.*[:/]\([^/]*\)$/\1/'`
```

- [ ] **Step 4: Commit**

```bash
git add .claude/commands/define.md .claude/commands/discuss.md .claude/commands/complete.md
git commit -m "feat: enforce GitHub repo name as claude-mem project parameter in all commands"
```

---

### Task 2: Layer 3 coaching check — `save_observation` missing `project`

**Files:**
- Modify: `.claude/hooks/post-tool-navigator.sh:322-334` (add sibling check near existing check 4)
- Test: `tests/run-tests.sh` (add to post-tool-navigator.sh suite)

- [ ] **Step 1: Write failing tests**

Add after the existing post-tool-navigator coaching tests (find the autonomy coaching tests, add after them):

```bash
# --- Claude-mem project enforcement ---

# Test: coaching fires when save_observation has no project field
setup_test_project
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
OUTPUT=$(echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__save_observation","tool_input":{"text":"some observation"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "without project" "coaching fires when save_observation missing project field"

# Test: coaching does NOT fire when save_observation has project field
setup_test_project
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
OUTPUT=$(echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__save_observation","tool_input":{"text":"some observation","project":"claude-code-workflows"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_not_contains "$OUTPUT" "without project" "no coaching when save_observation has project field"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`

- [ ] **Step 3: Add Layer 3 check for missing project**

In `post-tool-navigator.sh`, after the existing check 4 (minimal handover, around line 334), add:

```bash
# Check 4b: save_observation without project field (any phase)
if echo "$TOOL_NAME" | grep -qE 'mcp.*save_observation'; then
    HAS_PROJECT=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
project = ti.get('project', '')
print('true' if project else 'false')
" 2>/dev/null || echo "false")
    if [ "$HAS_PROJECT" = "false" ]; then
        PROJ_MSG="[Workflow Coach — ${PHASE^^}] save_observation called without project parameter. Always pass project to scope observations. Derive repo name: git remote get-url origin 2>/dev/null | sed 's/.*[:/]\([^/]*\)\.git\$/\1/' | sed 's/.*[:/]\([^/]*\)\$/\1/'"
        if [ -n "$L3_MSG" ]; then
            L3_MSG="$L3_MSG

$PROJ_MSG"
        else
            L3_MSG="$PROJ_MSG"
        fi
    fi
fi
```

Note: This check fires in any phase (not just COMPLETE), because claude-mem is used in DEFINE and DISCUSS too.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/post-tool-navigator.sh tests/run-tests.sh
git commit -m "feat: Layer 3 coaching check for save_observation missing project parameter"
```

---

### Task 3: State management — `last_observation_id`

**Files:**
- Modify: `.claude/hooks/workflow-state.sh` (add get/set functions)
- Test: `tests/run-tests.sh` (add to workflow-state.sh suite)

- [ ] **Step 1: Write failing tests**

Add after the existing autonomy level tests in the workflow-state.sh suite:

```bash
# --- Last observation ID tracking ---

# Test: get_last_observation_id returns empty when no state file
setup_test_project
rm -f "$TEST_DIR/.claude/state/workflow.json"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_last_observation_id)
assert_eq "" "$RESULT" "get_last_observation_id returns empty when no state file"

# Test: set and get last_observation_id
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_last_observation_id 3007
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_last_observation_id)
assert_eq "3007" "$RESULT" "set/get_last_observation_id roundtrip"

# Test: last_observation_id preserved across phase transitions
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_last_observation_id)
assert_eq "3007" "$RESULT" "last_observation_id preserved across phase transitions"

# Test: set_phase("off") clears last_observation_id
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_last_observation_id)
assert_eq "" "$RESULT" "set_phase off clears last_observation_id"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`

- [ ] **Step 3: Implement `get_last_observation_id`**

Add after `set_autonomy_level` in `workflow-state.sh`:

```bash
# ---------------------------------------------------------------------------
# Last observation ID tracking (claude-mem)
# ---------------------------------------------------------------------------

get_last_observation_id() {
    if [ ! -f "$STATE_FILE" ]; then
        echo ""
        return
    fi
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    v = d.get('last_observation_id', '')
    print(v if v else '')
except Exception:
    print('')
" "$STATE_FILE" 2>/dev/null
}

set_last_observation_id() {
    local obs_id="$1"
    if [ ! -f "$STATE_FILE" ]; then
        return
    fi
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
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

- [ ] **Step 4: Preserve `last_observation_id` in `set_phase`**

Explicit changes to `set_phase()` in `workflow-state.sh`:

1. Add `local existing_last_observation_id=""` alongside the other variable declarations (near `existing_autonomy_level`)

2. Inside the `if [ -f "$STATE_FILE" ]` block, add:
   ```bash
   existing_last_observation_id=$(get_last_observation_id)
   ```

3. In the off-clearing block (`if [ "$new_phase" = "off" ]`), add:
   ```bash
   existing_last_observation_id=""
   ```

4. In the Python block, add after the `autonomy_level` argument read:
   ```python
   last_observation_id = sys.argv[8]
   ```
   And after the `autonomy_level` conditional inclusion in the state dict:
   ```python
   if last_observation_id:
       state['last_observation_id'] = int(last_observation_id)
   ```
   Note: The `if last_observation_id:` guard prevents `int("")` ValueError when the field is cleared.

5. Update the shell call to pass the 8th argument:
   ```bash
   " "$new_phase" "$current_phase" "$existing_active_skill" "$existing_decision_record" "$ts" "$STATE_FILE" "$existing_autonomy_level" "$existing_last_observation_id"
   ```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`

- [ ] **Step 6: Commit**

```bash
git add .claude/hooks/workflow-state.sh tests/run-tests.sh
git commit -m "feat: add last_observation_id state tracking for claude-mem"
```

---

### Task 4: PostToolUse hook captures observation IDs

**Files:**
- Modify: `.claude/hooks/post-tool-navigator.sh` (add ID capture after save/get observation tool calls)
- Test: `tests/run-tests.sh`

- [ ] **Step 1: Write failing tests**

```bash
# --- Observation ID capture ---

# Test: hook captures observation ID from save_observation response
setup_test_project
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__save_observation","tool_input":{"text":"test","project":"test"},"tool_response":{"content":[{"type":"text","text":"{\"success\":true,\"id\":4242,\"title\":\"test\",\"project\":\"test\",\"message\":\"Memory saved as observation #4242\"}"}]}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_last_observation_id)
assert_eq "4242" "$RESULT" "hook captures observation ID from save_observation"

# Test: hook captures observation ID from get_observations response
setup_test_project
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__get_observations","tool_input":{"ids":[1234]},"tool_response":{"content":[{"type":"text","text":"[{\"id\":1234,\"title\":\"test obs\"}]"}]}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_last_observation_id)
assert_eq "1234" "$RESULT" "hook captures observation ID from get_observations"
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Add observation ID capture to `post-tool-navigator.sh`**

**CRITICAL placement note:** This code MUST be placed before the early exit `case` statement (around line 92-110) which exits for irrelevant tools. The `get_observations` tool would hit the `*) exit 0` branch and never reach code placed after it. Place this immediately after the `TOOL_NAME` extraction (around line 34).

Also update the early exit case statement to pass through `mcp*get_observations` alongside `mcp*save_observation`. In the existing case at line 101, change:

```bash
    mcp*save_observation) ;;
```

To:

```bash
    mcp*save_observation|mcp*get_observations) ;;
```

Add near the top of the script, after the `TOOL_NAME` extraction (around line 34), before the Layer 1 block:

```bash
# ---------------------------------------------------------------------------
# Claude-mem observation ID tracking
# ---------------------------------------------------------------------------
# Capture the last observation ID from save_observation or get_observations responses
if echo "$TOOL_NAME" | grep -qE 'mcp.*save_observation'; then
    OBS_ID=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
resp = d.get('tool_response', {})
# MCP responses come as content blocks with text
content = resp.get('content', [])
for block in content:
    if block.get('type') == 'text':
        try:
            data = json.loads(block['text'])
            if isinstance(data, dict) and 'id' in data:
                print(data['id'])
                sys.exit(0)
        except (json.JSONDecodeError, KeyError):
            pass
# Fallback: try parsing tool_response directly
if isinstance(resp, dict) and 'id' in resp:
    print(resp['id'])
else:
    print('')
" 2>/dev/null || echo "")
    if [ -n "$OBS_ID" ]; then
        set_last_observation_id "$OBS_ID"
    fi
elif echo "$TOOL_NAME" | grep -qE 'mcp.*get_observations'; then
    OBS_ID=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
resp = d.get('tool_response', {})
content = resp.get('content', [])
for block in content:
    if block.get('type') == 'text':
        try:
            data = json.loads(block['text'])
            if isinstance(data, list) and len(data) > 0 and 'id' in data[-1]:
                print(data[-1]['id'])
                sys.exit(0)
        except (json.JSONDecodeError, KeyError):
            pass
print('')
" 2>/dev/null || echo "")
    if [ -n "$OBS_ID" ]; then
        set_last_observation_id "$OBS_ID"
    fi
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/post-tool-navigator.sh tests/run-tests.sh
git commit -m "feat: capture claude-mem observation IDs in PostToolUse hook"
```

---

### Task 5: Status line displays last observation ID

**Files:**
- Modify: `statusline/statusline.sh:150-157` (add observation ID to Claude-Mem display)
- Test: `tests/run-tests.sh` (add to statusline.sh suite)

- [ ] **Step 1: Write failing tests**

```bash
# --- Claude-Mem observation ID in statusline ---

# Test: statusline shows observation ID when present
SL_OBS_DIR=$(mktemp -d)
mkdir -p "$SL_OBS_DIR/.claude/state" "$SL_OBS_DIR/.claude/hooks"
echo '{"phase": "implement", "autonomy_level": 2, "last_observation_id": 3007, "message_shown": true, "active_skill": ""}' > "$SL_OBS_DIR/.claude/state/workflow.json"
touch "$SL_OBS_DIR/.claude/hooks/workflow-gate.sh"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_OBS_DIR\",\"mcp_servers\":[\"claude-mem\"]}")
assert_contains "$OUTPUT" "#3007" "statusline shows observation ID when present"
assert_contains "$OUTPUT" "Claude-Mem" "statusline still shows Claude-Mem label"
rm -rf "$SL_OBS_DIR"

# Test: statusline shows no ID when field absent
SL_NOOBS_DIR=$(mktemp -d)
mkdir -p "$SL_NOOBS_DIR/.claude/state" "$SL_NOOBS_DIR/.claude/hooks"
echo '{"phase": "implement", "message_shown": true, "active_skill": ""}' > "$SL_NOOBS_DIR/.claude/state/workflow.json"
touch "$SL_NOOBS_DIR/.claude/hooks/workflow-gate.sh"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_NOOBS_DIR\",\"mcp_servers\":[\"claude-mem\"]}")
CLEAN_OUTPUT=$(echo "$OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
assert_not_contains "$CLEAN_OUTPUT" "#" "statusline shows no observation ID when field absent"
rm -rf "$SL_NOOBS_DIR"
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Add observation ID display to `statusline.sh`**

In `statusline.sh`, modify the Claude-Mem detection block (lines 150-157). After detecting Claude-Mem is available, read the last observation ID from `workflow.json` and append it:

Replace lines 151-154:

```bash
if echo "$DATA" | jq -e '.mcp_servers[]? | select(. == "claude-mem" or test("claude.mem"; "i"))' >/dev/null 2>&1; then
  OUTPUT+="  ${DIM}│${RESET}  ${GREEN}Claude-Mem ✓${RESET}"
elif command -v claude-mem >/dev/null 2>&1 || [ -d "$HOME/.claude/plugins/cache/thedotmack" ]; then
  OUTPUT+="  ${DIM}│${RESET}  ${GREEN}Claude-Mem ✓${RESET}"
```

With:

```bash
# Read last observation ID from workflow state (if available)
CM_OBS_ID=""
if [ -f "$WM_STATE_FILE" ]; then
  CM_OBS_ID=$(grep -o '"last_observation_id"[[:space:]]*:[[:space:]]*[0-9]*' "$WM_STATE_FILE" | grep -o '[0-9]*$')
fi
CM_SUFFIX=""
if [ -n "$CM_OBS_ID" ]; then
  CM_SUFFIX=" ${CYAN}#${CM_OBS_ID}${RESET}"
fi

if echo "$DATA" | jq -e '.mcp_servers[]? | select(. == "claude-mem" or test("claude.mem"; "i"))' >/dev/null 2>&1; then
  OUTPUT+="  ${DIM}│${RESET}  ${GREEN}Claude-Mem ✓${RESET}${CM_SUFFIX}"
elif command -v claude-mem >/dev/null 2>&1 || [ -d "$HOME/.claude/plugins/cache/thedotmack" ]; then
  OUTPUT+="  ${DIM}│${RESET}  ${GREEN}Claude-Mem ✓${RESET}${CM_SUFFIX}"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`

- [ ] **Step 5: Commit**

```bash
git add statusline/statusline.sh tests/run-tests.sh
git commit -m "feat: display last claude-mem observation ID in status line"
```

---

### Task 6: Documentation

**Files:**
- Modify: `docs/guides/claude-mem-guide.md` (add project scoping section)
- Modify: `docs/guides/statusline-guide.md` (document observation ID display)
- Modify: `docs/reference/hooks.md` (document Layer 3 project check)

- [ ] **Step 1: Update claude-mem guide with project scoping**

Add a section on project scoping: always pass `project` derived from the GitHub repo name. Explain the `git remote` derivation.

- [ ] **Step 2: Update statusline guide with observation ID**

Document that the status line now shows `Claude-Mem ✓ #3007` when an observation has been read or written.

- [ ] **Step 3: Update hooks reference with Layer 3 project check**

Document the new coaching check for `save_observation` missing project field.

- [ ] **Step 4: Commit**

```bash
git add docs/guides/claude-mem-guide.md docs/guides/statusline-guide.md docs/reference/hooks.md
git commit -m "docs: document claude-mem project scoping and observation ID in status line"
```
