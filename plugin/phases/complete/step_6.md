# Step 6: Branch Integration & Worktree Cleanup

Check if work was done on a feature branch or in a worktree:

```bash
CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
MAIN_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||' || echo "main")
IN_WORKTREE=$(git rev-parse --git-common-dir 2>/dev/null | grep -q "\.git/worktrees" && echo "true" || echo "false")
echo "Current branch: $CURRENT_BRANCH"
echo "Main branch: $MAIN_BRANCH"
echo "In worktree: $IN_WORKTREE"
```

**If on a feature branch (not main/master):**

Use `superpowers:finishing-a-development-branch` to present integration options:
1. **Create PR and merge** — create a pull request, review it, merge to main
2. **Merge directly** — fast-forward or merge commit to main locally
3. **Leave on branch** — keep changes on the feature branch for later

Recommend option 1 (PR) for non-trivial changes, option 2 for small fixes.

After merge, push main to remote if the user approves.

**If in a worktree:**

After the branch is merged, clean up:
```bash
WORKTREE_PATH=$(git rev-parse --show-toplevel)
MAIN_PROJECT=$(git rev-parse --git-common-dir | sed 's|/\.git/worktrees/.*||')
echo "Worktree at: $WORKTREE_PATH"
echo "Main project at: $MAIN_PROJECT"
echo "Clean up worktree? (yes / no)"
```
If **yes**: `git worktree remove <path>` and `git branch -d <branch>`
If **no**: note that worktree is still active

**If on main already:** skip this step.

Mark milestone:
```bash
.claude/hooks/workflow-cmd.sh set_completion_field "issues_reconciled" "true"
```
