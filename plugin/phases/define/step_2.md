# Step 2: Converge

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
