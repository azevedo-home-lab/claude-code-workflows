# Step 3: Implement

Use `superpowers:executing-plans` or `superpowers:subagent-driven-development` to implement the approved plan.

Use `superpowers:test-driven-development` — write tests before implementation code.

When all plan tasks are implemented, mark milestone:

```bash
.claude/hooks/workflow-cmd.sh set_implement_field "all_tasks_complete" "true"
```
