# /refresh-index — Regenerate project index

Regenerates `docs/project-index.md` from the current codebase.

## When to run

Run **before `/ship`** when the feature introduced structural changes:
- Added or renamed a `.gd` file
- Added a `signal` declaration
- Added an `@export` field to a resource
- Added a `.tres` data file

**Skip** for content-only changes: bug fixes, logic edits, doc updates, `.tscn` edits with no new scripts.

## Steps

1. Run the generator from the project root:
   ```
   python scripts/gen_project_index.py
   ```
2. Confirm `docs/project-index.md` was written without errors (the script prints a summary).
3. Stage `docs/project-index.md` — it is committed in the same commit as the structural change,
   not in a separate commit.
4. Proceed to `/ship`.
