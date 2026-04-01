# Step 1: Diverge

Use `superpowers:brainstorming` with **solution-design context**. Focus on how to solve the defined problem. Update the skill tracker:

```bash
.claude/hooks/workflow-cmd.sh set_active_skill "brainstorming"
```

Once the problem statement is confirmed (from DEFINE's plan or from brainstorming's natural discovery), **dispatch background research agents** (unless the solution is obvious — if so, state explicitly: "The solution approach is straightforward — skipping broad research. If you want alternatives explored, say so."):

1. **Solution researcher A** — Read `plugin/agents/solution-researcher-a.md`, then dispatch as `general-purpose`. Context: "Problem to solve: [PROBLEM_STATEMENT]. Research technical approaches."
2. **Solution researcher B** — Read `plugin/agents/solution-researcher-b.md`, then dispatch as `general-purpose`. Context: "Problem to solve: [PROBLEM_STATEMENT]. Research case studies and lessons learned."
3. **Prior art scanner** — Read `plugin/agents/prior-art-scanner.md`, then dispatch as `general-purpose`. Context: "Problem: [PROBLEM_STATEMENT]. Project: [PROJECT_NAME from git remote]. Search for previous related implementations." **Always pass `project` parameter to claude-mem tools.** Derive repo name: `git remote get-url origin 2>/dev/null | sed 's/.*[:/]\([^/]*\)\.git$/\1/' | sed 's/.*[:/]\([^/]*\)$/\1/'`

Present findings to user. Every approach must have stated downsides. Unsourced claims are opinions, not research.

After presenting diverge findings, mark the milestone:
```bash
.claude/hooks/workflow-cmd.sh set_discuss_field "research_done" "true"
```
