# Game Rules — Implementation Summary

Detailed quick-reference for how the design rules map to code. Load this when
touching combat, magic, or progression mechanics. CLAUDE.md carries only the
universal core table (roll resolution, guard, breach, wounds); everything below
is the specialist detail that used to live inline.

Rules live in `docs/game-rules/`; the implementation must match exactly.

## Core resolution

| Concept | Rule |
|---|---|
| Roll resolution | Build Pool → Roll → Keep → Flat → Outcome |
| Pool size | = Tier (T1=1 die … T4=4) |
| Die size | from stat field (`dominion_size`/`negation_size`/`ingenuity_size`), face int 4/6/8/10 |
| Keep | **N = keep N dice** (keep_grade=1→1 die, 2→2, 3→3) |
| VT (Fast/Slow) | VT is a static enemy property; only the **player's** action roll is compared. Player ≥ VT → Fast (acts first); < VT → Slow. Enemy timing implicit, no roll. |
| Guard | rolled **once per round** when first pressured; same-round pressure reuses it; resets to 0 at round start |
| Breach | `attack_total >= guard` (exactly 0 is a breach) |
| Wounds | 1 on breach; 2 if Massive: `(attack − guard) > defensive_size` |
| Defeat | `wounds >= max_wounds` |

## Magic

| Concept | Rule |
|---|---|
| Cantrip | Ingenuity die, pool = full Tier + cast tool bonuses (`_get_cast_modifier`; items never cap Tier), no Fervor die, no escalation, no school bonuses, usable during Burnout; via `node.spells` (Minor Studies: Arcane Bolt, Arcane Touch), `is_cantrip=true`. **Conduit gate:** truly empty hands OR equipped `MagicFocus` item (`CombatMath.can_channel_cantrips`) |
| True spell | Ingenuity + optional aspect dice + real Fervor die; pool = full Tier + cast tool bonuses + school pool bonus; Spellcasting L1+ (Arcane Missile vs Stance, Arcane Mark vs Resolve); escalation = `primary_dice_maxed_count + (1 if fervor_maxed)`. **Conduit gate:** equipped `MagicFocus` item always required (`CombatMath.can_channel_spells`) |
| Fervor cap | = `ingenuity_size` face; may act at cap; escalating **beyond** cap → Burnout |
| Burnout | Blocks true spells; cantrips unaffected; persists across combats; cleared by Long Rest (also resets Fervor) or Recovery (Burnout only) |
| Spellcasting L1–L3 | L1: Arcane Missile + Arcane Mark, unlocks Fervor. L2: all arcane keep 2, Arcane Missile +1 flat, Arcane Mark breach → enemy Stance flat −2. L3: all arcane keep 3, Arcane Missile +2 flat total, Arcane Mark breach also → enemy Stance keep −1 (Frattura Totale). |

## Stats and progression

| Concept | Rule |
|---|---|
| Stat sizes | Base from `CombatantData`; upgraded by Core nodes via `_stat_size()` |
| Tier advancement | Slot-budget: **5 combat + 2 Flavor slots** per tier; spending both advances + resets. Core = 2 combat slots; Training/Ability = 1; Flavor = 1 from Flavor budget. `tier_combat_spent`/`tier_flavor_spent` public. |
| Passive wounds | +1 Max Wounds at T2, +1 at T4 (cumulative +2). At `start_combat()` via `_tier_wound_bonus(tier)`; base `.tres` never mutated. |
| Player base Dominion | d4 (`player_default.tres`); `dom_core` L1→d6, L2→d8, L3→d10 via `_stat_size()`. |
| Physical keep grade | `_physical_keep_grade()` = `maxi(_training_keep_grade(), physical_keep nodes)`. Physical Strike only. Off-hand strikes use `_strike_mod` (resolved from `chosen_weapon`) for tier/flat/pool/keep; weapon-tag node bonuses (`weapon_flat`, `weapon_keep`) are matched against `chosen_weapon.tags`. |
| Defensive keep grade | `_defense_keep_grade(state, pool)` = `maxi(_training_keep_grade(), purchased level of the pool's defense node)` via `CombatMath.DEFENSE_NODE_FOR_POOL` (`neg_stance`/`ing_resolve`/`dom_stamina`). The `<pool>_keep` effect types are retired — defense-node levels carry riders instead. At guard rolls in `_resolve_attack`, `_cast_mind_rend`, and `_cast_time_lock`. |
| Stance flat (neg_stance L2) | `CombatMath.guard_flat_bonus(state, pool)` (+2, Stance pool only) added to the defend modifier's flat at the guard roll. |
| Iron guard die (neg_stance L3) | `CombatMath.guard_bonus_dice(state)` → +1 Negation-size die on EVERY defense pool roll: pool widened by the count AND passed as aspect dice (`aspect_stat_size` = Negation) to `RollEngine.resolve`. Added, not substituted. |
| Branch-spend gates | `NodeLevelData.branch_spend` (`{"branch": points}`, all entries must hold; hybrid = two keys) checked in `can_upgrade()` via `get_branch_spent()` (derived: sum of purchased level costs where `NodeData.branch` matches; no save field). Replaces `required_tier` (deprecated shim, ignored). Tier keeps its pool-size + slot-budget roles. |

## Dominion abilities

| Concept | Rule |
|---|---|
| Brutal Trade | RoundHUD toggle (visible when `dom_brutal >= 1`): VT −5, Flat +5 on player physical attack. |
| Earthshatter | Post-keep Dominion die on Stance physical attacks when `dom_earthshatter` purchased. Passed as `post_keep_bonus_size`. |
| Meat for the Grinder | `InterruptHandler` (`meat_for_the_grinder`, `on_massive_wound`, priority 20) at `start_combat()`. On a Massive Wound to the player, `_find_interrupts` fires it → emits `player_massive_incoming`, awaits `_massive_decision_gate`; a charge → 1 Wound instead of 2. |
| Stamina Guard L2 (+1 Max Wounds) | `training_wounds` rider on `dom_stamina` L2, summed by `_wounds_node_bonus()` at `start_combat()` — the only node HP bonus (`dom_wounds` deleted; Meat for the Grinder now prereqs `dom_stamina` L2). |

## Ingenuity disciplines

| Concept | Rule |
|---|---|
| Lucidity L1 | Proactive: lower Fervor 1 step, costs the turn, unlimited. Hidden at d4 (`_can_use_lucidity()`). `await _escalate_fervor(_player, -1)`; negative steps skip Burnout check + cap clamp. |
| Lucidity L2 | Reactive interrupt: a positive escalation that would Burnout prompts (`player_burnout_imminent`) to spend 1 charge/combat. If spent, Burnout cancelled but **Fervor stays at cap** (precarious truce). `InterruptHandler` (`lucidity_prevent_burnout`, `on_burnout`, priority 10); via `_try_prevent_burnout()` inside `_escalate_fervor()`, NOT `_resolve_interrupt`. |
| Magic Shield (ing_resolve L2/L3) | Guard-shaped `InterruptHandler` (`magic_shield`, `on_guard_break`, priority 10) registered at `start_combat()`. In `_resolve_attack`, when the player's guard would break (`attack_total >= guard`), `_try_magic_shield` emits `player_shield_opportunity`, awaits `_shield_decision_gate`; spending a charge rolls N Ingenuity-size dice (N = `ing_resolve` level via `CombatMath.magic_shield_dice`) added to that pool's guard, then the breach re-checks (shield can fail). Charges: L2 1, L3 2 (`CombatMath.magic_shield_charges`). Guard-layer only — direct-wound effects bypass it. |
| Mind Detonation | True spell (L1 tier≥2, prereq Spellcasting L1). Placement = pool=1 Ingenuity scratch vs Stance (Fervor die, no bonuses, gear-independent); applies `mind_detonation_primed` (duration=3; freezes `fervor_at_prime`+`md_level`+`cast_tier`+`cast_pool_bonus`+`cast_keep_bonus`+`cast_flat_bonus`). At Phase 2.1, if primed + `_current_round_player_breaches["stance"]`, `_detonate_mind_bomb` removes the status and explodes vs Resolve via `_resolve_attack` using frozen Fervor + frozen cast values (no escalation; bonuses via `_collect_spell_bonuses`). Legacy statuses without `cast_*` keys fall back to full Tier. Fizzle logged on expiry. L2 (tier≥3, prereq ing_core L3): +1 explosion keep. Simplification: breach tracking is global (any Stance breach triggers all primed bombs). |
| Hex Mastery / Mind Rend | True spell (L1 tier≥3, prereq Spellcasting L2; L2 also requires Spellcasting L3 — disciplines are final moves). Mind Rend attacks Resolve via `_cast_mind_rend` (bypasses `_resolve_attack` to suppress the breach wound). On breach: applies `hex_marked` (L1 duration 3 / "2 turns", L2 duration 7 / "4 turns"), no wound. On hold: nothing. While `hex_marked`, `_resolve_attack` adds `wounds_pending += 1` on every player breach (any pool); enemy-on-player never amplified. Own breach not self-amplified (mark applied after the hook). Fervor escalates normally. Combo with Mind Detonation: Stance breach +1 and explosion breach +1 from the same mark. |
| Echoing Mind / Mind Lash | True spell (L1 tier≥3, prereq Spellcasting L2; L2 also requires Spellcasting L3 — disciplines are final moves). Mind Lash `tags=["arcane","echo"]`. After cast, applies `echoing_spell` **on the player**. Each `end_of_round`, `_resolve_spell_echo` routes through `_resolve_attack(true,…)` with frozen `fervor_at_cast`, frozen `cast_tier`/`cast_pool_bonus`/`cast_flat_bonus`, and decremented `current_kept_dice` (starts cast_kept−1 where cast_kept includes `cast_mod.keep_bonus`; −1 per echo; removed when next < 1). Focus keep baked into initial `current_kept_dice` — no separate `cast_keep_bonus` key in echo status. No escalation. `echo_flat = current_kept` at L2, 0 at L1. New cast overwrites the existing echo (latest wins — simplification). Echo is a full player attack: Hex + Mind Detonation interactions live. Cast with cast_kept=1 → no echo. |
| Chrono-Tinkering / Time Lock | True spell (L1 tier≥3, prereq Spellcasting L2). Time Lock attacks Resolve via `_cast_time_lock` (bypasses `_resolve_attack` to suppress the breach wound). On Resolve breach: applies `time_locked` CombatStatus on the enemy in ARMED phase (payload: `phase`, `locked_pool`, `skip_resets`, `frozen_value` all in `stat_overrides`). On Resolve hold: nothing. The armed status waits for the next player attack on this enemy routed through `_resolve_attack` (any pool, including echoes and MD explosions). At that attack's end, the status transitions ARMED→FROZEN: `locked_pool` = the attacked pool, `skip_resets` = node level (1 for L1, 2 for L2), `frozen_value` = post-attack guard value (0 on breach, remaining on hold). While frozen, `_end_of_round` skips `reset_guard()` for that pool and restores `frozen_value` instead (marking the pool as rolled, so it won't re-roll). Each `_end_of_round` decrements `skip_resets`; when it reaches 0 the status is removed and the pool resets normally. L2 (tier≥3, prereq chrono_tinkering L1 + Spellcasting L3): freeze lasts 2 rounds. The frozen value tracks the player's progress: if the player presses the frozen guard lower in a frozen round, that new value carries forward. Fizzle log in `_tick_statuses` for an armed status that expires without triggering. New cast overwrites existing status (`_add_status` deduplication). |

Next unimplemented items: Group D — Ingenuity Branch: Late Game and Hybrids.
