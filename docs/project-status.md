# Project Status

Tracks what is implemented and what remains. Updated after each feature ships.

---

## Implemented

### Core engine
- **RollEngine** (`autoloads/RollEngine.gd`) — stateless dice resolver.
  Build Pool → Roll → Keep → Flat → Outcome. Returns `Dictionary` with `dice`, `kept`, `total`, `pool_size`, `die_size`, `keep_count`, `flat`, `fervor_roll`, `fervor_maxed`, `ingenuity_maxed_count`.
  Optional params: `fervor_size` (additive post-Keep Fervor die), `aspect_stat_size` + `aspect_count` (mixed-pool spells: aspect dice + Ingenuity-tagged dice combined before Keep). `ingenuity_maxed_count` = count of Ingenuity-tagged dice that rolled their max (pre-keep).
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
  `CombatantState` fields: `data`, `current_wounds`, `max_wounds`, `unlocked_nodes`, `tier_override`, `is_defeated`, `fervor_size` (d4 base), `is_burned_out`, `has_minor_studies`, `has_spellcasting`, `known_spells: Array`, `known_cantrips: Array`.
  Helpers: `_effective_tier()`, `_training_keep_grade()`, `_attack_flat()`, `_guard_flat()`, `_escalate_fervor()`, `_stat_size(state, stat)` (reads base from `CombatantData`, upgraded by matching `stat_size_*` Core nodes).
  At `start_combat()`, player's `unlocked_nodes`, `tier_override`, magic flags, and known spell lists are read from `PlayerProgression`. Initial `fervor_changed` signal emitted before first round.
  Round loop: `_begin_round → player_chose_strike / _cantrip(spell) / _spell(spell) → _resolve_round_* → _resolve_attack × 2 → loop`.
  Escalation: `steps = ingenuity_maxed_count + (1 if fervor_maxed)` — multiple steps possible per cast.
  Signals: `fervor_changed(is_player, fervor_size, fervor_cap, is_burned_out)`, `player_magic_available(can_cantrip, can_cast_spell)`.
- **PlayerProgression** (`autoloads/PlayerProgression.gd`) — singleton owning Constellation state across scenes.
  `ALL_NODES` catalog, `unlocked_nodes: Array[NodeData]`, `available_points`.
  Methods: `can_unlock`, `unlock`, `is_unlocked`, `get_category_count`, `get_tier` (breadth check), `get_known_spells()` (non-cantrip SpellData from unlocked spell nodes), `get_known_cantrips()` (cantrip SpellData).

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
- `resources/data/player_default.tres` — Tier 1, d6 off/def, max wounds 3; equipped with Iron Sword. `starting_nodes` still present but overridden by `PlayerProgression` at combat init.
- `resources/data/nodes/training_keep_1.tres` — Training, keep grade 1 (wired).
- `resources/data/nodes/training_keep_2.tres` — Training, keep grade 2 (wired).
- `resources/data/nodes/core_dominion_1.tres` — Core, Dominion d8 (stat-size mechanic wired via `_stat_size()`).
- `resources/data/nodes/core_dominion_2.tres` — Core, Dominion d10; prereq: Dominion I.
- `resources/data/nodes/core_negation_1.tres` — Core, Negation d8.
- `resources/data/nodes/core_negation_2.tres` — Core, Negation d10; prereq: Negation I.
- `resources/data/nodes/core_ingenuity_1.tres` — Core, Ingenuity d8.
- `resources/data/nodes/core_ingenuity_2.tres` — Core, Ingenuity d10; prereq: Ingenuity I.
- `resources/data/nodes/ability_minor_studies.tres` — Ability, effect_type="minor_studies", gates cantrip button; carries `spells=[cantrip_spark, arcane_touch]`.
- `resources/data/nodes/ability_spellcasting.tres` — Ability, effect_type="spellcasting", gates true spell button; prerequisite: Minor Studies (wired).
- `resources/data/nodes/ability_arcane_bolt.tres` — Ability, effect_type="spell", spell=arcane_bolt (stub; will be replaced by school nodes in Phase B).
- `resources/data/nodes/ability_fireball.tres` — Ability, effect_type="spell", spell=fireball (stub; Phase B).
- `resources/data/nodes/ability_charm.tres` — Ability, effect_type="spell", spell=charm (stub; Phase B).
- `resources/data/nodes/ability_cantrip_spark.tres` — Ability, effect_type="spell", spell=cantrip_spark (stub; Phase B).
- `resources/data/spells/arcane_bolt.tres`, `charm.tres`, `cantrip_spark.tres` — SpellData files (stub/orphaned; no longer in ALL_NODES).
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
- `resources/data/nodes/ability_sure_footed.tres` — Ability, flavor node.
- `resources/data/nodes/flavor_warrior_oath.tres` — Flavor, flavor node.
- `resources/data/enemy_grunt.tres` — Tier 1, d6 off / d4 def, keep grade 0, VT 10, max wounds 2; equipped with Crude Club.
- `resources/data/player_default.tres` — dominion_size now d4 (upgraded to d6+ via dom_core).
- `resources/data/weapons/iron_sword.tres` — Potency 1, Forging I (+1 flat attack), tags ["Sharp"].
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

### UI (prototype-quality)
- **BattleScene** (`scenes/battle/`) — root scene wiring CombatManager signals to HUDs. "Constellation" button (top-right) navigates to ConstellationScene; extracts `_teardown_signals()` helper for safe scene transitions.
- **ConstellationScene** (`scenes/constellation/`) — standalone skill tree. 4-column layout (Core / Training / Ability / Flavor), node cards with unlock buttons, point budget, tier badge and progress line. Back button returns to BattleScene. Reads/writes `PlayerProgression`.
- **CombatantHUD** — name, wound slots, guard value per combatant. Player HUD shows Fervor row (d-size / cap + BURNOUT indicator).
- **RoundHUD** — round label, phase label, Strike / Cantrip / Spell buttons (magic buttons appear only when known spells/cantrips exist), scrollable BBCode combat log. Spell/Cantrip buttons open an in-code popup listing known spells; single-spell auto-cast skips popup.
- **Combatant** — placeholder visual (colored rect + name label).
- **Combat narrative** — BBCode-formatted log with attack rolls, speed check, breach/wound outcomes, and Massive highlights.

### Tooling
- `/ship` — Conventional Commit, pull --rebase, and push in one command.
- `/audit-docs` — deploy the `docs-alignment-auditor` agent to cross-check all docs against the codebase.
- `docs-alignment-auditor` agent (`.claude/agents/docs-alignment-auditor.md`) — reads all docs and code, reports misalignments with severity and proposed fixes.
- Headless validation: `"$GODOT" --headless --path "<project>" --quit-after 5`.
- `CLAUDE.md` — engine setup, Autonomous Feature Loop workflow, architecture, rules summary.

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
- [x] **Keep grade from Training nodes** — `CombatantData.starting_nodes: Array[NodeData]` loaded into `CombatantState.unlocked_nodes`. `CombatManager._training_keep_grade()` scans for `"training_keep"` nodes; `keep_grade` remains as fallback. Debug widget `DebugNodeSelector` lets you swap grades mid-combat.
- [x] **Constellation scene** — `ConstellationScene` (`scenes/constellation/`). 4-column node grid, point-spend unlock, tier badge. `PlayerProgression` autoload persists state across scenes.
- [x] **Tier advancement** — `PlayerProgression.get_tier()` breadth check (min nodes per category + 1). `CombatantState.tier_override` propagates tier into `_effective_tier()` at combat start.
- [x] **Node prerequisites** — `NodeData.prerequisite: NodeData` (optional). `PlayerProgression.can_unlock()` blocks purchase if the prerequisite is not yet unlocked. `training_keep_2.tres` requires `training_keep_1.tres`.
  *Deferred: point gains from rewards (Group 5 reward loop), stat size effects for Core/Ability nodes.*

### Group 4 — Magic system
- [x] **Fervor subsystem** — real Fervor die (d4 base, additive post-keep, cannot be discarded) rolled on true spells; escalates on max-roll (d4 → d6 → d8 → d10); cap = `ingenuity_size`; `fervor_changed` signal updates HUD. `RollEngine.resolve()` extended with optional `fervor_size` param.
  *Deferred: substitution dice, multiple real Fervor dice.*
- [x] **Burnout state** — triggered when escalation exceeds Ingenuity cap. Blocks true spells; cantrips unaffected. Fervor clamped at cap. Resets each combat (Long Rest / Recovery Scene persistence deferred to Group 5).
- [x] **Cantrips** — Named cantrip spells via `SpellData` (is_cantrip=true) gated by Minor Studies prerequisite. Spell selection popup in RoundHUD. `player_chose_cantrip(spell: SpellData)` action.
  *Deferred: cantrip count formula (known slots).*
- [x] **True spells** — `SpellData` resource with per-spell resolution: `aspect_stat`, `aspect_dice`, `target_pool`, `flat_bonus`. Mixed pools (aspect + Ingenuity dice). Escalation steps = Ingenuity-tagged dice that maxed + (1 if Fervor die maxed). Spell selection popup in RoundHUD. `player_chose_spell(spell: SpellData)`.
  Sample spells: Arcane Bolt (pure Ingenuity, stance), Fireball (Dominion×1 + Ingenuity, stance), Charm (pure Ingenuity, resolve), Cantrip Spark (cantrip, stance).
  `NodeData` gains `@export var spell: SpellData`. `PlayerProgression.get_known_spells()` / `get_known_cantrips()`. `RollEngine.resolve()` gains `aspect_stat_size` and `aspect_count` params; returns `ingenuity_maxed_count`.
  *Deferred: multiple real Fervor dice, Fervor persistence across combats (Group 5), cantrip count formula.*

### Group 4.5 — Spell school system

Two sequential phases; Phase A is prerequisite for Phase B.

**Phase A — Core stat nodes**
- [x] `NodeData.prerequisite: NodeData` → `prerequisites: Array[NodeData]` (compound prereqs, all existing `.tres` migrated).
- [x] Author remaining Core nodes: `core_dominion_2.tres` (d8→d10), `core_negation_1/2.tres`, `core_ingenuity_1/2.tres`.
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
- [ ] **Deferred to Group 4.8** — geometric triangle canvas with vertex-affiliation positioning; connection lines. Requires `node_id` and affiliation data from the NodeData schema refactor.

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
- [x] Add all 11 Dominion nodes to `PlayerProgression.ALL_NODES`.
- [x] Run `/refresh-index` after adding new `.tres` files.

**Phase C — Combat hook architecture (new mechanics)**
- [x] **Passive modifiers** (Core Dominion size via `_stat_size()`, Martial Arts keep grade via `_physical_keep_grade()`, Titan's Grip +1 flat on TwoHanded via `_node_weapon_bonus_sum()`, Brutal L3 keep +1 on TwoHanded via `_node_weapon_bonus_sum()`): all wired through CombatManager node-level helpers.
- [x] **Wounds node max_wounds integration**: `_wounds_node_bonus(state)` sums `training_wounds` entries; added to `start_combat()` formula alongside tier bonus.
- [x] **Martial Arts physical_keep**: `_physical_keep_grade(state)` scans `physical_keep` entries; passed as keep grade for physical Strike (distinct from `_training_keep_grade()`).
- [x] **Earthshatter** (post-Keep additive die): `post_keep_bonus_size` param added to `RollEngine.resolve()`; `CombatManager` passes Dominion die size when `dom_earthshatter` is at L1 and target_pool is "stance".
- [x] **Brutal L1** (VT trade): `CheckButton` toggle in `RoundHUD` (visible when `dom_brutal >= 1`); `get_brutal_trade()` polled by BattleScene; `player_chose_strike(brutal_trade: bool)` + `_resolve_round(brutal_trade)` apply VT −5 / Flat +5.
- [x] **Meat for the Grinder** (reactive charges): `stamina_degrade_charges` on `CombatantState`; `_resolve_attack()` converted to coroutine; `player_massive_incoming` signal + `_massive_decision_resolved` internal gate; RoundHUD `show_massive_prompt()` + `wound_degrade_chosen` signal; `player_chose_degrade_wound()` public method.
- [ ] *Deferred: Melee L2 (Space Domination) — add a stateful flag on `CombatantState` that grants Advantage on the player's next Stamina defense roll this combat; persists until triggered, then clears. (Group 5 infrastructure.)*
- [ ] *Deferred: Brutal L2 (Cleave) multi-enemy overflow — requires Group 5 enemy roster and multi-target resolution.*

### Group 5 — Full game loop
- [ ] **Hub scene** — safe zone; access to character sheet, rest, loadout.
- [ ] **Character sheet UI** — stats, wounds, constellation summary.
- [ ] **Rest / recovery** — Long Rest (remove Burnout + reset Fervor), Recovery Scene (remove Burnout only).
- [ ] **Enemy roster** — author 3+ enemy types per `docs/game-rules/appendices/enemy-guidelines.md`; vary VT, stat sizes, and action sets.
- [ ] **Reward loop** — XP gain, item drops, point allocation after duel.
- [ ] **Dungeon / encounter flow** — sequence of duels, progression between them.

### Group 6 — Polish
- [ ] **Art pass** — replace placeholder colored rects with actual sprites / animations.
- [ ] **Sound** — attack, guard break, wound, defeat SFX.
- [ ] **Save / load** — persist character state between sessions.
