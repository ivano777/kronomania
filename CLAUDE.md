# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Engine and tooling

- **Godot 4.6.2** — Forward Plus renderer, D3D12 on Windows, Jolt Physics.
- The Godot console executable is at `$GODOT` (set in `.claude/settings.local.json`).
- Run headless validation: `"$GODOT" --headless --path "C:/Users/ivano/Documents/ivano/svago/godot/kronomania" --quit-after 5`
- No build step, no test runner, no linter — Godot parses scripts on load. Headless run is the check.

## Committing and pushing

Use `/ship` — stages everything, writes a Conventional Commit message from the diff, pulls `--rebase`, pushes. Never skip hooks, never force-push unless explicitly asked.

## Autonomous Feature Loop

Follow this workflow for every requested feature, without exception.

### 1. Plan
- Identify the smallest safe implementation slice that proves the feature.
- Present a clear plan: which files change, what logic is added, what is explicitly deferred.
- **Wait for explicit approval before writing any code.**

### 2. Implement
- Edit only the files identified in the approved plan.
- No unnecessary rewrites, refactors, or scope creep.

### 3. Validate (deploy a sub-agent)
Deploy a validation sub-agent that:
- Runs the project headless: `"$GODOT" --headless --path "C:/Users/ivano/Documents/ivano/svago/godot/kronomania" --quit-after 5`
- Checks for SCRIPT ERRORs and ERRORs in output (WARNINGs from invalid UIDs are expected and safe to ignore).
- Verifies: feature logic, scene/script integration, `@onready` node paths, signal connections, `class_name` registrations in `.godot/global_script_class_cache.cfg`.

### 4. Fix Loop
If validation fails:
- Fix the specific error reported.
- Re-run validation.
- Repeat until the headless run is clean.

### 5. Update Documentation
Only after a clean validation pass:
- Update relevant files under `docs/game-rules/` if mechanics changed.
- Update `CLAUDE.md` if architecture or rules changed.

### 6. Report
Return a concise summary covering:
- What was implemented and where.
- What the validation found and confirmed.
- What documentation was updated.

### 7. Commit and push
Ask the user to run `/ship`.

---

**Rules**
- Small iterative steps — never implement more than the approved slice.
- No unnecessary rewrites — edit what needs to change, leave the rest alone.
- Docs are updated only after successful validation, never before.
- Implementation and documentation must remain aligned at all times.
- The final report must be short enough to scan in under a minute.

## Project structure

```
autoloads/          # Singletons registered in project.godot
  RollEngine.gd     # Stateless dice engine (pure functions, no state)
  CombatManager.gd  # Combat state machine — owns all runtime combat state

resources/
  CombatantData.gd          # class_name CombatantData extends Resource
  data/player_default.tres  # Tier 1 player config
  data/enemy_grunt.tres     # Tier 1 enemy config

scenes/battle/
  BattleScene.tscn/.gd      # Root scene; wires CombatManager signals to HUDs
  CombatantHUD.tscn/.gd     # Per-combatant UI: name, wound slots, guard value
  RoundHUD.tscn/.gd         # Phase label, Strike button, scrollable combat log
  Combatant.tscn/.gd        # Placeholder visual (colored rect + name)

docs/game-rules/            # Design source of truth — rules drive implementation
  index.md                  # Entry point with reading order
  reference/cheat-sheet.md  # Quick rules reference
docs/game-style/
  style-concept.md          # Visual and tone direction
```

## Architecture

### One-way data flow

`CombatantData` (`.tres` resource) → `CombatManager` → signals → `BattleScene` → HUD nodes.

`CombatantData` is **immutable config** only. All runtime state (wounds, guard, defeated flag) lives inside `CombatManager.CombatantState`, an inner class instantiated per combat. Scene nodes hold no game state.

### Autoload singletons

- **`RollEngine`** — call for any dice resolution. Stateless; safe to call from anywhere. Returns a `Dictionary` with keys `dice`, `kept`, `total`, `pool_size`, `die_size`, `keep_count`, `flat`. Always cast Dictionary values with `as int` / `as Array` before use — the GDScript type inferencer cannot infer through `Dictionary` values.
- **`CombatManager`** — owns the round loop. The only entry points are `start_combat(player, enemy)` and `player_chose_strike()`. All output is via signals; nothing is returned. Disconnect all signals before `reload_current_scene()` to avoid duplicate connections.

### Round loop (CombatManager)

```
_begin_round()
  → emits player_action_required
  → (player presses Strike)
  → player_chose_strike() calls _resolve_round()
  → rolls both attacks, VT check, _resolve_attack() × 2
  → await 0.8s timer
  → _begin_round()  ← loops until defeat
```

`_resolve_round` uses `await` (it is a coroutine). Calling it without `await` from `player_chose_strike` is intentional — it runs asynchronously.

### GDScript typing rules

- All scene scripts that are referenced as types in other scripts **must** have a `class_name` declaration. Missing `class_name` causes "Could not find type" parse errors at load time.
- After adding a new `class_name`, update `.godot/global_script_class_cache.cfg` manually if the Godot editor has not been opened — the headless runner uses the cached index and will not rescan.
- Dictionary values from `RollEngine.resolve()` are `Variant`. Always annotate locals explicitly or cast with `as int` / `as Array`.

## Design references

- **Game rules** — entry point with reading order, section list, and current canonical design decisions:
  [docs/game-rules/index.md](docs/game-rules/index.md)
  @./docs/game-rules/index.md
- **Game style** — vision, setting, tone, art direction, and high-level gameplay loop:
  [docs/game-style/style-concept.md](docs/game-style/style-concept.md)
  @./docs/game-style/style-concept.md
- **Project status** — what is implemented, what is next, ordered roadmap:
  [docs/project-status.md](docs/project-status.md)
  @./docs/project-status.md

Before implementing any mechanic, verify the rules in `docs/game-rules/` — the code must match the docs exactly.

## Game rules summary

The rules live in `docs/game-rules/`. The implementation must match them exactly. Key rules for the current prototype:

| Concept | Rule |
|---|---|
| Roll resolution | Build Pool → Roll → Keep → Flat → Outcome |
| Pool size | = Tier (T1=1 die, T2=2, T3=3, T4=4) |
| Die size | from stat field (`dominion_size`, `negation_size`) — face value int (4/6/8/10) |
| Keep | grade 0 → keep 1, grade 1 → keep 2, grade 2 → keep 3 |
| VT (Fast/Slow) | VT is a **static enemy property**. Only the **player's** action roll is compared to the enemy's VT. Player >= VT → Fast (acts first); Player < VT → Slow (enemy acts first). Enemy timing is implicit in VT — no roll. |
| Guard | rolled fresh by defender each attack phase; resets to 0 at round start |
| Breach | `attack_total >= guard` (reaching exactly 0 is a breach) |
| Wounds | 1 on breach; 2 if Massive: `(attack - guard) > defensive_size` |
| Defeat | `wounds >= max_wounds` |

Stats not yet implemented (defer until design requires): Ingenuity/Resolve/Stamina pools, Advantage/Disadvantage, Flat modifiers, equipment, Fervor/magic, progression/Constellation.
