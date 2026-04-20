# Project Status

Tracks what is implemented and what remains. Updated after each feature ships.

---

## Implemented

### Core engine
- **RollEngine** (`autoloads/RollEngine.gd`) — stateless dice resolver.
  Build Pool → Roll → Keep → Flat → Outcome. Returns `Dictionary` with `dice`, `kept`, `total`, `pool_size`, `die_size`, `keep_count`, `flat`.
  Includes `flat` post-Keep numeric bonus parameter (wired; populated from equipment bonuses).
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
  `CombatantState` fields: `data`, `current_wounds`, `max_wounds`, `unlocked_nodes`, `tier_override`, `is_defeated`.
  Helpers: `_effective_tier()` (tier_override → data.tier → Potency cap), `_training_keep_grade()`, `_attack_flat()`, `_guard_flat()`.
  At `start_combat()`, player's `unlocked_nodes` and `tier_override` are read from `PlayerProgression`.
  Round loop: `_begin_round → player_chose_strike → _resolve_round → _resolve_attack × 2 → loop`.
- **PlayerProgression** (`autoloads/PlayerProgression.gd`) — singleton owning Constellation state across scenes.
  `ALL_NODES` catalog, `unlocked_nodes: Array[NodeData]`, `available_points`.
  Methods: `can_unlock`, `unlock`, `is_unlocked`, `get_category_count`, `get_tier` (breadth check).

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
- `resources/data/nodes/core_dominion_1.tres` — Core, Dominion stat size (authored; mechanic deferred).
- `resources/data/nodes/ability_sure_footed.tres` — Ability, flavor node.
- `resources/data/nodes/flavor_warrior_oath.tres` — Flavor, flavor node.
- `resources/data/enemy_grunt.tres` — Tier 1, d6 off / d4 def, keep grade 0, VT 10, max wounds 2; equipped with Crude Club.
- `resources/data/weapons/iron_sword.tres` — Potency 1, Forging I (+1 flat attack), tags ["Sharp"].
- `resources/data/weapons/crude_club.tres` — Potency 1, no bonuses, tags ["Blunt"].

### UI (prototype-quality)
- **BattleScene** (`scenes/battle/`) — root scene wiring CombatManager signals to HUDs. "Constellation" button (top-right) navigates to ConstellationScene; extracts `_teardown_signals()` helper for safe scene transitions.
- **ConstellationScene** (`scenes/constellation/`) — standalone skill tree. 4-column layout (Core / Training / Ability / Flavor), node cards with unlock buttons, point budget, tier badge and progress line. Back button returns to BattleScene. Reads/writes `PlayerProgression`.
- **CombatantHUD** — name, wound slots, guard value per combatant.
- **RoundHUD** — round label, phase label, Strike button, scrollable BBCode combat log.
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
- [ ] **Fervor subsystem** — real Fervor dice (additive post-keep, cannot be discarded), substitution dice (normal pool, Fervor-tagged), escalation per max roll, cap = current modified Ingenuity.
- [ ] **Burnout state** — triggered after a spell resolves if Fervor would exceed the Ingenuity cap. Blocks true spells; cantrips unaffected. Removed by Long Rest or Recovery Scene.
  *Applied post-resolution, not mid-cast. Does not block the spell that caused it.*
- [ ] **Cantrips** — Minor Studies unlock, known cantrip count formula, no Fervor cost, available during Burnout.
- [ ] **True spells** — Spellcasting node required; full spell resolution order (see cheat sheet).

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
