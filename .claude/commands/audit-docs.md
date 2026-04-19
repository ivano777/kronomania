# /audit-docs — Docs alignment audit

Deploy the `docs-alignment-auditor` agent to cross-check all documentation and configuration sources against the actual current state of the codebase.

## When to use

- After implementing a new feature or mechanic
- After refactoring code or renaming things
- After updating docs/game-rules/ manually
- Anytime you suspect documentation drift

## What it checks

- `CLAUDE.md` — project structure map, architecture, autoload descriptions, round loop, rules summary table
- `docs/game-rules/` — all markdown files vs actual implementation
- `docs/game-style/style-concept.md` — high-level alignment
- `docs/project-status.md` — implemented items vs actual codebase
- All GDScript files, scenes, resources, `.tres` data files, `project.godot`, and `.godot/global_script_class_cache.cfg`

## Steps

1. Deploy the `docs-alignment-auditor` agent against the project at `C:/Users/ivano/Documents/ivano/svago/godot/kronomania`.
2. Wait for the full audit report.
3. Present the report to the user, highlighting any **Critical** or **Major** misalignments.
4. Ask the user which fixes to apply.
