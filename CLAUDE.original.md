# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Engine and tooling

- **Godot 4.6.2** — Forward Plus renderer, D3D12 on Windows, Jolt Physics.
- Godot binary resolved automatically (see "Running all checks" for priority order).
- Headless validation: `python scripts/run_headless.py` · Unit + integration tests: `python scripts/run_tests.py`
- **GUT 9.6.0** at `addons/gut/`; tests in `tests/`.
- After adding a new addon or asset (PNG etc.), run `"$GODOT" --headless --import --path .` once to import resources / register class names before testing. (`run_headless.py` has no `--import` flag.)
- No build step, no linter — Godot parses scripts on load.

## Committing and pushing

Use `/ship` — stages everything, writes a Conventional Commit from the diff, pulls `--rebase`, pushes. Never skip hooks; never force-push unless explicitly asked.

## Autonomous Feature Loop

Follow this for every requested feature, without exception.

### 1. Plan
Identify the smallest safe slice that proves the feature. Present which files change, what logic is added, what is deferred. **Wait for explicit approval before writing code.**

### 2. Implement
- Edit only the files in the approved plan. No unnecessary rewrites or scope creep.
- Parallelize independent files via subagents; never parallelize writes to files that share state or have load-order dependencies (e.g. autoloads before scenes that depend on them).
- Match subagent model to task: `haiku` — validation/headless/single-file fixes/searches; `sonnet` — single-file features, most implementation; `opus` — multi-file architecture, cross-system reasoning, design decisions.

### 2b. Debug & Testability
Every new mechanic/runtime value ships with a way to exercise it interactively. Debug widgets live in `scenes/debug/`, referenced via null-safe `@onready var _dbg = $Widget if has_node("Widget") else null`. Removal at release: delete `scenes/debug/`, remove the child from the `.tscn`, remove the `@onready` + its delegation method. If a mechanic has no tunable parameters, log-only is acceptable — document it in the report.

### 2c. Inter-phase context compaction
For multi-phase features, `/compact` between phases (after a phase validates, before the next) is encouraged when context grows large. The phase boundary is a natural checkpoint; the plan file preserves intent.

### 3. Validate (deploy a sub-agent)
Run **both**, in order:
1. **Tests first**: `python scripts/run_tests.py` — a failure blocks the loop; do not proceed until green.
2. **Headless**: `"$GODOT" --headless --path "..." --quit-after 5` — check SCRIPT ERRORs and ERRORs (UID WARNINGs are safe), verify `@onready` paths, signal connections, `class_name` registrations in `.godot/global_script_class_cache.cfg`.

### 4. Fix Loop
On failure: if a **test** fails, fix logic → re-run tests → re-run headless. If the **headless run** fails, fix the SCRIPT ERROR → re-run headless only. Repeat until both clean.

### 5. Update Documentation
Only after a clean validation pass: update `docs/game-rules/` if mechanics changed; update `CLAUDE.md` if architecture/rules changed. If the feature added/renamed a `.gd`, added a signal or `@export`, or added a `.tres` — run `/refresh-index` as the final action before `/ship`. Content-only changes skip this.

### 6. Report
Short enough to scan in under a minute: what was implemented + where, what validation confirmed, what docs were updated.

### 7. Commit and push
Ask the user to run `/ship`.

**Rules**
- Docs updated only after successful validation, never before.
- Never edit `docs/game-rules/` without explicit user approval — it is the single source of truth for design. If a rule is ambiguous, ask; never decide unilaterally.

## Running all checks

Canonical command (tests first, then headless):
```
python scripts/run_tests.py && python scripts/run_headless.py
```
Exits 0 only if all tests pass **and** the headless check is clean.

Godot binary resolved from (in order): 1) `GODOT` env var; 2) `.env.local` in project root (copy `.env.local.example`); 3) `godot` on PATH; 4) common Windows locations (`%LOCALAPPDATA%\Programs\Godot\Godot.exe`, `C:\Program Files\Godot\Godot.exe`). New contributors: copy `.env.local.example` → `.env.local` and set your path.

## Testing rules

- Every new mechanic ships with ≥1 unit test in `tests/unit/<system>/test_<system>.gd`. Scene/autoload-dependent flows go in `tests/integration/`.
- Tests must be deterministic: `seed(N)` before `RollEngine` calls.
- No `class_name` on test files (avoids polluting the global class cache). Test-only helpers (e.g. `combat_rules_helper.gd`) live beside the test, extend `RefCounted`, no `class_name`.
- Debug widgets (`scenes/debug/`) are never tested directly.

## Art pipeline (pixel-sprites skill)

Invoke the **pixel-sprites skill** for any sprite/art-asset work — it holds the full workflow. Never hand-draw PNGs. Load-bearing invariants:

- **Viewport 640×360**, integer-scaled 2× into a 1280×720 window. Do NOT "fix" the small viewport numbers in `project.godot`. Standard characters ≈64px tall.
- **UI font = monogram** (`assets/fonts/monogram-extended.ttf`, CC0) as theme `default_font` @16 (titles 32), AA/hinting/subpixel disabled. monogram is on-grid at 16 — sizes must be multiples of 16. It lacks many symbol glyphs; UI strings use only covered glyphs (`♦ × • · ▶ ▼ * + − —`) — do not reintroduce uncovered symbols or `allow_system_fallback` (pulls AA'd system glyphs).
- **Pipeline art** (icons, spell/skill VFX, particles, effects, UI) = XPM frames in `tools/sprites/frames/`, compiled by `python tools/sprites/compile.py [--check] tools/sprites` (Pillow; scale 1). Install by convention (**no `.tres` edits**): icons → `assets/sprites/icons/{weapons|spells|nodes}/<key>.png` (key = name lowercased, spaces→underscores; node icons use `node_id`); animated effects → `assets/sprites/effects/<Clip>_sheet.png`+`.json`, via `SpriteRegistry.get_effect_frames`. `.xpm`/`clips.json` writes auto-validated by the PostToolUse hook; `out/` is gitignored.
- **NOT pipeline art** — converted from CC0 packs by own converters: combatant battle sprites (`import_pack.py` + `packs.json`), scene backgrounds (`import_env.py` + `env.json`, wired null-safe into battle/campfire/menu), UI 9-slice skin (`bake_ui.py`, re-run if theme palette changes). Loaded via `SpriteRegistry.get_combatant_frames`/`get_background`. Licenses in the respective `assets/sprites/*/LICENSE.md`; pack ZIPs gitignored.
- After installing a new PNG: `"$GODOT" --headless --import --path .`, commit PNG + `.png.import`. The Fireball clip is the loader's test fixture (`tests/integration/test_sprite_registry.gd`) — keep it.

## Project structure

```
autoloads/          # RollEngine (dice), CombatManager (combat SM), PlayerProgression (constellation), DungeonManager (run state), SaveManager, DebugManager, SpriteRegistry, TooltipManager
combat/             # CombatManager refactor layers: CombatantState.gd (per-combat state), CombatMath.gd (pure static math), StatusOps.gd + InterruptOps.gd (status/interrupt bookkeeping), Disciplines.gd (magic-discipline casts)
combat/effects/     # Discipline effect-handler layer: CombatEffect base + EffectRegistry + Hex/TimeLock/Echo/MindBomb handlers; typed status-payload views (CastSnapshot, *Payload) + AttackContext
resources/          # Resource class defs (.gd) + data/ (.tres) — see project-index.md
scenes/main_menu/   # MainMenuScene (title, New Game, 3-slot save/load, Quit)
scenes/battle/      # BattleScene (1v1), CombatantHUD, RoundHUD, Combatant
scenes/campfire/    # CampfireScene (rest, weapon selector, Constellation nav, Give Up)
scenes/constellation/  # ConstellationScene (skill tree)
scenes/debug/       # Debug widgets — removable at release; never imported by production code
scripts/            # gen_project_index.py — regenerates docs/project-index.md
tools/sprites/      # XPM→PNG pipeline (compile.py, frames/, clips.json; out/ gitignored) + CC0 pack converters (import_pack.py combatants, import_env.py backgrounds, bake_ui.py UI skin)
assets/sprites/     # icons/{weapons,spells,nodes}/, effects/, combatants/, backgrounds/, ui/ — convention-loaded by SpriteRegistry
assets/fonts/       # monogram pixel font (CC0) — theme default_font
docs/game-rules/    # Design source of truth — TOC at index.md; load on demand
docs/impl/          # per-group implementation specs + combat-invariants.md
docs/               # project-status.md (roadmap), project-index.md (generated map)
.claude/            # agents/, commands/, hooks/validate_godot.py (PostToolUse), skills/pixel-sprites
```

## Architecture

### One-way data flow

`CombatantData` (`.tres`, **immutable config only**) → `CombatManager` → signals → `BattleScene` → HUD nodes. All runtime state lives in `CombatantState` (`combat/CombatantState.gd`, global `class_name`, instantiated per combat). Scene nodes hold no game state.

**CombatManager is a decomposed strangler** (both decomposition refactors COMPLETE — full phase history in `docs/project-status.md`; deep invariants in `docs/impl/combat-invariants.md`). Extracted modules, all stateless `static` over the `CombatManager`/`PlayerProgression` autoload globals:
- `combat/CombatMath.gd` — pure stat/tier/keep/modifier/format math.
- `combat/StatusOps.gd` + `combat/InterruptOps.gd` — status/interrupt bookkeeping. `StatusOps.tick()` RETURNS log lines (the wrapper emits them).
- `combat/Disciplines.gd` — discipline CAST logic (Mind Rend, Time Lock, Mind Detonation, echo resolution + shared `roll_enemy_guard`).
- `combat/effects/` — discipline LIFECYCLE handlers (`CombatEffect` base with 5 optional hooks; `EffectRegistry.get_handler(status_id)` → `Hex`/`TimeLock`/`Echo`/`MindBomb`). Status payload de-smuggled via typed VIEWS over `stat_overrides` (`CastSnapshot`, `MindBombPayload`, `EchoPayload`, `TimeLockPayload`); `AttackContext` carries per-attack facts.

CombatManager keeps same-signature private wrappers (`_stat_size`, `_add_status`, `_check_mind_detonation`, `_cast_time_lock`, …) that delegate — **do NOT re-inline the logic**. The async spine (`_resolve_attack`, `_resolve_round*`, `_end_of_round`, `_process_statuses_hook`) stays in CombatManager and names NO discipline: it iterates `active_statuses.duplicate()` and dispatches to the registry. Cast dispatch is data-driven via `SpellData.cast_handler`/`placement_scratch`/`primes_status` (not `spell.spell_name`). **Adding a discipline = new handler + registry entry + spell fields, no spine edit.**

`CombatantState` fields, grouped:
- *Identity/HP:* `data`, `current_wounds`, `max_wounds`, `is_defeated`
- *Progression:* `node_levels: Dictionary` (NodeData→int), `tier_override`, `weapon_override`, `off_hand_override`
- *Per-combat charges:* `item_action_charges` (from `rest_type="combat"` ActionModifiers at `start_combat()`), `space_domination_active`
- *Effects:* `active_statuses: Array[CombatStatus]` (always iterated as `.duplicate()`), `interrupt_handlers: Array[InterruptHandler]` (combat-scoped, registered at `start_combat()`), `pending_guard_debuffs` (single-use, consumed on next guard roll)
- *Guard:* `stance_guard`/`resolve_guard`/`stamina_guard` + matching `_rolled` bools
- *Magic:* `fervor_size`, `is_burned_out`, `has_minor_studies`, `has_spellcasting`, `known_spells`, `known_cantrips`
- *Methods:* `init()`, `reset_guard()`, `get_guard(pool)`, `set_guard_val(pool, v)`, `is_pool_rolled(pool)`, `set_pool_rolled(pool, v)`

### Autoload singletons

Full signatures/signals live in `docs/project-index.md` (load on demand). Behavioural gotchas the index can't show:

- **`RollEngine`** — stateless. Returns `Dictionary`; always cast (`as int`/`as Array`). `resolve()` optional args: `fervor_size`, `aspect_stat_size`+`aspect_count`, `post_keep_bonus_size`. Returns `primary_dice_maxed_count`, `post_keep_bonus_roll`.
- **`CombatManager`** — all output via signals; nothing returned. Disconnect all signals before `reload_current_scene()`. `_get_cast_modifier(state)` resolves the chosen `_player_cast_weapon`'s `"cast"` modifier (bare-hands fallback, bonuses zero); cantrip and true-spell pools route through it, NEVER `_get_action_modifier(_, "strike")`. Player-strike bonuses source from `chosen_weapon` (`_strike_mod`), not main-hand. **Casting is equipment-gated** (equip-requirements rework): `CombatMath.can_channel_cantrips` (both hands empty OR `MagicFocus`-tagged item equipped) / `can_channel_spells` (`MagicFocus` always required) — enforced at `player_magic_available` emission + defensively in `player_chose_cantrip/_spell`. Items never cap Tier (`effective_tier(state)` has no mod param); expressed-dice throttle = node keep grades.
- **`PlayerProgression`** — constellation state; read by `CombatManager` at `start_combat()`. Fervor persistence via `saved_fervor_size`/`saved_is_burned_out`/`saved_wounds`. `_grant_default_keep_nodes()` (in `reset()`) auto-grants L1 of `dom_martial_arts`/`dom_stamina`/`neg_stance`/`ing_resolve` — the free 1-die keep baseline (L2/L3 are upgrades to 2/3).
- **`DungeonManager`** — 8-encounter run state; hard-coded sequence documented in `docs/project-status.md`.

### Round loop (CombatManager)

```
_begin_round()
  → _process_statuses_hook("start_of_round", …) → _tick_statuses (decrements/removes expired)
  → emits player_intents_available / player_magic_available
  → player presses Strike/Cantrip/Spell → BattleScene → player_chose_*
  → _resolve_round / _cantrip / _spell → rolls attacks, VT check, _resolve_attack() × N (Slow → Player → Fast)
	  → on breach: _process_statuses_hook("on_breach", …); interrupt check: _find_interrupts → await _resolve_interrupt
  → [Phase 2.1] await _check_mind_detonation(target, idx)   � all 3 round types
  → [spell only] _escalate_fervor(steps = primary_dice_maxed_count + (1 if fervor_maxed))

await _end_of_round()
  → await _process_statuses_hook("end_of_round", …)   � Echo dispatches here (async)
  → if _all_enemies_defeated(): _end_combat(); return  � echo may have killed last enemy
  → _tick_statuses; guard reset for all combatants; await 0.8s → _begin_round()
```

`_resolve_round*`, `_resolve_attack`, `_end_of_round`, `_process_statuses_hook` are all coroutines. `player_chose_*` call `_resolve_round*` without `await` intentionally (cooperative, yields at timer). Only the `_end_of_round` hook call is awaited (echo async); `start_of_round`/`on_breach` are fire-and-forget. Guards reset in `_end_of_round`, so they're 0 when `start_of_round` hooks fire.

### Status system

`CombatStatus` is data-only (`resources/CombatStatus.gd`); all logic lives in `CombatManager._process_statuses_hook()` / the effect handlers, never in the resource.

Helpers: `_add_status(state, status)` (removes same `status_id` then appends — re-applying refreshes, no stacking), `_remove_status`, `_has_status`, `_get_status`, `_tick_statuses` (decrements `duration_rounds`, removes at 0; runs once after `start_of_round` and once after `end_of_round` hooks → twice per full round). `_stat_size()` reads `status.stat_overrides[stat]` BEFORE node levels — overrides win. `stat_overrides` also carries non-stat payload (read only via the typed `combat/effects/` views).

### Interrupt system

`InterruptHandler` is a reactive hook registered per `CombatantState` at `start_combat()`. Two fire points, **separate dispatch paths**:
1. **`_resolve_attack()`** — trigger `"on_massive_wound"`, wounds-shaped. `_find_interrupts` → `await _resolve_interrupt`. Active: **Meat for the Grinder** (priority 20).
2. **`_escalate_fervor()`** — trigger `"on_burnout"`, bool-shaped. `await _try_prevent_burnout` directly (does NOT use `_resolve_interrupt`). Active: **Lucidity L2** (priority 10).

Lower priority fires first; the two never contend (different fire points).

### Data-only resource fields

Three data-only resources (zero methods; logic in `CombatManager`):
- **CombatStatus**: `status_id`, `duration_rounds` (-1 = permanent), `stat_overrides: Dictionary`, `escalation_threshold`, `source_node_id`.
- **InterruptHandler**: `handler_id`, `trigger`, `target`, `charges`, `priority`.
- **SpellOutcomeEffect**: `spell_id`, `trigger` ("on_hit"|"on_breach"|"on_cast"|"on_detonate"), `target`, `target_pool`, `effect_type`, `value`, `condition`, `status_to_apply`.

**Boundary — SpellOutcomeEffect vs CombatStatus:** SpellOutcomeEffect is instantaneous (same spell resolution). For cross-round persistence use `effect_type="apply_status"`. NEVER add a duration field to SpellOutcomeEffect.

### Magic system

- **Fervor** — player-only. Track d4→d6→d8→d10 (`FERVOR_TRACK`), cap = `data.ingenuity_size`. Persists across combats (`saved_fervor_size`); Long Rest resets to d4, Recovery only clears Burnout.
- **Escalation** — after a true spell, `await _escalate_fervor(_player, steps)`. A positive step that would set Burnout awaits `_try_prevent_burnout` (Lucidity L2) before committing.
- **Burnout** — blocks `player_chose_spell()`; cantrips remain. Persists; cleared by Long Rest or Recovery.
- **Cantrip** — `is_cantrip=true`. Ingenuity pool, no Fervor die, no escalation, available during Burnout. Via `node.spells` (Minor Studies). Conduit gate: both hands empty OR `MagicFocus` item equipped.
- **True spell** — Ingenuity + optional aspect dice + real Fervor die. Granted by Spellcasting L1+. Conduit gate: `MagicFocus` item equipped, always (empty hands not enough).

**SpellData**: `spell_name`, `description`, `aspect_stat`, `aspect_dice`, `target_pool`, `flat_bonus`, `is_cantrip`, `tags`, `cast_handler`, `placement_scratch`, `primes_status`.

### Node-driven spell bonuses

- **Core stat nodes:** `dom_core`/`neg_core`/`ing_core` L1–L3 via `effect_type="stat_size_<stat>"` + `effect_value`. `_stat_size(state, stat)` returns the highest across purchased entries.
- **SpellBonusEffect** (`tag`, `bonus_type` "pool"|"keep"|"flat", `value`, `stat`, `spell_id`): applies if `spell_id` matches (non-empty) OR `tag` matches a spell tag. Summed into `spell_pool_bonus`/`spell_keep_bonus`/`spell_flat_bonus` in `_resolve_round_spell()`.
- **Node schema:** `NodeData` (node_id, display_name, category, base_description, icon, max_levels, `levels_data: Array[NodeLevelData]`). `NodeLevelData` (level_index, cost, required_tier, prerequisites, effect_type, effect_value, stat, weapon_tags, uses_per_combat, spells, bonus_effects, outcome_effects). All `*_keep` effect_values follow **N = keep N dice** (1/2/3 for L1/L2/L3). Both `_physical_keep_grade` and `_defense_keep_grade` = `maxi(_training_keep_grade(state), _node_effect_max(state, key))` — training is the floor.

### Spell outcome effects

`SpellOutcomeEffect` (on `NodeLevelData.outcome_effects`) applies AFTER resolution — contrast `SpellBonusEffect` (modifies the roll). Flow in `_resolve_round_spell`/`_cantrip`: roll built with `SpellBonusEffect` applied → `_resolve_attack` runs → `_apply_spell_outcome_effects` collects matching entries → each filtered by `trigger` then `condition` → queues single-use `pending_guard_debuffs`, applies a `CombatStatus`, or no-ops with `push_warning`.

**Round-scoped tracking:** `_current_round_player_breaches` lives on `CombatManager` (not `CombatantState`), reset every `_begin_round()`. `"hit"/"breach"` in the outcome = "this spell caused the round's FIRST breach on its target_pool" (false if already breached).

### GDScript typing rules

- Scene scripts referenced as types elsewhere **must** declare `class_name` (missing it → "Could not find type" at load).
- After adding a `class_name`, update `.godot/global_script_class_cache.cfg` manually if the editor hasn't been opened — the headless runner uses the cached index.
- `RollEngine.resolve()` Dictionary values are `Variant` — annotate locals or cast (`as int`/`as Array`).

## Design references

- **Game rules** (canonical decisions): [docs/game-rules/index.md](docs/game-rules/index.md). Implementation summary (how rules map to code): [docs/game-rules/summary.md](docs/game-rules/summary.md). _Load on demand; the core table below covers the universal 20%._
- **Combat internals** (discipline/effect fragile invariants): [docs/impl/combat-invariants.md](docs/impl/combat-invariants.md). _Load before editing the async spine, `combat/effects/`, or any discipline._
- **Game style** — 2D turn-based dark-fantasy duel RPG; hand-drawn pixel art; UI feels like a tangible RPG document. [docs/game-style/style-concept.md](docs/game-style/style-concept.md)
- **Project status** (roadmap + refactor history; consult before proposing new work): [docs/project-status.md](docs/project-status.md)
- **Project index** (auto-generated code map: signals, signatures, resource schemas; read before scanning source): [docs/project-index.md](docs/project-index.md)

## Fragile areas — do not accidentally "fix" these

General invariants below. Discipline/effect-internal invariants (Mind Detonation, Hex, Echo, Time Lock, escalation, interrupts) live in `docs/impl/combat-invariants.md` — read it before editing those systems.

| Area | Why it's correct |
|---|---|
| `_resolve_round*` / `_end_of_round()` called without visible `await` | Coroutine pattern — run cooperatively on the main thread, yield at the timer; callers do use `await` where needed |
| Guard reset in `_end_of_round()` not `_begin_round()` | Guards must be 0 when `start_of_round` hooks fire |
| `global_script_class_cache.cfg` stale after new `class_name` | Update manually when the editor hasn't been opened — headless uses the cached index |
| `EquipmentData` flat fields (`flat_attack_bonus`, …) still present | Deprecated shims, superseded by `action_modifiers`; ignored at runtime when `action_modifiers` is non-empty. (`potency` and `ActionModifier.tier_cap` are fully deleted — do not reintroduce item Tier caps; keep grades are the throttle) |
| Three separate per-pool guard/rolled pairs | Cumulative Disadvantage on 2nd+ pool pressure is deferred (project-status Future) |
| `debug_set_player_weapon` public on a production autoload | Used by `DebugWeaponSelector`; null-guarded at the call site |
| `CombatStatus` has no methods | Logic lives in the dispatcher, not the data |
| `_process_statuses_hook` iterates `.duplicate()` | Prevents array mutation during iteration if a case adds/removes mid-loop |
| `_stat_size()` checks active_statuses before node_levels | Temporary overrides (e.g. Purple Hollow d12) must win over permanent progression |
| `_add_status` silently replaces duplicates | Re-applying refreshes, not stacks |
| Discipline spine logic lives in `combat/effects/` handlers, not the spine | The spine iterates `active_statuses.duplicate()` and dispatches to `EffectRegistry.get_handler(status_id)`. Do NOT re-inline hex/Time-Lock/echo/frozen. Breach-driven MD detonation stays in the round coroutines (`_check_mind_detonation` at Phase 2.1) — dispatch, not a lifecycle hook |
| Cast routing is data-driven via `SpellData.cast_handler`/`placement_scratch`/`primes_status` | `_resolve_round_spell` matches `cast_handler`, not `spell.spell_name`; do not reintroduce name string-matches. Echo arming stays tag-driven (`"echo" in spell.tags`) |
| Cantrip/true-spell pool uses `_get_cast_modifier`, never strike mod | Do not revert to `_get_action_modifier(_, "strike")`; that was the Phase 1 bug. Cast pool = `_effective_tier(player) + cast_mod.pool_bonus` (+ school bonuses for spells) |
| Casting gated by `CombatMath.can_channel_cantrips/spells`, checked in 3 places | Emission gate (`_begin_round`), choose-guards (`player_chose_cantrip/_spell`), and UI (RoundHUD grey + focus-only tool list + ATK-Auto conduit fallback) are deliberate defense-in-depth — removing one layer breaks a different path (auto-cast, stale HUD, or direct calls) |
| Player strike flat/pool/weapon-tag bonuses sourced from `chosen_weapon` | `_attack_flat`/`_pool_bonus`/`_node_weapon_bonus_sum` take optional `strike_mod`/`weapon`; the player-strike call site passes `_strike_mod` + `chosen_weapon`. Do NOT revert (that was the off-hand bug). `chosen_weapon == null` falls back to state's main-hand |
| `_resolve_interrupt` awaited inside `_resolve_attack` | Interrupts may need player input — the await is the point |
| `get_player_attack_preview()` is dead code | Zero callers; intentionally untouched. Do not rely on it to test strike bonuses |
