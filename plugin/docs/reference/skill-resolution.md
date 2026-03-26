# Skill Resolution

Before invoking any skill in this phase, resolve it through the registry:

1. Read `plugin/config/skill-registry.json` to find the default skill for each operation
2. Check if `plugin/config/skill-overrides.json` exists (NOT the `.example` file)
3. If overrides exist, merge them: override values replace defaults for matching operation keys
4. If an operation is listed in the `"disabled"` array, skip it entirely
5. Use the resolved `process_skill` and `reference_skills` when invoking skills below

If no overrides file exists, use the registry defaults as-is. This is the normal case.
