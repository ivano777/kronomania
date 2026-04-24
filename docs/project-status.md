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
- `resources/data/weapons/iron_sword.tres` — Potency 1, Forging I (+1 flat attack), tags ["Sharp"].
- `resources/data/weapons/crude_club.tres` — Potency 1, no bonuses, tags ["Blunt"].

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

### Group 4.5 — Spell school system (next)

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

### Group 4.6 — Constellation Tier Gating + Per-Tier Slot Budget

Two sequential phases.

**Phase A — Node tier gate**
- [ ] Add `required_tier: int` to `NodeData` (`resources/NodeData.gd`); default 1.
- [ ] Author `required_tier` values on all existing `.tres` node files: Core I / Training I / tier-1 Ability nodes → 1; Core II / Training II / Fire Magic II / Arcane II → 2; Fire Magic III / Arcane III → 3; Fire Magic IV → 4.
- [ ] `PlayerProgression.can_unlock()`: add check `get_tier() >= node.required_tier`.
- [ ] Constellation UI: show locked-by-tier nodes as visually dimmed with a tier badge.
- [ ] Run `/refresh-index` after `NodeData` schema change.

**Phase B — Per-tier slot budget**
- [ ] Confirm slot budget values with user before implementing (proposed: T1: 3 slots, T2: 2 slots, T3: 2 slots, T4: 1 slot).
- [ ] `PlayerProgression`: replace or supplement `available_points` with `tier_slots_remaining: int` that resets per tier from the budget; spending a node costs 1 slot.
- [ ] `can_unlock()`: also check `tier_slots_remaining > 0`.
- [ ] Constellation UI: show "X picks remaining this tier" counter.
- [ ] Tie slot grants into Group 5 reward loop (slot granted on tier advancement from XP/reward flow).

*Deferred: mutually exclusive node choices within a tier (requires `exclusive_group` on NodeData — Group 6+).*

### Group 4.7 — Progression Rules Redesign

Implements the new "5 Combat + 2 Flavor" tier advancement rule, passive wound bonuses, and the Triangle constellation UI. Depends on Group 4.6 Phase A (`required_tier` on `NodeData`) being complete first. Group 4.6 Phase B (per-tier slot budget) is **superseded** by this group and should not be implemented.

Three sequential implementation phases.

**Phase A — `PlayerProgression.gd` tier calculation refactor**
- [ ] Add two runtime counters: `_tier_combat_spent: int` and `_tier_flavor_spent: int`, tracking slots spent in the **current** tier (reset to 0 on tier advance).
- [ ] Rewrite `can_unlock(node)`:
  - If node.category in ["Core", "Training", "Ability"]: check `_tier_combat_spent < 5`.
  - If node.category == "Flavor": check `_tier_flavor_spent < 2`.
  - Existing prerequisite and `required_tier` checks remain.
- [ ] Rewrite `unlock(node)`: increment the matching counter. If `_tier_combat_spent >= 5 AND _tier_flavor_spent >= 2` and `_tier < 4`, advance `_tier` by 1 and reset both counters to 0.
- [ ] `get_tier()` returns the stored `_tier` value rather than computing breadth dynamically.
- [ ] `get_category_count()` is retained as-is for any UI display needs.
- [ ] `available_points` plumbing is retained unchanged (Group 5 reward loop depends on it).
- [ ] No `.tres` file changes required.

**Phase B — Passive Max Wounds injection in `CombatManager.gd`**
- [ ] Add private helper `_tier_wound_bonus(tier: int) -> int`:
  - Returns `(1 if tier >= 2 else 0) + (1 if tier >= 4 else 0)`.
- [ ] At `start_combat()`, compute `_player.max_wounds = data.max_wounds + equipment_bonus + _tier_wound_bonus(_player_tier)`.
  - `_player_tier` = `PlayerProgression.get_tier()` read once at combat init.
  - Enemy `max_wounds` is unaffected; enemy tier is not player-progression-driven.
  - Base `.tres` files (e.g. `player_default.tres`) are **never mutated**.
- [ ] Emit `wounds_changed` signal after updating `max_wounds` so the HUD reflects the new cap immediately.

**Phase C — `ConstellationScene` UI restructure (triangle + multi-level cards — single combined pass)**
- [ ] Replace 4-column grid layout with a triangular canvas.
  - Each node card's screen position is derived from its vertex affiliation (Dominion / Negation / Ingenuity) and distance from center.
  - Core nodes sit at the three vertices.
  - Edge nodes (hybrid paths between two stats) interpolate between two vertex positions.
  - Training and Ability nodes fill the interior, grouped by dominant stat.
- [ ] Node cards must be authored as **composable components** with built-in multi-level support from the start (level pips `●●○`, level counter, Upgrade button). This avoids a second rewrite when Group 4.8 data ships.
- [ ] "Unlock" button becomes "Upgrade"; disabled when `level >= max_level` or prerequisites unmet.
- [ ] Connection lines light up progressively as source node level meets the dependent node's required level.
- [ ] Add a central non-interactive **Tier + HP display widget** overlaid at the triangle center:
  - Reads `PlayerProgression.get_tier()` and player wounds on scene open.
  - Refreshes on `PlayerProgression.unlock()` (connect a local callback).
  - No game-state ownership — display only.
- [ ] Add a **"Background / Traits"** tab hosting all Flavor-category nodes:
  - Implemented as a separate tab (TabContainer or equivalent) entirely distinct from the triangle canvas.
  - Flavor nodes are not visible on the triangle.
- [ ] Locked-by-tier nodes remain visually dimmed (from Group 4.6 Phase A); no logic change required.
- [ ] Run `/refresh-index` only if any new `@export` field is added to `NodeData` during this work.

### Group 4.8 — Dominion Physical Tree (Multi-Level Node Refactor)

Implements the Dominion ("Meat Tank") skill tree and introduces the **Multi-Level Node** data model, which replaces the current one-`.tres`-per-level-up approach. Depends on Group 4.6 Phase A (`required_tier` on `NodeData`) and Group 4.7 Phase A (tier counter in `PlayerProgression`) being complete first.

Four sequential implementation phases.

**Phase A — `NodeData.gd` schema refactor**
- [ ] Add `max_level: int` to `NodeData` (default 1 — all existing nodes remain valid without changes).
- [ ] Author `NodeEffect` resource (`resources/NodeEffect.gd`): `effect_type: String`, `effect_value: int`, `stat: String`, `weapon_tags: PackedStringArray`, `uses_per_combat: int` (0 = passive/unlimited).
- [ ] Author `NodeLevelReq` resource (`resources/NodeLevelReq.gd`): `node: NodeData`, `required_level: int`.
- [ ] Replace `NodeData.effects_per_level: Array[NodeEffect]` (one entry per level, index 0 = L1 effect).
- [ ] Replace `NodeData.prerequisites: Array[NodeData]` → `level_prerequisites: Array[NodeLevelReq]`.
- [ ] Refactor `PlayerProgression`: replace `unlocked_nodes: Array[NodeData]` with `node_levels: Dictionary` (`NodeData → int`). Update `can_unlock` → `can_upgrade`, `unlock` → `upgrade`, `is_unlocked` → `get_level(node) > 0`.
- [ ] **Atomic rename** — the method rename above must be a single commit that simultaneously updates all callers: `CombatManager.gd`, `ConstellationScene.gd`, and `BattleScene.gd`. Do not split across multiple commits or phases.
- [ ] Migrate ALL existing `.tres` node files to include `effects_per_level: Array[NodeEffect]` entries. The old `effect_type`/`effect_value` fields may be retained during transition but are deprecated in favor of `NodeEffect` entries.
- [ ] Run `/refresh-index` after schema changes.

**Phase B — `ConstellationScene.gd` multi-level node cards**
*(Merged into Group 4.7 Phase C — multi-level card support is built in that single combined UI pass. No separate implementation needed here.)*

**Phase C — Author Dominion tree data (11 `.tres` files)**

Create under `resources/data/nodes/dominion/`:

| File | `max_level` | Key `level_prerequisites` |
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

- [ ] Change base Dominion stat from d6 → d4 in `player_default.tres`. **Confirmed design decision.** Core Dominion L1 brings it to d6, L2 to d8, L3 to d10.
- [ ] Remove `resources/data/nodes/core_dominion_1.tres` and `core_dominion_2.tres` from `PlayerProgression.ALL_NODES` when adding `dom_core.tres`; delete both old `.tres` files to prevent duplicate stat-size bonuses.
- [ ] Add all 11 Dominion nodes to `PlayerProgression.ALL_NODES`.
- [ ] Run `/refresh-index` after adding new `.tres` files.

**Phase D — Combat hook architecture (new mechanics)**
- [ ] **Passive modifiers** (Core Dominion size, Martial Arts keep grade, Titan's Grip Forging I on 2H, Brutal L3 keep +1 on 2H): extend `CombatManager` helpers to read `node_levels` and sum `NodeEffect` entries — mirrors existing `_stat_size()` / `_training_keep_grade()` pattern.
- [ ] **Wounds node max_wounds integration**: add `_wounds_node_bonus(state: CombatantState) -> int` helper (scan `node_levels` for `dom_wounds`, sum `effect_value` per unlocked level). Extend the `start_combat()` formula: `_player.max_wounds = data.max_wounds + equipment_bonus + _tier_wound_bonus(_player_tier) + _wounds_node_bonus(_player)`. Each `NodeEffect` entry in `dom_wounds.tres` must carry `effect_type="training_wounds"` and `effect_value=1`.
- [ ] **Martial Arts physical_keep**: add `_physical_keep_grade(state: CombatantState) -> int` helper scanning for `effect_type="physical_keep"` nodes; pass result as the keep grade for physical attack rolls only (distinct from `_training_keep_grade()` which applies to all rolls). The `dom_martial_arts.tres` `NodeEffect` entries must use `effect_type="physical_keep"`.
- [ ] **Earthshatter** (post-Keep additive die): add optional `post_keep_bonus_size: int` param to `RollEngine.resolve()`, parallel to `fervor_size`. `CombatManager` passes current stable Dominion size when player has `dom_earthshatter` at L1. Applies to Stance-pool and melee physical attacks only.
- [ ] **Brutal L1** (VT trade): add a toggle in `RoundHUD` visible when `dom_brutal >= 1`; passes `brutal_trade: bool` into `player_chose_strike()`. `CombatManager` applies −5 to the VT check and +5 Flat to that attack's resolution.
- [ ] **Meat for the Grinder** (reactive charges): add `stamina_degrade_charges: int` to `CombatantState` (set from `dom_meat_grinder` level at `start_combat()`). When `_resolve_attack()` would apply Massive Damage to the player and charges > 0, emit `player_massive_incoming()`. `RoundHUD` prompts the player to spend a charge and degrade to 1 Wound.
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
