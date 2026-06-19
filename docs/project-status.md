# Project Status

Tracks what is implemented and what remains. Updated after each feature ships.

---

## Implemented

### Bug fixes
- **Bug 2 — Off-hand strike bonuses** — `_resolve_round` player strike now sources flat bonus, pool bonus, and weapon-tag node bonuses (`weapon_flat`, `weapon_keep`) from the chosen weapon (`_strike_mod` + `chosen_weapon`) instead of the main-hand. Helpers `_attack_flat`, `_pool_bonus`, `_node_weapon_bonus_sum` gained optional params defaulting to the old behavior; enemy/auto/preview call sites are unchanged.

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
- **Nodes (43 total)**: Dominion tree (`dom_core/wounds/martial_arts/melee/ranged/dual_wield/titans_grip/disarm/brutal/meat_grinder/earthshatter`); `neg_core`, `ing_core` (multi-level, 3 levels each); pool-guard training nodes (`neg_stance`, `dom_stamina`, `ing_resolve`); ability nodes (`minor_studies`, `spellcasting` L1–L3); flavor nodes (`warrior_oath` + 15 under `flavors/`)
- **Spells**: cantrips — `arcane_bolt`, `arcane_touch`; true spells — `arcane_missile`, `arcane_mark`

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

### ✓ Group 4.5 — Spell school system (pipeline only; school nodes removed in B2)
Core stat nodes with compound prereqs + `_stat_size()` helper. `SpellBonusEffect` resource (`pool`/`keep`/`flat` bonus types); tag- and spell_id-matched bonuses applied at spell resolution. Original Fire Magic I–IV + Arcane I–III school nodes removed in Phase B2; ideas archived in `docs/game-rules/appendices/legacy-archive.md`.

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

### ✓ Group A — Foundational Architecture — fully complete; unblocks Group B (Ingenuity branch rewrite)

Four architectural systems that extend CombatManager without breaking existing
behaviour. All four phases implemented.

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

**Phase A4 — SpellOutcomeEffect** ✓
New resource `SpellOutcomeEffect` (data only) describing post-resolution spell
effects (flat/keep debuffs, conditional bonuses, status application).
`NodeLevelData` gains `outcome_effects: Array[SpellOutcomeEffect]`.
`SpellBonusEffect` gains optional `spell_id: String` filter for per-spell
numerical upgrades. `CombatantState` gains `pending_guard_debuffs: Dictionary`
(consumed on next guard roll). Round-scoped `_current_round_player_breaches`
on `CombatManager` tracks which pools the player breached each round.
Processing via `_apply_spell_outcome_effects()` called from both
`_resolve_round_spell()` and `_resolve_round_cantrip()`. `SpellBonusEffect`
also gains `bonus_type="flat"` (wired at B2). Spellcasting L2/L3 carry
the first live `outcome_effects` entries (Arcane Mark breach debuffs).

---

### ✓ Group B — Ingenuity Branch: Core and Spellcasting
Prerequisites: Group A complete.

**Phase B1 ✓ — cantrip_spark renamed to arcane_bolt** (refactor only)

**Phase B2 ✓ — Spellcasting L1-L3 (Strada A — Arcane branch)**
Legacy spell schools (Fire Magic I–IV, Arcane I–III) and their spells
(sparks, fire_orb, fireball, wall_of_fire, meteor, mind_spike, void_bolt)
removed. Design ideas preserved in
`docs/game-rules/appendices/legacy-archive.md`.
`SpellBonusEffect` gains `bonus_type="flat"` (third valid type).
Spellcasting node expanded to L1-L3:
- L1: grants Arcane Missile + Arcane Mark, unlocks Fervor
- L2: arcane Keep 2, Arcane Missile +1 flat, Arcane Mark breach → Stance −2
- L3: arcane Keep 3, Arcane Missile +2 flat, Arcane Mark breach + Stance −1
  keep (Frattura Totale: both L2 and L3 debuffs accumulate and fire together)

**Phase B3a ✓ — Lucidity L1 (proactive Fervor cooling)**
Node `ability_lucidity.tres` (max_levels=2, L2 placeholder non-functional).
L1: new "lucidity" intent, available when Lucidity L1 purchased and Fervor > d4.
`player_chose_lucidity()` calls `await _escalate_fervor(_player, -1)`, ends the round.
`_escalate_fervor` extended to support negative steps: Burnout check and cap clamp
gated to `steps > 0`; negative steps use `clampi` floor and raw track position.

**Phase B3b ✓ — Lucidity L2 (reactive anti-Burnout interrupt)**
L2 (required_tier 3): InterruptHandler ("lucidity_prevent_burnout", trigger="on_burnout",
priority=10, 1 charge/combat) registered in `start_combat`. `_escalate_fervor` is now a
coroutine; when a positive step would cause Burnout, `_try_prevent_burnout` is awaited —
a dedicated bool-returning path separate from the wounds-shaped `_resolve_interrupt`
dispatcher. Player prompted via `player_burnout_imminent` / `_burnout_decision_gate`
signals. Precarious-truce design: Burnout averted but Fervor stays at cap. Lucidity is
now fully implemented (L1 + L2).

**Remaining B work:** Minor Studies cantrip expansion (aether_barrier,
chrono_shift design-blocked — see Future).

**Note:** aether_barrier and chrono_shift require design decisions before
any stub implementation. See Future section for the open design questions
that must be resolved first.

---

### ✓ Group C — Ingenuity Branch: Disciplines — COMPLETE
Prerequisites: Group B complete.

Four specialised disciplines using all Group A systems:

**Phase C1 ✓ — Mind Detonation**
`ability_mind_detonation.tres` (max_levels=2). Placement scratch: pool=1,
Ingenuity die, training keep, Fervor die included (no SpellBonusEffect bonuses).
Applies `mind_detonation_primed` CombatStatus (duration=3) with frozen
`fervor_at_prime` + `md_level` in `stat_overrides`. At Phase 2.1 (post
player-attack) in all three round types: `_check_mind_detonation` fires
`_detonate_mind_bomb` if Stance was breached and the status is active — routes
through `_resolve_attack(true, …, "resolve")` using frozen Fervor + bonuses from
`_collect_spell_bonuses`. No Fervor escalation from explosion. Status removed
before `_resolve_attack` (anti-recursion guard). Fizzle message on expiry.
L2 (tier≥3, prereq ing_core L3): +1 explosion keep.
Known simplification: global `_current_round_player_breaches["stance"]` tracking —
any Stance breach in the round triggers all primed bombs; per-enemy tracking deferred.

**Phase C2 ✓ — Hex Mastery**
`ability_hex_mastery.tres` (max_levels=2). Injects Mind Rend (true spell, arcane tag,
target_pool="resolve"). Dedicated `_cast_mind_rend` bypasses `_resolve_attack`: on a
Resolve breach, suppresses the wound and applies `hex_marked` CombatStatus (L1:
duration_rounds=3, "2 turns"; L2: duration_rounds=7, "4 turns"). On Resolve holds:
nothing. While hex_marked is active, `_resolve_attack` applies `wounds_pending += 1`
for every player breach on the hexed enemy (any pool); enemy-on-player breaches are
never amplified. Intended combo: Hex + Mind Detonation — both the Stance breach AND
the explosion breach are amplified by the same mark.

**Phase C3 ✓ — Echoing Mind**
`ability_echoing_mind.tres` (max_levels=2). Injects Mind Lash (true spell, tags=["arcane","echo"],
target_pool="stance"). After a true spell cast with the "echo" tag, applies `echoing_spell`
CombatStatus on the PLAYER (the caster) with frozen `frozen_fervor`, `current_kept_dice` =
cast_kept−1, and `em_level`. At each `end_of_round`, `_process_statuses_hook` (now a coroutine)
awaits `_resolve_spell_echo` — routes through `_resolve_attack(true,…)` using frozen Fervor and
decremented kept dice; no Fervor escalation. `current_kept_dice` decrements by 1 each round;
status self-removes when next < 1. L2: each echo carries flat bonus = current_kept_dice for that
echo. `duration_rounds=20` is a safety bound; real termination is via kept-dice decay.
Known simplifications: one echo train at a time (new cast overwrites old);
global Stance breach tracking for MD interactions (same as Mind Detonation).
`_end_of_round` now `await`s hook calls and checks `_all_enemies_defeated()` mid-body
(echo can kill the last enemy); all four `_end_of_round` call sites guard `_begin_round()`.
New spell: `mind_lash.tres`. New node: `ability_echoing_mind.tres`.

**Phase C2.6 ✓ — Defensive keep grade unification**
`_defense_keep_grade` now uses `maxi(_training_keep_grade, _node_effect_max)` mirroring `_physical_keep_grade`.
Call sites in `_resolve_attack` and `_cast_mind_rend` simplified (redundant `_training_keep_guard` sum removed).
Defensive node effect_values shifted 0/1/2 → 1/2/3 to match their "Keep 1/2/3 dice" descriptions.
Behavior-identical (mathematical equivalence proven and probe-tested).

**Phase C4 ✓ — Chrono-Tinkering**
`ability_chrono_tinkering.tres` (max_levels=2). Injects Time Lock (true spell, arcane tag,
target_pool="resolve"). Dedicated `_cast_time_lock` bypasses `_resolve_attack`: on a Resolve
breach, suppresses the wound and applies `time_locked` CombatStatus on the enemy in ARMED
phase (`stat_overrides`: `phase`, `locked_pool`, `skip_resets`, `frozen_value`). On hold: nothing.
The ARMED status waits for the next player attack routed through `_resolve_attack` (any pool,
including echoes and MD explosions). At that attack's end, a new inline block (after the final
`guard_changed.emit`) transitions the status to FROZEN: records `locked_pool`, sets `skip_resets`
to the chrono node level (1 for L1, 2 for L2), and stores `frozen_value` = post-attack guard
(0 on breach via `did_breach` flag, remaining on hold). While FROZEN, `_end_of_round` reads
`frozen_value` from `stat_overrides`, resets all guards, then restores the frozen pool and
marks it rolled — preventing re-roll next round. Decrements `skip_resets` each round; removes
the status at 0. The frozen value tracks player progress (updated each time the player attacks
the frozen pool while FROZEN). Fizzle log in `_tick_statuses` for ARMED expiry via duration.
New spell: `time_lock.tres`. New node: `ability_chrono_tinkering.tres`.
Key architectural note: `frozen_value` in `stat_overrides` is the source of truth (not `get_guard`)
because `_resolve_attack`'s breach path does not clear the stored guard to 0 (intentional for
multi-enemy scenarios); breach-awareness is provided by the local `did_breach` flag.

**Phase D-pre ✓ — Cast Tool Selection (Phases 1 + 2) — COMPLETE**
Explicit casting-tool layer mirrors the strike weapon-selection flow. Player picks a casting tool
(list + pin/star default) before the spell list; chosen tool's `"cast"` ActionModifier governs the
cast pool. Mundane weapons get `tier_cap=1` (caps pool to 1 die); Bare Hands (or no `"cast"` key)
falls back to the uncapped bare-hands stub (full Tier). `_get_cast_modifier(state)` in
CombatManager resolves the chosen `_player_cast_weapon`. All four mundane weapon .tres files carry
the new `"cast"` sub-resource. Cantrip + true-spell paths use the cast tool; Mind Detonation
placement is gear-independent (pool=1).
Tooltip renders `"Cast  Tier cap"` and bonus rows. `RoundHUD` cast tool panel + pin button mirrors
attack behavior; signals `cantrip_selected`/`spell_selected` carry `source_weapon`.
Phase 2: chosen `cast_mod` frozen into `mind_detonation_primed.stat_overrides` (`cast_tier`,
`cast_pool_bonus`, `cast_keep_bonus`, `cast_flat_bonus`) and `echoing_spell.stat_overrides`
(`cast_tier`, `cast_pool_bonus`, `cast_flat_bonus`; focus keep baked into `current_kept_dice`).
Delayed payoffs (explosion + echo) read frozen values; legacy statuses without keys fall back to
full Tier (`_effective_tier(_player, null)`). `_player_cast_weapon` cleared after freeze, before Phase 2.1.

---

### ⏳ Group D — Ingenuity Branch: Late Game and Hybrids
Prerequisites: Group C + Phase D-pre complete. ✓ All prerequisites met.

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
- **aether_barrier cantrip** — concept: defensive cantrip for Minor Studies; mechanic undefined. Blocked on design decision: needs to choose between (a) instant +guard on a pool for one round, (b) CombatStatus shield with duration, or (c) reactive InterruptHandler that triggers on incoming magic. Pick one before implementation.
- **chrono_shift cantrip** — concept: time-manipulation cantrip for Minor Studies; mechanic undefined. Blocked on design decision: needs to choose between (a) enemy VT temporary modifier, (b) self-buff CombatStatus granting Advantage on next roll, or (c) enemy-skip status preventing one enemy action. Pick one before implementation.

Both items live in the "Cantrip Expansion" backlog — implementation group not assigned. They will be addressed in a dedicated design session, not as part of Group B/C/D.
- **Ingenuity non-magic subtree** — Resolve Guard and training nodes for Ingenuity have not been designed. Blocked on design decisions.
- **Cumulative Disadvantage on multiple pools** — deferred since Group 1, remains deferred. Requires `_current_round_targeted_pools` tracking.
- **Active DEF Mode for magic** — deferred since Group 7.6. Requires design of magic defensive action types.
- **Cantrip count cap** — all purchased cantrips always available. "Known slots" formula not designed.
- **Meat for the Grinder relocation/reframe** — currently dom_meat_grinder on Dominion. Planned to be reframed as a Dominion/Negation hybrid defensive node (physical damage mitigation identity). Mechanic stays (Massive 2→1 via charge); only its tree placement/identity changes. Not scheduled — future task.
- **Magic defense (Negation/Ingenuity hybrid)** — the defensive identity for casters. Design direction only; mechanic undefined. Distinct from Dominion's "absorb the blow" — should feel like prevention/manipulation/evasion, not damage soak. Blocked on design session.
