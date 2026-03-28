# Design: Open Issues Cleanup — v1.13.0

**Date:** 2026-03-28
**Issues addressed:** #4952, #4815, #4816, #4671, #4949, #4259

---

## Problem

Six open issues from the WFM auth path separation session (v1.12.0) need resolution:

1. **#4952 (Medium)** — `bash-write-guard.sh` `GUARD_SYSTEM_PATTERN` fires false positives when a command *mentions* a protected path but writes to `/dev/null` (e.g., `bash -n plugin/scripts/setup.sh > /dev/null`). Root cause: guard checks path-mentioned AND write-present, not path-is-write-target.

2. **#4815 (High)** — Background agent isolation for boundary-tester and devils-advocate. `isolation: "worktree"` found to be already implemented in `complete.md` lines 91-101. Only residual: "loop back to `/implement`" text at line 222 references deleted completion snapshot functions.

3. **#4816 (Medium)** — Check 8 auto-transitions concern: worry that Check 8 uses Skill invocation (subject to CC bug #22345). Investigation confirmed Check 8 uses direct `workflow-cmd.sh` bash calls, not Skill invocation. Non-issue.

4. **#4671 (Low)** — Check 9 redundancy monitoring. User decision: keep Check 9 unchanged. Evaluate period complete.

5. **#4949 (Low)** — Stale doc references: `wfm-architecture.md` line 68 still says "intent file bypasses gates" (intent files removed in v1.12.0). `CONTRIBUTING.md` line 52 still says "Ensure the test suite passes" (test suite deleted in v1.12.0).

6. **#4259 (Medium)** — Permission mode awareness. Downgraded from feature to documentation: add CC permissions × WFM autonomy interaction documentation to `wfm-architecture.md`.

---

## Approaches Considered (diverge)

### #4952 — Guard false positives

**Approach A: Inverted guard (target-checking)**
Replace `path_mentioned AND write_present` with `write_target_matches_protected_path`. Reuse the write-target extraction already at line 268. Add sub-patterns for `cp`/`mv`/`tee`/`sed -i`.
- **Pros:** Structurally correct fix; eliminates the entire class of false positives.
- **Cons:** `tee` uses positional args, not `>` redirects — target extractor misses it. `tee plugin/scripts/file.sh` in IMPLEMENT phase would bypass the guard. All positional-arg write commands need explicit coverage or a genuine security regression is introduced.

**Approach B: CLEAN_CMD strip extension** ← Chosen
Extend the `sed` at line 134 to also strip bare `>/dev/null` and `>>/dev/null` (currently only strips digit-prefixed forms like `2>/dev/null`).
- **Pros:** One-line change. No security regressions. Directly eliminates the reported false positive.
- **Cons:** Only fixes `/dev/null` redirects. Other redirect-target false positives not addressed.

### #4259 — Permission awareness

**Full feature (status line + safety mode)** — Rejected. Status line would be polluted by rarely-changing information. WFM already has autonomy levels; a parallel "safety mode" replicates CC's existing permission mode system. User agreed.

**Documentation only** ← Chosen — Add CC permissions × WFM autonomy decision matrix to `wfm-architecture.md`.

---

## Decision (converge)

### Chosen approaches

| Issue | Chosen | Rationale |
|-------|--------|-----------|
| #4952 | Approach B: CLEAN_CMD `/dev/null` strip | Approach A has `tee` bypass risk — not safe without positional-arg patterns for all write commands |
| #4815 | Text fix only: remove "loop back to /implement" | isolation: worktree already in complete.md dispatch |
| #4816 | Close observation, no code change | Check 8 uses bash, not Skill; CC bug #22345 does not apply |
| #4671 | Close observation, no code change | Keep Check 9; evaluate period done per user decision |
| #4949 | Two surgical text fixes | wfm-architecture.md L68 + CONTRIBUTING.md L52 |
| #4259 | Decision matrix in wfm-architecture.md | With explicit bypassPermissions warning |

### Trade-offs accepted

- Approach A (structural guard fix) deferred. Non-`/dev/null` false positive cases (e.g., `> /tmp/out.txt` while mentioning a guard path) are not fixed. If further false positive classes emerge, a new issue should track the full Approach A implementation.

### Risks identified

- Decision matrix for #4259 must explicitly state that `bypassPermissions` CC mode bypasses hooks entirely — WFM enforcement does not apply. Omitting this would be actively misleading.
- CONTRIBUTING.md wording change is low-stakes but must accurately reflect the current manual verification workflow (not just remove the stale line without replacing it meaningfully).

### Tech debt acknowledged

- Approach A (inverted guard, full positional-arg coverage) remains an open architectural improvement. Tracked as deferred work.

---

## CC Permissions × WFM Autonomy Matrix (for wfm-architecture.md)

| CC Permission Mode | WFM `ask` autonomy | WFM `auto` autonomy | Notes |
|---|---|---|---|
| `default` | Works — Claude prompts on unlisted tools | Works partially — pipeline may stall if Write/Bash prompt appears | Configure allow list to cover Write, Edit, Bash for unattended operation |
| `acceptEdits` | Intended use — edits auto-approve, Bash prompts | Works for edit-heavy pipelines — Bash still prompts | Best match for interactive supervision |
| `auto` | Over-permissive for supervised use | Intended use for unattended pipelines | All tools auto-approve |
| `dontAsk` | All prompts auto-denied — pipeline blocked | All prompts auto-denied — pipeline blocked | Not usable with WFM in any autonomy mode |
| `bypassPermissions` | **WFM enforcement does not apply** — hooks do not fire | **WFM enforcement does not apply** — hooks do not fire | Phase gates, write guards, and coaching are all bypassed |

---

## Review Findings (commit cde008e)

### Critical
None.

### Warnings
None (CQ-1 and CQ-2 were false positives — deduplication design is intentional, test suite was deleted in v1.12.0).

### Suggestions
- [HYG] `plugin/scripts/post-tool-navigator.sh:467-479` — Inconsistent milestone-check idiom: IMPLEMENT uses `_check_milestones`, DISCUSS/REVIEW use manual for-loop. Pre-existing; new DISCUSS block follows REVIEW pattern.

### Tech Debt (hygiene findings — pre-existing, not introduced by this commit)
- [HYG] `plugin/scripts/setup.sh:43` — Dead stub comment "Clean up stale intent files from previous sessions" with no implementation. `phase-intent.json` stale file confirmed on disk with `{"intent":"implement"}`.
- [HYG] `plugin/scripts/workflow-state.sh:343` — Comment references removed features `WF_SKIP_AUTH` and `intent file` in `agent_set_phase` function.
- [HYG] `plugin/scripts/bash-write-guard.sh:176` — `STATE_FILE_PATTERN` still guards `autonomy-intent.json` which no longer exists on disk and has no writer.

---

## Deliverables

1. `plugin/scripts/bash-write-guard.sh` — extend CLEAN_CMD strip (line 134)
2. `plugin/commands/complete.md` — replace "loop back to `/implement`" text (line 222) with: `"Version bump missing — run the versioning step before committing."`
3. `plugin/docs/reference/wfm-architecture.md` — fix line 68 + add CC × WFM matrix section
4. `CONTRIBUTING.md` — fix line 52: replace "Ensure the test suite passes" with "Verify manually: run the workflow through at least one full IMPLEMENT → REVIEW → COMPLETE cycle and confirm no regressions"
5. Close observations #4816 and #4671 in claude-mem by saving a resolution observation (type: discovery) for each that records the outcome and closes the open question
