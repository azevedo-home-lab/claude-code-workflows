---
description: Define the problem and outcomes (Diamond 1 — Problem Space)
disable-model-invocation: true
---
<!-- Do NOT invoke this command via the Skill tool. Use the native /command path only. -->
!`.claude/hooks/user-set-phase.sh "define" && .claude/hooks/workflow-cmd.sh set_active_skill ""`

Present the output to the user.

**You are in DEFINE phase.** Code edits are blocked — define the problem and outcomes first.

**You are now in DEFINE phase (Diamond 1 — Problem Space).**

**Git in DEFINE/DISCUSS:** Spec and plan files (`docs/plans/`, `docs/specs/`) can be committed. Use **single git commands** — run `git add` and `git commit` as separate commands, not chained with `&&`. Chained commands with heredoc-style commit messages may be blocked by the write guard.

Before proceeding:
1. Read `plugin/docs/reference/professional-standards.md` — apply the Universal Standards and DEFINE Phase Standards throughout this phase.

**Skill Resolution:** Follow the process in `plugin/docs/reference/skill-resolution.md` before invoking skills.

**Agent Dispatch:** Follow `plugin/docs/reference/agent-dispatch.md` — read each agent's `.md` file, then dispatch as `general-purpose` with the file content + runtime context as the prompt.

## Workflow

Use `superpowers:brainstorming` with **problem-discovery context**. Focus on understanding the problem, not solving it. Update the skill tracker:

```bash
.claude/hooks/workflow-cmd.sh set_active_skill "brainstorming"
```

### Diverge Phase

Guide the user through problem discovery — one question per message, prefer multiple choice:
- Who is affected by this problem?
- What pain or friction are they experiencing?
- What's the current state or workaround?
- Why does this matter now?

After 2-3 exchanges when an initial problem framing emerges, **dispatch background research agents** (unless the problem is trivial — if so, state explicitly: "This problem is well-defined — skipping background research. If you want broader exploration, say so."):

1. **Domain researcher** — Read `plugin/agents/domain-researcher.md`, then dispatch as `general-purpose`. Context: "Problem domain: [PROBLEM_STATEMENT]. Research the problem space."
2. **Context gatherer** — Read `plugin/agents/context-gatherer.md`, then dispatch as `general-purpose`. Context: "Problem: [PROBLEM_STATEMENT]. Project: [PROJECT_NAME from git remote]. Search project history and claude-mem for prior related work." **Always pass `project` parameter to claude-mem tools.** Derive repo name: `git remote get-url origin 2>/dev/null | sed 's/.*[:/]\([^/]*\)\.git$/\1/' | sed 's/.*[:/]\([^/]*\)$/\1/'`
3. **Assumption challenger** — Read `plugin/agents/assumption-challenger.md`, then dispatch as `general-purpose`. Context: "Current problem framing: [PROBLEM_STATEMENT]. Challenge these assumptions."

When agents return, synthesize findings into the conversation. Challenge the first framing — is this the real problem, or a symptom?

### Converge Phase

Once the user and you agree on the problem framing, synthesize into a crisp problem statement. Use "How Might We" framing if appropriate. Present to user: "Is this the right problem?" Iterate until confirmed.

Then dispatch **converge agents**:

1. **Outcome structurer** — Read `plugin/agents/outcome-structurer.md`, then dispatch as `general-purpose`. Context: "Agreed problem statement: [PROBLEM_STATEMENT]. Constraints: [CONSTRAINTS]. Structure measurable outcomes."
2. **Scope boundary checker** — Read `plugin/agents/scope-boundary-checker.md`, then dispatch as `general-purpose`. Context: "Problem: [PROBLEM_STATEMENT]. Proposed outcomes: [OUTCOMES_SUMMARY]. Identify scope boundaries and hidden dependencies."

Present structured outcomes to user for review. Each outcome must have:
- **Description** — what should be true when done
- **Type** — functional, performance, security, reliability, usability, maintainability, compatibility
- **Verification method** — how to demonstrate it (not just prove code exists)
- **Acceptance criteria** — specific evidence that confirms it

Define success metrics and scope boundaries (in-scope, out-of-scope, constraints).

## Output

Create the plan at `docs/plans/YYYY-MM-DD-<topic>.md` with the **Problem** section populated:

```markdown
# Decision Record: <topic>

## Problem (DEFINE phase)
- Problem statement
- Who is affected and why it matters now
- Current state / workarounds
- Measurable outcomes with verification methods
- Success metrics with targets
- Scope: in / out / constraints
```

Only the structured, converged version is written to the plan (raw diverge findings are conversation context, not persisted).

Commit the plan (use separate commands):

```bash
git add docs/plans/YYYY-MM-DD-<topic>.md
```
```bash
git commit -m "docs: add plan for <topic>"
```

Register the plan path:

```bash
.claude/hooks/workflow-cmd.sh set_plan_path "docs/plans/YYYY-MM-DD-<topic>.md"
```

### Decision Record→Issue Linking

Get the commit hash and link the plan to the originating GitHub issue (if one exists):

```bash
COMMIT_HASH=$(git rev-parse --short HEAD)
```

If there are tracked observation IDs with GitHub issue mappings, or if the user mentioned a specific issue number, post a comment:

```bash
gh issue comment <ISSUE_NUMBER> --body "## Problem Defined

**Commit:** <COMMIT_HASH>
**Plan:** \`<DECISION_RECORD_PATH>\`

Problem: <one-line problem statement>
Outcomes: <N> measurable outcomes defined"
```

If no issue is mapped, skip this step silently.

Confirm to the user: "Problem and outcomes saved to the plan. Use `/discuss` to proceed to solution design."

**Step expectations — what each step must produce before you move on:**

| Step | What you do | Evidence required before next step |
|------|-------------|-------------------------------------|
| Diverge | Ask discovery questions, dispatch 3 agents | Agents returned, findings synthesized |
| Converge | Agree on problem statement with user | User confirmed: "yes, that's the right problem" |
| Outcomes | Structure measurable outcomes | Each outcome has description, type, verification method, acceptance criteria |
| Plan | Write to `docs/plans/` | File exists on disk, `set_plan_path` called |
| Transition | Call `/discuss` or wait | Plan path registered in state |

**Autonomy-aware behavior:**
- **auto (▶▶▶):** Auto-transition to `/discuss` after problem is defined.
- **ask (▶▶):** Present the plan and wait for the user to run `/discuss`.
- **off (▶):** After each problem discovery exchange, summarize what was learned and wait for the user's direction before proceeding. Present the plan and wait for explicit approval before any transition.

**Auto-transition:** If autonomy is auto, invoke `/discuss` now. Do not wait for the user.
