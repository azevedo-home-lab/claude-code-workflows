!`WF_SKIP_AUTH=1 .claude/hooks/workflow-cmd.sh set_phase "discuss" && .claude/hooks/workflow-cmd.sh set_active_skill "" && echo "Phase set to DISCUSS — code edits blocked until plan is ready."`

**You are in DISCUSS phase.** Code edits are blocked — design the solution and write the plan.

**You are now in DISCUSS phase (Diamond 2 — Solution Space).**

Before proceeding:
1. Read `plugin/docs/reference/professional-standards.md` — apply the Universal Standards and DISCUSS Phase Standards throughout this phase.

## Setup

If no decision record exists yet, create one and register it:

```bash
EXISTING=$(.claude/hooks/workflow-cmd.sh get_decision_record)
if [ -z "$EXISTING" ]; then
    echo "No decision record found — will create one during this phase."
fi
```

If no decision record exists, brainstorming will naturally cover problem discovery (lighter than a full DEFINE phase). Create the decision record with a Problem section from what you learn, then proceed to solution design.

## Workflow

Use `superpowers:brainstorming` with **solution-design context**. Focus on how to solve the defined problem. Update the skill tracker:

```bash
.claude/hooks/workflow-cmd.sh set_active_skill "brainstorming"
```

### Diverge Phase

Once the problem statement is confirmed (from DEFINE's decision record or from brainstorming's natural discovery), **dispatch background research agents** (unless the solution is obvious — if so, state explicitly: "The solution approach is straightforward — skipping broad research. If you want alternatives explored, say so."):

1. **Solution researcher A** — Web search for technical approaches, libraries, frameworks, implementation patterns. Tools: WebSearch, WebFetch.
2. **Solution researcher B** — Web search for case studies, how others solved similar problems, lessons learned. Tools: WebSearch, WebFetch.
3. **Prior art scanner** — Search project history and codebase for previous related implementations or decisions. Tools: claude-mem search, git log, Grep, Read. **Always pass `project` parameter to claude-mem tools.** Derive repo name: `git remote get-url origin 2>/dev/null | sed 's/.*[:/]\([^/]*\)\.git$/\1/' | sed 's/.*[:/]\([^/]*\)$/\1/'`

Present findings to user. Every approach must have stated downsides. Unsourced claims are opinions, not research.

### Converge Phase

After the user narrows to 2-3 candidate approaches, **dispatch converge agents**:

1. **Codebase analyst** — Explore current architecture, integration points, dependency graph. Answer "which approaches fit what we have?" Tools: Read, Grep, Glob, git commands.
2. **Risk assessor** — For each shortlisted approach: breaking changes, security implications, performance concerns, tech debt implications. Tools: Read, Grep, WebSearch.

Present 2-3 viable approaches (discovered possibilities filtered through codebase reality) with your recommendation. Include trade-offs and tech debt implications for each.

After user selects an approach, enrich the decision record with:

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

## Implementation Plan

Use `superpowers:writing-plans` to create the step-by-step implementation plan. Update the skill tracker:

```bash
.claude/hooks/workflow-cmd.sh set_active_skill "writing-plans"
```

Every plan step must trace back to the chosen approach. If a step can't be justified by the decision, it's scope creep.

**Review transparency:** When the spec review loop or plan review loop finds issues, always present a summary to the user: what the reviewer found, what you fixed, and the final verdict. Never silently fix and move on — the user must see what was caught.

**Autonomy-aware behavior:**
- **off/ask:** When the plan is ready and the user approves, they will run `/implement` to proceed.

**Auto-transition:** If autonomy is auto, invoke `/implement` now after the plan passes review. Do not wait for the user. Only stop if user input is needed during the converge phase (approach selection).
