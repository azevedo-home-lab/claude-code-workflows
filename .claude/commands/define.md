Transition the workflow to DEFINE phase. Run this command:

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_phase "define" && set_active_skill ""
echo "Phase set to DEFINE — code edits are blocked. Define the problem and outcomes first."
```

Then confirm to the user that the phase has changed and code edits are blocked.

**You are now in DEFINE phase (Diamond 1 — Problem Space).**

Before proceeding:
1. Read `docs/reference/professional-standards.md` — apply the Universal Standards and DEFINE Phase Standards throughout this phase.

## Workflow

Use `superpowers:brainstorming` with **problem-discovery context**. Focus on understanding the problem, not solving it. Update the skill tracker:

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_active_skill "brainstorming"
```

### Diverge Phase

Guide the user through problem discovery — one question per message, prefer multiple choice:
- Who is affected by this problem?
- What pain or friction are they experiencing?
- What's the current state or workaround?
- Why does this matter now?

After 2-3 exchanges when an initial problem framing emerges, **dispatch background research agents** (unless the problem is trivial — if so, state explicitly: "This problem is well-defined — skipping background research. If you want broader exploration, say so."):

1. **Domain researcher** — Web search for the problem domain: similar pain points, industry context, standards, user research patterns. Tools: WebSearch, WebFetch.
2. **Context gatherer** — Search project history for prior discussions, related decisions, failed attempts. Tools: claude-mem search, git log, Grep. **Always pass `project` parameter to claude-mem tools.** Derive repo name: `git remote get-url origin 2>/dev/null | sed 's/.*[:/]\([^/]*\)\.git$/\1/' | sed 's/.*[:/]\([^/]*\)$/\1/'`
3. **Assumption challenger** — Takes the emerging problem statement, looks for counterevidence, edge cases, overlooked stakeholders. Tools: WebSearch, Grep, Read.

When agents return, synthesize findings into the conversation. Challenge the first framing — is this the real problem, or a symptom?

### Converge Phase

Once the user and you agree on the problem framing, synthesize into a crisp problem statement. Use "How Might We" framing if appropriate. Present to user: "Is this the right problem?" Iterate until confirmed.

Then dispatch **converge agents**:

1. **Outcome structurer** — Structure measurable outcomes with verification methods, acceptance criteria, success metrics. Reads the conversation context so far.
2. **Scope boundary checker** — Identify in/out scope, hidden dependencies, unstated constraints, regulatory considerations. Tools: WebSearch, Read, Grep.

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
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_decision_record "docs/plans/YYYY-MM-DD-<topic>-decisions.md"
```

Confirm to the user: "Problem and outcomes saved to the decision record. Use `/discuss` to proceed to solution design."

**Level 3 auto-transition:** If autonomy level is 3, invoke `/discuss` now. Do not wait for the user.
