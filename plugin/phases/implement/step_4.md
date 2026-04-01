# Step 4: Version Bump

After all tasks complete, before final test run.

Dispatch a **Versioning agent** — read `plugin/agents/versioning-agent.md`, then dispatch as `general-purpose`:

Context: "Plan: [PLAN_PATH]. Determine the semantic version bump for this release."

Apply the version bump to both files:

```bash
python3 -c "
import json, sys
new_version = sys.argv[1]
for path in ['.claude-plugin/marketplace.json', '.claude-plugin/plugin.json']:
    with open(path) as f:
        data = json.load(f)
    if 'plugins' in data:
        data['plugins'][0]['version'] = new_version
    else:
        data['version'] = new_version
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
" "<NEW_VERSION>"
```

Run `scripts/check-version-sync.sh` to validate both files match. This is not an IMPLEMENT exit gate — COMPLETE Step 5 will verify it.
