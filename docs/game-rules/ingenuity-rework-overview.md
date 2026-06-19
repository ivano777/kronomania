# Ingenuity Rework — Overview

Reference document for the Ingenuity branch rewrite.
Describes design intent before implementation.

_Changelog: Mental Fortress node removed; anti-Burnout intent absorbed into Lucidity (cross-tier, L1-L2). MftG relocation and magic defense deferred to Future._

## Philosophy

1. **Horizontal growth:** the branch widens early. Disciplines are
   accessible without spending slots on mandatory passives.
2. **Spells injected by nodes:** spells are physically added to the
   character by the node that purchases them. No external reference needed
   to understand how to unlock them.
3. **Specific target pools:** magic bypasses physical defence (Stance)
   and pressures Resolve or Stamina, setting up follow-up strikes from
   warrior builds.

## Branch structure

### Tier 1 — Foundation
- `ing_core` (L1-L3): upgrade Ingenuity die, automatically raises Fervor cap
- `minor_studies` (L1): base cantrips — arcane_bolt, aether_barrier (stub),
  chrono_shift (stub)

### Tier 2 — The Engine
- `spellcasting` (L1-L3): unlocks Fervor/Escalation, injects Arcane Missile
  and Arcane Mark, progressive Keep on all arcane spells, SpellOutcomeEffects
  that upgrade spells with node level

### Tier 2-3 — Disciplines (horizontal choice)
- `mind_detonation` (L1-L2) ✓ — Phase C1. Placement scratch (pool=1, Ingenuity
  die, training keep, Fervor die, no SpellBonusEffect bonuses) applies
  `mind_detonation_primed` (duration=3, frozen `fervor_at_prime`). Phase 2.1
  (post player-attack, all round types): detonates via `_detonate_mind_bomb` →
  `_resolve_attack(true, …, "resolve")` if Stance was breached; uses frozen
  Fervor + explosion bonuses from `_collect_spell_bonuses`. No Fervor escalation.
  L2 (tier≥3, prereq ing_core L3): +1 explosion keep.
- `chrono_tinkering` (L1-L2) ✓ — Phase C4. Injects Time Lock (true spell, arcane tag,
  target_pool="resolve"). Dedicated `_cast_time_lock` bypasses `_resolve_attack`: on a
  Resolve breach, suppresses the wound and applies `time_locked` CombatStatus on the enemy
  in ARMED phase. The next player attack routed through `_resolve_attack` (any pool, incl.
  echoes and explosions) transitions the status to FROZEN: records which pool was attacked,
  sets `skip_resets` = node level, stores `frozen_value` = post-attack guard (0 on breach,
  remaining on hold). `_end_of_round` reads `frozen_value` and restores the frozen pool
  after reset, preventing it from re-rolling. Each round decrements `skip_resets`; status
  removed when 0. L1: freeze lasts 1 round. L2 (tier≥3, prereq chrono_tinkering L1):
  freeze lasts 2 rounds. Frozen value tracks player progress across rounds.
- `echoing_mind` (L1-L2) ✓ — Phase C3. Injects Mind Lash (true spell, tags=["arcane","echo"],
  target_pool="stance"). After cast, applies `echoing_spell` CombatStatus on the PLAYER with
  frozen `frozen_fervor`, `current_kept_dice` = cast_kept−1, `em_level`. At each `end_of_round`,
  `_process_statuses_hook` awaits `_resolve_spell_echo`: routes through `_resolve_attack(true,…)`
  using frozen Fervor and decremented kept dice; no Fervor escalation; Hex amplification and Mind
  Detonation interactions fire normally. Status self-removes when `next_kept < 1`. L2: echo flat
  bonus = current_kept_dice for that echo. Known simplification: one echo train at a time (new
  cast overwrites). `cast_kept=1` → initial_echo=0 → no status applied.
- `hex_mastery` (L1-L2) ✓ — Phase C2. Injects Mind Rend (true spell, tags=["arcane"],
  target_pool="resolve"). Mind Rend uses a dedicated helper `_cast_mind_rend` that
  bypasses `_resolve_attack`: on a Resolve breach, suppresses the wound and applies
  `hex_marked` CombatStatus (duration L1=3, L2=7; "2 turns"/"4 turns" perceived).
  On Resolve holds: nothing. While `hex_marked` is active, every player breach on
  that enemy (any pool) adds `wounds_pending += 1` in `_resolve_attack`. Enemy-on-player
  breaches are never amplified. Mind Rend's own breach is not self-amplified (mark applied
  after on_breach hook, wound suppressed). Known combo: Hex + Mind Detonation — both
  the Stance breach and the explosion breach are amplified by the same mark.

### Tier 1 to Tier 3 — Cross-tier
- `lucidity` (cross-tier, L1-L2): the caster's Fervor self-control node.
  L1 ✓ (Tier 1): proactive action — lower Fervor by 1 step, costs the
  turn, unlimited. Implemented: `ability_lucidity.tres` L1, "lucidity"
  intent in CombatManager/RoundHUD, `player_chose_lucidity()` public method.
  L2 ✓ (Tier 3): reactive — when escalation would cause Burnout, spend a
  charge to cancel it. One identity (control your own magic), two depths
  (manage early, resist collapse late). L2 uses an InterruptHandler registered
  in start_combat; _escalate_fervor is now a coroutine; _try_prevent_burnout
  is the dedicated bool-returning path (separate from the wounds-shaped
  _resolve_interrupt dispatcher). Fully implemented: B3b.

### Tier 3-4 — Apex and Hybrids
- `purple_hollow` (L1): suicide trance with temporary d12
- `blood_channeling` (Dom+Ing hybrid): cast during Burnout with self-damage
- `cataclysmic_arts` (hybrid): Meteor Shower with aspect_stat="dominion"

## Casting implement system (Phase D-pre)

Spells and cantrips use an explicit **casting tool** selected by the player each round — structurally identical to the strike weapon-selection flow.

**Pool formula:** `pool = effective_tier(cast_mod) + cast_mod.pool_bonus + school_pool_bonus`
- `cast_mod` = the chosen tool's `"cast"` ActionModifier (or bare-hands stub if none)
- `_effective_tier(player, cast_mod)` = `mini(tier, cast_mod.tier_cap)` if tier_cap > 0, else full Tier
- Mundane weapons: `tier_cap = 1` — casting while holding steel caps the pool to 1 die
- Bare Hands (or no item with `"cast"` key): `tier_cap = 0` → full Tier, all bonuses zero
- Magic foci (future content): any `tier_cap`/`pool_bonus`/`keep_bonus`/`flat_bonus` combination

**Mind Detonation placement** is gear-independent: pool=1 always.

**Phase 1 (implemented):** direct casts (cantrip + true spell) use the chosen cast tool.

**Phase 2 (implemented):** the chosen `cast_mod` is frozen into `mind_detonation_primed.stat_overrides` and `echoing_spell.stat_overrides` at prime/cast time. Keys frozen: `cast_tier`, `cast_pool_bonus`, `cast_flat_bonus` (both); `cast_keep_bonus` in bomb only (echo bakes keep into `current_kept_dice` at arming). Delayed payoffs read these keys; legacy statuses without them fall back to full Tier. `_player_cast_weapon` cleared after freeze, before Phase 2.1.

## Design not yet completed

- aether_barrier: defensive mechanic undefined
- chrono_shift: time mechanic undefined
- Resolve Guard training nodes: not designed
- Ingenuity non-magic subtree: not designed
- **Meat for the Grinder relocation/reframe** — currently dom_meat_grinder on Dominion. Planned to be reframed as a Dominion/Negation hybrid defensive node (physical damage mitigation identity). Mechanic unchanged; only tree placement/identity changes. Not scheduled.
- **Magic defense (Negation/Ingenuity hybrid)** — defensive identity for casters. Design direction only; mechanic undefined. Should feel like prevention/manipulation/evasion, not damage soak. Blocked on design session.

## Architectural dependencies

The entire branch depends on the four systems from Group A. No node in the
branch can be implemented until Group A is complete and validated.
