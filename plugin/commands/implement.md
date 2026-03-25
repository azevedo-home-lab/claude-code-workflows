Transition the workflow to IMPLEMENT phase. First check for soft gate warnings:

```bash
WF="$(git rev-parse --show-toplevel)/.claude/hooks/workflow-cmd.sh"
WARN=$("$WF" check_soft_gate "implement")
if [ -n "$WARN" ]; then
    echo "WARNING: $WARN"
fi
```

If a warning was shown, ask the user: "Proceed anyway? (yes/no)". If they say no, stop. If yes or no warning, continue:

```bash
WF="$(git rev-parse --show-toplevel)/.claude/hooks/workflow-cmd.sh" && "$WF" set_phase "implement" && "$WF" reset_implement_status && "$WF" set_active_skill "" && echo "Phase set to IMPLEMENT — code edits are now allowed."
```

Then confirm to the user that the phase has changed and they can now proceed with implementation.

**You are now in IMPLEMENT phase.** Before proceeding:
1. Read `plugin/docs/reference/professional-standards.md` — apply the Universal Standards and IMPLEMENT Phase Standards throughout this phase.

**Autonomy-aware behavior:**
- **auto (▶▶▶):** Use `superpowers:subagent-driven-development` (recommended execution mode) without asking. Make operational decisions (execution approach, model selection, task ordering) autonomously. Only stop for genuine blockers.
- **off/ask:** Ask the user which execution approach they prefer if multiple options exist.

Follow this workflow:
1. Read the plan file and mark milestone:
```bash
WF="$(git rev-parse --show-toplevel)/.claude/hooks/workflow-cmd.sh" && "$WF" set_implement_field "plan_read" "true"
```
2. Use `superpowers:executing-plans` or `superpowers:subagent-driven-development` to implement the approved plan
3. Use `superpowers:test-driven-development` — write tests before implementation code
4. When all plan tasks are implemented, mark milestone:
```bash
WF="$(git rev-parse --show-toplevel)/.claude/hooks/workflow-cmd.sh" && "$WF" set_implement_field "all_tasks_complete" "true"
```
4b. **Version bump** (after all tasks complete, before final test run):

Dispatch a **Versioning agent** to determine the bump type:

Prompt: "Determine the semantic version bump for this release.
1. Read the decision record at [DECISION_RECORD_PATH] for phase history
2. Read `git log --oneline main...HEAD` for commit history (if no divergence, check last 10 commits)
3. Read current version from `.claude-plugin/marketplace.json`
4. Apply these rules:
   - **Major** (X.0.0): Breaking changes to public API — hook contract changes, state schema changes that break existing state files, command interface changes
   - **Minor** (x.Y.0): New features — session went through DEFINE/DISCUSS phases (new capability), new commands added, new state fields
   - **Patch** (x.y.Z): Bug fixes, refactors, tech debt cleanup, doc updates — changes are internal only
5. Return: current version, bump type (major/minor/patch), new version, one-line reasoning"

Apply the version bump to all 3 files:
```bash
python3 -c "
import json, sys
new_version = sys.argv[1]
for path in ['.claude-plugin/marketplace.json', '.claude-plugin/plugin.json', 'plugin/.claude-plugin/plugin.json']:
    with open(path) as f:
        data = json.load(f)
    if 'plugins' in data:
        data['plugins'][0]['version'] = new_version
    else:
        data['version'] = new_version
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
" "<NEW_VERSION>"
```

Run `scripts/check-version-sync.sh` to validate all 3 files match. This is not an IMPLEMENT exit gate — COMPLETE Step 5 will verify it.

5. Run the full test suite and verify all pass. Then mark milestone:
```bash
WF="$(git rev-parse --show-toplevel)/.claude/hooks/workflow-cmd.sh" && "$WF" set_implement_field "tests_passing" "true"
```
6. Proceed to `/review` (auto) or wait for the user to run `/review` (off/ask)

**HARD GATE: You cannot transition to /review without completing all 3 milestones (plan_read, all_tasks_complete, tests_passing). set_phase will refuse.**

**Review transparency:** When spec compliance reviewers or code quality reviewers find issues during implementation, always present a summary to the user: what the reviewer found, what you fixed, and the final verdict. Never silently fix and move on — the user must see what was caught.

**Important:** When you invoke a superpowers skill, update the active skill tracker:
```bash
WF="$(git rev-parse --show-toplevel)/.claude/hooks/workflow-cmd.sh" && "$WF" set_active_skill "SKILL_NAME"
```
Replace SKILL_NAME with the skill being used (e.g., "executing-plans", "test-driven-development").

**Auto-transition:** If autonomy is auto, invoke `/review` now when all plan tasks are complete and tests pass. Do not wait for the user.
