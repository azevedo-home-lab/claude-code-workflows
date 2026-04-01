# Step 1: Write Plan

Write the implementation plan using `superpowers:writing-plans`. Every plan step must trace back to the chosen approach from DISCUSS. If a step can't be justified by the decision, it's scope creep. Update the skill tracker:

```bash
.claude/hooks/workflow-cmd.sh set_active_skill "writing-plans"
```

After the plan is written and reviewed, mark milestone and commit (use separate commands):

```bash
.claude/hooks/workflow-cmd.sh set_implement_field "plan_written" "true"
```
```bash
git add <PLAN_PATH>
```
```bash
git commit -m "docs: add implementation plan for <feature>"
```
