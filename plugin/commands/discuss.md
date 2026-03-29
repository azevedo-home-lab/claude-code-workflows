---
description: Design the solution and write the implementation plan (Diamond 2 — Solution Space)
disable-model-invocation: true
---
<!-- Do NOT invoke this command via the Skill tool. Use the native /command path only. -->
!`.claude/hooks/user-set-phase.sh "discuss" && .claude/hooks/workflow-cmd.sh reset_discuss_status && .claude/hooks/workflow-cmd.sh set_active_skill ""`

Present the output to the user.

**You are now in DISCUSS phase (Diamond 2 — Solution Space).** Code edits are blocked — design the solution and write the plan.

**Git in DEFINE/DISCUSS:** Spec and plan files (`docs/plans/`, `docs/specs/`) can be committed. Use **single git commands** — run `git add` and `git commit` as separate commands, not chained with `&&`. Chained commands with heredoc-style commit messages may be blocked by the write guard.

Before proceeding:
1. Read `plugin/docs/reference/professional-standards.md` — apply the Universal Standards and DISCUSS Phase Standards throughout this phase.

**Skill Resolution:** Follow the process in `plugin/docs/reference/skill-resolution.md` before invoking skills.

**Agent Dispatch:** Follow `plugin/docs/reference/agent-dispatch.md` — read each agent's `.md` file, then dispatch as `general-purpose` with the file content + runtime context as the prompt.

## Setup

If no plan exists yet, create one and register it:

```bash
EXISTING=$(.claude/hooks/workflow-cmd.sh get_plan_path)
if [ -z "$EXISTING" ]; then
    echo "No plan found — will create one during this phase."
fi
```

If no plan exists, brainstorming will naturally cover problem discovery (lighter than a full DEFINE phase). Create the plan with a Problem section from what you learn, then proceed to solution design.

Once the problem statement is confirmed (from DEFINE's plan or from brainstorming), mark the milestone:
```bash
.claude/hooks/workflow-cmd.sh set_discuss_field "problem_confirmed" "true"
```

## Workflow

Use `superpowers:brainstorming` with **solution-design context**. Focus on how to solve the defined problem. Update the skill tracker:

```bash
.claude/hooks/workflow-cmd.sh set_active_skill "brainstorming"
```

### Diverge Phase

Once the problem statement is confirmed (from DEFINE's plan or from brainstorming's natural discovery), **dispatch background research agents** (unless the solution is obvious — if so, state explicitly: "The solution approach is straightforward — skipping broad research. If you want alternatives explored, say so."):

1. **Solution researcher A** — Read `plugin/agents/solution-researcher-a.md`, then dispatch as `general-purpose`. Context: "Problem to solve: [PROBLEM_STATEMENT]. Research technical approaches."
2. **Solution researcher B** — Read `plugin/agents/solution-researcher-b.md`, then dispatch as `general-purpose`. Context: "Problem to solve: [PROBLEM_STATEMENT]. Research case studies and lessons learned."
3. **Prior art scanner** — Read `plugin/agents/prior-art-scanner.md`, then dispatch as `general-purpose`. Context: "Problem: [PROBLEM_STATEMENT]. Project: [PROJECT_NAME from git remote]. Search for previous related implementations." **Always pass `project` parameter to claude-mem tools.** Derive repo name: `git remote get-url origin 2>/dev/null | sed 's/.*[:/]\([^/]*\)\.git$/\1/' | sed 's/.*[:/]\([^/]*\)$/\1/'`

Present findings to user. Every approach must have stated downsides. Unsourced claims are opinions, not research.

After presenting diverge findings, mark the milestone:
```bash
.claude/hooks/workflow-cmd.sh set_discuss_field "research_done" "true"
```

### Converge Phase

After the user narrows to 2-3 candidate approaches, **dispatch converge agents**:

1. **Codebase analyst** — Read `plugin/agents/codebase-analyst.md`, then dispatch as `general-purpose`. Context: "Shortlisted approaches: [APPROACH_LIST]. Analyze which fit the current architecture."
2. **Risk assessor** — Read `plugin/agents/risk-assessor.md`, then dispatch as `general-purpose`. Context: "Shortlisted approaches: [APPROACH_LIST]. Assess risks for each."

Present 2-3 viable approaches (discovered possibilities filtered through codebase reality) with your recommendation. Include trade-offs and tech debt implications for each.

After user selects an approach, enrich the plan with:

```markdown
## Approaches Considered (DISCUSS phase — diverge)
### Approach A: <name>
- Description, Pros/cons, Source

### Approach B: <name>
- Description, Pros/cons, Source

## Decision (DISCUSS phase — converge)
- **Chosen approach:** <which and why>
- **Rationale:** Why this over alternatives
- **Trade-offs accepted:** What downsides we're taking on
- **Risks identified:** What could go wrong
- **Constraints applied:** What codebase factors narrowed options
- **Tech debt acknowledged:** Deliberate shortcuts
- Link to implementation plan
```

After updating the plan with the chosen approach, mark the milestone:
```bash
.claude/hooks/workflow-cmd.sh set_discuss_field "approach_selected" "true"
```

## Implementation Plan

Use `superpowers:writing-plans` to create the step-by-step implementation plan. Update the skill tracker:

```bash
.claude/hooks/workflow-cmd.sh set_active_skill "writing-plans"
```

Every plan step must trace back to the chosen approach. If a step can't be justified by the decision, it's scope creep.

After the plan is written and reviewed, mark the milestone:
```bash
.claude/hooks/workflow-cmd.sh set_discuss_field "plan_written" "true"
```

### Plan→Issue Linking

After the plan passes review, commit the spec and plan files (use separate commands):

```bash
git add <SPEC_PATH> <PLAN_PATH> <DECISION_RECORD_PATH>
```
```bash
git commit -m "docs: add spec and plan for <feature>"
```

Then get the commit hash for traceability:

```bash
COMMIT_HASH=$(git rev-parse --short HEAD)
```

Check if this work maps to an existing GitHub issue. If there are tracked observation IDs with GitHub issue mappings, or if the user mentioned a specific issue number, post a comment linking to the spec, plan, and commit:

```bash
gh issue comment <ISSUE_NUMBER> --body "## Design & Plan

**Commit:** <COMMIT_HASH>
**Spec:** \`<SPEC_PATH>\`
**Plan:** \`<PLAN_PATH>\`
**Plan:** \`<DECISION_RECORD_PATH>\`

Approach: <chosen approach name>
Tasks: <N> implementation tasks"
```

If no issue is mapped, skip this step silently — not all work originates from a GitHub issue.

**Step expectations — what each step must produce before you move on:**

| Step | What you do | Evidence required before next step | Milestone |
|------|-------------|-------------------------------------|-----------|
| Problem confirmed | Verify problem statement from DEFINE or brainstorm | User or plan confirms the problem | `problem_confirmed=true` |
| Diverge | Dispatch 3 research agents | Agents returned, findings presented with sources and downsides | `research_done=true` |
| Converge | User narrows to approach, dispatch 2 agents | User selected approach, plan enriched | `approach_selected=true` |
| Plan | Write plan with `superpowers:writing-plans`, run reviewer | Plan file exists on disk, reviewer passed | `plan_written=true` |

**Review transparency:** When the spec review loop or plan review loop finds issues, always present a summary to the user: what the reviewer found, what you fixed, and the final verdict. Never silently fix and move on — the user must see what was caught.

**Autonomy-aware behavior:**
- **off (▶):** After each design decision or research finding, present the result and wait for explicit user approval before proceeding. Never batch diverge/converge phases. Present the plan section by section, waiting for approval after each.
- **ask (▶▶):** When the plan is ready and the user approves, they will run `/implement` to proceed.

**Auto-transition:** If autonomy is auto, invoke `/implement` now after the plan passes review. Do not wait for the user. Only stop if user input is needed during the converge phase (approach selection).
