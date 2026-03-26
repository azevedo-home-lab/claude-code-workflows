!`WF_SKIP_AUTH=1 .claude/hooks/workflow-cmd.sh set_phase "define" && .claude/hooks/workflow-cmd.sh set_active_skill "" && echo "Phase set to DEFINE — code edits are blocked."`

**You are in DEFINE phase.** Code edits are blocked — define the problem and outcomes first.

**You are now in DEFINE phase (Diamond 1 — Problem Space).**

Before proceeding:
1. Read `plugin/docs/reference/professional-standards.md` — apply the Universal Standards and DEFINE Phase Standards throughout this phase.

## Skill Resolution

Before invoking any skill in this phase, resolve it through the registry:

1. Read `plugin/config/skill-registry.json` to find the default skill for each operation
2. Check if `plugin/config/skill-overrides.json` exists (NOT the `.example` file)
3. If overrides exist, merge them: override values replace defaults for matching operation keys
4. If an operation is listed in the `"disabled"` array, skip it entirely
5. Use the resolved `process_skill` and `reference_skills` when invoking skills below

If no overrides file exists, use the registry defaults as-is. This is the normal case.

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

1. **Domain researcher** (subagent_type: `workflow-manager:domain-researcher`) — Context: "Problem domain: [PROBLEM_STATEMENT]. Research the problem space."
2. **Context gatherer** (subagent_type: `workflow-manager:context-gatherer`) — Context: "Problem: [PROBLEM_STATEMENT]. Project: [PROJECT_NAME from git remote]. Search project history and claude-mem for prior related work." **Always pass `project` parameter to claude-mem tools.** Derive repo name: `git remote get-url origin 2>/dev/null | sed 's/.*[:/]\([^/]*\)\.git$/\1/' | sed 's/.*[:/]\([^/]*\)$/\1/'`
3. **Assumption challenger** (subagent_type: `workflow-manager:assumption-challenger`) — Context: "Current problem framing: [PROBLEM_STATEMENT]. Challenge these assumptions."

When agents return, synthesize findings into the conversation. Challenge the first framing — is this the real problem, or a symptom?

### Converge Phase

Once the user and you agree on the problem framing, synthesize into a crisp problem statement. Use "How Might We" framing if appropriate. Present to user: "Is this the right problem?" Iterate until confirmed.

Then dispatch **converge agents**:

1. **Outcome structurer** (subagent_type: `workflow-manager:outcome-structurer`) — Context: "Agreed problem statement: [PROBLEM_STATEMENT]. Constraints: [CONSTRAINTS]. Structure measurable outcomes."
2. **Scope boundary checker** (subagent_type: `workflow-manager:scope-boundary-checker`) — Context: "Problem: [PROBLEM_STATEMENT]. Proposed outcomes: [OUTCOMES_SUMMARY]. Identify scope boundaries and hidden dependencies."

Present structured outcomes to user for review. Each outcome must have:
- **Description** — what should be true when done
- **Type** — functional, performance, security, reliability, usability, maintainability, compatibility
- **Verification method** — how to demonstrate it (not just prove code exists)
- **Acceptance criteria** — specific evidence that confirms it

Define success metrics and scope boundaries (in-scope, out-of-scope, constraints).

## Output

Create the decision record at `docs/plans/YYYY-MM-DD-<topic>-decisions.md` with the **Problem** section populated:

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

Only the structured, converged version is written to the decision record (raw diverge findings are conversation context, not persisted).

Register the decision record path:

```bash
.claude/hooks/workflow-cmd.sh set_decision_record "docs/plans/YYYY-MM-DD-<topic>-decisions.md"
```

Confirm to the user: "Problem and outcomes saved to the decision record. Use `/discuss` to proceed to solution design."

**Auto-transition:** If autonomy is auto, invoke `/discuss` now. Do not wait for the user.
