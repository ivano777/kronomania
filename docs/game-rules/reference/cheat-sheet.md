# Cheat Sheet

## Core Flow
**Build Pool -> Roll -> Keep -> Flat -> Outcome**

## Tier
- T1 -> 1 die
- T2 -> 2 dice
- T3 -> 3 dice
- T4 -> 4 dice

## Stable Dice
- d4
- d6
- d8
- d10

Exceptional / temporary:
- d2
- d12

## Default Stats
- Default offensive: **Dominion**
- Default defensive: **Negation**
- Default mental / control: **Ingenuity**

## Keep
- Grade 0 -> keep 1
- Grade 1 -> keep 2
- Grade 2 -> keep 3

## Modifier Layers
- Status -> Size
- Situation -> Pool
- Flat -> post-Keep total

## Advantage / Disadvantage
- Cancel 1-for-1; remaining net applies normally.
- Net Disadvantage to 0 dice -> **Desperation** (roll 2, keep worst).

## Defense Pools
- Stance (from Negation)
- Resolve (from Ingenuity)
- Stamina (from Dominion)

Default target if unspecified: **Stance**

Each defense pool is normally rolled **once per turn**.
Once rolled, it absorbs further same-type pressure until depleted or turn ends.
Additional different pools in same turn: cumulative Disadvantage.
Guard resets at start of each new turn.

## Wounds and Defeat
- 1 Wound on broken Guard
- 2 Wounds on Massive result
- Massive: (total - Guard) > defensive Size
- Player Max Wounds = 3 (default)
- Defeat when Wounds >= Max Wounds

## VT (Velocity Threshold)
- VT is a **static value authored on the enemy / target**.
- Only the **player's** action roll is compared to the enemy's VT.
- **>= VT → Fast** (player acts first) | **< VT → Slow** (enemy acts first)
- The enemy does not roll for timing — its speed is encoded in the VT value itself.

## Spell Resolution Order
1. Normal pool from Tier
2. Advantage / Disadvantage / Desperation
3. Substitutions
4. Roll normal pool
5. Keep
6. Roll real Fervor dice
7. Sum (kept + Fervor total)
8. Flat
9. Resolve
10. Check Fervor-tagged dice for max rolls -> escalate
11. If escalation exceeds Ingenuity cap -> Burnout
12. Fervor clamped at cap

## Fervor
- Cap = **current modified Ingenuity**
- Real Fervor dice: additive, post-keep, cannot be discarded
- Substitution dice: part of normal pool, can be discarded, still Fervor-tagged
- Escalation check: any Fervor-tagged die at max (even discarded) -> +1 Fervor step

## Burnout
- Triggered after the overflowing spell resolves
- Blocks true spells
- Does not block cantrips
- Fervor clamped at Ingenuity cap

## Recovery
- Long Rest -> remove Burnout + full Fervor reset
- Recovery Scene -> remove Burnout only (Fervor stays)

## Cantrip Knowledge
stable Ingenuity / 2 + Minor Studies bonus

| Stable Ingenuity | Base |
|------------------|------|
| d2               | 1    |
| d4               | 2    |
| d6               | 3    |
| d8               | 4    |
| d10              | 5    |
| d12              | 6    |
