**Key takeaways from your PDFs (today, Nov 22, 2025)**  
- Persistent context: a “context management plugin” captures tool I/O, summarizes, and auto-injects last N summaries so new sessions start warm.  
- Worktrees + spec-driven flow: create isolated worktrees per feature, generate a plan/spec before coding, then execute against that spec.  
- Skills-first: lean on Claude Skills (e.g., Superpowers, playwright, MCP builder) to cut context use and standardize actions; auto-activate skills when relevant.  
- Smaller CLAUDE.md: extract long procedures into individual skill files and keep the root file as an index; target ~30% size reduction.  
- Vibe coding discipline: start every task with `vision.md`, numbered steps with “do not proceed until I say so”, and checkpoints to avoid wandering.  
- Realism: Claude can’t one‑shot complex apps; enforce plan→approve→execute loops and require verification before “done.”

**Web findings (current as of Nov 22, 2025)**  
- `cc-sessions` v0.3.0 adds a unified `sessions` command, trigger‑phrase automation (mek:/start^:/finito), DAIC enforcement, branch/task persistence, and specialized sub‑agents for context/refinement/review. ([github.com](https://github.com/GWUDCAP/cc-sessions?utm_source=openai))  
- `superpowers` provides a rich skills library plus `/superpowers:brainstorm`, `/write-plan`, `/execute-plan`, with automatic skill activation for TDD, debugging, collaboration, and worktrees. ([github.com](https://github.com/obra/superpowers?utm_source=openai))  
- No off‑the‑shelf “superpowers + cc-sessions” integration exists, but adjacent tools (e.g., ccmanager) manage multiple CC worktrees/sessions—useful if you juggle many branches. ([github.com](https://github.com/kbwo/ccmanager?utm_source=openai))

**Proposed integrated workflow**

1) **Install the scaffolds**  
- In each repo: `npx cc-sessions` (or `pipx run cc-sessions`) to lay down protocols, hooks, and agents.  
- Add Superpowers via marketplace (`/plugin marketplace add obra/superpowers-marketplace` then `/plugin install superpowers@superpowers-marketplace`).  
- Upload your trimmed `CLAUDE.md` that points to individual skill files; store skills under `.claude/skills/`.

2) **Session lifecycle (DAIC + Superpowers)**  
- **Discuss**: Kick off with `/superpowers:brainstorm` to refine scope; save to `docs/vision.md`.  
- **Align**: Use `/superpowers:write-plan`; paste plan into a cc-sessions task (`mek:`) so DAIC locks edits to the approved todos.  
- **Implement**: Start with `start^:`; cc-sessions loads context and blocks edits outside approved todos. Use `/superpowers:execute-plan` for batch execution inside that boundary.  
- **Verify**: Before `finito`, trigger the `verification-before-completion` skill and run cc-sessions’ review agent; require tests/linters as part of the todo list.  
- **Complete**: `finito` to auto-commit/merge per cc-sessions; archived logs stay in `sessions/`.

3) **Context durability**  
- Enable your context-management summaries as a pre-task hook: after each `start^:` or `yert`, run your summarizer to append to `sessions/logs` and cc-sessions’ state so future sessions load condensed context.  
- Keep last 10 summaries auto-injected; let cc-sessions’ context-gathering agent refresh when files change.

4) **Worktrees + parallelism**  
- Use cc-sessions to create directory tasks per feature; couple with Superpowers’ `using-git-worktrees` skill to spawn branches and copy minimal context.  
- If juggling many tasks, consider ccmanager to monitor multiple CC instances without tmux overhead. ([github.com](https://github.com/kbwo/ccmanager?utm_source=openai))

5) **Skill library curation**  
- Import from the PDFs:  
  - “Deploy-production”, “spec-driven dev”, “playwright regression” skills.  
  - A `context-compaction` skill that rotates summaries into `sessions/context/`.  
- Map each high-friction action to a skill and reference it from `skill-rules.json` so cc-sessions’ protocols can auto-require them (e.g., always activate TDD skill when task label includes “feature”).

6) **Minimal governance**  
- Keep `CLAUDE.md` under 1–2 screens; link out to skills.  
- Enforce “plan before edit” via DAIC; forbid tool writes until `/sessions approve` confirms the plan.  
- Set branch protection to require cc-sessions’ status check outputs (logs/test artifacts) before merge.

**How to integrate quickly (checklist)**  
- Run installers (cc-sessions, Superpowers).  
- Drop your slim `CLAUDE.md`, add extracted skills to `.claude/skills/`, and point `skill-rules.json` to them.  
- Configure `sessions-config.json`: trigger phrases, blocked tools until plan approved, auto tests on `finito`.  
- Add pre-commit hook to run `sessions api status --fail-on-dirty` and your summarizer.  
- Script a daily `sessions compact-context` job to keep state lean.

**Benefits**  
- cc-sessions gives guardrails (DAIC, task persistence, branch discipline) while Superpowers supplies battle-tested skills and commands; together they deliver structured, repeatable flows without bloated context.  
- Your PDF-sourced practices (context summaries, worktree isolation, skills extraction, vibe checkpoints) slot naturally into cc-sessions protocols and Superpowers skills, reducing re-explanation, runaway edits, and plan drift.

If you want, I can wire this into the repo now: add `sessions-config.json` defaults, import key skills, and stub the hooks for your summarizer.
