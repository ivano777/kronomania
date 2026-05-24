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
- `mind_detonation` (L1-L2): delayed effect via CombatStatus
- `chrono_tinkering` (L1): skip next guard roll on one pool
- `echoing_mind` (L1): end_of_round echo for spells with tag "echo"
- `hex_mastery` (L1): persistent CombatStatus, +1 wound on every breach

### Tier 1 to Tier 3 — Cross-tier
- `lucidity` (cross-tier, L1-L2): the caster's Fervor self-control node.
  L1 (Tier 1-2): proactive action — lower Fervor by 1 step, costs the
  turn, unlimited. L2 (Tier 3): reactive — when escalation would cause
  Burnout, spend a charge to cancel it. One identity (control your own
  magic), two depths (manage early, resist collapse late). L1 uses the
  action system; L2 uses an InterruptHandler in _escalate_fervor.

### Tier 3-4 — Apex and Hybrids
- `purple_hollow` (L1): suicide trance with temporary d12
- `blood_channeling` (Dom+Ing hybrid): cast during Burnout with self-damage
- `cataclysmic_arts` (hybrid): Meteor Shower with aspect_stat="dominion"

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
