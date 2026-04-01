# Step 3: Dispatch 5 Review Agents in Parallel

Launch all five agents simultaneously using the Agent tool (5 parallel calls in one message). Pass each agent the list of changed files as runtime context.

**Agent 1 — Code Quality Reviewer** — read `plugin/agents/code-quality-reviewer.md`, dispatch as `general-purpose`
Context: "Changed files: [LIST]"

**Agent 2 — Security Reviewer** — read `plugin/agents/security-reviewer.md`, dispatch as `general-purpose`
Context: "Changed files: [LIST]"

**Agent 3 — Architecture & Plan Compliance Reviewer** — read `plugin/agents/architecture-reviewer.md`, dispatch as `general-purpose`

Before dispatching Agent 3, find the plan file path: check `docs/plans/` for the most recent `.md` file. If found, include it in the context.

Context: "Changed files: [LIST]. Plan file: [PLAN_PATH or 'no plan file found']"

**Agent 4 — Governance & Production Readiness Reviewer** — read `plugin/agents/governance-reviewer.md`, dispatch as `general-purpose`
Context: "Changed files: [LIST]"

**Agent 5 — Codebase Hygiene Reviewer** — read `plugin/agents/codebase-hygiene-reviewer.md`, dispatch as `general-purpose`
Context: "Changed files: [LIST]"

If any agent fails or times out, note which agent failed and proceed with findings from agents that succeeded.
