# Project Status

Tracks what is implemented and what remains. Updated after each feature ships.

---

## Implemented

### Core systems
- **RollEngine** — stateless dice resolver: Pool → Roll → Keep → Flat. Optional `fervor_size`, `aspect_stat_size`/`aspect_count`, `post_keep_bonus_size`. Returns `primary_dice_maxed_count`, `post_keep_bonus_roll`. Helpers: `is_fast()`, `is_massive()`.
- **CombatManager** — 1v1 state machine. `CombatantState` tracks wounds, per-pool guard, magic state, item charges. Round loop: `_begin_round → player_chose_* → _resolve_round_* → _resolve_attack × 2 → loop`. Node-level helpers for stat sizes, keep grades, flat bonuses.
- **PlayerProgression** — constellation state singleton. `node_levels: Dictionary`, tier/budget counters, equipped weapon, Fervor/Burnout persistence (`saved_fervor_size` / `saved_is_burned_out` / `saved_wounds`), spell lists. Serialize/deserialize for save system.
- **DungeonManager** — run state. 8-encounter sequence (chained waves `→`, parallel `+`). Short/long rest attempts, ambush system, serialize/deserialize.
- **SaveManager** — 3-slot JSON at `user://saves/slot_{n}.json`. Slot metadata (tier, points, date). Auto-save on campfire entry.

### Data (key files)
- **Player**: `player_default.tres` (Tier 1, all d4 base, Iron Sword, bare_hands stub)
- **Enemies**: `enemy_grunt.tres` (T1, d4/d4, VT 10, 2 wounds), `enemy_soldier.tres` (T1, d6/d6, VT 12, 3 wounds), `enemy_knight.tres` (T2, d8/d8, VT 15, 4 wounds, keep 1)
- **Weapons**: `iron_sword.tres` (tier_cap=2, flat+1, Sharp), `crude_club.tres` (tier_cap=1, Blunt), `greatsword.tres` (tier_cap=2, flat+1, Sharp+TwoHanded)
- **Nodes (50 total)**: Dominion tree (`dom_core/wounds/martial_arts/melee/ranged/dual_wield/titans_grip/disarm/brutal/meat_grinder/earthshatter`); `neg_core`, `ing_core` (multi-level, 3 levels each); pool-guard training nodes (`neg_stance`, `dom_stamina`, `ing_resolve`); spell schools (`fire_magic_1–4`, `arcane_1–3`); ability nodes (`minor_studies`, `spellcasting`); flavor nodes (`warrior_oath` + 15 under `flavors/`)
- **Spells**: cantrips — `sparks`, `arcane_touch`; true spells — `fire_orb`, `fireball`, `wall_of_fire`, `meteor`, `arcane_missile`, `mind_spike`, `void_bolt`

### UI
- **BattleScene** — `WorldLayer` (Node2D, combatant sprites/anchors) + `UILayer` (CanvasLayer, HUDs). `AnimatedSprite2D` stubs with ColorRect fallback.
- **CampfireScene** — Short/Long Rest, weapon selector, Constellation nav, ambush feedback, Give Up.
- **MainMenuScene** — title, New Game, 3-slot save/load, Quit.
- **ConstellationScene** — triangle canvas (DOM/ING/NEG vertices), `Line2D` connections, expand/collapse sub-trees, level pips, budget label, Background/Traits tab.
- **CombatantHUD** — wounds, per-pool guard, Fervor row (player only).
- **RoundHUD** — round/phase labels, action buttons, BBCode combat log, Brutal Trade toggle, Meat for the Grinder prompt.

### Tooling
- `/ship`, `/audit-docs`, headless validation, `docs-alignment-auditor` agent, `DebugManager` (F12 toggle, 6 debug widgets).
- Theme: `res://theme/dark_fantasy.tres` — dark purple panels, parchment text, gold accents.

---

## Roadmap

Ordered by dependency. Items within a group can be parallelized.

### ✓ Group 1 — Mechanics completions
Advantage/Disadvantage (`net_advantage` on `RollEngine`; net ≤ 0 → Desperation). Multiple defense pools (Stance/Resolve/Stamina tracked independently per combatant).

### ✓ Group 2 — Equipment and effect system
`EquipmentData` with Potency/Forging/Warding/Fortitude/Surge/Drain. All effects applied at combat init/roll time via helpers in CombatManager.

### ✓ Group 3 — Progression / Constellation
`NodeData` resource + Training keep-grade nodes. `ConstellationScene` + `PlayerProgression` autoload. Tier advancement + node prerequisites. *(Schema superseded by Group 4.8.)*

### ✓ Group 4 — Magic system
Fervor (d4→d6→d8→d10, cap = ingenuity_size, escalates on max-roll) + Burnout (blocks true spells). Cantrips (`SpellData.is_cantrip=true`, Minor Studies gated) + True spells (aspect dice + Fervor die, mixed pools, per-spell escalation).

### ✓ Group 4.5 — Spell school system
Core stat nodes with compound prereqs + `_stat_size()` helper. `SpellBonusEffect` resource; Fire Magic I–IV + Arcane I–III spell schools; tag-matched bonuses applied at spell resolution.

### ✓ Group 4.6 — Constellation Tier Gating
`required_tier` on `NodeData`. Tier check in `can_upgrade()`. Dimmed locked-by-tier nodes in Constellation UI.

### ✓ Group 4.7 — Progression Rules Redesign
"5 Combat + 2 Flavor" tier budget (Core = 2 slots; `tier_combat_spent`/`tier_flavor_spent`). Passive max wounds from tier (+1 at T2, +1 at T4). Constellation UI: level pips, "Upgrade" button with slot cost, budget label, Background/Traits tab.

### ✓ Group 4.8 — Dominion Physical Tree (Multi-Level Node Refactor)
`NodeLevelData` sub-resource; `NodeData` refactored (node_id, max_levels, levels_data). `node_levels: Dictionary` in `PlayerProgression`. 11 Dominion nodes authored. Combat hooks: Earthshatter (post-keep Dominion die on Stance), Brutal L1 (VT −5/Flat +5 trade), Meat for the Grinder (reactive Massive mitigation charges), Martial Arts keep grade, Titan's Grip/Brutal L3 flat bonuses.

### ✓ Group 5 — Full game loop
Hub scene (rest/recovery/weapon selector/save). Enemy roster (Grunt/Soldier/Knight). Reward loop (1 point per kill, 3 starting points). DungeonManager: 8-encounter sequence with chained waves (`→`) and parallel enemies (`+`).

### ✓ Group 5.5 — Mechanics completion
Space Domination (Melee L2): once-per-combat Advantage on player's next Stamina guard roll.

### ✓ Group A — Foundational Architecture (prerequisite for Ingenuity branch)

Four architectural systems that extend CombatManager without breaking existing
behaviour. A1–A3 are implemented. A4 remains pending before Group B can start.

**Phase A1 — CombatStatus and active_statuses** ✓
New resource `CombatStatus` (data only, zero logic). `CombatantState` gains
`active_statuses: Array[CombatStatus]`. Helpers on CombatManager:
`_add_status`, `_remove_status`, `_has_status`, `_get_status`,
`_tick_statuses`. `_stat_size()` updated to read stat_overrides from active
statuses before node-level values.

**Phase A2 — Phased round loop with hooks** ✓
The flat round loop becomes explicit phases: START_OF_ROUND →
PLAYER_ACTION → ON_BREACH → END_OF_ROUND. New coroutine `_end_of_round()`;
guard reset moved there so guards are already 0 when start_of_round hooks fire.
New method `_process_statuses_hook(hook, state, context)` — dispatches on
`status_id` via match block; iterates `.duplicate()` for mutation safety.
No match cases active yet — combat behaviour is identical to pre-A2.

**Phase A3 — Generalised InterruptHandler** ✓
New resource `InterruptHandler` (data only). `CombatantState` gains
`interrupt_handlers: Array[InterruptHandler]`. The hardcoded Meat for the
Grinder pattern is migrated: registered via `_register_interrupt()` at
`start_combat()`, fired by `_find_interrupts()` + `await _resolve_interrupt()`
inside `_resolve_attack()`. Behaviour identical to pre-A3, now extensible.

**Phase A4 — SpellOutcomeEffect** ⏳
New resource `SpellOutcomeEffect` describing post-resolution spell effects
(flat/keep debuffs, conditional bonuses, status application).
`NodeLevelData` gains `outcome_effects: Array[SpellOutcomeEffect]`.
`SpellBonusEffect` gains optional field `spell_id: String`.
Processing in `_resolve_round_spell()` via dedicated helper
`_apply_spell_outcome_effects()`.

---

### ⏳ Group B — Ingenuity Branch: Core and Spellcasting
Prerequisites: Group A complete.

Full rewrite of the Ingenuity branch. Minor Studies rewritten with new
cantrips (arcane_bolt, aether_barrier stub, chrono_shift stub).
Spellcasting node L1-L3: caster engine, injects Arcane Missile and Arcane
Mark, adds progressive Keep and SpellOutcomeEffects for spell upgrades.
Mental Fortress migrated from Dominion to Ingenuity as a generalised
InterruptHandler.

**Note:** aether_barrier and chrono_shift are created as stub .tres files
with no special effects. Their full design must be written in
docs/game-rules/ before functional implementation.

---

### ⏳ Group C — Ingenuity Branch: Disciplines
Prerequisites: Group B complete.

Four specialised disciplines using all Group A systems:
- Mind Detonation (delayed effect via CombatStatus, explosion at
  start_of_round)
- Chrono-Tinkering (skip next guard roll on a specific pool)
- Echoing Mind (spells with tag "echo" hit again at end_of_round)
- Hex Mastery (persistent CombatStatus: +1 wound on every player breach)

---

### ⏳ Group D — Ingenuity Branch: Late Game and Hybrids
Prerequisites: Group C complete.

- Lucidity (L1-L2): action to decrement Fervor by 1 step,
  uses existing item_action_charges
- Purple Hollow (L1): suicide trance, CombatStatus with stat_override
  ingenuity_size=12 and escalation_threshold=10, consequences on expiry
- Blood Channeling (Dom+Ing hybrid): cast during Burnout with self-damage
  via direct RollEngine call, keep grade scales with node level (3→2→1)
- Cataclysmic Arts / Meteor Shower: hybrid spell with aspect_stat="dominion",
  uses existing RollEngine.resolve() with no resolver changes

---

### Group 6 — Polish
- [x] **Save / load** — `SaveManager`, 3-slot JSON, auto-save on campfire entry.
- [x] **Constellation triangle canvas** — DOM/ING/NEG vertex layout, `Line2D` connections, expand/collapse, compact node cards.
- [x] **UI theme** — `res://theme/dark_fantasy.tres`.
- [x] **Art architecture** — `WorldLayer`/`UILayer` split; `AnimatedSprite2D` stubs + ColorRect dev placeholder; animation stub API (`play_idle/attack_melee/cast_spell/hurt/die`).
- [ ] **Art pass** — replace placeholder colored rects with sprites/animations.
- [ ] **Sound** — attack, guard break, wound, defeat SFX.

### ✓ Group 6.5 — Out-of-Combat Flow Redesign
Replaced `HubScene` with `MainMenuScene` + `CampfireScene`. Short Rest (−1 wound, −1 Fervor step, clear Burnout; once per run) + Long Rest (full heal, Fervor reset; 50%−luck% ambush risk → Disadvantage next fight). `luck: int` stat on `PlayerProgression`.

```
MainMenu ──New Game──────────────────────► BattleScene
		 └─Load (run_active)─────────────► CampfireScene
BattleScene ──Victory + has_next─────────► CampfireScene
			├─Victory + run complete──────► MainMenu
			└─Defeat─────────────────────► MainMenu
CampfireScene ──Continue─────────────────► BattleScene
			  ├─Constellation───────────► ConstellationScene
			  └─Give Up─────────────────► MainMenu
ConstellationScene ──Back (run_active)───► CampfireScene
				   └─Back (not active)───► MainMenu
```

Deferred stubs: consumable items, money deduction on ambush, ambush as extra encounter.

### ✓ Group 7 — Action System Foundation
`ActionModifier` resource (action_key, tier_cap, flat/keep/pool bonus, rest_type, uses_per_rest, target_pool). `EquipmentData.action_modifiers` array replaces flat fields (old fields kept as deprecated shims). `CombatManager`: `_get_action_modifier()` with bare_hands fallback, `item_action_charges` on `CombatantState`, `reset_item_charges()`. `CombatPreferences` (atk_mode, def_mode, defaults dict) on `PlayerProgression`.

---

### ✓ Group 7.5 — Cascading Combat UI (Intent → Tool → Execution)

Replaces the flat Strike / Cantrip / Spell button row with a three-layer cascading menu driven by
action keys. Target pool is defined by the `ActionModifier` itself (`target_pool` field), not chosen
by the player. Depends on Group 7.

**Phase A — Intent layer**
- [x] `CombatManager` gains signal: `player_intents_available(intents: Array[String])`. Emitted
  from `_begin_round()` alongside `player_action_required`. Intent values: `"attack"` (always),
  `"magic"` (when `has_minor_studies` or `has_spellcasting`), `"item"` (stub — disabled,
  label "coming soon").
- [x] `RoundHUD`: replace `_on_player_action_required()` with `_on_intents_available(intents)`.
  Top-level buttons become one button per intent. Compact row, dark-fantasy styled.

**Phase B — Tool sub-panel**
- [x] Selecting an intent opens a Tool panel listing items whose `action_modifiers` contain a
  matching `action_key`:
  - `"attack"` → items with `"strike"`. Bare hands treated as a weapon: if the equipped weapon
	has no `"strike"` action, falls back to `CombatManager.get_player_bare_hands_modifier("strike")`
	(actual `ActionModifier` from `CombatantData.bare_hands_actions`).
  - `"magic"` → conceptual `[Arcane Arts]` entry (not a physical item; stat source = Ingenuity).
	Always single-entry; auto-collapses.
  - Each entry shows: item name, modifier summary (e.g. `"Flat +1  Tier ≤ 2"`), [★] pin, Select button.
  - [★] pin on attack tools saves `CombatPreferences.defaults["attack"] = action_key` (foundation for Group 7.6 Auto Mode). Bare hands entries are pinnable the same way.

**Phase C — Execution options panel**
- [x] Selecting a tool opens an Execution panel:
  - For Strike: shows target pool from `ActionModifier.target_pool` (e.g. `"Target: Stance  (Guard: Negation)"`),
	roll preview, optional Brutal Trade toggle, and Confirm button.
	Pool is an action property — not a player choice.
  - For Cantrip / Spell: known spell list with [★] pin per entry; pin saves
	`CombatPreferences.defaults["magic"] = spell_name` (foundation for Group 7.6 Auto Mode).
  - Confirm → `CombatManager.player_chose_*`.
- [x] `DebugPoolSelector` remains debug-only (was already gated on `DebugManager.enabled`).
  `DebugAdvantageControl` remains debug-only (net advantage is not a player-facing choice).
- [x] Brutal Trade checkbox in the Strike execution panel (visible when `dom_brutal >= 1`).
- [x] Execution panel shows roll preview: `tier × avg_die_face + flat_bonus`.

**Phase D — Auto-collapse and back-navigation**
- [x] Each layer has a Back button to return to the previous panel.
- [x] Single-option layers collapse automatically (no Back button shown for that layer).
- [x] Panel state is cleared when `player_action_required` fires again (start of each round).

---

### ✓ Group 7.6 — Breakpoint System (ATK & DEF Modes)

Adds Auto / Manual mode toggles to combat pacing. ATK Auto follows saved defaults or falls back to
a scored heuristic. DEF Observe pauses before the enemy's attack resolves to display incoming info.
Depends on Groups 7 and 7.5.

**Phase A — ATK Mode toggle**
- [x] `RoundHUD`: ATK toggle button (`"ATK: Manual"` / `"ATK: Auto"`) reads/writes
  `CombatPreferences.atk_mode`. Persistent strip above the action panel.
- [x] **Manual Mode** (default): waits for player to navigate cascading menus.
- [x] **Auto Mode** flow in `CombatManager._begin_round()` via `_try_auto_execute()`:
  1. Complete path (attack_weapon + attack_action both set, weapon name matches) → execute immediately;
     log `"[Auto] Strike → Stance (default)"`.
  2. Magic default set → execute cantrip/spell immediately; log `"[Auto] Cast Fire Orb (default)"`.
  3. Any step undefined → call `_auto_best_action()` and execute; log
     `"[Auto-Best] Strike → Stance (score: 6.5)"`.

**Phase B — `_auto_best_action()` in `CombatManager`**
- [x] Private helper `_auto_best_action() -> Dictionary`. Returns `{ target_pool, score }`.
- [x] Score formula: `(effective_tier × (1 + die_size) / 2.0) + flat_bonus`. Higher = better.
- [x] Called only when `atk_mode == "auto"` and no complete default path resolves.
- [x] Magic actions only auto-execute when a default spell is saved; no heuristic for magic.
- [x] `docs/game-rules/combat-options/auto-best.md` — documents the heuristic formula.

**Phase C — DEF Observe Mode**
- [x] `RoundHUD`: DEF toggle (`"DEF: Auto"` / `"DEF: Observe"`) reads/writes `CombatPreferences.def_mode`.
- [x] **Auto Mode** (default): fully automatic defense as before.
- [x] **Observe Mode**: `_resolve_attack()` emits `player_defense_incoming(attacker_name, attack_total, target_pool)`
  before rolling defense, then awaits `_defense_acknowledged`. `BattleScene` routes it to
  `RoundHUD.show_defense_overlay(...)`. Overlay shows attacker name, attack total, target pool, `[ OK ]`
  button → `CombatManager.player_acknowledged_defense()` → resumes. No mechanic change.
  *Note: Active DEF Mode (player chooses defensive tool/action) is a future design task — requires
  designing defensive action types per weapon. Deferred to Future.*

---

### ✓ Group 8 — Sprite Registry & Art Infrastructure

Convention-based asset loader. Drop a PNG in the right folder with the right name; the system picks
it up automatically — no `.tres` editing required. Covers battle combatant sprites and a registry
foundation for weapon / spell / node icons.

Full spec: [docs/impl/group-8-sprite-registry.md](impl/group-8-sprite-registry.md)

---

### Future — Undesigned or blocked items

- **Brutal L2 Cleave** — multi-enemy overflow after a breach. Needs design decision on overflow mechanics (does excess carry over? to which target? in what order?).
- **Negation and Ingenuity subtrees** — `neg_core` and `ing_core` exist. Training/ability nodes not yet designed.
- **Cantrip count formula** — all known cantrips always available; "known slots" cap deferred.
- **Cumulative Disadvantage** — second+ different pool targeted same turn should stack Disadvantage. Deferred since Group 1.
- **Hybrid node proportional positioning** — constellation canvas barycentric positioning for cross-tree nodes. Blocked on NEG/ING subtrees being designed.
- **Active DEF Mode** — player chooses defensive tool/action. Requires game design work on defensive action types per weapon.
- **aether_barrier cantrip design** — stub .tres created, mechanic undefined. Requires a design session before functional implementation.
- **chrono_shift cantrip design** — same as above.
- **Ingenuity non-magic subtree** — Resolve Guard and training nodes for Ingenuity have not been designed. Blocked on design decisions.
- **Cumulative Disadvantage on multiple pools** — deferred since Group 1, remains deferred. Requires `_current_round_targeted_pools` tracking.
- **Active DEF Mode for magic** — deferred since Group 7.6. Requires design of magic defensive action types.
- **Cantrip count cap** — all purchased cantrips always available. "Known slots" formula not designed.
