# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Engine and tooling

- **Godot 4.6.2** — Forward Plus renderer, D3D12 on Windows, Jolt Physics.
- The Godot binary is resolved automatically (see "Running all checks" for the priority order).
- Run headless validation: `python scripts/run_headless.py`
- Run unit + integration tests: `python scripts/run_tests.py`
- **GUT 9.6.0** is installed at `addons/gut/`. Tests live in `tests/`.
- After adding a new plugin/addon for the first time, set `GODOT` and run `python scripts/run_headless.py` with `--import` manually if needed to register class names before running tests.
- No build step, no linter — Godot parses scripts on load. See "Running all checks" for the canonical validation command.

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
- Where files are independent (no shared state, no load order dependency),
  implement them in parallel using subagents (using the appropriate model based on task complexity).
- Never parallelize writes to files that share state or that must be
  applied in a specific order (e.g. autoloads before scenes that depend on them).
- Match subagent model to task complexity:
  - `haiku` — validation runs, headless checks, single-file doc/typo fixes, simple searches.
  - `sonnet` — single-file feature work, moderate reasoning, most implementation tasks.
  - `opus` — multi-file architecture, complex cross-system reasoning, design decisions.

### 2b. Debug & Testability
Every feature that introduces a new mechanic or runtime value must ship with a way to exercise it interactively.

Debug widgets live exclusively in `scenes/debug/`. Reference via null-safe `@onready` delegate: `@onready var _dbg = $Widget if has_node("Widget") else null`. Remove at release: delete `scenes/debug/`, remove the child from the parent `.tscn`, remove the `@onready` and its delegation method — nothing else changes. If a mechanic has no tunable parameters, a log-only approach is acceptable; document the decision in the feature report.

### 2c. Inter-phase context compaction
When implementing a multi-phase feature (e.g. Phase A / B / C), it is acceptable — and encouraged when the context window is growing large — to `/compact` the conversation between phases. Compact after each phase's validation passes and before starting the next phase. This keeps context healthy without losing continuity: the phase boundary is a natural checkpoint, the plan file preserves intent, and the next phase can be resumed from the plan.

### 3. Validate (deploy a sub-agent)
Deploy a sub-agent and run **both** checks in order:
1. **Tests first**: `python scripts/run_tests.py` — a test failure blocks the loop; do not proceed to the headless run until tests are green.
2. **Headless run**: `"$GODOT" --headless --path "..." --quit-after 5` — check for SCRIPT ERRORs and ERRORs (UID WARNINGs are safe), verify `@onready` paths, signal connections, and `class_name` registrations in `.godot/global_script_class_cache.cfg`.

### 4. Fix Loop
If validation fails:
- If a **test** fails: fix the logic first, re-run `python scripts/run_tests.py`, then re-run headless validation.
- If the **headless run** fails: fix the specific SCRIPT ERROR reported, re-run headless only (tests need not re-run for script-load errors).
- Repeat until both checks are clean.

### 5. Update Documentation
Only after a clean validation pass:
- Update relevant files under `docs/game-rules/` if mechanics changed.
- Update `CLAUDE.md` if architecture or rules changed.
- If the feature added or renamed a `.gd` file, added a signal, added an `@export` field,
  or added a `.tres` file — run `/refresh-index` as the final action in this step, before
  asking the user to run `/ship`. Content-only changes (bug fixes, logic edits) skip this.

### 6. Report
Return a concise summary covering:
- What was implemented and where.
- What the validation found and confirmed.
- What documentation was updated.

### 7. Commit and push
Ask the user to run `/ship`.

---

**Rules**
- Docs updated only after successful validation, never before.
- The final report must be short enough to scan in under a minute.
- Never edit files under `docs/game-rules/` without explicit user approval — it is the single source of truth for all game design. If a rule is ambiguous, ask; never decide unilaterally.

## Running all checks

Canonical validation command (run tests first, then headless):
```
python scripts/run_tests.py && python scripts/run_headless.py
```
Exits 0 only if all tests pass **and** the headless engine check is clean.

The Godot binary is resolved automatically from (in order):
1. `GODOT` environment variable
2. `.env.local` file in the project root (copy `.env.local.example` to get started)
3. `godot` on the system PATH
4. Common Windows install locations (`%LOCALAPPDATA%\Programs\Godot\Godot.exe`, `C:\Program Files\Godot\Godot.exe`)

New contributors: copy `.env.local.example` → `.env.local` and set your path.

## Testing rules

- Every new mechanic must ship with at least one unit test.
- Tests live in `tests/unit/<system_name>/test_<system_name>.gd`.
- Integration-level tests (scene-dependent or autoload-dependent flows) go in `tests/integration/`.
- Tests must be deterministic: seed `RollEngine` calls with `seed(N)` before calling `resolve()`.
- Do not add `class_name` to test files — avoids polluting the global script class cache.
- Debug widgets (`scenes/debug/`) are never tested directly.
- Helper classes used only by tests (e.g. `combat_rules_helper.gd`) live alongside the test file and extend `RefCounted` with no `class_name`.

## Project structure

```
autoloads/          # RollEngine (dice), CombatManager (combat SM), PlayerProgression (constellation), DungeonManager (run state), SaveManager (save/load), DebugManager (debug toggle), SpriteRegistry (sprite/icon registry), TooltipManager (contextual tooltips)
resources/          # Resource class definitions (.gd) + data/ (.tres files) — see project-index.md
scenes/main_menu/   # MainMenuScene (title, New Game, 3-slot save/load, Quit)
scenes/battle/      # BattleScene (1v1 combat), CombatantHUD, RoundHUD, Combatant
scenes/campfire/    # CampfireScene (post-combat rest, weapon selector, Constellation nav, Give Up)
scenes/constellation/  # ConstellationScene (skill tree)
scenes/debug/       # Debug widgets — removable at release; never imported by production code directly
scripts/            # gen_project_index.py — regenerates docs/project-index.md
docs/game-rules/    # Design source of truth — navigation TOC at index.md; load files on demand
docs/impl/          # per-group implementation specs (e.g. group-8-sprite-registry.md)
docs/               # project-status.md (roadmap), project-index.md (generated code map)
.claude/            # agents/docs-alignment-auditor.md, commands/audit-docs.md + refresh-index.md
```

## Architecture

### One-way data flow

`CombatantData` (`.tres` resource) → `CombatManager` → signals → `BattleScene` → HUD nodes.

`CombatantData` is **immutable config** only. All runtime state lives inside `CombatManager.CombatantState`, an inner class instantiated per combat. Scene nodes hold no game state.

`CombatantState` fields: `data` (CombatantData), `current_wounds`, `max_wounds`, `is_defeated`, `node_levels: Dictionary` (NodeData → int), `tier_override`, `weapon_override`, `off_hand_override` (EquipmentData), `space_domination_active: bool`, `item_action_charges: Dictionary` (action_key → remaining uses; initialized at `start_combat()` from `ActionModifier`s with `rest_type="combat"`), `active_statuses: Array[CombatStatus]` (temporary effects; always iterated as `.duplicate()`), `interrupt_handlers: Array[InterruptHandler]` (registered at `start_combat()` based on purchased nodes; combat-scoped, charges reset each combat), `pending_guard_debuffs: Dictionary` (`{ "<pool>": { "flat": int, "keep": int } }`; single-use debuffs queued by SpellOutcomeEffect, consumed on the next guard roll for that pool), plus per-pool guard state (`stance_guard`, `resolve_guard`, `stamina_guard`, and matching `_rolled` booleans), plus magic state (`fervor_size`, `is_burned_out`, `has_minor_studies`, `has_spellcasting`, `known_spells: Array`, `known_cantrips: Array`). Methods: `init()`, `reset_guard()`, `get_guard(pool)`, `set_guard_val(pool, value)`, `is_pool_rolled(pool)`, `set_pool_rolled(pool, value)`.

### Autoload singletons

Signatures and signals are in `docs/project-index.md`. Architectural gotchas:
- **`RollEngine`** — stateless. Returns `Dictionary`; always cast values with `as int` / `as Array` — the type inferencer cannot infer through `Dictionary`. `resolve()` accepts optional `fervor_size` (additive post-Keep Fervor die), `aspect_stat_size` and `aspect_count` (for mixed-pool spells), `post_keep_bonus_size` (additive post-Keep bonus die, e.g. Earthshatter). Returns `primary_dice_maxed_count` (Fervor escalation) and `post_keep_bonus_roll` (Earthshatter die result).
- **`CombatManager`** — all output via signals; nothing returned. Disconnect all signals before `reload_current_scene()`. Signals: `player_intents_available(intents: Array[String])`, `fervor_changed(is_player, fervor_size, fervor_cap, is_burned_out)`, `player_magic_available(can_cantrip, can_cast_spell)`, `player_massive_incoming(charges_left)`, `player_defense_incoming(attacker_name, attack_total, target_pool)`, `player_defense_item_choice(options: Array)`. Public methods: `start_combat(player_data: CombatantData, enemies_data: Array)`, `player_chose_strike(net_advantage, target_pool, brutal_trade, target_index: int = 0, source_weapon: EquipmentData = null)`, `player_chose_cantrip(spell: SpellData, target_index: int = 0)`, `player_chose_spell(spell: SpellData, target_index: int = 0)`, `player_chose_degrade_wound(use_charge: bool)`, `player_acknowledged_defense()`, `player_chose_defense_item(mod: ActionModifier)`, `player_auto_execute_attack(target_index: int = 0, net_advantage: int = 0)`, `reset_item_charges(rest_type: String)` (called by DungeonManager on rest), `debug_set_fervor(size, burned_out)`, `debug_refill_hp()`, `debug_set_immortal(enabled: bool)`, `debug_set_lethal(enabled: bool)`, `debug_set_player_off_hand(weapon: EquipmentData)`, `get_player_bare_hands_modifier(action_key: String) → ActionModifier`, `get_player_attack_preview() → int`. Key helpers: `_get_action_modifier(state, action_key) → ActionModifier` (weapon → bare_hands → zero stub), `_effective_tier(state, mod: ActionModifier = null)` (mod.tier_cap=0 = uncapped), `_attack_flat(state)` / `_guard_flat(state)` / `_pool_bonus(state, action_key="strike")` all delegate to `_get_action_modifier`.
- **`PlayerProgression`** — constellation state; read by `CombatManager` at `start_combat()`. `ALL_NODES` catalog (now includes 11 Dominion nodes; old core_dominion_1/2 replaced by dom_core). `get_known_spells()` and `get_known_cantrips()` iterate all purchased `node_levels`, collect from `levels_data[0..level-1].spells`. `get_node_level_by_id(id)` looks up a node by string ID and returns its current level (0 if absent). **Fervor persistence** (Group 5): `saved_fervor_size` / `saved_is_burned_out` / `saved_wounds` fields written by `CombatManager._end_combat()`, read by `start_combat()` (`saved_wounds` carries wounds between chained encounters). `combat_prefs: CombatPreferences` — persisted action defaults and mode flags; instantiated fresh in `reset()`, serialized/deserialized with save data. Methods: `reset()`, `apply_long_rest()` (reset fervor + clear burnout), `apply_short_rest()` (−1 wound, −1 fervor step, clear burnout), `apply_recovery()` (clear burnout only), `grant_points(n)`, `equip_main_hand(w)`, `equip_off_hand(w)`, `debug_set_points(n)`, `debug_set_tier(t)`.
- **`DungeonManager`** — run state: `start_run()`, `current_enemies() → Array`, `on_victory()` (grants 1 point + advances index), `on_defeat()`, `has_next_enemy()`, `is_run_complete()`, `was_last_fight_chained()`, `enemies_cleared()`, `enemies_total()`. Hard-coded 8-encounter sequence: [1] Grunt, [2] Grunt→Grunt, [3] Grunt+Grunt, [4] Soldier, [5] Grunt→Grunt+Soldier, [6] Grunt+Grunt+Grunt, [7] Grunt+Soldier→Soldier+Soldier, [8] Knight (solo).

### Round loop (CombatManager)

```
_begin_round()
  → _process_statuses_hook("start_of_round", _player / enemy × N)
  → _tick_statuses(_player / enemy × N)           ← decrements/removes expired statuses
  → emits player_intents_available(intents: Array[String])
  → emits player_magic_available(can_cantrip, can_cast_spell)
  → emits player_action_required
  → (player presses Strike / Cantrip / Spell → BattleScene calls player_chose_strike / _cantrip / _spell)
  → _resolve_round / _resolve_round_cantrip / _resolve_round_spell
  → rolls attacks, VT check, _resolve_attack() × N (Slow enemies → Player → Fast enemies)
      → after breach confirmed: _process_statuses_hook("on_breach", defender, {pool, attacker})
      → [interrupt check] _find_interrupts(defender, trigger) → await _resolve_interrupt() for each
  → [spell only] _escalate_fervor(steps) where steps = primary_dice_maxed_count (Ingenuity-tagged dice that rolled max, pre-Keep, including discarded) + (1 if fervor_maxed)

await _end_of_round()
  → _process_statuses_hook("end_of_round", _player / enemy × N)
  → _tick_statuses(_player / enemy × N)           ← decrements/removes expired statuses
  → guard reset for all combatants (+ guard_changed signals)
  → await 0.8s timer
  → _begin_round()  ← loops until defeat
```

`_resolve_round*` are GDScript coroutines (use `await`). Calling them without `await` from the `player_chose_*` methods is intentional — they run cooperatively on the main thread, yielding at the timer. `_resolve_attack()` is also a coroutine (awaits inside the interrupt gate and inside `_defense_acknowledged`); all `_resolve_round*` calls to it use `await`. `_end_of_round()` is likewise a coroutine and must be called with `await`.

Guards are reset inside `_end_of_round()`, not `_begin_round()`. This ensures guards are already 0 when `start_of_round` hooks fire.

### Status system

`CombatStatus` is a data-only resource (`resources/CombatStatus.gd`). Hard rule: zero functional methods — all processing logic lives in `CombatManager._process_statuses_hook()`, never in `CombatStatus` itself.

Helpers on `CombatManager`:
- `_add_status(state, status)` — removes any existing status with the same `status_id`, then appends. Applying the same status twice refreshes it (no stacking).
- `_remove_status(state, status_id)` — filters out all matching entries.
- `_has_status(state, status_id) → bool`
- `_get_status(state, status_id) → CombatStatus`
- `_tick_statuses(state)` — decrements `duration_rounds` for all non-permanent statuses and removes those that reach 0. Called once after `start_of_round` hooks in `_begin_round()` and once after `end_of_round` hooks in `_end_of_round()`.

`_process_statuses_hook(hook, state, context)` dispatches on `status.status_id` via a `match` block. Always iterates `state.active_statuses.duplicate()` to prevent mutation during iteration. No match cases are active yet — Groups B–D will add them. Logic must never move into `CombatStatus` itself.

Stat overrides: `_stat_size(state, stat)` reads `status.stat_overrides[stat]` before falling through to node levels — status overrides always win over permanent progression.

### Interrupt system

`InterruptHandler` is a reactive hook fired inside `_resolve_attack()` before final outcome
application. Handlers are registered per `CombatantState` at `start_combat()` based on
purchased nodes. Each handler has a trigger (currently only `"on_massive_wound"`), charges,
and priority.

Flow:
1. `_resolve_attack()` detects a triggerable event (e.g. wound is Massive and defender is player)
2. `_find_interrupts(state, trigger)` returns matching handlers sorted by priority ascending
3. For each handler in order, `_resolve_interrupt()` dispatches to the handler-specific method
4. The handler may emit signals, await player input, modify the outcome, and consume a charge
5. The next handler (if any) sees the outcome already modified by the previous

Priority table (lower = processed first):
- Mental Fortress (B3): 10
- Meat for the Grinder: 20

Adding a new handler:
1. Add a case in `_resolve_interrupt()` dispatching by `handler_id`
2. Implement `_resolve_<handler_name>()` with the signal/await contract
3. Register in `start_combat()` based on the relevant node level
4. Update the priority table above and in CLAUDE.md

### New architectural resources (Group A — fully implemented; unblocks Group B)

**CombatStatus** — temporary state on a combatant. Hard rule: data only,
zero functional methods. Fields: `status_id`, `duration_rounds`
(-1 = permanent), `stat_overrides: Dictionary`, `escalation_threshold: int`,
`source_node_id: String`.

**InterruptHandler** — reactive interrupt during _resolve_attack(). Fields:
`handler_id`, `trigger` ("on_massive_wound" | "on_lethal_wound" | "on_wound"),
`target` ("self" | "enemy"), `charges`, `priority`.
Priority table: Mental Fortress = 10, Meat for the Grinder = 20.
Rule: the second handler sees the outcome already modified by the first.

**SpellOutcomeEffect** — post-resolution spell effect. Fields: `spell_id`,
`trigger` ("on_hit" | "on_breach" | "on_cast" | "on_detonate"), `target`,
`target_pool`, `effect_type`
("debuff_flat" | "debuff_keep" | "bonus_keep" | "bonus_flat" | "apply_status"),
`value`, `condition`, `status_to_apply: CombatStatus`.

**Critical boundary — SpellOutcomeEffect vs CombatStatus:**
- SpellOutcomeEffect = instantaneous effect resolved within the same spell
  resolution
- If the effect must persist across rounds, SpellOutcomeEffect with
  effect_type="apply_status" applies a CombatStatus
- NEVER add a duration field to SpellOutcomeEffect

### Magic system

Group 4 implements Fervor / Burnout / Cantrips / True Spells with per-spell `SpellData`:

- **Fervor** — player-only runtime state on `CombatantState`. Track: d4 → d6 → d8 → d10 (`FERVOR_TRACK` const). Cap = `data.ingenuity_size`. Persists across combats via `PlayerProgression.saved_fervor_size`; Long Rest resets to d4, Recovery Scene only clears Burnout.
- **Escalation** — after a true spell resolves, `_escalate_fervor(_player, steps)` where `steps = primary_dice_maxed_count` (Ingenuity-tagged dice that rolled max, pre-Keep, including discarded) `+ (1 if fervor_maxed)`. Multiple steps possible in a single cast.
- **Burnout** — blocks `player_chose_spell()`; cantrips remain available. Persists across combats; cleared by Long Rest or Recovery.
- **Cantrip** — uses `SpellData` (is_cantrip=true). Ingenuity pool, no Fervor die, no escalation. Available during Burnout. Granted via `node.spells` (Minor Studies carries "Arcane Bolt" [`arcane_bolt.tres`] + "Arcane Touch" [`arcane_touch.tres`]).
- **True spell** — uses `SpellData`. Ingenuity pool + optional aspect dice + real Fervor die. Granted by Spellcasting L1+ (Arcane Missile + Arcane Mark at L1).

### SpellData (implemented)

`resources/SpellData.gd` (`class_name SpellData`):
- `spell_name: String`, `description: String`
- `aspect_stat: String` (`"dominion"` | `"negation"` | `""`) — non-Ingenuity stat for anchor dice; `""` = pure Ingenuity.
- `aspect_dice: int` — how many pool dice use `aspect_stat`; the rest are Ingenuity-tagged (count toward escalation even if discarded).
- `target_pool: String` — defense pool the spell pressures.
- `flat_bonus: int` — post-keep flat addition.
- `is_cantrip: bool` — no Fervor die, available during Burnout.
- `tags: PackedStringArray` — matched against `SpellBonusEffect.tag` at spell resolution.

### Spell school system (implemented — Groups 4.5 A + B)

**Phase A — Core stat nodes (implemented):**
- Core nodes (`dom_core` L1–L3, `neg_core` L1–L3, `ing_core` L1–L3) grant stat size upgrades via `effect_type="stat_size_<stat>"` and `effect_value`.
- `CombatManager._stat_size(state, stat)` — reads base from `CombatantData`, returns highest `effect_value` across all purchased `NodeLevelData` entries for `"stat_size_<stat>"`.

**Phase B — SpellBonusEffect pipeline (implemented):**
- `SpellBonusEffect` resource (`resources/SpellBonusEffect.gd`): `tag: String`, `bonus_type: "pool"|"keep"|"flat"`, `value: int`, `stat: String`, `spell_id: String` (optional per-spell filter; empty = tag matching, non-empty = name match, overrides tag check).
- `Spellcasting` L2/L3 inject bonus_effects: L2 adds `tag="arcane", keep+1` + `spell_id="Arcane Missile", flat+1`; L3 stacks another `keep+1` and `flat+1`. Keep bonuses are additive with L3 reaching grade 2 (keep 3 dice).
- `CombatManager._resolve_round_spell()` sums matching `bonus_effects`: a bonus applies if `spell_id` matches the spell's name (non-empty), or `tag` matches one of the spell's tags (empty `spell_id`). Three summed locals: `spell_pool_bonus`, `spell_keep_bonus`, `spell_flat_bonus`.

**Multi-level Node Schema (implemented — Group 4.8 Phase A):**
- `NodeData` fields: `node_id: String`, `display_name: String`, `category: String`, `base_description: String`, `icon: Texture2D`, `max_levels: int`, `levels_data: Array[NodeLevelData]`.
- `NodeLevelData` fields: `level_index`, `cost`, `required_tier`, `prerequisites: Array` (untyped, `[{node_id: String, required_level: int}]`), `level_effect_description`, `effect_type`, `effect_value`, `stat`, `weapon_tags: PackedStringArray`, `uses_per_combat`, `spells: Array[SpellData]`, `bonus_effects: Array[SpellBonusEffect]`, `outcome_effects: Array[SpellOutcomeEffect]`.
- `PlayerProgression.node_levels: Dictionary` (NodeData → int); methods: `can_upgrade(node)`, `upgrade(node)`, `get_level(node)`, `get_node_level_by_id(id)`.
- `CombatManager` helpers: `_node_effect_max(state, key)`, `_node_effect_sum(state, key)`, `_node_weapon_bonus_sum(state, key)`, `_has_effect_type(state, key)`, `_physical_keep_grade(state)`, `_wounds_node_bonus(state)`, `_meat_grinder_charges(state)`.

### Spell outcome effect system (Group A4)

`SpellOutcomeEffect` is a data-only resource attached to `NodeLevelData` via `outcome_effects: Array[SpellOutcomeEffect]`. It describes effects applied AFTER spell resolution, in contrast to `SpellBonusEffect` which modifies the caster's roll itself.

Flow at spell resolution (`_resolve_round_spell`, `_resolve_round_cantrip`):
1. The attack roll is built (`SpellBonusEffect` applied here, including `spell_id`-filtered bonuses)
2. `_resolve_attack` runs, producing breach/hit outcome; updates `_current_round_player_breaches`
3. `_apply_spell_outcome_effects` collects all matching `SpellOutcomeEffect` entries from purchased nodes
4. Each effect is filtered by `trigger`, then `condition`, then dispatched
5. Effects either: queue a single-use debuff in `pending_guard_debuffs` (consumed on next defense on that pool), apply a `CombatStatus`, or are no-ops with `push_warning`

**Boundary with `SpellBonusEffect`:**
- `SpellBonusEffect` modifies the caster's roll → applied at roll construction time
- `SpellOutcomeEffect` modifies post-resolution state → applied after the resolver returns
- `SpellBonusEffect` now has optional `spell_id` for per-spell numerical upgrades (e.g. "Arcane Missile gets +1 flat from Spellcasting L2")

**Boundary with `CombatStatus`:**
- `SpellOutcomeEffect` is instantaneous — resolves in the same spell resolution that produced it
- If persistence is needed, use `effect_type="apply_status"` to apply a `CombatStatus`
- NEVER add a duration field to `SpellOutcomeEffect`

**Round-scoped tracking:**
- `_current_round_player_breaches: Dictionary` lives on `CombatManager` (not `CombatantState`) — it is round-scoped, reset every `_begin_round()`
- Conditions like `"if_stance_breached_this_round"` read from this dict
- `"hit"/"breach"` in the outcome dict means "this spell caused the round's FIRST breach on its target_pool". A spell that targets an already-breached pool will have `breach=false`. Pure per-spell breach detection is deferred to Group B.

### GDScript typing rules

- All scene scripts that are referenced as types in other scripts **must** have a `class_name` declaration. Missing `class_name` causes "Could not find type" parse errors at load time.
- After adding a new `class_name`, update `.godot/global_script_class_cache.cfg` manually if the Godot editor has not been opened — the headless runner uses the cached index and will not rescan.
- Dictionary values from `RollEngine.resolve()` are `Variant`. Always annotate locals explicitly or cast with `as int` / `as Array`.

## Design references

- **Game rules** — entry point with reading order, section list, and current canonical design decisions:
  [docs/game-rules/index.md](docs/game-rules/index.md)
  _(Load specific rule files on demand; the rules summary table below covers 90% of coding needs.)_
- **Game style** — 2D turn-based dark fantasy duel RPG. Hand-drawn or dark-fantasy pixel art.
  UI should feel like a tangible RPG document. Tone: tense, strategic, rewarding.
  Full vision: [docs/game-style/style-concept.md](docs/game-style/style-concept.md)
- **Project status** — what is implemented, what is next, ordered roadmap:
  consult this before proposing any new implementation to ensure suggestions
  align with the current development phase and do not skip planned dependencies.
  [docs/project-status.md](docs/project-status.md)
  @./docs/project-status.md
- **Project index** — auto-generated code map: all GDScript files, resource schemas, data files,
  scenes, and their dependencies. Read this before scanning source files.
  @./docs/project-index.md

## Fragile areas — do not accidentally "fix" these

| Area | What looks wrong | Why it's correct |
|------|-----------------|-----------------|
| `_resolve_round*` in CombatManager | Called without `await` from `player_chose_*` | Intentional coroutine pattern — runs cooperatively on main thread, yields at the timer |
| `global_script_class_cache.cfg` | May be stale after adding a new `class_name` | Must be updated manually when Godot editor hasn't been opened — headless runner uses the cached index |
| `EquipmentData` flat fields (`potency`, `flat_attack_bonus`, etc.) | Still present on the resource | Deprecated shims — superseded by `action_modifiers`. Retained for backwards-compat with old `.tres` files; ignored at runtime when `action_modifiers` is non-empty |
| Per-pool guard state in `CombatantState` | Three separate guard/rolled pairs | Intentional; cumulative Disadvantage on second+ pool pressure is deferred to a future group (see project-status.md Future section) |
| `debug_set_player_weapon` on `CombatManager` | Public method with "debug" in name on a production autoload | Used by `DebugWeaponSelector`; safe because it's null-guarded at the call site |
| `_process_statuses_hook` with potential `await` | Adds latency to the round loop | Required for future statuses that need player input |
| `CombatStatus` with no methods | Nearly empty resource | Intentional — logic lives in the dispatcher, not in the data |
| `_apply_wounds` bypassing interrupts in some contexts | Appears to ignore the interrupt system | Intentional for self-damage (blood_channeling) and hex damage — documented in code |
| InterruptHandler priority 10/20 | Apparently arbitrary numbers | Mental Fortress (10) before MftG (20) — deliberate design order, do not change |
| `_end_of_round()` called without visible `await` | Looks like a blocking call | It is a coroutine, must be called with await — same rule as _resolve_round* |
| `_stat_size()` checks active_statuses before node_levels | Seems to give statuses higher priority than purchased nodes | Intentional — temporary overrides (e.g. Purple Hollow d12) must win over permanent progression |
| `_add_status` silently replaces duplicates | Looks like a bug swallower | Intentional — applying the same status twice refreshes it, not stacks it |
| `_process_statuses_hook` iterates `.duplicate()` of `active_statuses` | Unnecessary copy | Prevents array mutation during iteration if a future case adds/removes statuses mid-loop |
| Guard reset is in `_end_of_round()` not `_begin_round()` | Reset should happen at round start | Intentional — guards are 0 when `start_of_round` hooks fire, which is the correct state for status processing |
| `_resolve_interrupt` is awaited inside `_resolve_attack` | Adds an await point in the attack resolution | Intentional — interrupts may need player input; the await is the whole point |
| InterruptHandler charges live on the handler instance, not on `CombatantState` | Charge counting feels scattered | Intentional — each handler manages its own resource; multiple handlers with the same trigger have independent charges |
| Interrupt registration happens in `start_combat`, not on node purchase | Looks like late binding | Intentional — handlers are combat-scoped; charges reset every combat per design |
| `wounds_pending` reassigned inside the interrupt loop before being assigned to `wounds` | Looks like a refactor smell | Intentional — the interrupt loop modifies wound count only on the player-defender/massive path; the final `var wounds := wounds_pending` is always the applied count |
| `pending_guard_debuffs` is consumed and erased in `_resolve_attack` before the roll | Looks like state mutation during read | Intentional — debuffs are single-use; consuming before the roll guarantees they apply once and only once |
| `_current_round_player_breaches` lives on `CombatManager`, not `CombatantState` | Looks like scope confusion | Intentional — it is round-scoped, not combatant-scoped; resets every `_begin_round()` |
| `status_to_apply` is `.duplicate()`'d before adding in `_dispatch_spell_outcome_effect` | Looks like unnecessary copy | Intentional — each application must be independent; otherwise duration ticks would share state across enemies |
| `bonus_keep`/`bonus_flat` in `SpellOutcomeEffect` produce a `push_warning` at dispatch | Looks like a stub | Intentional — reserved for outcome-driven bonuses (e.g. Mind Detonation L2); the warning prevents silent misuse before Group D authors them |
| `SpellBonusEffect` with `spell_id` set matches OR-style with tag | Looks like permissive matching | Intentional — when `spell_id` is non-empty it is a name filter; when empty the existing tag-based matching applies; both being true simultaneously is harmless (summed once) |
| `"hit"/"breach"` in spell outcome dict can be false even when attack_total >= guard | Looks like a bug | Intentional — they mean "this spell caused the round's FIRST breach on its target_pool"; a spell hitting an already-breached pool yields false. Pure per-spell breach detection is deferred to Group B. |

## Game rules summary

The rules live in `docs/game-rules/`. The implementation must match them exactly. Key rules for the current prototype:

| Concept | Rule |
|---|---|
| Roll resolution | Build Pool → Roll → Keep → Flat → Outcome |
| Pool size | = Tier (T1=1 die, T2=2, T3=3, T4=4) |
| Die size | from stat field (`dominion_size`, `negation_size`, `ingenuity_size`) — face value int (4/6/8/10) |
| Keep | grade 0 → keep 1, grade 1 → keep 2, grade 2 → keep 3 |
| VT (Fast/Slow) | VT is a **static enemy property**. Only the **player's** action roll is compared to the enemy's VT. Player >= VT → Fast (acts first); Player < VT → Slow (enemy acts first). Enemy timing is implicit in VT — no roll. |
| Guard | rolled **once per round** when first pressured; subsequent same-round pressure reuses existing Guard without re-rolling; resets to 0 at round start |
| Breach | `attack_total >= guard` (reaching exactly 0 is a breach) |
| Wounds | 1 on breach; 2 if Massive: `(attack - guard) > defensive_size` |
| Defeat | `wounds >= max_wounds` |
| Cantrip | Ingenuity die, Tier pool, no Fervor die, no escalation, available during Burnout; granted via `node.spells` (Minor Studies: Arcane Bolt, Arcane Touch) (`SpellData.is_cantrip=true`) |
| True spell | Ingenuity + optional aspect dice + real Fervor die; granted by Spellcasting L1+ (Arcane Missile vs Stance, Arcane Mark vs Resolve); escalation = `primary_dice_maxed_count` (Ingenuity-tagged dice maxed pre-Keep, including discarded) `+ (1 if fervor_maxed)` |
| Fervor cap | = `ingenuity_size` die face; caster may act at cap; escalating **beyond** cap triggers Burnout |
| Burnout | Blocks true spells; cantrips unaffected; persists across combats. Cleared by Long Rest (also resets Fervor) or Recovery Scene (Burnout only). |
| Stat sizes | Base from `CombatantData`; upgraded by Core nodes (mechanic wired in Phase A of spell school feature) |
| Spellcasting L1-L3 | L1: grants Arcane Missile + Arcane Mark, unlocks Fervor. L2: all arcane Keep 2, Arcane Missile +1 flat, Arcane Mark breach → enemy Stance flat −2. L3: all arcane Keep 3, Arcane Missile +2 flat total, Arcane Mark breach also → enemy Stance keep −1 (Frattura Totale). |
| Tier advancement | Slot-budget model: **5 combat slots + 2 Flavor slots** per tier; spending both advances the tier and resets counters. **Core nodes cost 2 combat slots** (Training / Ability cost 1; Flavor costs 1 from the Flavor budget). `PlayerProgression.tier_combat_spent` / `tier_flavor_spent` are public vars. |
| Passive wounds | +1 Max Wounds at Tier 2, +1 at Tier 4 (cumulative +2). Applied at `start_combat()` via `_tier_wound_bonus(tier)`; base `.tres` files never mutated. |
| Player base Dominion | d4 (base in `player_default.tres`). `dom_core` L1→d6, L2→d8, L3→d10 via `_stat_size()`. |
| Physical keep grade | `_physical_keep_grade()` = max(`_training_keep_grade()`, `physical_keep` nodes). Applied to physical Strike only. |
| Brutal Trade | Toggle in RoundHUD (visible when `dom_brutal >= 1`): VT −5, Flat +5 on player physical attack. |
| Earthshatter | Post-keep Dominion die added to Stance physical attacks when `dom_earthshatter` is purchased. Passed as `post_keep_bonus_size` to `RollEngine.resolve()`. |
| Meat for the Grinder | Registered as an `InterruptHandler` (`handler_id="meat_for_the_grinder"`, `trigger="on_massive_wound"`, `priority=20`) at `start_combat()` via `_register_interrupt`. When a Massive Wound would hit the player, `_find_interrupts` fires the handler, which emits `player_massive_incoming` and awaits `_massive_decision_gate`; player can spend a charge → 1 Wound instead of 2. |
| Wounds Training | `dom_wounds` NodeLevelData entries (effect_type="training_wounds", effect_value=1 each) summed by `_wounds_node_bonus()` at `start_combat()`. |

Next unimplemented items: Group 6 remainder — Art pass (replace placeholder visuals with sprites/animations) and Sound (SFX for attack, guard break, wound, defeat).
