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
Deploy a sub-agent: run headless (see Engine section), check for SCRIPT ERRORs and ERRORs (UID WARNINGs are safe), verify `@onready` paths, signal connections, and `class_name` registrations in `.godot/global_script_class_cache.cfg`.

### 4. Fix Loop
If validation fails:
- Fix the specific error reported.
- Re-run validation.
- Repeat until the headless run is clean.

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

## Project structure

```
autoloads/          # RollEngine (dice), CombatManager (combat SM), PlayerProgression (constellation), DungeonManager (run state), SaveManager (save/load), DebugManager (debug toggle)
resources/          # Resource class definitions (.gd) + data/ (.tres files) — see project-index.md
scenes/hub/         # HubScene (main entry, rest/recovery, run navigation)
scenes/battle/      # BattleScene (1v1 combat), CombatantHUD, RoundHUD, Combatant
scenes/constellation/  # ConstellationScene (skill tree)
scenes/debug/       # Debug widgets — removable at release; never imported by production code directly
scripts/            # gen_project_index.py — regenerates docs/project-index.md
docs/game-rules/    # Design source of truth — navigation TOC at index.md; load files on demand
docs/               # project-status.md (roadmap), project-index.md (generated code map)
.claude/            # agents/docs-alignment-auditor.md, commands/audit-docs.md + refresh-index.md
```

## Architecture

### One-way data flow

`CombatantData` (`.tres` resource) → `CombatManager` → signals → `BattleScene` → HUD nodes.

`CombatantData` is **immutable config** only. All runtime state lives inside `CombatManager.CombatantState`, an inner class instantiated per combat. Scene nodes hold no game state.

`CombatantState` fields: `data` (CombatantData), `current_wounds`, `max_wounds`, `is_defeated`, `node_levels: Dictionary` (NodeData → int), `tier_override`, `weapon_override`, `stamina_degrade_charges` (Meat for the Grinder charges), `space_domination_active: bool`, `item_action_charges: Dictionary` (action_key → remaining uses; initialized at `start_combat()` from `ActionModifier`s with `rest_type="combat"`), plus per-pool guard state (`stance_guard`, `resolve_guard`, `stamina_guard`, and matching `_rolled` booleans), plus magic state (`fervor_size`, `is_burned_out`, `has_minor_studies`, `has_spellcasting`, `known_spells: Array`, `known_cantrips: Array`). Methods: `init()`, `reset_guard()`, `get_guard(pool)`, `set_guard_val(pool, value)`, `is_pool_rolled(pool)`, `set_pool_rolled(pool, value)`.

### Autoload singletons

Signatures and signals are in `docs/project-index.md`. Architectural gotchas:
- **`RollEngine`** — stateless. Returns `Dictionary`; always cast values with `as int` / `as Array` — the type inferencer cannot infer through `Dictionary`. `resolve()` accepts optional `fervor_size` (additive post-Keep Fervor die), `aspect_stat_size` and `aspect_count` (for mixed-pool spells), `post_keep_bonus_size` (additive post-Keep bonus die, e.g. Earthshatter). Returns `primary_dice_maxed_count` (Fervor escalation) and `post_keep_bonus_roll` (Earthshatter die result).
- **`CombatManager`** — all output via signals; nothing returned. Disconnect all signals before `reload_current_scene()`. Signals: `fervor_changed(is_player, fervor_size, fervor_cap, is_burned_out)`, `player_magic_available(can_cantrip, can_cast_spell)`, `player_massive_incoming(charges_left)`. Public methods: `start_combat(player_data: CombatantData, enemies_data: Array)`, `player_chose_strike(net_advantage, target_pool, brutal_trade, target_index: int = 0)`, `player_chose_cantrip(spell: SpellData, target_index: int = 0)`, `player_chose_spell(spell: SpellData, target_index: int = 0)`, `player_chose_degrade_wound(use_charge: bool)`, `reset_item_charges(rest_type: String)` (called by DungeonManager on rest), `debug_set_fervor(size, burned_out)`. Key helpers: `_get_action_modifier(state, action_key) → ActionModifier` (weapon → bare_hands → zero stub), `_effective_tier(state, mod: ActionModifier = null)` (mod.tier_cap=0 = uncapped), `_attack_flat()` / `_guard_flat()` / `_pool_bonus()` all delegate to `_get_action_modifier`.
- **`PlayerProgression`** — constellation state; read by `CombatManager` at `start_combat()`. `ALL_NODES` catalog (now includes 11 Dominion nodes; old core_dominion_1/2 replaced by dom_core). `get_known_spells()` and `get_known_cantrips()` iterate all purchased `node_levels`, collect from `levels_data[0..level-1].spells`. `get_node_level_by_id(id)` looks up a node by string ID and returns its current level (0 if absent). **Fervor persistence** (Group 5): `saved_fervor_size` / `saved_is_burned_out` / `saved_wounds` fields written by `CombatManager._end_combat()`, read by `start_combat()` (`saved_wounds` carries wounds between chained encounters). `combat_prefs: CombatPreferences` — persisted action defaults and mode flags; instantiated fresh in `reset()`, serialized/deserialized with save data. Methods: `reset()`, `apply_long_rest()` (reset fervor + clear burnout), `apply_recovery()` (clear burnout only), `grant_points(n)`, `set_weapon(w)`, `debug_set_points(n)`, `debug_set_tier(t)`.
- **`DungeonManager`** — run state: `start_run()`, `current_enemies() → Array`, `on_victory()` (grants 1 point + advances index), `on_defeat()`, `has_next_enemy()`, `is_run_complete()`, `was_last_fight_chained()`, `enemies_cleared()`, `enemies_total()`. Hard-coded 8-encounter sequence: Grunt→Grunt→Soldier (chained, return to Hub after Soldier), Grunt→Grunt→Soldier (chained), Grunt+Grunt+Soldier (parallel), Knight (solo).

### Round loop (CombatManager)

```
_begin_round()
  → resets all three guard pools to 0 (stance, resolve, stamina) for player and all enemies
  → emits player_magic_available(can_cantrip, can_cast_spell)
  → emits player_action_required
  → (player presses Strike / Cantrip / Spell → BattleScene calls player_chose_strike / _cantrip / _spell)
  → _resolve_round / _resolve_round_cantrip / _resolve_round_spell
  → rolls both attacks, VT check, _resolve_attack() × 2
  → [spell only] _escalate_fervor(steps) where steps = primary_dice_maxed_count + (1 if fervor_maxed)
  → await 0.8s timer
  → _begin_round()  ← loops until defeat
```

`_resolve_round*` are GDScript coroutines (use `await`). Calling them without `await` from the `player_chose_*` methods is intentional — they run cooperatively on the main thread, yielding at the timer. `_resolve_attack()` is also a coroutine (conditionally awaits `_massive_decision_resolved` for Meat for the Grinder); all `_resolve_round*` calls to it use `await`.

### Magic system

Group 4 implements Fervor / Burnout / Cantrips / True Spells with per-spell `SpellData`:

- **Fervor** — player-only runtime state on `CombatantState`. Track: d4 → d6 → d8 → d10 (`FERVOR_TRACK` const). Cap = `data.ingenuity_size`. Persists across combats via `PlayerProgression.saved_fervor_size`; Long Rest resets to d4, Recovery Scene only clears Burnout.
- **Escalation** — after a true spell resolves, `_escalate_fervor(_player, steps)` where `steps = primary_dice_maxed_count + (1 if fervor_maxed)`. Multiple steps possible in a single cast.
- **Burnout** — blocks `player_chose_spell()`; cantrips remain available. Persists across combats; cleared by Long Rest or Recovery.
- **Cantrip** — uses `SpellData` (is_cantrip=true). Ingenuity pool, no Fervor die, no escalation. Available during Burnout. Granted via `node.spells` (Minor Studies carries cantrip_spark + arcane_touch; Fire Magic I carries Sparks).
- **True spell** — uses `SpellData`. Ingenuity pool + optional aspect dice + real Fervor die. Granted by spell school nodes (Fire Magic II–IV, Arcane I–III).

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

**Phase B — Spell schools (implemented):**
- `SpellBonusEffect` resource (`resources/SpellBonusEffect.gd`): `tag: String`, `bonus_type: "pool"|"keep"`, `value: int`, `stat: String`.
- School nodes Fire Magic I–IV and Arcane I–III grant spells via `levels_data[0].spells`. Fire Magic II adds fire pool +1, Fire Magic IV adds fire keep +1 via `bonus_effects` on the `NodeLevelData`.
- `CombatManager._resolve_round_spell()` sums matching `bonus_effects` from all purchased `node_levels → levels_data` entries.

**Multi-level Node Schema (implemented — Group 4.8 Phase A):**
- `NodeData` fields: `node_id: String`, `display_name: String`, `category: String`, `base_description: String`, `icon: Texture2D`, `max_levels: int`, `levels_data: Array[NodeLevelData]`.
- `NodeLevelData` fields: `level_index`, `cost`, `required_tier`, `prerequisites: Array` (untyped, `[{node_id: String, required_level: int}]`), `level_effect_description`, `effect_type`, `effect_value`, `stat`, `weapon_tags: PackedStringArray`, `uses_per_combat`, `spells: Array[SpellData]`, `bonus_effects: Array[SpellBonusEffect]`.
- `PlayerProgression.node_levels: Dictionary` (NodeData → int); methods: `can_upgrade(node)`, `upgrade(node)`, `get_level(node)`, `get_node_level_by_id(id)`.
- `CombatManager` helpers: `_node_effect_max(state, key)`, `_node_effect_sum(state, key)`, `_node_weapon_bonus_sum(state, key)`, `_has_effect_type(state, key)`, `_physical_keep_grade(state)`, `_wounds_node_bonus(state)`, `_meat_grinder_charges(state)`.

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
| Cantrip | Ingenuity die, Tier pool, no Fervor die, no escalation, available during Burnout; spell granted by Minor Studies or school nodes (`SpellData.is_cantrip=true`) |
| True spell | Ingenuity + optional aspect dice + real Fervor die; spell granted by school node; escalation = `primary_dice_maxed_count + (1 if fervor_maxed)` |
| Fervor cap | = `ingenuity_size` die face; caster may act at cap; escalating **beyond** cap triggers Burnout |
| Burnout | Blocks true spells; cantrips unaffected; persists across combats. Cleared by Long Rest (also resets Fervor) or Recovery Scene (Burnout only). |
| Stat sizes | Base from `CombatantData`; upgraded by Core nodes (mechanic wired in Phase A of spell school feature) |
| Spell schools | Fire Magic I–IV + Arcane I–III; `SpellBonusEffect` pool/keep bonuses applied at spell resolution (implemented) |
| Tier advancement | Slot-budget model: **5 combat slots + 2 Flavor slots** per tier; spending both advances the tier and resets counters. **Core nodes cost 2 combat slots** (Training / Ability cost 1; Flavor costs 1 from the Flavor budget). `PlayerProgression.tier_combat_spent` / `tier_flavor_spent` are public vars. |
| Passive wounds | +1 Max Wounds at Tier 2, +1 at Tier 4 (cumulative +2). Applied at `start_combat()` via `_tier_wound_bonus(tier)`; base `.tres` files never mutated. |
| Player base Dominion | d4 (base in `player_default.tres`). `dom_core` L1→d6, L2→d8, L3→d10 via `_stat_size()`. |
| Physical keep grade | `_physical_keep_grade()` = max(`_training_keep_grade()`, `physical_keep` nodes). Applied to physical Strike only. |
| Brutal Trade | Toggle in RoundHUD (visible when `dom_brutal >= 1`): VT −5, Flat +5 on player physical attack. |
| Earthshatter | Post-keep Dominion die added to Stance physical attacks when `dom_earthshatter` is purchased. Passed as `post_keep_bonus_size` to `RollEngine.resolve()`. |
| Meat for the Grinder | `stamina_degrade_charges` on `CombatantState` (from `dom_meat_grinder`). When Massive Wound would hit player, `player_massive_incoming` emitted; RoundHUD shows prompt; player can spend charge → 1 Wound instead of 2. |
| Wounds Training | `dom_wounds` NodeLevelData entries (effect_type="training_wounds", effect_value=1 each) summed by `_wounds_node_bonus()` at `start_combat()`. |

Next unimplemented items: Group 6 remainder — Art pass (replace placeholder visuals with sprites/animations) and Sound (SFX for attack, guard break, wound, defeat).
