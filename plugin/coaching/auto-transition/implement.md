▶▶▶ Unattended (auto) — when all milestones are complete (plan_read, tests_passing, all_tasks_complete), auto-transition: run these commands now:
  .claude/hooks/workflow-cmd.sh agent_set_phase "review"
  .claude/hooks/workflow-cmd.sh reset_review_status
Then read plugin/commands/review.md for phase instructions. Do NOT commit, push, or do other work after milestones are done.