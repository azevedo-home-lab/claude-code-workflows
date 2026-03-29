# Open Issues Cleanup v1.13.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 4 code/doc issues and close 2 stale observations from the v1.12.0 open issues backlog.

**Architecture:** Five targeted edits across four files plus two claude-mem observation closures. No new files, no structural changes. Each task is independent and can be committed separately.

**Tech Stack:** bash, markdown, claude-mem MCP

**Spec:** `docs/superpowers/specs/2026-03-28-open-issues-cleanup-design.md`

---

### Task 1: Fix bash-write-guard.sh CLEAN_CMD false positive (#4952)

**Problem:** `CLEAN_CMD` stripping at line 134 only removes digit-prefixed `/dev/null` redirects (`2>/dev/null`) but not bare `>/dev/null`. Commands like `bash -n plugin/scripts/setup.sh > /dev/null` trigger the guard because `> /dev/null` survives stripping and matches `REDIRECT_OPS`.

**Files:**
- Modify: `plugin/scripts/bash-write-guard.sh:134`

- [ ] **Step 1: Read the current line to confirm exact text**

```bash
sed -n '134p' plugin/scripts/bash-write-guard.sh
```
Expected output:
```
CLEAN_CMD=$(echo "$COMMAND" | sed -E 's/[0-9]+>\/dev\/null//g; s/[0-9]*>&[0-9]+//g')
```

- [ ] **Step 2: Verify the false positive is reproducible**

Run bash-write-guard.sh manually with the failing input to confirm behaviour before changing:
```bash
echo '{"tool_input":{"command":"bash -n plugin/scripts/setup.sh > /dev/null"}}' | \
  PHASE=discuss bash plugin/scripts/bash-write-guard.sh 2>&1 || true
```
Expected: output contains `BLOCKED`

- [ ] **Step 3: Edit line 134 to also strip bare >/dev/null**

Change line 134 from:
```bash
CLEAN_CMD=$(echo "$COMMAND" | sed -E 's/[0-9]+>\/dev\/null//g; s/[0-9]*>&[0-9]+//g')
```
To:
```bash
CLEAN_CMD=$(echo "$COMMAND" | sed -E 's/[0-9]+>\/dev\/null//g; s/[0-9]*>&[0-9]+//g; s/>>[[:space:]]*\/dev\/null//g; s/>[[:space:]]*\/dev\/null//g')
```

Note: `>>` must be stripped before `>` (ordering matters — otherwise the `>` pattern matches the first `>` of `>>` and leaves a trailing `>`).

- [ ] **Step 4: Verify the false positive is gone**

```bash
echo '{"tool_input":{"command":"bash -n plugin/scripts/setup.sh > /dev/null"}}' | \
  PHASE=discuss bash plugin/scripts/bash-write-guard.sh 2>&1 || true
```
Expected: no output (exit 0 — allowed)

- [ ] **Step 5: Verify legitimate write is still blocked**

```bash
echo '{"tool_input":{"command":"echo x > plugin/scripts/workflow-state.sh"}}' | \
  PHASE=discuss bash plugin/scripts/bash-write-guard.sh 2>&1 || true
```
Expected: output contains `BLOCKED`

- [ ] **Step 6: Verify digit-prefixed forms still work**

```bash
echo '{"tool_input":{"command":"bash -n plugin/scripts/setup.sh 2>/dev/null"}}' | \
  PHASE=discuss bash plugin/scripts/bash-write-guard.sh 2>&1 || true
```
Expected: no output (exit 0 — allowed, same as before)

- [ ] **Step 7: Commit**

```bash
git add plugin/scripts/bash-write-guard.sh
git commit -m "fix: strip bare >/dev/null from CLEAN_CMD to eliminate guard false positive

Commands like 'bash -n plugin/scripts/setup.sh > /dev/null' were blocked
because bare '>/dev/null' survived CLEAN_CMD stripping and matched REDIRECT_OPS.
Extended the sed strip to cover bare >/dev/null and >>/dev/null forms.

Fixes open issue #4952."
```

---

### Task 2: Remove loop-back reference in complete.md (#4815)

**Problem:** Line 222 of `complete.md` says `"Version bump missing — loop back to /implement and run the versioning step."` The completion snapshot loop-back was removed in v1.11.0 (commit `8bcba8e`). This reference is stale and confusing.

**Files:**
- Modify: `plugin/commands/complete.md:222`

- [ ] **Step 1: Read the current line to confirm exact text**

```bash
sed -n '220,225p' plugin/commands/complete.md
```

- [ ] **Step 2: Edit line 222**

Change:
```
> "Version bump missing — loop back to `/implement` and run the versioning step."
```
To:
```
> "Version bump missing — run the versioning step before committing."
```

- [ ] **Step 3: Verify no other loop-back or snapshot references remain**

```bash
grep -n "loop back\|loop-back\|completion_snapshot\|save_completion\|restore_completion\|has_completion" plugin/commands/complete.md
```
Expected: no matches

- [ ] **Step 4: Commit**

```bash
git add plugin/commands/complete.md
git commit -m "fix: remove stale loop-back reference in complete.md

'Loop back to /implement' referenced the completion snapshot mechanism
removed in v1.11.0. Replaced with current failure guidance.

Resolves residual from #4815."
```

---

### Task 3: Fix stale docs — wfm-architecture.md (#4949 + #4259)

**Problem 1:** Line 68 of `wfm-architecture.md` says `User /command  → always works (intent file bypasses gates)`. Intent files were removed in v1.12.0. The current mechanism is `user-set-phase.sh` called from `!backtick` in command files.

**Problem 2:** No documentation exists for how CC permission modes interact with WFM autonomy levels. Users setting `/autonomy auto` may be surprised when CC prompts block the pipeline.

**Files:**
- Modify: `plugin/docs/reference/wfm-architecture.md`

- [ ] **Step 1: Read the "Who Can Transition Phases" section**

```bash
sed -n '63,75p' plugin/docs/reference/wfm-architecture.md
```

- [ ] **Step 2: Fix line 68 — replace intent file reference**

Change:
```
User /command  → always works (intent file bypasses gates)
```
To:
```
User /command  → always works (!backtick calls user-set-phase.sh, which writes state directly — no gates)
```

- [ ] **Step 3: Add the CC × WFM permissions matrix section**

After the "Who Can Transition Phases" section (after the closing ` ``` ` of the code block at approximately line 73) and before "The 6 Hook Scripts", insert:

```markdown
## Claude Code Permissions × WFM Autonomy

WFM autonomy levels control what the *agent* should do. Claude Code's permission mode controls which *tool calls* auto-approve without prompting you. These are independent systems — both must be configured for unattended operation to work.

**Evaluation order (highest to lowest precedence):**
1. CC deny rules — always block
2. CC allow rules — always permit
3. CC permission mode — fallback for unmatched tools

| CC Permission Mode | WFM `ask` autonomy | WFM `auto` autonomy | Notes |
|---|---|---|---|
| `default` | Works — Claude prompts on unlisted tools | Works partially — pipeline may stall if Write/Bash prompt appears | Add Write, Edit, Bash to allow list for unattended operation |
| `acceptEdits` | Intended use — edits auto-approve, Bash prompts | Works for edit-heavy pipelines — Bash still prompts | Best match for interactive supervision |
| `auto` | Over-permissive for supervised use | Intended use for unattended pipelines | All tools auto-approve |
| `dontAsk` | All prompts auto-denied — pipeline blocked | All prompts auto-denied — pipeline blocked | Not usable with WFM in any autonomy mode |
| `bypassPermissions` | **WFM enforcement does not apply** — hooks do not fire | **WFM enforcement does not apply** — hooks do not fire | Phase gates, write guards, and coaching are all bypassed |

**Recommended setup for `/autonomy auto` (unattended):** Use `auto` or `acceptEdits` CC mode and ensure Write, Edit, Bash are in your allow list in `.claude/settings.json`.

```

- [ ] **Step 4: Verify the document renders cleanly**

```bash
grep -n "intent file\|phase-intent\|autonomy-intent" plugin/docs/reference/wfm-architecture.md
```
Expected: no matches (all intent file references removed)

- [ ] **Step 5: Commit**

```bash
git add plugin/docs/reference/wfm-architecture.md
git commit -m "docs: fix stale intent file ref + add CC permissions × WFM autonomy matrix

- Line 68: replace 'intent file bypasses gates' with current !backtick mechanism
- New section: CC permission modes × WFM autonomy interaction matrix
  including bypassPermissions warning (hooks do not fire in that mode)

Fixes #4949, closes #4259 as documentation-only."
```

---

### Task 4: Fix stale CONTRIBUTING.md test suite reference (#4949)

**Problem:** Line 52 of `CONTRIBUTING.md` says "Ensure the test suite passes". The automated test suite was deleted in v1.12.0 (commit removed `tests/run-tests.sh`). Line 30 was already updated but line 52 in the PR process section was missed.

**Files:**
- Modify: `CONTRIBUTING.md:52`

- [ ] **Step 1: Read the PR Process section**

```bash
sed -n '48,58p' CONTRIBUTING.md
```

- [ ] **Step 2: Edit line 52**

Change:
```
1. Ensure the test suite passes
```
To:
```
1. Verify manually: run the workflow through at least one full IMPLEMENT → REVIEW → COMPLETE cycle and confirm no regressions
```

- [ ] **Step 3: Verify no other test suite references remain**

```bash
grep -n "test suite\|run-tests" CONTRIBUTING.md
```
Expected: no matches

- [ ] **Step 4: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "docs: fix stale test suite reference in CONTRIBUTING.md

The automated test suite was deleted in v1.12.0. Line 52 in the PR
process section still referenced it. Updated to describe current
manual verification workflow.

Part of #4949 cleanup."
```

---

### Task 5: Close stale observations in claude-mem (#4816, #4671)

**Problem:** Two open observations are no longer actionable — their questions have been answered during this session's research.

- **#4816:** CC bug #22345 concern about Check 8 using Skill invocation. Research confirmed Check 8 uses direct `workflow-cmd.sh` bash calls, not Skill invocation. Non-issue.
- **#4671:** Check 9 redundancy monitoring. User decision: keep Check 9 unchanged.

**Files:**
- claude-mem MCP (no code files)

- [ ] **Step 1: Save resolution observation for #4816**

Use the `mcp__plugin_claude-mem_mcp-search__save_observation` tool:

```
project: claude-code-workflows
type: discovery
title: RESOLVED — Check 8 uses bash not Skill; CC bug #22345 does not apply
narrative: |
  ## Resolution of Open Issue #4816

  Observation #4816 was concerned that Check 8 auto-transitions in
  post-tool-navigator.sh used Skill invocation, which is subject to
  CC bug #22345 (disable-model-invocation silently ignored for plugin skills).

  Investigation during 2026-03-28 open issues cleanup session confirmed:
  Check 8 (lines 462-497 of post-tool-navigator.sh) emits coaching messages
  that instruct the agent to run:
    .claude/hooks/workflow-cmd.sh agent_set_phase "review"
    .claude/hooks/workflow-cmd.sh reset_review_status

  These are direct workflow-cmd.sh bash invocations. No Skill invocation
  is present. CC bug #22345 does not apply.

  The design spec Component 5 (docs/superpowers/specs/2026-03-27-security-fixes-architecture-cleanup-design.md)
  references disable-model-invocation frontmatter as a separate concern —
  that is a different item from the Check 8 stall message mechanism.

  Status: CLOSED. No code change required.
```

- [ ] **Step 2: Save resolution observation for #4671**

Use the `mcp__plugin_claude-mem_mcp-search__save_observation` tool:

```
project: claude-code-workflows
type: discovery
title: RESOLVED — Check 9 kept unchanged; evaluate period complete
narrative: |
  ## Resolution of Open Issue #4671

  Observation #4671 flagged Check 9 (within-phase step ordering enforcement
  in post-tool-navigator.sh) as potentially redundant with the COMPLETE
  phase agent pipeline, and requested evaluation after 2-3 stable sessions.

  User decision during 2026-03-28 session: keep Check 9 unchanged.
  Rationale: "if it is working why change?" Defense-in-depth is acceptable
  even with the agent pipeline. Check 9 also enforces step ordering in
  DISCUSS phase (plan-before-research gate) where it is the sole enforcement.

  Status: CLOSED. Evaluate period complete. No code change.
```

- [ ] **Step 3: Verify both observations saved**

Inspect the tool response from Steps 1 and 2 — each should return a non-null numeric `id` field confirming the observation was persisted. No bash command needed; the MCP response is the evidence.

---

### Task 6: Register decision record and finalize

- [ ] **Step 1: Register the spec as the decision record for this cycle**

```bash
.claude/hooks/workflow-cmd.sh set_decision_record "docs/superpowers/specs/2026-03-28-open-issues-cleanup-design.md"
```

- [ ] **Step 2: Verify all changes**

```bash
git log --oneline -6
```
Expected: 4 commits visible (Tasks 1-4), plus any earlier commits

- [ ] **Step 3: Verify no stale references remain across the key files**

```bash
grep -rn "intent file\|test suite passes\|loop back to.*implement\|WF_SKIP_AUTH" \
  plugin/docs/reference/wfm-architecture.md \
  CONTRIBUTING.md \
  plugin/commands/complete.md \
  plugin/scripts/bash-write-guard.sh
```
Expected: no matches
