# Project Status

Tracks what is implemented and what remains. Updated after each feature ships.

---

## Implemented

### Core engine
- **RollEngine** (`autoloads/RollEngine.gd`) — stateless dice resolver.
  Build Pool → Roll → Keep → Flat → Outcome. Returns `Dictionary` with `dice`, `kept`, `total`, `pool_size`, `die_size`, `keep_count`, `flat`, `fervor_roll`, `fervor_maxed`, `primary_dice_maxed_count`, `post_keep_bonus_roll`.
  Optional params: `fervor_size` (additive post-Keep Fervor die), `aspect_stat_size` + `aspect_count` (mixed-pool spells: aspect dice + Ingenuity-tagged dice combined before Keep). `primary_dice_maxed_count` = count of primary pool dice that rolled their max (pre-keep). `post_keep_bonus_roll` = result of the post-keep bonus die (Earthshatter).
  Helpers: `is_fast(total, vt)`, `is_massive(attack, guard, defensive_size)`.
- **CombatantData** (`resources/CombatantData.gd`) — immutable combatant config as a `.tres` Resource.
  Fields: `combatant_name`, `tier`, `dominion_size`, `negation_size`, `ingenuity_size`, `keep_grade`, `velocity_threshold`, `max_wounds`, `equipped_weapon`, `starting_nodes`.
  Both player and enemy `max_wounds` are configurable; player default = 3, enemy values vary per `.tres` file.
  `keep_grade` is a fallback default; `starting_nodes` provides data-driven Training nodes that override it at runtime.
- **EquipmentData** (`resources/EquipmentData.gd`) — immutable equipment config as a `.tres` Resource.
  Fields: `item_name`, `potency`, `flat_attack_bonus` (Forging), `flat_guard_bonus` (Warding), `max_wounds_bonus` (Fortitude), `pool_bonus` (Surge/Drain), `tags`.
  Referenced by `CombatantData.equipped_weapon`. All effects applied at combat init or roll time; `null` = no weapon (no penalty).
  *Deferred: Inefficiency rule (Potency → 1, Flat → 0 without training) — requires Group 3 nodes.*
- **CombatManager** (`autoloads/CombatManager.gd`) — 1v1 combat state machine.
  `CombatantState` fields: `data`, `current_wounds`, `max_wounds`, `is_defeated`, `node_levels: Dictionary` (NodeData → int), `tier_override`, `weapon_override`, `stamina_degrade_charges`, per-pool guard state (`stance_guard`, `resolve_guard`, `stamina_guard` + matching `_rolled` booleans), magic state (`fervor_size`, `is_burned_out`, `has_minor_studies`, `has_spellcasting`, `known_spells`, `known_cantrips`).
  Helpers: `_effective_tier()`, `_training_keep_grade()`, `_physical_keep_grade()`, `_attack_flat()`, `_guard_flat()`, `_escalate_fervor()`, `_stat_size(state, stat)`, `_node_effect_max()`, `_node_effect_sum()`, `_node_weapon_bonus_sum()`, `_wounds_node_bonus()`, `_meat_grinder_charges()`.
  At `start_combat()`, player's `node_levels`, `tier_override`, magic flags, and known spell lists are read from `PlayerProgression`. Initial `fervor_changed` signal emitted before first round.
  Round loop: `_begin_round → player_chose_strike / _cantrip(spell) / _spell(spell) → _resolve_round_* → _resolve_attack × 2 → loop`.
  Escalation: `steps = primary_dice_maxed_count + (1 if fervor_maxed)` — multiple steps possible per cast.
  Signals: `fervor_changed(is_player, fervor_size, fervor_cap, is_burned_out)`, `player_magic_available(can_cantrip, can_cast_spell)`, `player_massive_incoming(charges_left)`.
- **PlayerProgression** (`autoloads/PlayerProgression.gd`) — singleton owning Constellation state across scenes.
  `ALL_NODES` catalog (50 nodes), `node_levels: Dictionary` (NodeData → int), `available_points`, `tier_combat_spent`, `tier_flavor_spent`, `equipped_weapon: EquipmentData`, `AVAILABLE_WEAPONS` array.
  Methods: `can_upgrade`, `upgrade`, `get_level(node)`, `get_node_level_by_id(id)`, `get_category_count`, `get_tier`, `get_known_spells()`, `get_known_cantrips()`, `apply_long_rest()`, `apply_recovery()`, `grant_points(n)`, `set_weapon(w)`, `serialize() -> Dictionary`, `deserialize(data: Dictionary)`.
- **SaveManager** (`autoloads/SaveManager.gd`) — 3-slot JSON save/load at `user://saves/slot_{n}.json`.
  `active_slot: int` (0 = unset). Methods: `save(slot)`, `load(slot)`, `get_slot_meta(slot) -> Dictionary` (exists, tier, points, timestamp), `delete_slot(slot)`. Calls `PlayerProgression.serialize/deserialize` and `DungeonManager.serialize/deserialize`.

### Combat mechanics
- **Roll / Keep** — Tier-based pool, grade-based keep (0→1, 1→2, 2→3).
- **VT / initiative** — only the player's roll is compared to the enemy's static VT; Fast → player first, Slow → enemy first. Enemy timing is implicit in VT — no roll.
- **Active Guard** — Stance is rolled once per round when first pressured (`stance_rolled` flag on `CombatantState`). Subsequent same-round pressure reuses the existing Guard value without re-rolling. Guard resets to 0 and `stance_rolled` resets to `false` at round start.
  *Future: replace the boolean flag with a per-pool data structure tracking `{ guard: int, rolled: bool }` for each of Stance / Resolve / Stamina.*
- **Advantage / Disadvantage** — `net_advantage` parameter on `RollEngine.resolve()`. Positive = extra dice, negative = fewer dice. Net pool ≤ 0 triggers Desperation (roll 2d, keep worst). Applied to player attack only; enemy A/D deferred.
- **Multiple defense pools** — Stance (Negation), Resolve (Ingenuity), Stamina (Dominion) tracked independently per combatant via per-pool guard/rolled state in `CombatantState`. `guard_changed` signal carries pool name. `CombatantHUD` shows all 3 pools. Debug pool selector in `scenes/debug/` lets you target any pool mid-combat.
- **Breach** — `attack_total >= guard`.
- **Massive damage** — `(attack - guard) > defensive_size` → 2 Wounds instead of 1.
- **Wound tracking + Defeat** — `wounds >= max_wounds` (runtime field on `CombatantState`, includes Fortitude bonus).
- **Equipment effects** — Potency (Tier cap), Forging (flat attack +), Warding (flat guard +), Fortitude (max wounds +), Surge/Drain (pool ±). Applied via helpers in `CombatManager`; logged in combat narrative when non-zero. Tags stored for future skill prerequisites.

### Data
- `resources/data/player_default.tres` — Tier 1, dominion_size=4 (d4 base; upgraded via dom_core), negation_size=4, ingenuity_size=4, max wounds 3; equipped with Iron Sword. `starting_nodes` present but overridden by `PlayerProgression` at combat init.
- `resources/data/nodes/ability_minor_studies.tres` — Ability, effect_type="minor_studies", gates cantrip button; carries `spells=[cantrip_spark, arcane_touch]`.
- `resources/data/nodes/ability_spellcasting.tres` — Ability, effect_type="spellcasting", gates true spell button; prerequisite: Minor Studies (wired).
- `resources/data/spells/cantrip_spark.tres` — SpellData (orphaned; not in ALL_NODES; superseded by school node spells).
- `resources/data/spells/fireball.tres` — SpellData, tags=["fire"], used by Fire Magic III.
- `resources/data/spells/sparks.tres` — cantrip, fire tag, stance (Fire Magic I).
- `resources/data/spells/arcane_touch.tres` — cantrip, arcane tag, resolve (Minor Studies).
- `resources/data/spells/fire_orb.tres` — fire tag, stance (Fire Magic II).
- `resources/data/spells/wall_of_fire.tres` — fire tag, stance, dominion×1 (Fire Magic IV).
- `resources/data/spells/meteor.tres` — fire tag, stance, dominion×2 (Fire Magic IV).
- `resources/data/spells/arcane_missile.tres` — arcane tag, stance (Arcane I).
- `resources/data/spells/mind_spike.tres` — arcane tag, resolve (Arcane II).
- `resources/data/spells/void_bolt.tres` — arcane tag, stance, flat+2 (Arcane III).
- `resources/data/nodes/fire_magic_1.tres` — Ability, spells=[sparks], prereq=minor_studies.
- `resources/data/nodes/fire_magic_2.tres` — Ability, spells=[fire_orb], bonus fire pool+1, prereqs=fire_magic_1+spellcasting.
- `resources/data/nodes/fire_magic_3.tres` — Ability, spells=[fireball], prereq=fire_magic_2.
- `resources/data/nodes/fire_magic_4.tres` — Ability, spells=[wall_of_fire, meteor], bonus fire keep+1, prereq=fire_magic_3.
- `resources/data/nodes/arcane_1.tres` — Ability, spells=[arcane_missile], prereq=spellcasting.
- `resources/data/nodes/arcane_2.tres` — Ability, spells=[mind_spike], prereq=arcane_1.
- `resources/data/nodes/arcane_3.tres` — Ability, spells=[void_bolt], prereq=arcane_2.
- `resources/data/nodes/flavor_warrior_oath.tres` — Flavor, flavor node.
- `resources/data/enemy_grunt.tres` — Tier 1, d4 off / d4 def, keep grade 0, VT 10, max wounds 2; equipped with Crude Club.
- `resources/data/weapons/iron_sword.tres` — Potency 2, Forging I (+1 flat attack), tags ["Sharp"].
- `resources/data/weapons/crude_club.tres` — Potency 1, no bonuses, tags ["Blunt"].
- `resources/data/weapons/greatsword.tres` — Potency 2, Forging I (+1 flat attack), tags ["Sharp", "TwoHanded"].
- `resources/data/nodes/dominion/dom_core.tres` — Core, max_levels=3; stat_size_dominion d6/d8/d10.
- `resources/data/nodes/dominion/dom_wounds.tres` — Training, max_levels=3; training_wounds +1 per level (req dom_core L1/2/3).
- `resources/data/nodes/dominion/dom_martial_arts.tres` — Training, max_levels=2; physical_keep 1→2 (req dom_core L2).
- `resources/data/nodes/dominion/dom_melee.tres` — Ability, max_levels=2; weapon_flat+1 L1, space_domination L2 (deferred).
- `resources/data/nodes/dominion/dom_ranged.tres` — Ability, max_levels=2, stub.
- `resources/data/nodes/dominion/dom_dual_wield.tres` — Ability, max_levels=2, stub.
- `resources/data/nodes/dominion/dom_titans_grip.tres` — Ability, max_levels=2; weapon_flat+1 (TwoHanded) L1.
- `resources/data/nodes/dominion/dom_disarm.tres` — Ability, max_levels=2, stub.
- `resources/data/nodes/dominion/dom_brutal.tres` — Ability, max_levels=3; brutal_trade L1, cleave L2 (deferred), weapon_keep+1 TwoHanded L3.
- `resources/data/nodes/dominion/dom_meat_grinder.tres` — Ability, max_levels=2; meat_grinder 1/2 uses_per_combat.
- `resources/data/nodes/dominion/dom_earthshatter.tres` — Ability, max_levels=1; earthshatter (post-keep Dominion die on Stance attacks).
- `resources/data/nodes/negation/neg_core.tres` — Core, max_levels=3; stat_size_negation d6/d8/d10.
- `resources/data/nodes/ingenuity/ing_core.tres` — Core, max_levels=3; stat_size_ingenuity d6/d8/d10.

### UI (prototype-quality)
- **BattleScene** (`scenes/battle/`) — root scene wiring CombatManager signals to HUDs. "Constellation" button (top-right) navigates to ConstellationScene; `_teardown_signals()` helper for safe scene transitions. Auto-navigates to Hub 1.5 s after combat ends (win or defeat).
- **ConstellationScene** (`scenes/constellation/`) — standalone skill tree. Skills tab: flat geometric canvas with DOM/ING/NEG vertex triangle, `Line2D` connection lines (gold=met, grey=unmet), vertex-click expand/collapse for sub-trees, compact node cards with level pips and tooltip descriptions. Background/Traits tab: Flavor nodes. Tier + HP header, combat/flavor budget label. Back button returns to Hub. Reads/writes `PlayerProgression`.
- **CombatantHUD** — name, wound slots (grown dynamically to match max_wounds), guard value per combatant. Player HUD shows Fervor row (d-size / cap + BURNOUT indicator) and equipped weapon name.
- **RoundHUD** — round label, phase label, Strike / Cantrip / Spell buttons (magic buttons appear only when known spells/cantrips exist), scrollable BBCode combat log. Spell/Cantrip buttons open an in-code popup listing known spells; single-spell auto-cast skips popup.
- **Combatant** — placeholder visual (colored rect + name label).
- **Combat narrative** — BBCode-formatted log with attack rolls, speed check, breach/wound outcomes, and Massive highlights.

### Tooling
- `/ship` — Conventional Commit, pull --rebase, and push in one command.
- `/audit-docs` — deploy the `docs-alignment-auditor` agent to cross-check all docs against the codebase.
- `docs-alignment-auditor` agent (`.claude/agents/docs-alignment-auditor.md`) — reads all docs and code, reports misalignments with severity and proposed fixes.
- Headless validation: `"$GODOT" --headless --path "<project>" --quit-after 5`.
- `CLAUDE.md` — engine setup, Autonomous Feature Loop workflow, architecture, rules summary.
- **Global Debug Toggle** (`autoloads/DebugManager.gd`) — F12 toggles all debug UI widgets on/off at runtime. Hidden by default; a `[ DEBUG ]` label (22% opacity, bottom-right corner) confirms the toggle state. All six debug widgets (`DebugEquipmentDisplay`, `DebugFervorDisplay`, `DebugWeaponSelector`, `DebugAdvantageControl`, `DebugPoolSelector`, `DebugProgressionControl`) subscribe via `debug_mode_changed` signal.

---

## Roadmap

Ordered by dependency. Items within a group can be parallelized.

### Group 1 — Mechanics completions (no new systems)
- [x] **Advantage / Disadvantage** — pool modifier; cancels 1-for-1; net Disadvantage to 0 → Desperation (roll 2, keep worst). Debug UI in `scenes/debug/` (removable at release).
  *Integration point: tied to status effects and equipment traits; does not interact with Fervor dice.*
- [x] **Multiple defense pools** — Resolve (Ingenuity) and Stamina (Dominion) alongside the already-implemented Stance.
  *Deferred: cumulative Disadvantage on 2nd+ different pool per turn; mixed-threat enemy actions.*

### Group 2 — Equipment and effect system
- [x] **Equipment resource** — Potency cap, flat bonuses (Forging/Warding), Fortitude, Surge/Drain, tags.
  *Inefficiency rule (without training) deferred to Group 3. Channeling deferred to Group 4.*
- [x] **Effect Taxonomy integration** — Forging / Warding / Fortitude / Surge / Drain applied from item data.
  *Channeling (magical flat) deferred to Group 4. Potency/Diminishment (die-size steps) deferred.*

### Group 3 — Progression / Constellation
- [x] **Node resource** — `NodeData` (`resources/NodeData.gd`): `node_name`, `category`, `effect_type`, `effect_value`. Sample nodes: `training_keep_1.tres`, `training_keep_2.tres`.
- [x] **Keep grade from Training nodes** — `CombatantData.starting_nodes: Array[NodeData]` loaded into `CombatantState.unlocked_nodes`. `CombatManager._training_keep_grade()` scans for `"training_keep"` nodes; `keep_grade` remains as fallback. Debug widget `DebugProgressionControl` lets you inspect and modify progression state at runtime.
- [x] **Constellation scene** — `ConstellationScene` (`scenes/constellation/`). 4-column node grid, point-spend unlock, tier badge. `PlayerProgression` autoload persists state across scenes.
- [x] **Tier advancement** — `PlayerProgression.get_tier()` breadth check (min nodes per category + 1). `CombatantState.tier_override` propagates tier into `_effective_tier()` at combat start.
- [x] **Node prerequisites** — `NodeData.prerequisite: NodeData` (optional). `PlayerProgression.can_unlock()` blocks purchase if the prerequisite is not yet unlocked. `training_keep_2.tres` requires `training_keep_1.tres`. _(superseded by Group 4.8: `NodeLevelData.prerequisites: Array[Dictionary]` and `can_upgrade()`)_
  *Deferred: point gains from rewards (Group 5 reward loop), stat size effects for Core/Ability nodes.*

### Group 4 — Magic system
- [x] **Fervor subsystem** — real Fervor die (d4 base, additive post-keep, cannot be discarded) rolled on true spells; escalates on max-roll (d4 → d6 → d8 → d10); cap = `ingenuity_size`; `fervor_changed` signal updates HUD. `RollEngine.resolve()` extended with optional `fervor_size` param.
  *Deferred: substitution dice, multiple real Fervor dice.*
- [x] **Burnout state** — triggered when escalation exceeds Ingenuity cap. Blocks true spells; cantrips unaffected. Fervor clamped at cap. Resets each combat (Long Rest / Recovery Scene persistence deferred to Group 5).
- [x] **Cantrips** — Named cantrip spells via `SpellData` (is_cantrip=true) gated by Minor Studies prerequisite. Spell selection popup in RoundHUD. `player_chose_cantrip(spell: SpellData)` action.
  *Deferred: cantrip count formula (known slots).*
- [x] **True spells** — `SpellData` resource with per-spell resolution: `aspect_stat`, `aspect_dice`, `target_pool`, `flat_bonus`. Mixed pools (aspect + Ingenuity dice). Escalation steps = Ingenuity-tagged dice that maxed + (1 if Fervor die maxed). Spell selection popup in RoundHUD. `player_chose_spell(spell: SpellData)`.
  Sample spells: Arcane Bolt (pure Ingenuity, stance), Fireball (Dominion×1 + Ingenuity, stance), Charm (pure Ingenuity, resolve), Cantrip Spark (cantrip, stance).
  `NodeData` gains `@export var spell: SpellData`. `PlayerProgression.get_known_spells()` / `get_known_cantrips()`. `RollEngine.resolve()` gains `aspect_stat_size` and `aspect_count` params; returns `primary_dice_maxed_count`.
  *Deferred: multiple real Fervor dice, Fervor persistence across combats (Group 5), cantrip count formula.*

### Group 4.5 — Spell school system

Two sequential phases; Phase A is prerequisite for Phase B.

**Phase A — Core stat nodes**
- [x] `NodeData.prerequisite: NodeData` → `prerequisites: Array[NodeData]` (compound prereqs, all existing `.tres` migrated).
- [x] Author remaining Core nodes: `core_dominion_2.tres` (d8→d10), `core_negation_1/2.tres`, `core_ingenuity_1/2.tres` (later consolidated into multi-level `neg_core.tres` / `ing_core.tres` in Group 4.8).
- [x] `CombatManager`: compute effective stat sizes from unlocked Core nodes at `start_combat()`; `_stat_size(state, stat)` helper replaces direct `state.data.*_size` reads.
- [x] `PlayerProgression.can_unlock()`: check all entries in `prerequisites` array.

**Phase B — Spell schools**
- [x] New `SpellBonusEffect` resource: `tag: String`, `bonus_type: "pool"|"keep"`, `value: int`, `stat: String`.
- [x] `NodeData`: `spell → spells: Array[SpellData]`; add `bonus_effects: Array[SpellBonusEffect]`.
- [x] `SpellData`: add `tags: PackedStringArray`.
- [x] Remove 4 flat stub spell nodes; `ability_minor_studies.tres` gains `spells = [cantrip_spark, arcane_touch]`.
- [x] Author spell schools: Fire Magic I–IV (Sparks, Fire Orb, Fireball, Wall of Fire, Meteor; +1 pool bonus tier II, +1 keep bonus tier IV); Arcane I–III (Arcane Missile, Mind Spike, Void Bolt).
- [x] `PlayerProgression.get_known_spells/cantrips()`: scan `node.spells` array.
- [x] `CombatManager`: apply `bonus_effects` at spell resolution (tag-matched pool/keep bonuses).
- [x] Constellation UI: unchanged (tree visual deferred to Group 6).

### Group 4.6 — Constellation Tier Gating

- [x] Add `required_tier: int` to `NodeData` (`resources/NodeData.gd`); default 1.
- [x] Author `required_tier` values on all existing `.tres` node files: Core I / Training I / tier-1 Ability nodes → 1; Core II / Training II / Fire Magic II / Arcane II → 2; Fire Magic III / Arcane III → 3; Fire Magic IV → 4.
- [x] `PlayerProgression.can_unlock()`: add check `get_tier() >= node.required_tier`.
- [x] Constellation UI: show locked-by-tier nodes as visually dimmed with a tier badge.
- [x] Run `/refresh-index` after `NodeData` schema change.

### Group 4.7 — Progression Rules Redesign

Implements the new "5 Combat + 2 Flavor" tier advancement rule, passive wound bonuses, and the Triangle constellation UI. Depends on Group 4.6 (`required_tier` on `NodeData`) being complete first.

Three sequential implementation phases.

**Phase A — `PlayerProgression.gd` tier calculation refactor**
- [x] Add two runtime counters: `tier_combat_spent: int` and `tier_flavor_spent: int`, tracking slots spent in the **current** tier (reset to 0 on tier advance). Public vars; readable by ConstellationScene for budget display.
- [x] Rewrite `can_unlock(node)`:
  - Core nodes cost 2 combat slots (`_slot_cost()`); Training / Ability cost 1. Check: `tier_combat_spent + _slot_cost(node) <= 5`.
  - Flavor: `tier_flavor_spent < 2`.
  - Existing prerequisite and `required_tier` checks remain.
- [x] Rewrite `unlock(node)`: increment the matching counter by `_slot_cost(node)`. If both spent (≥5 combat + ≥2 flavor) and `_tier < 4`, advance `_tier` by 1 and reset both counters to 0.
- [x] `get_tier()` returns the stored `_tier` value rather than computing breadth dynamically.
- [x] `get_category_count()` is retained as-is for any UI display needs.
- [x] `available_points` plumbing is retained unchanged (Group 5 reward loop depends on it).
- [x] No `.tres` file changes required.

**Phase B — Passive Max Wounds injection in `CombatManager.gd`**
- [x] Add private helper `_tier_wound_bonus(tier: int) -> int`:
  - Returns `(1 if tier >= 2 else 0) + (1 if tier >= 4 else 0)`.
- [x] At `start_combat()`, `_player.max_wounds += _tier_wound_bonus(_player.tier_override)` immediately after `CombatantState.init()` sets the base value.
  - `_player_tier` = `PlayerProgression.get_tier()` read once at combat init.
  - Enemy `max_wounds` is unaffected; enemy tier is not player-progression-driven.
  - Base `.tres` files (e.g. `player_default.tres`) are **never mutated**.
- [x] Emit `wounds_changed` signal after updating `max_wounds` so the HUD reflects the new cap immediately.

**Phase C — `ConstellationScene` UI restructure (multi-level cards + tab separation)**
- [x] Node cards rewritten as composable components: level pips (`○` / `●`), `L0/1` level counter, "Upgrade" button (was "Unlock"), slot cost shown in button label ("Upgrade (2 slots)" for Core).
- [x] "Upgrade" button disabled when `level >= max_level` or prerequisites / tier / budget gate. All current nodes are max_level = 1.
- [x] Tier + HP display widget added to header (`TierHPLabel`): reads `PlayerProgression.get_tier()` and player base max wounds + tier bonus. Refreshes on every `_refresh()` call.
- [x] Budget display label (`BudgetLabel`) replaces old breadth-based ProgressLabel. Shows `"Combat: X/5 · Flavor: Y/2  (fill both to reach Tier N)"`.
- [x] **"Background / Traits"** tab added via `TabContainer`: Flavor nodes moved there, not visible on the Skills tab.
- [x] Locked-by-tier nodes remain visually dimmed (from Group 4.6 Phase A); no logic change required.
  *Triangle canvas (vertex-affiliation positioning + connection lines) → moved to Group 6 Polish.*

### Group 4.8 — Dominion Physical Tree (Multi-Level Node Refactor)

Implements the Dominion ("Meat Tank") skill tree and introduces the **Multi-Level Node** data model, which replaces the current one-`.tres`-per-level-up approach. Depends on Group 4.6 Phase A (`required_tier` on `NodeData`) and Group 4.7 Phase A (tier counter in `PlayerProgression`) being complete first.

Four sequential implementation phases.

**Phase A — `NodeData.gd` schema refactor (Nested Resource Architecture)**

Per-level data is consolidated into a single `NodeLevelData` sub-resource. `NodeData` holds only level-agnostic identity data. This eliminates the need for separate `NodeEffect` and `NodeLevelReq` resource files and keeps the Godot Inspector usable without custom tooling. Full schema mandate in `docs/game-rules/progression/constellation.md`.

- [x] **Author `NodeLevelData` resource** (`resources/NodeLevelData.gd`): `level_index: int`, `cost: int`, `required_tier: int`, `prerequisites: Array[Dictionary]` (each entry: `{"node_id": String, "required_level": int}`), `level_effect_description: String`. Mechanical effect payload fields (`effect_type: String`, `effect_value: int`, `stat: String`, `weapon_tags: PackedStringArray`, `uses_per_combat: int`) and spell/bonus-effect data (`spells: Array[SpellData]`, `bonus_effects: Array[SpellBonusEffect]`) belong here — not on the root.
- [x] **Refactor `NodeData.gd`**: rename `node_name` → `display_name`, `description` → `base_description`; add `node_id: String`, `icon: Texture2D`, `max_levels: int` (default 1); replace `prerequisites: Array[NodeData]`, `effect_type`, `effect_value`, `unlock_cost`, `spells`, and `bonus_effects` with `levels_data: Array[NodeLevelData]`. Retain `category: String` unchanged.
- [x] **Refactor `PlayerProgression`**: replace `unlocked_nodes: Array[NodeData]` with `node_levels: Dictionary` (`NodeData → int`). Update `can_unlock` → `can_upgrade`, `unlock` → `upgrade`, `is_unlocked` → `get_level(node) > 0`.
- [x] **Atomic rename** — the method rename above must be a single commit that simultaneously updates all callers: `CombatManager.gd`, `ConstellationScene.gd`, and `BattleScene.gd`. Do not split across multiple commits or phases.
- [x] Migrate ALL existing `.tres` node files to the new schema: populate `levels_data` with one `NodeLevelData` entry each (all current nodes have `max_levels = 1`); move `effect_type`, `effect_value`, `unlock_cost`, `spells`, and `bonus_effects` values into that entry.
- [x] Run `/refresh-index` after schema changes.

**Phase B — Author Dominion tree data (11 `.tres` files)**

Create under `resources/data/nodes/dominion/`:

| File | `max_levels` | Key `prerequisites` (per `NodeLevelData` entry) |
|------|-------------|--------------------------|
| `dom_core.tres` | 3 | — |
| `dom_martial_arts.tres` | 2 | dom_core L2 |
| `dom_melee.tres` | 2 | dom_martial_arts L1 |
| `dom_ranged.tres` | 2 | dom_martial_arts L1 |
| `dom_dual_wield.tres` | 2 | dom_melee L1 |
| `dom_titans_grip.tres` | 2 | dom_melee L1 |
| `dom_disarm.tres` | 2 | dom_melee L1 |
| `dom_brutal.tres` | 3 | dom_titans_grip L1 |
| `dom_wounds.tres` | 3 | L1: dom_core L1 · L2: dom_core L2 + dom_wounds L1 · L3: dom_core L3 + dom_wounds L2 |
| `dom_meat_grinder.tres` | 2 | dom_wounds L2 |
| `dom_earthshatter.tres` | 1 | dom_brutal L3 |

- [x] Change base Dominion stat from d6 → d4 in `player_default.tres`. **Confirmed design decision.** Core Dominion L1 brings it to d6, L2 to d8, L3 to d10.
- [x] Remove `resources/data/nodes/core_dominion_1.tres` and `core_dominion_2.tres` from `PlayerProgression.ALL_NODES` when adding `dom_core.tres`; delete both old `.tres` files to prevent duplicate stat-size bonuses.
- [x] Migrate Negation and Ingenuity Core nodes to multi-level format (`neg_core.tres` / `ing_core.tres`, max_levels=3 each, under `resources/data/nodes/negation/` and `resources/data/nodes/ingenuity/`); remove old `core_negation_1/2.tres` and `core_ingenuity_1/2.tres` from `ALL_NODES`.
- [x] Add all 11 Dominion nodes to `PlayerProgression.ALL_NODES`.
- [x] Run `/refresh-index` after adding new `.tres` files.

**Phase C — Combat hook architecture (new mechanics)**
- [x] **Passive modifiers** (Core Dominion size via `_stat_size()`, Martial Arts keep grade via `_physical_keep_grade()`, Titan's Grip +1 flat on TwoHanded via `_node_weapon_bonus_sum()`, Brutal L3 keep +1 on TwoHanded via `_node_weapon_bonus_sum()`): all wired through CombatManager node-level helpers.
- [x] **Wounds node max_wounds integration**: `_wounds_node_bonus(state)` sums `training_wounds` entries; added to `start_combat()` formula alongside tier bonus.
- [x] **Martial Arts physical_keep**: `_physical_keep_grade(state)` scans `physical_keep` entries; passed as keep grade for physical Strike (distinct from `_training_keep_grade()`).
- [x] **Earthshatter** (post-Keep additive die): `post_keep_bonus_size` param added to `RollEngine.resolve()`; `CombatManager` passes Dominion die size when `dom_earthshatter` is at L1 and target_pool is "stance".
- [x] **Brutal L1** (VT trade): `CheckButton` toggle in `RoundHUD` (visible when `dom_brutal >= 1`); `get_brutal_trade()` polled by BattleScene; `player_chose_strike(brutal_trade: bool)` + `_resolve_round(brutal_trade)` apply VT −5 / Flat +5.
- [x] **Meat for the Grinder** (reactive charges): `stamina_degrade_charges` on `CombatantState`; `_resolve_attack()` converted to coroutine; `player_massive_incoming` signal + `_massive_decision_resolved` internal gate; RoundHUD `show_massive_prompt()` + `wound_degrade_chosen` signal; `player_chose_degrade_wound()` public method.
  *Space Domination (Melee L2) → moved to Group 5.5. Brutal L2 Cleave → moved to Future (needs design decision).*

### Group 5 — Full game loop
- [x] **Hub scene** (`scenes/hub/HubScene.gd/.tscn`) — main entry point; shows Tier, HP, Fervor, stats, run status; Long Rest / Recovery / Constellation / Continue / Start New Run buttons. Weapon selector row lets the player equip Iron Sword or Greatsword before a run; active weapon highlighted, persists via `PlayerProgression.equipped_weapon`. BattleScene and CombatantHUD read and display the equipped weapon. 3-slot save UI with Save/Load buttons; slot metadata (Tier, Points, date) shown; auto-saves on return from dungeon when `SaveManager.active_slot > 0`.
- [x] **Character sheet UI** — integrated into Hub (Tier, HP, Dominion/Negation/Ingenuity die sizes, run progress, known spell counts).
- [x] **Rest / recovery** — `PlayerProgression.apply_long_rest()` (reset Fervor to d4 + clear Burnout) and `apply_recovery()` (clear Burnout only). Fervor now persists via `saved_fervor_size` / `saved_is_burned_out` fields on PlayerProgression; written by `CombatManager._end_combat()`, read by `start_combat()`.
- [x] **Enemy roster** — Grunt (existing Minion) + `enemy_soldier.tres` (Standard: d6/d6, VT 12, 3 wounds) + `enemy_knight.tres` (Elite: d8/d8, VT 15, 4 wounds, keep 1).
- [x] **Reward loop** — `DungeonManager.on_victory()` calls `PlayerProgression.grant_points(1)` per kill. Starting `available_points = 3`.
- [x] **Dungeon / encounter flow** — `DungeonManager` autoload: `start_run()`, `current_enemies()`, `on_victory()` / `on_defeat()`, `has_next_enemy()`, `was_last_fight_chained()`. 3-level nested `ENCOUNTERS[encounter][wave][enemy]` structure: (1) Grunt, (2) Grunt→Grunt, (3) Grunt+Grunt, (4) Soldier, (5) Grunt→Grunt+Soldier, (6) Grunt×3, (7) Grunt+Soldier→Soldier+Soldier, (8) Knight. `->` = chained wave (no campfire stop, wounds carry over); `+` = parallel enemies in the same fight. BattleScene shows "Another enemy approaches…" on a chain and reloads; goes to Campfire after a complete encounter; goes to MainMenu on run complete.

### Group 5.5 — Mechanics completion (deferred from 4.8)

Small, self-contained items that were deferred during Group 4.8 and have no remaining blockers.

- [x] **Space Domination** (Melee L2) — `space_domination_active: bool` on `CombatantState`; when `dom_melee` L2 is purchased, grants Advantage on the player's next Stamina guard roll each combat; flag cleared once triggered. Wired in `CombatManager.start_combat()` / `_resolve_attack()`.

### Group 6 — Polish
- [x] **Save / load** — `SaveManager` autoload; 3 JSON slot files at `user://saves/slot_{n}.json`; Hub save/load UI; auto-save on return from dungeon. `PlayerProgression.serialize/deserialize`, `DungeonManager.serialize/deserialize`.
- [x] **Constellation triangle canvas** — flat geometric canvas replacing 4-column layout; DOM/ING/NEG vertex positioning; `Line2D` connection lines (gold=met, grey=unmet); vertex-click expand/collapse for sub-trees; compact node cards with tooltip descriptions.
- [x] **UI theme** — `res://theme/dark_fantasy.tres`; dark purple panels, styled button states, warm parchment text, gold accents. Applied globally via `project.godot gui/theme/custom`.
- [ ] **Art architecture pass** — pixel-perfect rendering foundation before any assets are created.
  - [ ] `project.godot`: base resolution 640×360, `stretch/mode=viewport`, `aspect=keep`, `default_texture_filter=0` (Nearest).
  - [ ] `BattleScene.tscn/.gd`: root Control → Node2D; split into `WorldLayer` (Node2D, holds combatant sprites + `Marker2D` spawn anchors: PlayerAnchor bottom-right, EnemyAnchor1/2/3 top-left) and `UILayer` (CanvasLayer layer=1, holds all HUDs). Enemy spawning split: visuals → WorldLayer at anchor positions, HUDs → `EnemiesHUDContainer` in UILayer.
  - [ ] `Combatant.tscn/.gd`: root Control → Node2D; add `AnimatedSprite2D` (invisible until `SpriteFrames` assigned); keep `ColorRect Body` as dev placeholder (auto-hidden when frames present); add public animation stub API — `play_idle()`, `play_attack_melee()`, `play_cast_spell()`, `play_hurt()`, `play_die()` (silent no-ops until art ships); `flip_h = is_player` in `setup()`.
- [ ] **Art pass** — replace placeholder colored rects with actual sprites / animations. Depends on art architecture pass above.
- [ ] **Sound** — attack, guard break, wound, defeat SFX.

### Group 6.5 — Out-of-Combat Flow Redesign

Splits the monolithic `HubScene` into a **MainMenuScene** (title screen) and a **CampfireScene**
(between-encounter rest hub). Adds Short Rest / Long Rest wound healing and an ambush risk system
on Long Rest driven by a hidden `luck` stat. Four sequential implementation phases.

**Phase A — `PlayerProgression.gd` + `DungeonManager.gd` (parallel)**

`PlayerProgression.gd`:
- [ ] Add `luck: int = 0` — hidden stat; adjusts Long Rest ambush probability in pct-points (positive = less likely to be ambushed). Serialized.
- [ ] Add `apply_short_rest() -> void`: `saved_wounds = max(0, saved_wounds - 1)`; step `saved_fervor_size` down one notch in `[4,6,8,10]` track (min d4); `saved_is_burned_out = false`.
- [ ] Modify `apply_long_rest() -> void`: add `saved_wounds = 0` (full heal) before existing Fervor reset. Ambush roll lives in DungeonManager, not here.
- [ ] Update `serialize()` / `deserialize()` to include `luck`.

`DungeonManager.gd`:
- [ ] Add `short_rest_used: bool = false` — per-run flag; reset by `start_run()`.
- [ ] Add `ambush_net_advantage: int = 0` — net advantage modifier applied to all player strikes in the next combat after an ambush; cleared by `on_victory()` and `on_defeat()`.
- [ ] Add `attempt_short_rest() -> void`: guard on `short_rest_used`; call `PlayerProgression.apply_short_rest()`; set `short_rest_used = true`.
- [ ] Add `attempt_long_rest() -> Dictionary`: call `PlayerProgression.apply_long_rest()`; roll `var ambushed := (randi() % 100) < (50 - PlayerProgression.luck)`; if ambushed set `ambush_net_advantage = -2`; stub comment `# TODO: deduct money when money system is implemented`; return `{"ambushed": ambushed}`.
- [ ] `start_run()`: also reset `short_rest_used = false`, `ambush_net_advantage = 0`.
- [ ] `on_victory()` / `on_defeat()`: also clear `ambush_net_advantage = 0`.
- [ ] Update `serialize()` / `deserialize()` to include `short_rest_used`, `ambush_net_advantage`.

**Phase B — New scenes (sequential after Phase A)**

Create `scenes/main_menu/MainMenuScene.gd` + `.tscn`:
- [ ] Title header "◆ KRONOMANIA ◆".
- [ ] **New Game** button → `PlayerProgression.reset()`, `DungeonManager.start_run()`, navigate to `BattleScene`.
- [ ] **Load Game** section — 3 slots with metadata + Load button each; after load navigate to `CampfireScene` if `DungeonManager.run_active`, else refresh.
- [ ] **Settings** placeholder button (disabled, "coming soon").
- [ ] **Quit** button → `get_tree().quit()`.
- [ ] Manual save: 3-slot Save/Load UI (moved from HubScene; sole manual save point).

Create `scenes/campfire/CampfireScene.gd` + `.tscn`:
- [ ] Guard in `_ready()`: if `not DungeonManager.run_active`, redirect to MainMenuScene.
- [ ] Auto-save on `_ready()`: `if SaveManager.active_slot > 0: SaveManager.save(active_slot)`.
- [ ] Header "◆ CAMPFIRE ◆"; character status row (`Wounds: X/Y | Fervor: dN [BURNOUT]`); run progress row (`Encounter X/Y`).
- [ ] Equipment selector (same weapon-button row as HubScene).
- [ ] **Consumables stub block** — comment `# --- CONSUMABLES (deferred) ---` + placeholder Label "No consumables."
- [ ] **Short Rest** button: disabled + "(used)" label when `DungeonManager.short_rest_used`. On press: `DungeonManager.attempt_short_rest()`, refresh.
- [ ] **Long Rest** button: always available. On press: call `DungeonManager.attempt_long_rest()`; show "Rested safely." or "⚠ Ambushed! Next fight: Disadvantage." feedback; refresh status.
- [ ] **Constellation** button → navigate to `ConstellationScene`.
- [ ] **Continue** button (shows ambush warning label when `DungeonManager.ambush_net_advantage != 0`) → navigate to `BattleScene`.
- [ ] **Give Up** button → `DungeonManager.on_defeat()`, navigate to `MainMenuScene`.

**Phase C — Wire up callers (sequential after Phase B)**

`scenes/battle/BattleScene.gd`:
- [ ] Store `_ambush_base_disadvantage: int = DungeonManager.ambush_net_advantage` in `_ready()`.
- [ ] Add `_ambush_base_disadvantage` to `net_advantage` in every `player_chose_strike()` call.
- [ ] Post-combat navigation: victory + `has_next_enemy()` → CampfireScene; victory + run complete → MainMenuScene; defeat → MainMenuScene.

`scenes/constellation/ConstellationScene.gd`:
- [ ] Back button: navigate to CampfireScene if `DungeonManager.run_active`, else MainMenuScene.

`project.godot`:
- [ ] Change `run/main_scene` to `"res://scenes/main_menu/MainMenuScene.tscn"`.

**Phase D — Cleanup + validation**
- [ ] Delete `scenes/hub/HubScene.gd` and `scenes/hub/HubScene.tscn`.
- [ ] Run headless validation; confirm zero SCRIPT ERRORs.
- [ ] Run `/refresh-index` (new `.gd` files added, old ones deleted).

Navigation map (post-implementation):
```
MainMenuScene ──New Game──────────────────────────────► BattleScene
              └─Load (run_active)───────────────────────► CampfireScene
BattleScene ───Victory + has_next──────────────────────► CampfireScene
            ├──Victory + run complete──────────────────► MainMenuScene
            └──Defeat──────────────────────────────────► MainMenuScene
CampfireScene ─Continue────────────────────────────────► BattleScene
              ├─Constellation─────────────────────────► ConstellationScene
              └─Give Up───────────────────────────────► MainMenuScene
ConstellationScene ─Back (run_active)──────────────────► CampfireScene
                   └─Back (not active)─────────────────► MainMenuScene
```

Deferred stubs: consumable items (comment block in CampfireScene), money deduction on ambush (comment in `attempt_long_rest()`), skill-point loss on ambush (not implemented), ambush as a true extra encounter (future design decision).

### Future — Undesigned or blocked items

- **Brutal L2 Cleave** — multi-enemy overflow after a breach. Group 5 roster exists (3 enemies), but Cleave needs a design decision on overflow mechanics (does excess damage carry over? to which target? in what order?) before implementation.
- **Negation and Ingenuity subtrees** — `neg_core.tres` and `ing_core.tres` exist as Core-only nodes. Training and ability nodes (analogues to the Dominion tree) are not yet designed or roadmapped.
- **Cantrip count formula** — currently all known cantrips are always available; a future "known slots" cap is deferred.
- **Inefficiency rule** — Potency → 1 / Flat → 0 without matching Training node. Deferred since Group 2.
- **Cumulative Disadvantage** — second+ different pool targeted in the same turn should stack Disadvantage. Deferred since Group 1.
- **Hybrid node proportional positioning** — nodes that depend on two different stat trees should be placed on the constellation canvas at a position proportional to their dependency tiers. Example: a node requiring Dominion Tier 3 and Negation Tier 1 sits 3× closer to the Dominion vertex than the Negation vertex (weighted barycentric interpolation between the two vertices using the required tier values as weights). Blocked on: Negation and Ingenuity subtrees being designed.
