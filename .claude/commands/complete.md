Complete the current task after a successful review. Run the pre-completion checks first:

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh"
PHASE=$(get_phase)
if [ "$PHASE" != "review" ]; then
    echo "ERROR: Not in REVIEW phase (current: $PHASE). Run /review first."
    exit 1
fi
VC=$(get_review_field "verification_complete")
AD=$(get_review_field "agents_dispatched")
FP=$(get_review_field "findings_presented")
FA=$(get_review_field "findings_acknowledged")
echo "Pre-completion checks:"
echo "  verification_complete: $VC"
echo "  agents_dispatched: $AD"
echo "  findings_presented: $FP"
echo "  findings_acknowledged: $FA"
if [ "$VC" != "true" ] || [ "$AD" != "true" ] || [ "$FP" != "true" ] || [ "$FA" != "true" ]; then
    echo ""
    echo "BLOCKED: Review not complete. Run /review first and respond to findings."
    exit 1
fi
echo ""
echo "All checks passed. Proceeding with task completion."
```

If pre-completion checks fail, report what's missing and do NOT proceed. The user needs to run `/review` first.

If all checks pass, execute the completion pipeline below.

---

## Completion Pipeline

### Step 1: Smart Documentation Detection

Analyze what changed (from `git diff --name-only main...HEAD` plus unstaged/untracked files) and recommend documentation updates:
- Services modified → suggest updating relevant service doc in `docs/services/`
- CLAUDE.md-referenced features changed → suggest updating CLAUDE.md
- New scripts/commands added → suggest updating README or `docs/operations/script-reference.md`
- Infrastructure changed → suggest updating `docs/infrastructure/HARDWARE.md`
- Nothing needs updating → report "No documentation updates needed"

Present recommendations and ask: "Update these now? (yes / no / skip)"
- If **yes** → make the documentation updates (they'll be included in the commit)
- If **no/skip** → proceed without docs update

### Step 2: Commit & Push

Stage all changed files relevant to the task and commit. Follow the project's commit conventions:

1. Run `git status` and `git diff --stat` to see what needs committing
2. Stage the relevant files (prefer specific files over `git add -A`)
3. Draft a concise conventional commit message summarizing the work
4. Commit with YubiKey touch banner:
   ```bash
   echo "========== YUBIKEY: TOUCH NOW FOR GIT COMMIT ==========" && git commit -m "$(cat <<'EOF'
   <type>: <description>

   Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
   EOF
   )"
   ```
5. Ask the user: "Push to remote? (yes / no)"
   - If **yes** → push with YubiKey touch banner:
     ```bash
     echo "========== YUBIKEY: TOUCH NOW FOR GIT PUSH ==========" && git push
     ```
   - If **no** → skip push, note that changes are committed locally

If there are no changes to commit (clean working tree and no new commits beyond main), skip this step and note "Nothing to commit."

### Step 3: Plan Validation

Tests already ran during `/review`. This step validates that the **plan deliverables and spec outcomes** were actually delivered.

**Before starting validation**, invoke the `superpowers:verification-before-completion` skill to load evidence-before-assertions rules into context.

**If a plan file exists** (check `docs/superpowers/plans/`, `docs/plans/`, or any plan referenced in the session):

1. Read the plan file
2. Extract every deliverable, acceptance criterion, and expected outcome
3. Classify each deliverable:
   - **Structural** (file/config exists) → `ls` or `cat` is sufficient
   - **Behavioral** (endpoint works, bug fixed, security hardened, feature functions) → must **demonstrate the behavior**, not just prove code exists
4. For behavioral deliverables, grep/cat is NOT sufficient evidence. You must:
   - Endpoint protection? → `curl` with a malicious input, show it's rejected
   - Security fix? → attempt the attack vector, show it's blocked
   - Feature works? → exercise it and show the output
   - Bug fixed? → reproduce the original trigger, show it no longer fails
5. Present a checklist to the user:
   ```
   ## Plan Validation
   - [x] Deliverable 1 (structural) — evidence: file exists at path
   - [x] Deliverable 2 (behavioral) — evidence: curl with malicious redirect_uri → 400 rejected
   - [ ] Deliverable 3 (behavioral) — FAILED: curl shows attack still succeeds
   ```
6. If any item fails:
   - Report what's missing and ask: "Fix now and re-commit, or proceed anyway?"
   - If fix → make fixes, create new commit, re-validate the failed items
   - If proceed → note the gaps in the handover observation

**If no plan file exists**: report "No plan file found — skipping plan validation" and continue.

### Step 4: Handover (Claude-Mem Observation)

Save a summary observation to claude-mem using the `save_observation` MCP tool. This captures the full session context for future sessions.

Include:
- **What was built or changed** (summarize the work done)
- **Commit hash** (from `git rev-parse --short HEAD`)
- **Verification results** (tests passed/failed/skipped, deliverables confirmed)
- **Key decisions** made during the session
- **Gotchas or learnings** discovered that future sessions should know
- **Files modified** (key files, not exhaustive list)

Set the `project` parameter to match the current project name.

This always runs — it ensures future sessions have context about this work.

### Step 5: Phase Transition

Run this command to complete the task:
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_phase "off" && cat > "$STATE_DIR/active-skill.json" <<'SK'
{"skill": "", "updated": "phase-transition"}
SK
echo "Task complete. Phase set to OFF — workflow enforcement disabled."
```

Note: `set_phase("off")` automatically deletes `review-status.json` since we're leaving the review phase.

Confirm to the user that the task is complete and the workflow has reset to OFF phase (normal Claude Code operation). To start a new workflow cycle, use `/discuss`.
