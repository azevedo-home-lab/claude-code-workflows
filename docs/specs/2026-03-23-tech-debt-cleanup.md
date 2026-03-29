# Tech Debt Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate all python3 JSON dependencies by migrating to jq, extract generic helpers, decompose `set_phase()`, and add missing test assertions.

**Architecture:** Five-phase approach — enforce jq dependency, migrate python3→jq file-by-file (simplest→complex), extract `_update_state` generic helper, decompose `set_phase()` into focused helpers, add missing hard gate test assertions.

**Tech Stack:** Bash 3.2+, jq 1.6+

**Spec:** `docs/superpowers/specs/2026-03-23-tech-debt-cleanup-design.md`

---

## Task 1: Enforce jq as Hard Dependency

**Files:**
- Modify: `plugin/scripts/setup.sh`

- [ ] **Step 1: Change jq check from warning to hard error in setup.sh**

In `plugin/scripts/setup.sh`, find the existing jq warning (near the top of the file) and replace it with a hard error that exits the script:

```bash
# Replace the existing jq warning with:
if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not installed. Install it:" >&2
    echo "  macOS:  brew install jq" >&2
    echo "  Ubuntu: sudo apt-get install jq" >&2
    echo "  Other:  https://jqlang.github.io/jq/download/" >&2
    return 1
fi
```

Remove any existing soft-warning jq check that allows execution to continue.

- [ ] **Step 2: Run tests to verify no regressions**

Run: `bash tests/run-tests.sh`
Expected: All 322 assertions pass. Tests source setup.sh indirectly, so jq must be present in the test environment (it is — the statusline already uses jq).

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/setup.sh
git commit -m "feat: enforce jq as hard dependency in setup.sh

jq is required for the python3→jq migration. Replace soft warning
with a hard error and installation instructions."
```

---

## Task 2: Migrate check-version-sync.sh (3 python3 calls)

**Files:**
- Modify: `scripts/check-version-sync.sh`

- [ ] **Step 1: Replace all 3 python3 version extraction calls with jq**

The file has 3 python3 one-liners that extract version strings. Replace each:

```bash
# Line ~6: marketplace.json version
# Before: V1=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/.claude-plugin/marketplace.json'))['plugins'][0]['version'])")
# After:
V1=$(jq -r '.plugins[0].version' "$REPO_ROOT/.claude-plugin/marketplace.json")

# Line ~7: .claude-plugin/plugin.json version
# Before: V2=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/.claude-plugin/plugin.json'))['version'])")
# After:
V2=$(jq -r '.version' "$REPO_ROOT/.claude-plugin/plugin.json")

# Line ~8: plugin/.claude-plugin/plugin.json version
# Before: V3=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/plugin/.claude-plugin/plugin.json'))['version'])")
# After:
V3=$(jq -r '.version' "$REPO_ROOT/plugin/.claude-plugin/plugin.json")
```

- [ ] **Step 2: Verify the script works**

Run: `bash scripts/check-version-sync.sh`
Expected: `✓ All versions in sync: 1.1.0`

- [ ] **Step 3: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 322 assertions pass.

- [ ] **Step 4: Commit**

```bash
git add scripts/check-version-sync.sh
git commit -m "refactor: migrate check-version-sync.sh from python3 to jq"
```

---

## Task 3: Migrate workflow-gate.sh (1 python3 call)

**Files:**
- Modify: `plugin/scripts/workflow-gate.sh`

- [ ] **Step 1: Replace python3 stdin parsing with jq**

Find the python3 call (line ~54-59) that parses stdin JSON to extract `tool_input.file_path`:

```bash
# Before: FILE_PATH=$(echo "$INPUT" | python3 -c "import sys, json; d = json.load(sys.stdin); ti = d.get('tool_input', {}); print(ti.get('file_path', ''))")
# After:
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || FILE_PATH=""
```

Note: This file has `set -euo pipefail`, so the `|| FILE_PATH=""` fallback is critical.

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 322 assertions pass.

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/workflow-gate.sh
git commit -m "refactor: migrate workflow-gate.sh from python3 to jq"
```

---

## Task 4: Migrate bash-write-guard.sh (4 python3 calls)

**Files:**
- Modify: `plugin/scripts/bash-write-guard.sh`

- [ ] **Step 1: Replace python3 stdin parsing for command extraction (line ~54)**

```bash
# Before: COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))")
# After:
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || COMMAND=""
```

- [ ] **Step 2: Replace python3 chain detection logic (line ~82-89)**

This extracts the first line of a command and strips `-m "..."` arguments for chain detection. The python3 code uses regex — replace with sed:

```bash
# Before: python3 regex-based first-line + strip
# After: Use the existing extract_bash_command helper (already refactored in prior session)
# or replace with:
FIRST_LINE=$(echo "$COMMAND" | head -1 | sed -E 's/-m "[^"]*"/-m MSG/g; s/-m '"'"'[^'"'"']*'"'"'/-m MSG/g; s/-m [^ ;|&]+/-m MSG/g')
```

Read the current code carefully — the `extract_bash_command` helper may already handle this. If so, this python3 call may already be gone.

- [ ] **Step 3: Replace python3 write-target extraction (line ~144-158)**

This python3 code uses regex to extract redirect targets (`>`, `>>`) or last arguments from cp/mv/install commands. Replace with bash/sed:

```bash
# Before: python3 regex extraction for redirect targets AND cp/mv/install last-arg
# After: Handle both redirect targets and file operation targets:

# Redirect targets (> and >>)
WRITE_TARGET=$(echo "$COMMAND" | sed -n 's/.*>>\?[[:space:]]*\([^[:space:];|&]*\).*/\1/p' | head -1)

# If no redirect target found, check for cp/mv/install (last argument is the target)
if [ -z "$WRITE_TARGET" ]; then
    WRITE_TARGET=$(echo "$COMMAND" | sed -n 's/.*\(cp\|mv\|install\)[[:space:]].*[[:space:]]\([^[:space:];|&]*\)[[:space:]]*$/\2/p' | head -1)
fi
```

Read the current file to verify exactly which python3 calls remain and what patterns they handle — the WRITE_PATTERN regex refactoring from the prior session may already cover some of this logic via bash regex groups.

- [ ] **Step 4: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 322 assertions pass. The bash-write-guard tests specifically exercise command parsing.

- [ ] **Step 5: Commit**

```bash
git add plugin/scripts/bash-write-guard.sh
git commit -m "refactor: migrate bash-write-guard.sh from python3 to jq"
```

---

## Task 5: Migrate setup.sh (remaining python3 calls)

**Files:**
- Modify: `plugin/scripts/setup.sh`

- [ ] **Step 1: Replace python3 state initialization with jq**

Find the python3 block (line ~36-53) that creates the default workflow.json:

```bash
# Before: python3 -c "import json, datetime; ..." creates the initial state dict
# After (note: no `local` — this runs at file scope, not inside a function):
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -n --arg ts "$ts" '{
    "phase": "off",
    "message_shown": false,
    "active_skill": "",
    "decision_record": "",
    "coaching": {"tool_calls_since_agent": 0, "layer2_fired": []},
    "updated": $ts,
    "autonomy_level": 2
}' > "$STATE_FILE"
```

- [ ] **Step 2: Replace python3 global settings.json modification with jq**

Find the python3 block (line ~89-110) that modifies `~/.claude/settings.json`:

```bash
# Before: python3 read-modify-write of settings.json
# After:
local settings_file="$HOME/.claude/settings.json"
if [ -f "$settings_file" ]; then
    jq '.statusLine = {"type": "command", "command": "~/.claude/statusline.sh", "padding": 2}' \
        "$settings_file" > "${settings_file}.tmp" && mv "${settings_file}.tmp" "$settings_file"
fi
```

Read the current code carefully — the exact jq filter depends on what fields are being set.

- [ ] **Step 3: Replace python3 project settings.json modification with jq**

Find the python3 block (line ~122-145) that ensures permissions are in project settings:

```bash
# Before: python3 read-modify-write of project settings
# After:
local project_settings="$PROJECT_DIR/.claude/settings.json"
if [ -f "$project_settings" ]; then
    jq '.permissions.allow = ((.permissions.allow // []) + ["Read", "Agent", "Glob", "Grep"] | unique)' \
        "$project_settings" > "${project_settings}.tmp" && mv "${project_settings}.tmp" "$project_settings"
fi
```

- [ ] **Step 4: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 322 assertions pass.

- [ ] **Step 5: Commit**

```bash
git add plugin/scripts/setup.sh
git commit -m "refactor: migrate setup.sh from python3 to jq"
```

---

## Task 6: Migrate post-tool-navigator.sh (~13 python3 calls)

**Files:**
- Modify: `plugin/scripts/post-tool-navigator.sh`

This is the second-largest migration. Work through each python3 call:

- [ ] **Step 1: Replace stdin JSON parsing calls**

Replace the tool_name, tool_input.command, and tool_input.file_path extractors:

```bash
# Line ~22: tool_name extraction
# Before: TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; ...")
# After:
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || TOOL_NAME=""

# Line ~26: bash command extraction
# Before: BASH_CMD=$(echo "$INPUT" | python3 -c "...")
# After:
BASH_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || BASH_CMD=""

# Line ~174: file_path extraction
# Before: FILE_PATH=$(echo "$INPUT" | python3 -c "...")
# After:
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || FILE_PATH=""
```

- [ ] **Step 2: Replace observation ID extraction (line ~41-64)**

This is the most complex parsing — it reads tool_response content blocks looking for observation IDs:

```bash
# Before: Complex python3 parsing of nested JSON blocks
# After:
OBS_ID=$(echo "$INPUT" | jq -r '
    .tool_response.content[]?
    | select(.type == "text")
    | .text
    | try fromjson
    | .id // empty
' 2>/dev/null | tail -1) || OBS_ID=""
```

- [ ] **Step 3: Replace JSON output formatting (lines ~151-160, ~498-507)**

These produce the hook response JSON. Both are identical:

```bash
# Before: python3 -c "import json; print(json.dumps(...))"
# After:
jq -n --arg msg "$MESSAGES" '{
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "systemMessage": $msg
    }
}'
```

- [ ] **Step 4: Replace save_observation measurement (line ~375-382)**

```bash
# Before: python3 extracts text length and project presence
# After:
read -r TEXT_LEN HAS_PROJECT < <(echo "$INPUT" | jq -r '
    (.tool_input.narrative // .tool_input.text // "") as $t |
    (.tool_input.project // "") as $p |
    "\($t | length) \(if $p != "" then "true" else "false" end)"
' 2>/dev/null) || { TEXT_LEN=0; HAS_PROJECT="false"; }
```

- [ ] **Step 5: Replace agent prompt length measurement (line ~300-305)**

```bash
# Before: python3 extracts prompt and returns len()
# After:
PROMPT_LEN=$(echo "$INPUT" | jq -r '.tool_input.prompt // "" | length' 2>/dev/null) || PROMPT_LEN=0
```

- [ ] **Step 6: Replace commit message extraction (line ~315-331)**

This uses python3 regex to extract `-m "..."` content. Replace with sed:

```bash
# Before: python3 regex extraction of commit message
# After:
COMMIT_MSG=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null | \
    sed -n 's/.*-m[[:space:]]*"\([^"]*\)".*/\1/p; s/.*-m[[:space:]]*'"'"'\([^'"'"']*\)'"'"'.*/\1/p' | head -1) || COMMIT_MSG=""
MSG_LEN=${#COMMIT_MSG}
```

Read the current code — this may use a HEREDOC pattern too. Adapt the sed expression to match what's actually there.

- [ ] **Step 7: Replace state file reads (lines ~407-414, ~433-442)**

These read from workflow.json (not stdin). Replace with jq file reads:

```bash
# Line ~407-414: coaching counter
# Before: python3 reads coaching.tool_calls_since_agent from file
# After:
TOOL_CALLS=$(jq -r '.coaching.tool_calls_since_agent // 0' "$STATE_FILE" 2>/dev/null) || TOOL_CALLS=0

# Line ~433-442: check layer2_fired for agent_return
# Before: python3 checks array membership
# After:
HAS_AGENT_RETURN=$(jq -r '.coaching.layer2_fired[]? | select(startswith("agent_return")) | "true"' "$STATE_FILE" 2>/dev/null | head -1)
HAS_AGENT_RETURN=${HAS_AGENT_RETURN:-false}
```

- [ ] **Step 8: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 322 assertions pass. PostToolUse hooks are tested by multiple test suites.

- [ ] **Step 9: Commit**

```bash
git add plugin/scripts/post-tool-navigator.sh
git commit -m "refactor: migrate post-tool-navigator.sh from python3 to jq

Replaces ~13 python3 invocations with jq equivalents. Stdin JSON
parsing, observation ID extraction, hook response formatting, and
state file reads all now use jq."
```

---

## Task 7: Migrate workflow-state.sh getters and emit_deny (~18 python3 calls)

**Files:**
- Modify: `plugin/scripts/workflow-state.sh`

This is the largest migration. Split into getters first (read-only, lower risk), then setters in Task 8.

- [ ] **Step 1: Replace emit_deny() (line ~30-40)**

```bash
# Before: python3 constructs deny JSON
# After:
emit_deny() {
    local reason="$1"
    jq -n --arg reason "$reason" '{
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": $reason
        }
    }'
}
```

- [ ] **Step 2: Replace get_phase() (line ~53-63)**

```bash
# Before: python3 reads phase from file
# After:
get_phase() {
    if [ ! -f "$STATE_FILE" ]; then echo "off"; return; fi
    local phase
    phase=$(jq -r '.phase // "off"' "$STATE_FILE" 2>/dev/null) || phase="off"
    echo "$phase"
}
```

- [ ] **Step 3: Replace get_autonomy_level() (line ~71-80)**

```bash
# Before: python3 reads autonomy_level
# After:
get_autonomy_level() {
    if [ ! -f "$STATE_FILE" ]; then echo "2"; return; fi
    local level
    level=$(jq -r '.autonomy_level // 2' "$STATE_FILE" 2>/dev/null) || level="2"
    echo "$level"
}
```

- [ ] **Step 4: Replace remaining getter functions**

Apply the same pattern to all getters:

```bash
# get_last_observation_id (line ~117-126)
# After: jq -r '.last_observation_id // ""' "$STATE_FILE"

# get_tracked_observations (line ~168-177)
# After: jq -r '.tracked_observations // [] | map(tostring) | join(",")' "$STATE_FILE"

# get_message_shown (line ~471-480)
# After: jq -r 'if .message_shown == true then "true" else "false" end' "$STATE_FILE"

# get_active_skill (line ~531-539)
# After: jq -r '.active_skill // ""' "$STATE_FILE"

# get_decision_record (line ~571-579)
# After: jq -r '.decision_record // ""' "$STATE_FILE"

# get_pending_verify (line ~908-916)
# After: jq -r '.coaching.pending_verify // 0' "$STATE_FILE"
```

- [ ] **Step 5: Replace helper getters (_get_section_field, _section_exists, _check_milestones, has_completion_snapshot, has_coaching_fired, check_soft_gate)**

```bash
# _get_section_field (line ~676-686)
# After: jq -r --arg s "$section" --arg f "$field" '.[$s][$f] // "" | tostring' "$STATE_FILE"

# _section_exists (line ~716-724)
# After: jq -e --arg s "$section" 'has($s)' "$STATE_FILE" >/dev/null 2>&1

# _check_milestones (line ~729-742)
# After: jq -r --arg s "$section" '.[$s] // {} | to_entries[] | select(.value != true) | .key' "$STATE_FILE" | paste -sd ' ' -

# has_completion_snapshot (line ~309-317)
# After: jq -e '.completion_snapshot != null and .completion_snapshot != {}' "$STATE_FILE" >/dev/null 2>&1

# has_coaching_fired (line ~842-854)
# After: jq -e --arg t "$trigger_type" '.coaching.layer2_fired[]? | select(. == $t)' "$STATE_FILE" >/dev/null 2>&1

# check_soft_gate (line ~617-626)
# After: jq -r '.review.findings_acknowledged // false | tostring' "$STATE_FILE"
```

- [ ] **Step 6: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 322 assertions pass. Getters are tested extensively.

- [ ] **Step 7: Commit**

```bash
git add plugin/scripts/workflow-state.sh
git commit -m "refactor: migrate workflow-state.sh getters from python3 to jq

Replaces ~18 python3 read operations with jq equivalents including
emit_deny, get_phase, get_autonomy_level, and all helper getters."
```

---

## Task 8: Migrate workflow-state.sh setters (~18 python3 calls)

**Files:**
- Modify: `plugin/scripts/workflow-state.sh`

- [ ] **Step 1: Replace simple setters (set_message_shown, set_active_skill, set_decision_record)**

Each follows the same pattern — read-modify-write with timestamp:

```bash
# set_message_shown (line ~489-499)
set_message_shown() {
    local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg ts "$ts" '.message_shown = true | .updated = $ts' \
        "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# set_active_skill (line ~513-523)
set_active_skill() {
    local name="$1" ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg v "$name" --arg ts "$ts" '.active_skill = $v | .updated = $ts' \
        "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# set_decision_record (line ~553-563)
set_decision_record() {
    local path="$1" ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg v "$path" --arg ts "$ts" '.decision_record = $v | .updated = $ts' \
        "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}
```

- [ ] **Step 2: Replace set_autonomy_level (with validation)**

```bash
set_autonomy_level() {
    local level="$1"
    case "$level" in 1|2|3) ;; *) echo "Invalid autonomy level: $level" >&2; return 1;; esac
    local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --argjson v "$level" --arg ts "$ts" '.autonomy_level = $v | .updated = $ts' \
        "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}
```

- [ ] **Step 3: Replace observation setters (set_last_observation_id, set/add/remove_tracked_observations)**

These have create-or-update branching:

```bash
# set_last_observation_id — create branch (line ~136-143)
# When file doesn't exist, create minimal state:
local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -n --argjson id "$obs_id" --arg ts "$ts" \
    '{"phase": "off", "last_observation_id": $id, "updated": $ts}' > "$STATE_FILE"

# set_last_observation_id — update branch (line ~146-156)
jq --argjson id "$obs_id" --arg ts "$ts" \
    '.last_observation_id = $id | .updated = $ts' \
    "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

# set_tracked_observations — similar create/update pattern with CSV→array conversion:
# Convert CSV to JSON array: "1,2,3" → [1,2,3]
jq --arg ids "$ids_csv" --arg ts "$ts" \
    '.tracked_observations = ($ids | split(",") | map(select(. != "") | tonumber)) | .updated = $ts' \
    "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

# add_tracked_observation — append + unique:
jq --argjson id "$obs_id" --arg ts "$ts" \
    '.tracked_observations = ((.tracked_observations // []) + [$id] | unique) | .updated = $ts' \
    "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

# remove_tracked_observation:
jq --argjson id "$obs_id" --arg ts "$ts" \
    '.tracked_observations |= map(select(. != $id)) | .updated = $ts' \
    "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
```

- [ ] **Step 4: Replace snapshot functions (save/restore_completion_snapshot)**

```bash
# save_completion_snapshot (line ~272-284)
save_completion_snapshot() {
    local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg ts "$ts" '.completion_snapshot = (.completion // {}) | .updated = $ts' \
        "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# restore_completion_snapshot (line ~291-304)
restore_completion_snapshot() {
    local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg ts "$ts" '.completion = (.completion_snapshot // {}) | del(.completion_snapshot) | .updated = $ts' \
        "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}
```

- [ ] **Step 5: Replace coaching setters**

```bash
# increment_coaching_counter (line ~775-787)
increment_coaching_counter() {
    local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg ts "$ts" '.coaching.tool_calls_since_agent += 1 | .updated = $ts' \
        "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# reset_coaching_counter (line ~796-808)
reset_coaching_counter() {
    local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg ts "$ts" '.coaching.tool_calls_since_agent = 0 | .updated = $ts' \
        "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# add_coaching_fired (line ~818-833)
add_coaching_fired() {
    local trigger="$1" ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg t "$trigger" --arg ts "$ts" \
        '.coaching.layer2_fired += [$t] | .coaching.last_layer2_at = .coaching.tool_calls_since_agent | .updated = $ts' \
        "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# check_coaching_refresh (line ~862-879)
check_coaching_refresh() {
    local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg ts "$ts" '
        if (.coaching.tool_calls_since_agent - (.coaching.last_layer2_at // 0)) >= 30 then
            .coaching.layer2_fired = [] | .coaching.last_layer2_at = .coaching.tool_calls_since_agent | .updated = $ts
        else . end
    ' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# set_pending_verify (line ~891-903)
set_pending_verify() {
    local count="$1" ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --argjson c "$count" --arg ts "$ts" '.coaching.pending_verify = $c | .updated = $ts' \
        "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}
```

- [ ] **Step 6: Replace _reset_section and _set_section_field**

```bash
# _reset_section (line ~655-668): initializes all fields to false
_reset_section() {
    local section="$1"; shift
    local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    # Build jq filter from field names
    local filter=".${section} = {"
    local first=true
    for field in "$@"; do
        $first || filter+=", "
        filter+="\"$field\": false"
        first=false
    done
    filter+="} | .updated = \$ts"
    jq --arg ts "$ts" "$filter" \
        "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# _set_section_field (line ~696-708): sets nested field with type handling
_set_section_field() {
    local section="$1" field="$2" value="$3"
    local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [ "$value" = "true" ] || [ "$value" = "false" ]; then
        jq --arg ts "$ts" ".${section}.${field} = ${value} | .updated = \$ts" \
            "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    else
        jq --arg v "$value" --arg ts "$ts" ".${section}.${field} = \$v | .updated = \$ts" \
            "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    fi
}
```

- [ ] **Step 7: Replace set_phase's python3 state write (line ~416-462)**

This is the most complex setter. The python3 block takes ~10 arguments and conditionally builds the entire state object. Replace with a jq filter that preserves all fields:

```bash
# Inside set_phase(), replace the python3 block with:
local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Build the jq filter based on what needs to be preserved/cleared
local jq_filter=". | .phase = \"$new_phase\" | .message_shown = false | .updated = \$ts"

# Preserve or clear fields based on transition
if [ "$new_phase" = "off" ]; then
    jq_filter+=" | .active_skill = \"\" | .decision_record = \"\" | .autonomy_level = 2"
else
    jq_filter+=" | .active_skill = \$skill | .decision_record = \$decision"
    if [ -n "$preserved_autonomy" ]; then
        jq_filter+=" | .autonomy_level = $preserved_autonomy"
    fi
fi

# Handle observation fields
jq_filter+=" | .last_observation_id = \$obs_id"
if [ -n "$preserved_tracked" ]; then
    jq_filter+=" | .tracked_observations = $preserved_tracked"
fi
if [ -n "$preserved_snapshot" ]; then
    jq_filter+=" | .completion_snapshot = $preserved_snapshot"
fi

jq --arg ts "$ts" --arg skill "$preserved_skill" --arg decision "$preserved_decision" \
   --arg obs_id "$preserved_obs_id" \
   "$jq_filter" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
```

Read the actual set_phase() code carefully when implementing — the exact variable names and conditional logic must match. This pseudocode shows the pattern; adapt to the real variable names.

- [ ] **Step 8: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 322 assertions pass. This is the highest-risk step — every setter is affected.

- [ ] **Step 9: Commit**

```bash
git add plugin/scripts/workflow-state.sh
git commit -m "refactor: migrate workflow-state.sh setters from python3 to jq

Replaces ~18 python3 write operations with jq equivalents. All writes
now use atomic temp+mv pattern for crash safety. set_phase's 49-line
python3 block replaced with jq filter chain."
```

---

## Task 9: Extract _update_state Generic Helper

**Files:**
- Modify: `plugin/scripts/workflow-state.sh`

- [ ] **Step 1: Add _update_state helper function**

Add near the top of workflow-state.sh (after STATE_FILE/STATE_DIR definitions, before any setter):

```bash
# Generic state write helper. Atomic: writes to temp file, then mv.
# Usage: _update_state <jq_filter> [--arg name val]... [--argjson name val]...
_update_state() {
    local filter="$1"; shift
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg ts "$ts" "$@" \
        "$filter | .updated = \$ts" \
        "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}
```

- [ ] **Step 2: Refactor simple setters to use _update_state**

```bash
set_message_shown() { _update_state '.message_shown = true'; }

set_active_skill() { _update_state '.active_skill = $v' --arg v "$1"; }

set_decision_record() { _update_state '.decision_record = $v' --arg v "$1"; }

increment_coaching_counter() { _update_state '.coaching.tool_calls_since_agent += 1'; }

reset_coaching_counter() { _update_state '.coaching.tool_calls_since_agent = 0'; }

set_pending_verify() { _update_state '.coaching.pending_verify = $c' --argjson c "$1"; }

save_completion_snapshot() { _update_state '.completion_snapshot = (.completion // {})'; }

restore_completion_snapshot() { _update_state '.completion = (.completion_snapshot // {}) | del(.completion_snapshot)'; }
```

- [ ] **Step 3: Refactor coaching setters to use _update_state**

```bash
add_coaching_fired() {
    _update_state '.coaching.layer2_fired += [$t] | .coaching.last_layer2_at = .coaching.tool_calls_since_agent' \
        --arg t "$1"
}

check_coaching_refresh() {
    _update_state '
        if (.coaching.tool_calls_since_agent - (.coaching.last_layer2_at // 0)) >= 30 then
            .coaching.layer2_fired = [] | .coaching.last_layer2_at = .coaching.tool_calls_since_agent
        else . end'
}
```

- [ ] **Step 4: Refactor observation setters (update branches only)**

The create-from-nothing branches still use `jq -n` (they write a new file, not modify existing). Only the update branches use `_update_state`:

```bash
# set_last_observation_id — update branch:
_update_state '.last_observation_id = $id' --argjson id "$obs_id"

# set_tracked_observations — update branch:
_update_state '.tracked_observations = ($ids | split(",") | map(select(. != "") | tonumber))' --arg ids "$ids_csv"

# add_tracked_observation — update branch:
_update_state '.tracked_observations = ((.tracked_observations // []) + [$id] | unique)' --argjson id "$obs_id"

# remove_tracked_observation:
_update_state '.tracked_observations |= map(select(. != $id))' --argjson id "$obs_id"

# set_autonomy_level (after validation):
_update_state '.autonomy_level = $v' --argjson v "$level"
```

- [ ] **Step 5: Refactor _reset_section and _set_section_field to use _update_state**

```bash
_reset_section() {
    local section="$1"; shift
    local filter=".${section} = {"
    local first=true
    for field in "$@"; do
        $first || filter+=", "
        filter+="\"$field\": false"
        first=false
    done
    filter+="}"
    _update_state "$filter"
}

_set_section_field() {
    local section="$1" field="$2" value="$3"
    if [ "$value" = "true" ] || [ "$value" = "false" ]; then
        _update_state ".${section}.${field} = ${value}"
    else
        _update_state ".${section}.${field} = \$v" --arg v "$value"
    fi
}
```

- [ ] **Step 6: Update set_phase to use _update_state for its final write**

Replace the jq write block at the end of set_phase (from Task 8 Step 7) with a call to `_update_state` using the assembled filter.

- [ ] **Step 7: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 322 assertions pass. This is a pure refactor — behavior unchanged.

- [ ] **Step 8: Commit**

```bash
git add plugin/scripts/workflow-state.sh
git commit -m "refactor: extract _update_state generic helper

Consolidates atomic jq write pattern (timestamp + temp + mv) into a
single helper. ~15 setter functions now delegate to _update_state,
eliminating ~200 lines of duplicated boilerplate."
```

---

## Task 10: Decompose set_phase()

**Files:**
- Modify: `plugin/scripts/workflow-state.sh`

- [ ] **Step 1: Extract _check_phase_gates()**

Move all hard gate milestone checking logic out of set_phase into a dedicated helper:

```bash
# Returns gate error message on stdout and exits non-zero if gate blocks.
# Pure validation — no side effects.
#
# IMPORTANT: This depends on _check_milestones having been rewritten in Task 7
# to use jq's to_entries approach (discovering fields from JSON dynamically).
# If _check_milestones still requires explicit field names, pass them here too:
#   _check_milestones "implement" "plan_read" "tests_passing" "all_tasks_complete"
_check_phase_gates() {
    local current="$1" new_phase="$2"

    # IMPLEMENT exit gate
    if [ "$current" = "implement" ] && [ "$new_phase" != "implement" ]; then
        if _section_exists "implement"; then
            local missing
            missing=$(_check_milestones "implement")
            if [ -n "$missing" ]; then
                echo "HARD GATE: Cannot leave IMPLEMENT — incomplete milestones: $missing" >&2
                return 1
            fi
        fi
    fi

    # COMPLETE exit gate
    if [ "$current" = "complete" ]; then
        if _section_exists "completion"; then
            local missing
            missing=$(_check_milestones "completion")
            if [ -n "$missing" ]; then
                echo "HARD GATE: Cannot leave COMPLETE — incomplete milestones: $missing" >&2
                return 1
            fi
        fi
    fi

    return 0
}
```

**Dependency note:** This extraction assumes `_check_milestones` was rewritten in Task 7/Step 5 to discover fields dynamically from JSON via `jq -r '.[$s] // {} | to_entries[] | select(.value != true) | .key'`. If you reach this task and `_check_milestones` still takes explicit field names, preserve the existing calling convention with field name arguments. Read the actual gate logic in set_phase to verify field names match.

- [ ] **Step 2: Extract _read_preserved_state()**

Reads the 6 fields that survive phase transitions:

```bash
# Reads fields from current state that must be preserved across transitions.
# Sets variables in the caller's scope (bash functions without `local` write to caller's scope).
_read_preserved_state() {
    if [ ! -f "$STATE_FILE" ]; then return; fi

    # Scalar fields via single jq call
    IFS=$'\t' read -r preserved_skill preserved_decision preserved_autonomy preserved_obs_id < <(
        jq -r '[
            (.active_skill // ""),
            (.decision_record // ""),
            (.autonomy_level // 2 | tostring),
            (.last_observation_id // "" | tostring)
        ] | @tsv' "$STATE_FILE" 2>/dev/null
    ) || true

    # JSON fields via separate calls (can't safely go through TSV)
    preserved_tracked=$(jq -c '.tracked_observations // []' "$STATE_FILE" 2>/dev/null) || preserved_tracked="[]"
    preserved_snapshot=$(jq -c '.completion_snapshot // null' "$STATE_FILE" 2>/dev/null) || preserved_snapshot="null"
}
```

- [ ] **Step 3: Refactor set_phase to use extracted helpers**

Rewrite set_phase to call the helpers:

```bash
set_phase() {
    local new_phase="$1"

    # Input validation
    case "$new_phase" in
        off|define|discuss|implement|review|complete) ;;
        *) echo "Invalid phase: $new_phase" >&2; return 1 ;;
    esac

    mkdir -p "$STATE_DIR"

    # Hard gate checks
    if [ -f "$STATE_FILE" ]; then
        local current
        current=$(get_phase)
        if ! _check_phase_gates "$current" "$new_phase"; then
            return 1
        fi
    fi

    # Read preserved state
    local preserved_skill="" preserved_decision="" preserved_autonomy=""
    local preserved_obs_id="" preserved_tracked="[]" preserved_snapshot="null"
    _read_preserved_state

    # Clear on OFF transition
    if [ "$new_phase" = "off" ]; then
        preserved_skill=""
        preserved_decision=""
        preserved_autonomy="2"
    fi

    # Initialize autonomy when entering active phase from OFF
    local current_phase
    current_phase=$(get_phase 2>/dev/null) || current_phase="off"
    if [ "$current_phase" = "off" ] && [ "$new_phase" != "off" ] && [ -z "$preserved_autonomy" ]; then
        preserved_autonomy="2"
    fi

    # Write new state
    local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq -n --arg phase "$new_phase" --arg ts "$ts" \
        --arg skill "$preserved_skill" --arg decision "$preserved_decision" \
        --argjson autonomy "${preserved_autonomy:-2}" \
        --arg obs_id "$preserved_obs_id" \
        --argjson tracked "$preserved_tracked" \
        --argjson snapshot "$preserved_snapshot" \
        '{
            phase: $phase,
            message_shown: false,
            active_skill: $skill,
            decision_record: $decision,
            autonomy_level: $autonomy,
            last_observation_id: (if $obs_id == "" then null else ($obs_id | tonumber) end),
            tracked_observations: $tracked,
            coaching: {tool_calls_since_agent: 0, layer2_fired: []},
            updated: $ts
        } + if $snapshot != null then {completion_snapshot: $snapshot} else {} end' \
        > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}
```

This is a full rebuild of the state file (using `jq -n`, not modifying existing) — matching the current python3 behavior. Read the actual code to verify all fields and edge cases.

- [ ] **Step 4: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 322 assertions pass. Hard gate tests, phase transition tests, and state preservation tests are all critical here.

- [ ] **Step 5: Commit**

```bash
git add plugin/scripts/workflow-state.sh
git commit -m "refactor: decompose set_phase into focused helpers

Extract _check_phase_gates (pure validation) and _read_preserved_state
(field preservation) from set_phase. Function reduced from ~120 lines
to ~45 lines with clear single-responsibility helpers."
```

---

## Task 11: Add Hard Gate Phase-Unchanged Assertions

**Files:**
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Add assertion after "gate blocks leaving IMPLEMENT" test**

Find the test at line ~338-343 that verifies the gate blocks leaving IMPLEMENT. After the existing `assert_contains` for "HARD GATE", add:

```bash
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "implement" "$RESULT" "phase remains implement after gate blocks"
```

- [ ] **Step 2: Add assertion after "gate blocks leaving COMPLETE" test**

Find the test at line ~357-362. After the existing assertion, add:

```bash
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "complete" "$RESULT" "phase remains complete after gate blocks"
```

- [ ] **Step 3: Add assertion after "COMPLETE gate blocks all exits" test**

Find the test at line ~406-411. After the existing assertion, add:

```bash
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "complete" "$RESULT" "phase remains complete after complete→implement gate block"
```

- [ ] **Step 4: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 325 assertions pass (322 + 3 new).

- [ ] **Step 5: Commit**

```bash
git add tests/run-tests.sh
git commit -m "test: add phase-unchanged assertions to hard gate tests

Verify that when a hard gate blocks a phase transition, the phase
remains at its original value in the state file. Covers implement,
complete, and complete→implement gate scenarios."
```

---

## Task 12: Final Verification and Cleanup

**Files:**
- All modified files

- [ ] **Step 1: Verify no python3 references remain in production code**

Run: `grep -r "python3" plugin/scripts/ scripts/check-version-sync.sh`
Expected: No matches (or only comments referencing the migration).

- [ ] **Step 2: Run full test suite one final time**

Run: `bash tests/run-tests.sh`
Expected: All 325 assertions pass.

- [ ] **Step 3: Run version sync check**

Run: `bash scripts/check-version-sync.sh`
Expected: `✓ All versions in sync: 1.1.0`

- [ ] **Step 4: Verify atomic write pattern is consistent**

Run: `grep -c '\.tmp" && mv' plugin/scripts/workflow-state.sh`
Expected: Count matches the number of write operations (should be consistent — all writes go through `_update_state` or use the same pattern).

- [ ] **Step 5: Commit spec and decision docs (if not yet committed)**

```bash
git add docs/superpowers/specs/2026-03-23-tech-debt-cleanup-design.md docs/superpowers/specs/2026-03-23-tech-debt-cleanup-decision.md
git commit -m "docs: add tech debt cleanup design spec and decision record"
```
