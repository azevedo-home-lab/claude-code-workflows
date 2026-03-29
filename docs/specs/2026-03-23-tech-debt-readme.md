# Tech Debt Cleanup + README Overhaul — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 7 tech debt items in workflow enforcement hooks, overhaul README, and fix installer missing permissions.

**Architecture:** All hook changes are in `.claude/hooks/` (bash scripts sourced by Claude Code). Tests in `tests/run-tests.sh` (single file, section-organized). README is standalone. Items are independent — can be implemented in any order, but Item 8 (write guard hardening) should come after Item 2 (git commit allowlist) since both modify `bash-write-guard.sh`.

**Tech Stack:** Bash, Python3 (inline), JSON state files, Markdown

**Spec:** `docs/superpowers/specs/2026-03-23-tech-debt-readme-design.md`

---

### Task 1: COMPLETE whitelist — add `.claude/commands/`

**Files:**
- Modify: `.claude/hooks/workflow-state.sh:20`
- Test: `tests/run-tests.sh` (add to `=== COMPLETE phase edit-blocking ===` section, ~line 1311)

- [ ] **Step 1: Write failing tests**

Add three tests to the `=== COMPLETE phase edit-blocking ===` section (around line 1350) in `tests/run-tests.sh`:

```bash
# Test: .claude/commands/ writable in COMPLETE phase (workflow-gate)
echo '{"tool_input":{"file_path":"'$TEST_DIR'/.claude/commands/foo.md"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/workflow-gate.sh"
RESULT=$?
assert_eq "0" "$RESULT" "workflow-gate: .claude/commands/ writable in COMPLETE"

# Test: .claude/commands/ blocked in DISCUSS phase (workflow-gate)
python3 -c "import json; d=json.load(open('$STATE_FILE')); d['phase']='discuss'; json.dump(d,open('$STATE_FILE','w'),indent=2)"
RESULT=$(echo '{"tool_input":{"file_path":"'$TEST_DIR'/.claude/commands/foo.md"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/workflow-gate.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "workflow-gate: .claude/commands/ blocked in DISCUSS"

# Test: .claude/hooks/ still blocked in COMPLETE phase
python3 -c "import json; d=json.load(open('$STATE_FILE')); d['phase']='complete'; json.dump(d,open('$STATE_FILE','w'),indent=2)"
RESULT=$(echo '{"tool_input":{"file_path":"'$TEST_DIR'/.claude/hooks/foo.sh"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/workflow-gate.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "workflow-gate: .claude/hooks/ still blocked in COMPLETE"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | grep -E "(PASS|FAIL).*commands"`
Expected: First test FAIL (`.claude/commands/` not yet whitelisted)

- [ ] **Step 3: Implement the whitelist change**

In `.claude/hooks/workflow-state.sh` line 20, change:
```bash
COMPLETE_WRITE_WHITELIST='(\.claude/state/|docs/|^[^/]*\.md$)'
```
To:
```bash
COMPLETE_WRITE_WHITELIST='(\.claude/state/|\.claude/commands/|docs/|^[^/]*\.md$)'
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -5`
Expected: All tests pass including the 3 new ones

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/workflow-state.sh tests/run-tests.sh
git commit -m "fix: add .claude/commands/ to COMPLETE phase whitelist

Command templates need to be editable during the completion pipeline.
.claude/hooks/ remains excluded — enforcement must not be self-modifiable."
```

---

### Task 2: git commit allowlist in bash-write-guard

**Files:**
- Modify: `.claude/hooks/bash-write-guard.sh` (after line 58)
- Test: `tests/run-tests.sh` (add to `=== bash-write-guard.sh ===` section, ~line 579)

- [ ] **Step 1: Write failing tests**

Add to the `=== bash-write-guard.sh ===` section in `tests/run-tests.sh`. First, find the existing test setup for this section (it sets up a state file in DISCUSS phase). Add after the existing tests:

```bash
# Test: git commit with HEREDOC allowed in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"git commit -m \"$(cat <<'"'"'EOF'"'"'\nfeat: something\nEOF\n)\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_eq "" "$RESULT" "bash-guard: git commit with HEREDOC allowed in DISCUSS"

# Test: git commit chained with destructive command blocked
RESULT=$(echo '{"tool_input":{"command":"git commit -m \"msg\" && rm -rf /"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: git commit && rm blocked"

# Test: git commit allowed at Level 1
python3 -c "import json; d=json.load(open('$STATE_FILE')); d['autonomy_level']=1; json.dump(d,open('$STATE_FILE','w'),indent=2)"
RESULT=$(echo '{"tool_input":{"command":"git commit -m \"feat: something\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_eq "" "$RESULT" "bash-guard: git commit allowed at Level 1"
# Reset autonomy
python3 -c "import json; d=json.load(open('$STATE_FILE')); d['autonomy_level']=2; json.dump(d,open('$STATE_FILE','w'),indent=2)"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | grep -E "(PASS|FAIL).*git commit"`
Expected: HEREDOC test FAIL (currently blocked), chained test may pass or fail depending on existing patterns

- [ ] **Step 3: Implement the git commit allowlist**

In `.claude/hooks/bash-write-guard.sh`, after line 58 (closing `fi` of the chain check), add:

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

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -5`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/bash-write-guard.sh tests/run-tests.sh
git commit -m "fix: allow git commit in all phases including HEREDOC format

git commit writes to the git object store, not arbitrary files. Chain
guard prevents bypass via 'git commit && evil_command'. Commit message
quality is monitored by Layer 3 coaching."
```

---

### Task 3: bash-write-guard comprehensive hardening (Item 8)

**Files:**
- Modify: `.claude/hooks/bash-write-guard.sh` (WRITE_PATTERN at line 24, PYTHON_WRITE flag after line 62, Level 1 check at line 70, phase-gated check at line 94)
- Test: `tests/run-tests.sh` (add to `=== bash-write-guard.sh ===` section)

**Depends on:** Task 2 (git commit allowlist must be in place first — both modify same file)

- [ ] **Step 1: Write failing tests for multi-line python3 bypass**

Add to the bash-write-guard test section:

```bash
# --- Item 8: Write guard hardening ---

# Test: multi-line python3 with open() blocked in DISCUSS
python3 -c "import json; d=json.load(open('$STATE_FILE')); d['phase']='discuss'; d['autonomy_level']=2; json.dump(d,open('$STATE_FILE','w'),indent=2)"
RESULT=$(echo '{"tool_input":{"command":"python3 -c \"\nimport json\nwith open('"'"'f'"'"','"'"'w'"'"') as fh:\n  fh.write('"'"'x'"'"')\n\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: multi-line python3 open() blocked in DISCUSS"

# Test: multi-line python3 with shutil blocked
RESULT=$(echo '{"tool_input":{"command":"python3 -c \"\nimport shutil\nshutil.copy('"'"'a'"'"','"'"'b'"'"')\n\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: multi-line python3 shutil blocked"

# Test: multi-line python3 with subprocess blocked
RESULT=$(echo '{"tool_input":{"command":"python3 -c \"\nimport subprocess\nsubprocess.run(['"'"'cp'"'"','"'"'a'"'"','"'"'b'"'"'])\n\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: multi-line python3 subprocess blocked"

# Test: multi-line python3 with os.system blocked
RESULT=$(echo '{"tool_input":{"command":"python3 -c \"\nimport os\nos.system('"'"'rm file'"'"')\n\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: multi-line python3 os.system blocked"

# Test: harmless python3 -c allowed
RESULT=$(echo '{"tool_input":{"command":"python3 -c \"print('"'"'hello'"'"')\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_eq "" "$RESULT" "bash-guard: harmless python3 -c allowed in DISCUSS"
```

- [ ] **Step 2: Write failing tests for wrapper and anchoring bypasses**

```bash
# Test: eval blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"eval \"echo data > file.txt\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: eval blocked in DISCUSS"

# Test: bash -c blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"bash -c \"cp src dst\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: bash -c blocked in DISCUSS"

# Test: sh -c blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"sh -c \"mv a b\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: sh -c blocked in DISCUSS"

# Test: chained cp (no ^ anchor) blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"cd /tmp && cp src dst"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: chained cp blocked in DISCUSS"

# Test: VAR=x rm blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"VAR=x rm file"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: prefixed rm blocked in DISCUSS"

# Test: command cp blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"command cp src dst"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: command cp blocked in DISCUSS"
```

- [ ] **Step 3: Write failing tests for heredoc variants and missing commands**

```bash
# Test: bash heredoc blocked
RESULT=$(echo '{"tool_input":{"command":"bash << EOF\necho hello\nEOF"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: bash heredoc blocked in DISCUSS"

# Test: sh heredoc blocked
RESULT=$(echo '{"tool_input":{"command":"sh << '"'"'EOF'"'"'\necho hello\nEOF"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: sh heredoc blocked in DISCUSS"

# Test: python3 heredoc blocked
RESULT=$(echo '{"tool_input":{"command":"python3 << EOF\nprint(1)\nEOF"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: python3 heredoc blocked in DISCUSS"

# Test: touch blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"touch newfile.txt"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: touch blocked in DISCUSS"

# Test: truncate blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"truncate -s 0 file"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: truncate blocked in DISCUSS"

# Test: perl -i blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"perl -i -pe '"'"'s/old/new/'"'"' file"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: perl -i blocked in DISCUSS"

# Test: tar xf blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"tar xf archive.tar"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: tar xf blocked in DISCUSS"

# Test: unzip blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"unzip archive.zip"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: unzip blocked in DISCUSS"

# Test: rsync blocked in DISCUSS
RESULT=$(echo '{"tool_input":{"command":"rsync -av src/ dst/"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: rsync blocked in DISCUSS"
```

- [ ] **Step 4: Write regression tests**

```bash
# Test: all new patterns allowed in IMPLEMENT phase
python3 -c "import json; d=json.load(open('$STATE_FILE')); d['phase']='implement'; json.dump(d,open('$STATE_FILE','w'),indent=2)"
RESULT=$(echo '{"tool_input":{"command":"eval \"echo hello\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_eq "" "$RESULT" "bash-guard: eval allowed in IMPLEMENT"

RESULT=$(echo '{"tool_input":{"command":"touch newfile.txt"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_eq "" "$RESULT" "bash-guard: touch allowed in IMPLEMENT"

# Test: multi-line python3 blocked at Level 1 even in IMPLEMENT
python3 -c "import json; d=json.load(open('$STATE_FILE')); d['autonomy_level']=1; json.dump(d,open('$STATE_FILE','w'),indent=2)"
RESULT=$(echo '{"tool_input":{"command":"python3 -c \"\nwith open('"'"'f'"'"','"'"'w'"'"') as fh:\n  fh.write('"'"'x'"'"')\n\""}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>/dev/null)
assert_contains "$RESULT" "deny" "bash-guard: python3 write blocked at Level 1 in IMPLEMENT"

# Reset
python3 -c "import json; d=json.load(open('$STATE_FILE')); d['phase']='discuss'; d['autonomy_level']=2; json.dump(d,open('$STATE_FILE','w'),indent=2)"
```

- [ ] **Step 5: Run all new tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | grep -E "FAIL.*(multi-line|eval|bash -c|sh -c|chained cp|touch|truncate|perl|tar|unzip|rsync|heredoc|prefixed|command cp)"`
Expected: Multiple FAILs for the bypass tests

- [ ] **Step 6: Implement WRITE_PATTERN restructure (8a + 8c)**

In `.claude/hooks/bash-write-guard.sh`, replace line 24 (the WRITE_PATTERN definition) with:

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
#  10. Wrappers: eval, bash -c, sh -c
WRITE_PATTERN='(>[^&]|>>|sed[[:space:]]+-i|perl[[:space:]]+-i|ruby[[:space:]]+-i|tee[[:space:]]|cat[[:space:]].*<<|bash[[:space:]].*<<|sh[[:space:]].*<<|python[3]?[[:space:]].*<<|echo[[:space:]].*>|cp[[:space:]]|mv[[:space:]]|rm[[:space:]]|install[[:space:]]|curl[[:space:]].*-o[[:space:]]|wget[[:space:]].*-O[[:space:]]|dd[[:space:]].*of=|patch[[:space:]]|ln[[:space:]]|touch[[:space:]]|truncate[[:space:]]|tar[[:space:]].*-?x|unzip[[:space:]]|rsync[[:space:]]|eval[[:space:]]|bash[[:space:]]+-c|sh[[:space:]]+-c)'
```

- [ ] **Step 7: Implement PYTHON_WRITE flag (8b)**

In `.claude/hooks/bash-write-guard.sh`, after the CLEAN_CMD construction (line 62, `CLEAN_CMD=$(echo...)`), add:

```bash
# Multi-line python3 write detection — separate from WRITE_PATTERN because
# the compound pattern (python -c + write indicator) can span lines.
PYTHON_WRITE=false
if echo "$COMMAND" | grep -qE 'python[3]?[[:space:]]+-c'; then
    if echo "$COMMAND" | grep -qiE '\.(write|open|read_text|write_text)|os\.(system|remove|rename|unlink|makedirs)|subprocess\.(run|call|Popen|check_call|check_output)|shutil\.(copy|move|rmtree|copytree)'; then
        PYTHON_WRITE=true
    fi
fi
```

- [ ] **Step 8: Update Level 1 check to include PYTHON_WRITE**

In the Level 1 autonomy check block, change:
```bash
    if echo "$CLEAN_CMD" | grep -qE "$WRITE_PATTERN"; then
```
To:
```bash
    if echo "$CLEAN_CMD" | grep -qE "$WRITE_PATTERN" || [ "$PYTHON_WRITE" = "true" ]; then
```

- [ ] **Step 9: Update phase-gated check to include PYTHON_WRITE**

In the phase-gated write detection (after whitelist selection), change:
```bash
if echo "$CLEAN_CMD" | grep -qE "$WRITE_PATTERN"; then
```
To:
```bash
if echo "$CLEAN_CMD" | grep -qE "$WRITE_PATTERN" || [ "$PYTHON_WRITE" = "true" ]; then
```

- [ ] **Step 10: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -5`
Expected: All tests pass (old + new)

- [ ] **Step 11: Commit**

```bash
git add .claude/hooks/bash-write-guard.sh tests/run-tests.sh
git commit -m "security: harden bash-write-guard against multi-line and wrapper bypasses

Close multiple bypass vectors: multi-line python3 -c (PYTHON_WRITE flag),
eval/bash -c/sh -c wrappers, ^-anchored pattern evasion via command
chaining, bash/sh/python3 heredocs, and missing write commands (touch,
truncate, perl -i, ruby -i, tar, unzip, rsync).

Defense-in-depth: fail-closed for restrictive phases, IMPLEMENT/REVIEW
unaffected via early exit."
```

---

### Task 4: Coaching silence counter (Item 4)

**Files:**
- Modify: `.claude/hooks/workflow-state.sh` (add `check_coaching_refresh`, modify `add_coaching_fired`)
- Modify: `.claude/hooks/post-tool-navigator.sh` (add refresh call in Layer 2 block)
- Test: `tests/run-tests.sh` (add to `=== post-tool-navigator.sh ===` section, ~line 880)

- [ ] **Step 1: Write failing tests**

Add to the `=== post-tool-navigator.sh ===` section:

```bash
# --- Coaching refresh tests ---

# Test: Layer 2 trigger fires normally (baseline)
python3 -c "
import json
d = {'phase':'discuss','message_shown':True,'active_skill':'','decision_record':'','coaching':{'tool_calls_since_agent':0,'layer2_fired':[]},'autonomy_level':2}
with open('$STATE_FILE','w') as f: json.dump(d,f,indent=2); f.write('\n')
"
# Simulate an Agent return (fires agent_return_discuss trigger)
echo '{"tool_name":"Agent","tool_input":{"prompt":"test"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1
FIRED=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('coaching',{}).get('layer2_fired',[]))")
assert_contains "$FIRED" "agent_return_discuss" "coaching: Layer 2 trigger fires on Agent return"

# Test: same trigger does NOT re-fire immediately
echo '{"tool_name":"Agent","tool_input":{"prompt":"test again"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1
FIRED_COUNT=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('coaching',{}).get('layer2_fired',[]).count('agent_return_discuss'))")
assert_eq "1" "$FIRED_COUNT" "coaching: same trigger does not re-fire"

# Test: after 30 calls of silence, trigger re-fires
python3 -c "
import json
d = json.load(open('$STATE_FILE'))
d['coaching']['tool_calls_since_agent'] = 31
d['coaching']['last_layer2_at'] = 0
with open('$STATE_FILE','w') as f: json.dump(d,f,indent=2); f.write('\n')
"
echo '{"tool_name":"Agent","tool_input":{"prompt":"test after refresh"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1
FIRED_COUNT=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('coaching',{}).get('layer2_fired',[]).count('agent_return_discuss'))")
assert_eq "1" "$FIRED_COUNT" "coaching: trigger re-fires after 30 calls of silence"

# Test: backward compat — state file without last_layer2_at field
python3 -c "
import json
d = {'phase':'discuss','message_shown':True,'active_skill':'','decision_record':'','coaching':{'tool_calls_since_agent':5,'layer2_fired':[]},'autonomy_level':2}
with open('$STATE_FILE','w') as f: json.dump(d,f,indent=2); f.write('\n')
"
echo '{"tool_name":"Agent","tool_input":{"prompt":"test compat"}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1
RESULT=$?
assert_eq "0" "$RESULT" "coaching: no crash without last_layer2_at field"
```

- [ ] **Step 2: Run tests to verify refresh test fails**

Run: `bash tests/run-tests.sh 2>&1 | grep -E "(PASS|FAIL).*coaching"`
Expected: "re-fires after 30 calls" test FAIL (refresh not implemented yet)

- [ ] **Step 3: Implement `check_coaching_refresh` in workflow-state.sh**

Add after the `has_coaching_fired` function (around line 655):

```bash
# Check if Layer 2 coaching should be refreshed (30+ calls of silence)
# Silently clears layer2_fired array if threshold exceeded — no stdout output
# to avoid corrupting hook JSON stream.
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

- [ ] **Step 4: Modify `add_coaching_fired` to record `last_layer2_at`**

Replace the existing `add_coaching_fired` function with the version from the spec that also sets `coaching['last_layer2_at']`:

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

- [ ] **Step 5: Add refresh call in post-tool-navigator.sh**

In `.claude/hooks/post-tool-navigator.sh`, inside the `if [ "$(get_message_shown)" = "true" ]` block, after the counter increment logic (around line 179), add:

```bash
    # Refresh Layer 2 triggers after 30 calls of silence
    check_coaching_refresh
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -5`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add .claude/hooks/workflow-state.sh .claude/hooks/post-tool-navigator.sh tests/run-tests.sh
git commit -m "feat: refresh coaching Layer 2 triggers after 30 calls of silence

Layer 1 coaching fires once at phase entry then gets evicted from
context in long sessions. Global silence counter re-enables all Layer 2
triggers after 30 tool calls without any Layer 2 firing. Additive state
change (last_layer2_at field), backward compatible."
```

---

### Task 5: Observation ID tracking regardless of phase (Item 6)

**Files:**
- Modify: `.claude/hooks/workflow-state.sh` (`set_last_observation_id`)
- Modify: `.claude/hooks/post-tool-navigator.sh` (restructure top of file)
- Test: `tests/run-tests.sh` (add to `=== post-tool-navigator.sh ===` section)

- [ ] **Step 1: Write failing tests**

Add to the post-tool-navigator test section:

```bash
# --- Observation ID tracking in OFF phase ---

# Test: observation ID captured when phase is OFF + state file exists
python3 -c "
import json
d = {'phase':'off','message_shown':False,'active_skill':'','decision_record':'','coaching':{'tool_calls_since_agent':0,'layer2_fired':[]},'autonomy_level':2}
with open('$STATE_FILE','w') as f: json.dump(d,f,indent=2); f.write('\n')
"
echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__save_observation","tool_input":{"text":"test"},"tool_response":{"content":[{"type":"text","text":"{\"id\":9999,\"success\":true}"}]}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1
OBS_ID=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('last_observation_id',''))")
assert_eq "9999" "$OBS_ID" "obs-tracking: ID captured when phase is OFF"

# Test: observation ID captured when no state file exists
rm -f "$STATE_FILE"
echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__save_observation","tool_input":{"text":"test"},"tool_response":{"content":[{"type":"text","text":"{\"id\":8888,\"success\":true}"}]}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1
if [ -f "$STATE_FILE" ]; then
    OBS_ID=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('last_observation_id',''))")
    assert_eq "8888" "$OBS_ID" "obs-tracking: ID captured and state file created"
else
    assert_eq "exists" "missing" "obs-tracking: state file should have been created"
fi

# Test: observation ID still works in active phase (regression)
python3 -c "
import json
d = {'phase':'discuss','message_shown':True,'active_skill':'','decision_record':'','coaching':{'tool_calls_since_agent':0,'layer2_fired':[]},'autonomy_level':2}
with open('$STATE_FILE','w') as f: json.dump(d,f,indent=2); f.write('\n')
"
echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__get_observations","tool_input":{"ids":[1]},"tool_response":{"content":[{"type":"text","text":"[{\"id\":7777}]"}]}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1
OBS_ID=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('last_observation_id',''))")
assert_eq "7777" "$OBS_ID" "obs-tracking: ID captured in active phase (regression)"
```

- [ ] **Step 2: Run tests to verify OFF phase test fails**

Run: `bash tests/run-tests.sh 2>&1 | grep -E "(PASS|FAIL).*obs-tracking"`
Expected: "ID captured when phase is OFF" FAIL (currently exits early)

- [ ] **Step 3: Restructure post-tool-navigator.sh top section**

Move `INPUT=$(cat)` and `TOOL_NAME` extraction to the very top (after `source workflow-state.sh`), then the observation ID block, then the early exits. The new structure:

```bash
#!/bin/bash
# [copyright header unchanged]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workflow-state.sh"

# Read tool input from stdin — consumed once, used by all layers
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")

# ---------------------------------------------------------------------------
# Claude-mem observation ID tracking (runs regardless of phase)
# ---------------------------------------------------------------------------
if echo "$TOOL_NAME" | grep -qE 'mcp.*(save_observation|get_observations)'; then
    # [existing extraction logic — unchanged]
    ...
fi

# No state file = no enforcement
if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

PHASE=$(get_phase)

# OFF phase = no coaching
if [ "$PHASE" = "off" ]; then
    exit 0
fi

# [rest of coaching logic unchanged — but remove the duplicate INPUT=$(cat)
# and TOOL_NAME extraction that were previously at lines 33-34]
```

**Important:** Remove the old `INPUT=$(cat)` at line 33 and `TOOL_NAME` extraction at line 34 since they've moved to the top. The rest of the file references `$INPUT` and `$TOOL_NAME` — these still work since the variables are now set earlier.

- [ ] **Step 4: Modify `set_last_observation_id` to create state file if missing**

In `.claude/hooks/workflow-state.sh`, replace the `set_last_observation_id` function:

```bash
set_last_observation_id() {
    local obs_id="$1"
    mkdir -p "$STATE_DIR"
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [ ! -f "$STATE_FILE" ]; then
        # Create minimal state file for observation tracking
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

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -5`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add .claude/hooks/workflow-state.sh .claude/hooks/post-tool-navigator.sh tests/run-tests.sh
git commit -m "fix: track observation IDs regardless of workflow phase

Move observation extraction above phase early-exits in post-tool-navigator.
set_last_observation_id now creates a minimal state file if none exists.
Fixes status line not showing latest claude-mem observation number."
```

---

### Task 6: Observation extraction hardening tests (Item 5)

**Files:**
- Test: `tests/run-tests.sh` (add to `=== post-tool-navigator.sh ===` section)

- [ ] **Step 1: Write tests for malformed responses**

Add to the post-tool-navigator test section:

```bash
# --- Observation extraction edge cases ---

# Test: empty content array — graceful degradation
python3 -c "
import json
d = {'phase':'discuss','message_shown':True,'active_skill':'','decision_record':'','coaching':{'tool_calls_since_agent':0,'layer2_fired':[]},'autonomy_level':2,'last_observation_id':1234}
with open('$STATE_FILE','w') as f: json.dump(d,f,indent=2); f.write('\n')
"
echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__save_observation","tool_input":{"text":"test"},"tool_response":{"content":[]}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1
OBS_ID=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('last_observation_id',''))")
assert_eq "1234" "$OBS_ID" "obs-extraction: empty content preserves existing ID"

# Test: non-JSON text block — graceful degradation
echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__save_observation","tool_input":{"text":"test"},"tool_response":{"content":[{"type":"text","text":"not valid json"}]}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1
OBS_ID=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('last_observation_id',''))")
assert_eq "1234" "$OBS_ID" "obs-extraction: non-JSON preserves existing ID"

# Test: missing id field — graceful degradation
echo '{"tool_name":"mcp__plugin_claude-mem_mcp-search__save_observation","tool_input":{"text":"test"},"tool_response":{"content":[{"type":"text","text":"{\"success\":true}"}]}}' | \
    CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1
OBS_ID=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('last_observation_id',''))")
assert_eq "1234" "$OBS_ID" "obs-extraction: missing id preserves existing ID"
```

- [ ] **Step 2: Run tests to verify they pass (existing code handles these)**

Run: `bash tests/run-tests.sh 2>&1 | grep -E "(PASS|FAIL).*obs-extraction"`
Expected: All PASS (existing extraction code already handles edge cases)

- [ ] **Step 3: Commit**

```bash
git add tests/run-tests.sh
git commit -m "test: add edge case tests for observation extraction

Verify graceful degradation on empty content, non-JSON text, and
missing id field. Existing code handles all cases — tests confirm."
```

---

### Task 7: README overhaul (Item 7)

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite README with new structure**

Rewrite `README.md` with this structure:
1. Title + tagline + badges
2. Four core tools with corrected descriptions (Workflow Manager → "Phase-based workflow enforcement with coaching and edit gates")
3. Workflow phases table
4. Autonomy levels section
5. Core Tools table (without YubiKey/iTerm)
6. Optional Tools section (YubiKey, iTerm — clearly marked as opt-in with `--iterm`/`--yubikey` flags)
7. Docs links
8. Install section (moved down)
9. Sources section (renamed from "Informed By", add claude-mem sources)
10. Contributing
11. License

Sources to add:
- [claude-mem](https://github.com/thedotmack/claude-mem) — cross-session memory MCP server
- [Context Engineering for AI Agents](https://docs.claude-mem.ai/context-engineering) — context rot, progressive disclosure, agentic memory

Keep existing Anthropic links.

- [ ] **Step 2: Review README for accuracy**

Read through the full README and verify:
- All doc links point to files that exist
- Phase table matches actual behavior
- Autonomy level descriptions match `autonomy.md`
- Install instructions are correct
- No mentions of YubiKey/iTerm as "core" tools

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: overhaul README structure and accuracy

Fix Workflow Manager description, move install section below tools/docs,
rename Informed By to Sources with claude-mem additions, separate
optional tools (YubiKey, iTerm) from core package."
```

---

### Task 8: Installer missing permissions

**Files:**
- Modify: `install.sh` (fresh-create path ~line 172 and merge path ~line 137)
- Test: `tests/run-tests.sh` (add to `=== install.sh ===` section, ~line 779)

The installer creates `settings.json` with hooks but no `permissions.allow` block. Projects that install Workflow Manager get hook enforcement but Claude Code prompts for permission on every Bash call because `Bash` isn't in the allow list. This breaks Level 3 (unattended) operation.

- [ ] **Step 1: Write failing tests**

Add to the `=== install.sh ===` section in `tests/run-tests.sh`:

```bash
# Test: fresh install includes Bash in permissions allow list
FRESH_DIR=$(mktemp -d)
mkdir -p "$FRESH_DIR/.git"
bash install.sh "$FRESH_DIR" 2>/dev/null
BASH_ALLOWED=$(python3 -c "
import json
with open('$FRESH_DIR/.claude/settings.json') as f:
    d = json.load(f)
perms = d.get('permissions', {}).get('allow', [])
print('true' if 'Bash' in perms else 'false')
")
assert_eq "true" "$BASH_ALLOWED" "install: fresh install includes Bash permission"

# Test: fresh install includes WebFetch in permissions allow list
WF_ALLOWED=$(python3 -c "
import json
with open('$FRESH_DIR/.claude/settings.json') as f:
    d = json.load(f)
perms = d.get('permissions', {}).get('allow', [])
print('true' if 'WebFetch' in perms else 'false')
")
assert_eq "true" "$WF_ALLOWED" "install: fresh install includes WebFetch permission"

# Test: fresh install includes WebSearch in permissions allow list
WS_ALLOWED=$(python3 -c "
import json
with open('$FRESH_DIR/.claude/settings.json') as f:
    d = json.load(f)
perms = d.get('permissions', {}).get('allow', [])
print('true' if 'WebSearch' in perms else 'false')
")
assert_eq "true" "$WS_ALLOWED" "install: fresh install includes WebSearch permission"
rm -rf "$FRESH_DIR"

# Test: merge install adds permissions to existing settings.json
MERGE_DIR=$(mktemp -d)
mkdir -p "$MERGE_DIR/.git" "$MERGE_DIR/.claude"
echo '{"permissions":{"allow":["SomeExisting"]}}' > "$MERGE_DIR/.claude/settings.json"
bash install.sh "$MERGE_DIR" 2>/dev/null
BASH_MERGED=$(python3 -c "
import json
with open('$MERGE_DIR/.claude/settings.json') as f:
    d = json.load(f)
perms = d.get('permissions', {}).get('allow', [])
print('true' if all(t in perms for t in ['Bash','WebFetch','WebSearch','SomeExisting']) else 'false')
")
assert_eq "true" "$BASH_MERGED" "install: merge preserves existing and adds all permissions"
rm -rf "$MERGE_DIR"

# Test: re-install with hooks present but no permissions adds permissions
RERUN_DIR=$(mktemp -d)
mkdir -p "$RERUN_DIR/.git" "$RERUN_DIR/.claude"
cat > "$RERUN_DIR/.claude/settings.json" <<'NOPERMS'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{"type":"command","command":"$CLAUDE_PROJECT_DIR/.claude/hooks/workflow-gate.sh"}]
      }
    ]
  }
}
NOPERMS
bash install.sh "$RERUN_DIR" 2>/dev/null
RERUN_PERMS=$(python3 -c "
import json
with open('$RERUN_DIR/.claude/settings.json') as f:
    d = json.load(f)
perms = d.get('permissions', {}).get('allow', [])
print('true' if 'Bash' in perms else 'false')
")
assert_eq "true" "$RERUN_PERMS" "install: re-install adds permissions when hooks already present"
rm -rf "$RERUN_DIR"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | grep -E "(PASS|FAIL).*install.*permission"`
Expected: FAIL — permissions not included in current installer

- [ ] **Step 3: Update fresh-create path in install.sh**

In `install.sh`, replace the fresh `settings.json` creation (around line 172-207) to include permissions:

```bash
    cat > "$SETTINGS" <<'HOOKSCFG'
{
  "permissions": {
    "allow": [
      "Bash",
      "WebFetch",
      "WebSearch"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/workflow-gate.sh"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/bash-write-guard.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/post-tool-navigator.sh"
          }
        ]
      }
    ]
  }
}
HOOKSCFG
    ok "Created settings.json with hooks and permissions"
```

- [ ] **Step 4: Update merge path in install.sh**

In the Python merge block (around line 137-168), add permissions merging after the hooks merging:

```python
# Permissions
perms = settings.setdefault('permissions', {})
allow = perms.setdefault('allow', [])
for tool in ['Bash', 'WebFetch', 'WebSearch']:
    if tool not in allow:
        allow.append(tool)
```

- [ ] **Step 5: Update the "hooks already configured" check**

The existing check at line 134 (`if grep -q "workflow-gate.sh" "$SETTINGS"`) skips merging entirely if hooks are already present. This means existing installs that already have hooks but are missing permissions won't get the permissions added. Update to also check for permissions:

```bash
    if grep -q "workflow-gate.sh" "$SETTINGS" 2>/dev/null; then
        # Hooks present — ensure permissions are also set
        PERM_STATUS=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    settings = json.load(f)
perms = settings.setdefault('permissions', {})
allow = perms.setdefault('allow', [])
changed = False
for tool in ['Bash', 'WebFetch', 'WebSearch']:
    if tool not in allow:
        allow.append(tool)
        changed = True
if changed:
    with open(sys.argv[1], 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
    print('updated')
else:
    print('ok')
" "$SETTINGS")
        if [ "$PERM_STATUS" = "updated" ]; then
            ok "Hooks already configured, added missing permissions"
        else
            ok "Hooks already configured in settings.json"
        fi
    else
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -5`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add install.sh tests/run-tests.sh
git commit -m "fix: installer now includes Bash/WebFetch/WebSearch permissions

Fresh installs got hooks but no permissions, causing Claude Code to
prompt for every Bash command. Existing installs with hooks but missing
permissions are also updated on re-run. Fixes Level 3 (unattended)
operation for newly installed projects."
```

---

### Task 9: Final verification

- [ ] **Step 1: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass (263 existing + ~45 new)

- [ ] **Step 2: Verify spec and plan committed**

```bash
git add docs/superpowers/specs/2026-03-23-tech-debt-readme-design.md docs/superpowers/plans/2026-03-23-tech-debt-readme.md
git commit -m "docs: add spec and implementation plan for tech debt cleanup"
```

- [ ] **Step 3: Verify observation ID appears in status line**

Run workflow-cmd.sh to check state has `last_observation_id` set (from earlier claude-mem calls this session).
