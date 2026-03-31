# Coaching Visibility Improvements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make WFM coaching messages visible to users in the terminal via `systemMessage`, with file paths and content previews.

**Architecture:** All changes are in `plugin/scripts/post-tool-navigator.sh`. The approach enriches `_trace()` calls at each coaching fire site to include file path + truncated content preview, downgrades noise to `_log()`, and adds infrastructure command detection for early exit.

**Tech Stack:** Bash, jq

**Spec:** `docs/plans/2026-03-30-debug-show-mode.md` (Issue #31 section)

---

### Task 1: Infrastructure skip for Bash calls

**Files:**
- Modify: `plugin/scripts/post-tool-navigator.sh:42-47` (after stdin read, before state file check)

- [ ] **Step 1: Add infrastructure command detection after line 47**

Insert after the `extract_bash_command()` helper (line 47), before the observation ID tracking block (line 55):

```bash
# Skip coaching entirely for infrastructure Bash calls (phase transitions, state queries).
# PostToolUse output for these is swallowed by Claude Code, so L1 would waste
# its once-per-phase message on an invisible call.
if [ "$TOOL_NAME" = "Bash" ]; then
    _INFRA_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || _INFRA_CMD=""
    if echo "$_INFRA_CMD" | grep -qE '(user-set-phase\.sh|workflow-cmd\.sh|workflow-state\.sh)'; then
        exit 0
    fi
fi
```

- [ ] **Step 2: Verify infrastructure skip**

Run:
```bash
echo '{"tool_name":"Bash","tool_input":{"command":".claude/hooks/workflow-cmd.sh get_phase"}}' | bash plugin/scripts/post-tool-navigator.sh
echo "Exit: $?"
```
Expected: no output, exit 0.

- [ ] **Step 3: Verify normal Bash calls still work**

Run:
```bash
bash -n plugin/scripts/post-tool-navigator.sh
```
Expected: no syntax errors.

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/post-tool-navigator.sh
git commit -m "fix: skip coaching for infrastructure Bash calls in post-tool-navigator

Infrastructure commands (workflow-cmd.sh, user-set-phase.sh, workflow-state.sh)
trigger PostToolUse but Claude Code swallows the output. L1 was firing on these
invisible calls, wasting the once-per-phase coaching message.

Fixes part of #31"
```

---

### Task 2: Downgrade noise lines from `_trace()` to `_log()`

**Files:**
- Modify: `plugin/scripts/post-tool-navigator.sh:632,637,644-645`

- [ ] **Step 1: Change L3 boolean dump from `_trace` to `_log`**

At line 632, change:
```bash
_trace "[WFM coach] L3: short_agent=$_L3_SHORT_AGENT, generic_commit=$_L3_GENERIC_COMMIT, all_downgraded=$_L3_ALL_DOWNGRADED, minimal_handover=$_L3_MINIMAL_HANDOVER, missing_project=$_L3_MISSING_PROJECT, skip_research=$_L3_SKIP_RESEARCH, options_no_rec=$_L3_OPTIONS_NO_REC, no_verify=$_L3_NO_VERIFY, stalled=$_L3_STALLED, step_order=$_L3_STEP_ORDER"
```
To:
```bash
_log "[WFM coach] L3: short_agent=$_L3_SHORT_AGENT, generic_commit=$_L3_GENERIC_COMMIT, all_downgraded=$_L3_ALL_DOWNGRADED, minimal_handover=$_L3_MINIMAL_HANDOVER, missing_project=$_L3_MISSING_PROJECT, skip_research=$_L3_SKIP_RESEARCH, options_no_rec=$_L3_OPTIONS_NO_REC, no_verify=$_L3_NO_VERIFY, stalled=$_L3_STALLED, step_order=$_L3_STEP_ORDER"
```

- [ ] **Step 2: Change counter summary from `_trace` to `_log`**

At line 637, change:
```bash
_trace "[WFM coach] Counters: calls_since_agent=$_COACH_COUNTER, layer2_fired=[$_COACH_L2_FIRED]"
```
To:
```bash
_log "[WFM coach] Counters: calls_since_agent=$_COACH_COUNTER, layer2_fired=[$_COACH_L2_FIRED]"
```

- [ ] **Step 3: Downgrade "Message sent to Claude:" block**

At lines 644-645, change:
```bash
    _trace "[WFM coach] Message sent to Claude:"
    echo "$MESSAGES" | while IFS= read -r line; do _show "  $line"; done
```
To:
```bash
    _log "[WFM coach] Message sent to Claude:"
    echo "$MESSAGES" | while IFS= read -r line; do _log "  $line"; done
```

- [ ] **Step 4: Verify syntax and that tool header still produces output**

Run:
```bash
bash -n plugin/scripts/post-tool-navigator.sh
```
Expected: no syntax errors.

Note: The tool header `_trace "[WFM coach] Tool: $TOOL_NAME (phase=$PHASE_UPPER)"` at line 107 remains as `_trace`, ensuring `DEBUG_TRACE` is non-empty in show mode even when no coaching fires.

- [ ] **Step 5: Commit**

```bash
git add plugin/scripts/post-tool-navigator.sh
git commit -m "fix: downgrade coaching noise from _trace to _log in post-tool-navigator

L3 boolean dump, counter summary, and 'Message sent to Claude' block now go
to log file only, not to systemMessage. Reduces terminal noise on every tool
call. Tool header and fire-site traces still go to systemMessage.

Fixes part of #31"
```

---

### Task 3: Enrich L1 fire trace with file path + preview

**Files:**
- Modify: `plugin/scripts/post-tool-navigator.sh:161` (L1 fire trace in default case)
- Modify: `plugin/scripts/post-tool-navigator.sh:130` (L1 fire trace in error case — same block)

- [ ] **Step 1: Enrich default L1 fire trace**

At line 161 (inside the `if [ "$FIRE_LAYER1" = "true" ]` block, after `set_message_shown`), change:
```bash
        _trace "[WFM coach] L1: phase entry — FIRED"
```
To:
```bash
        _trace "[WFM coach] L1: objectives/$PHASE.md — ${OBJ_MSG:0:80}..."
```

Note: `OBJ_MSG` is already in scope — it's set at line 136 (`OBJ_MSG=$(load_message "objectives/$PHASE.md")`). For the error phase (line 129), `ERR_MSG` is the variable. Add a similar trace inside the error case block after line 133:

After line 133 (`fi` closing the error message block), before the `;;`, add:
```bash
                _trace "[WFM coach] L1: objectives/error.md — ${ERR_MSG:0:80}..."
```

And wrap the existing `_trace` at line 161 to only fire for non-error phases (it's already in the `*)` case, so this is automatic).

- [ ] **Step 2: Verify syntax**

Run:
```bash
bash -n plugin/scripts/post-tool-navigator.sh
```

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/post-tool-navigator.sh
git commit -m "fix: show coaching file path and content preview in L1 trace

When L1 fires, users now see:
  [WFM coach] L1: objectives/implement.md — <first 80 chars of message>...
instead of just 'phase entry — FIRED'.

Fixes part of #31"
```

---

### Task 4: Enrich L2 fire trace with file path + preview

**Files:**
- Modify: `plugin/scripts/post-tool-navigator.sh:289` (L2 FIRED trace)

- [ ] **Step 1: Change L2 fire trace**

At line 289, change:
```bash
            _trace "[WFM coach] L2: trigger=$TRIGGER — FIRED"
```
To:
```bash
            _trace "[WFM coach] L2: nudges/$TRIGGER.md — ${L2_MSG_BODY:0:80}..."
```

Note: `L2_MSG_BODY` is in scope — set at line 273 (`L2_MSG_BODY=$(load_message "nudges/$TRIGGER.md")`).

Also enrich the findings_present_review L2 trace. After line 310 (`add_coaching_fired "$FINDINGS_TRIGGER"`), add a trace before the message assignment:
```bash
                    _trace "[WFM coach] L2: nudges/findings_present_review.md — ${FINDINGS_BODY:0:80}..."
```

- [ ] **Step 2: Verify syntax**

Run:
```bash
bash -n plugin/scripts/post-tool-navigator.sh
```

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/post-tool-navigator.sh
git commit -m "fix: show coaching file path and content preview in L2 trace

When L2 fires, users now see:
  [WFM coach] L2: nudges/source_edit_implement.md — <first 80 chars>...
instead of just 'trigger=source_edit_implement — FIRED'.

Fixes part of #31"
```

---

### Task 5: Enrich L3 fire traces with file path + preview

**Files:**
- Modify: `plugin/scripts/post-tool-navigator.sh` — multiple L3 check sites

Each L3 check loads a message via `load_message("checks/<name>.md")` into `CHECK_BODY`, then calls `_append_l3`. Add a `_trace` call at each fire site.

- [ ] **Step 1: Add trace to Check 1 (short agent prompt, ~line 359)**

After:
```bash
        [ -n "$CHECK_BODY" ] && _append_l3 "[Workflow Coach — $PHASE_UPPER] $CHECK_BODY"
        _L3_SHORT_AGENT=true
```
Add:
```bash
        [ -n "$CHECK_BODY" ] && _trace "[WFM coach] L3: checks/short_agent_prompt.md — ${CHECK_BODY:0:80}..."
```

- [ ] **Step 2: Add trace to Check 2 (generic commit, ~line 386)**

After:
```bash
            [ -n "$CHECK_BODY" ] && _append_l3 "[Workflow Coach — $PHASE_UPPER] $CHECK_BODY"
            _L3_GENERIC_COMMIT=true
```
Add:
```bash
            [ -n "$CHECK_BODY" ] && _trace "[WFM coach] L3: checks/generic_commit.md — ${CHECK_BODY:0:80}..."
```

- [ ] **Step 3: Add trace to Check 3 (all findings downgraded, ~line 415)**

After:
```bash
            [ -n "$CHECK_BODY" ] && _append_l3 "[Workflow Coach — REVIEW] $CHECK_BODY"
            _L3_ALL_DOWNGRADED=true
```
Add:
```bash
            [ -n "$CHECK_BODY" ] && _trace "[WFM coach] L3: checks/all_findings_downgraded.md — ${CHECK_BODY:0:80}..."
```

- [ ] **Step 4: Add trace to Check 4a (minimal handover, ~line 435)**

After:
```bash
        [ -n "$CHECK_BODY" ] && _append_l3 "[Workflow Coach — COMPLETE] $CHECK_BODY"
        _L3_MINIMAL_HANDOVER=true
```
Add:
```bash
        [ -n "$CHECK_BODY" ] && _trace "[WFM coach] L3: checks/minimal_handover.md — ${CHECK_BODY:0:80}..."
```

- [ ] **Step 5: Add trace to Check 4b (missing project field, ~line 442)**

After:
```bash
        [ -n "$CHECK_BODY" ] && _append_l3 "[Workflow Coach — $PHASE_UPPER] $CHECK_BODY"
        _L3_MISSING_PROJECT=true
```
Add:
```bash
        [ -n "$CHECK_BODY" ] && _trace "[WFM coach] L3: checks/missing_project_field.md — ${CHECK_BODY:0:80}..."
```

- [ ] **Step 6: Add trace to Check 5 (skipping research, ~line 453)**

After:
```bash
        [ -n "$CHECK_BODY" ] && _append_l3 "[Workflow Coach — $PHASE_UPPER] $CHECK_BODY"
        _L3_SKIP_RESEARCH=true
```
Add:
```bash
        [ -n "$CHECK_BODY" ] && _trace "[WFM coach] L3: checks/skipping_research.md — ${CHECK_BODY:0:80}..."
```

- [ ] **Step 7: Add trace to Check 6 (options without recommendation, ~line 467)**

After:
```bash
        [ -n "$CHECK_BODY" ] && _append_l3 "[Workflow Coach — $PHASE_UPPER] $CHECK_BODY"
        _L3_OPTIONS_NO_REC=true
```
Add:
```bash
        [ -n "$CHECK_BODY" ] && _trace "[WFM coach] L3: checks/options_without_recommendation.md — ${CHECK_BODY:0:80}..."
```

- [ ] **Step 8: Add trace to Check 7 (no verify after edits, ~line 483)**

The verify message is constructed inline, not from `CHECK_BODY`. After:
```bash
                    _append_l3 "$VERIFY_MSG"
                    _L3_NO_VERIFY=true
```
Add:
```bash
                    _trace "[WFM coach] L3: checks/no_verify_after_edits.md — ${VERIFY_MSG:0:80}..."
```

- [ ] **Step 9: Add trace to Check 8 (stalled auto-transition, ~line 523)**

After:
```bash
            _append_l3 "[Workflow Coach — $PHASE_UPPER] $STALL_BODY"
            _L3_STALLED=true
```
Add:
```bash
            _trace "[WFM coach] L3: checks/stalled_auto_transition/$PHASE.md — ${STALL_BODY:0:80}..."
```

- [ ] **Step 10: Add trace to Check 9 (step ordering, ~line 616)**

The step msg is loaded via `_load_step`. After line 617:
```bash
    _L3_STEP_ORDER=true
```
Add:
```bash
    _trace "[WFM coach] L3: step_ordering — ${STEP_MSG:0:80}..."
```

- [ ] **Step 11: Verify syntax**

Run:
```bash
bash -n plugin/scripts/post-tool-navigator.sh
```

- [ ] **Step 12: Commit**

```bash
git add plugin/scripts/post-tool-navigator.sh
git commit -m "fix: show coaching file path and content preview in L3 traces

When any L3 check fires, users now see:
  [WFM coach] L3: checks/short_agent_prompt.md — Agent prompts under 150...
instead of only seeing boolean flags in the summary line.

Fixes part of #31"
```

---

### Task 6: Final verification and close

- [ ] **Step 1: Full syntax check**

Run:
```bash
bash -n plugin/scripts/post-tool-navigator.sh
```

- [ ] **Step 2: Verify clean output on non-firing tool call**

With debug=show active, a normal tool call (no coaching fires) should produce only:
```
[WFM coach] Tool: Bash (phase=IMPLEMENT)
[WFM coach] L1: already shown, skipped
[WFM coach] L2: no trigger matched
```
No L3 boolean dump. No counter summary.

- [ ] **Step 3: Verify coaching fire output format**

After a phase transition, the first relevant tool call should produce:
```
[WFM coach] Tool: Bash (phase=IMPLEMENT)
[WFM coach] L1: objectives/implement.md — <first 80 chars of objective>...
```

- [ ] **Step 4: Close issue**

```bash
gh issue comment 31 --body "Fixed in commits on main. Coaching messages now show file path + content preview in systemMessage. Noise downgraded to log-only."
gh issue close 31
```
