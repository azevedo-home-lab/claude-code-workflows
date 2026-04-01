# Step 1: Diverge

Use `superpowers:brainstorming` with **problem-discovery context**. Focus on understanding the problem, not solving it. Update the skill tracker:

```bash
.claude/hooks/workflow-cmd.sh set_active_skill "brainstorming"
```

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
