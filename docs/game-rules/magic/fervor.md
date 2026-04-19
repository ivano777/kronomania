# Fervor

Fervor is the instability mechanic used by true spellcasting.

## Fervor Cap
The Fervor cap is based on **current modified Ingenuity**, not stable Ingenuity.

- A caster may still cast while Fervor equals the current Ingenuity cap.
- If, after a spell resolves, Fervor escalation would move beyond the cap, the spell still resolves, then the caster enters Burnout.
- The Fervor value is clamped at the cap; it does not rise above it.

### Ingenuity Reduction Interaction
If a temporary effect lowers Ingenuity, the Fervor cap tightens immediately to match the new current modified Ingenuity.

If current Fervor is now above the new cap:
- Fervor is immediately clamped down to the new cap.
- This clamp-down does **not** count as recovery.
- This clamp-down does **not** remove Burnout.
- If the actor was already in Burnout, they remain in Burnout until a valid recovery effect removes it.
- If the actor was **not** in Burnout, this clamp-down alone does **not** create Burnout.

Burnout is a state transition checked after spell resolution or an explicit Fervor-escalating effect — not from passive state drift such as a cap shrinking.

If Ingenuity later rises again, Fervor does **not** automatically rise with it.

## Real Fervor Dice
Real Fervor dice are granted by the Spellcasting node or later features.

Properties:
- Added **after** the normal pool has been rolled and kept.
- Their total is added to the final spell total.
- They are **not** part of the normal Keep process.
- They **cannot** be discarded.

Default base Fervor die: **d4**

Normal baseline escalation:
- d4 -> d6
- d6 -> d8
- d8 -> d10

## Substitution Dice
Some spells or features convert one or more normal spell-pool dice into Ingenuity-based dice.

Properties:
- Remain **part of the normal pool**.
- Rolled with the normal pool.
- Subject to normal Keep and may be discarded.
- Still **Fervor-tagged** for escalation purposes.

## General Escalation Rule
Every Fervor-tagged die that rolls its **maximum value** increases Fervor by 1 step after resolution.

This rule applies uniformly to all Fervor-tagged dice:
- **Real Fervor dice** — additive, not part of the normal Keep; each one that rolls maximum contributes 1 escalation step.
- **Substitution-tagged dice** — part of the normal pool and subject to Keep; they may be discarded from the final kept pool, but still count for Fervor escalation if they rolled maximum.

Escalation is checked **after** the current spell fully resolves (see [Spell Resolution](./spell-resolution.md)).

### Multiple Escalation Steps per Cast
If multiple Fervor-tagged dice roll their maximum value in the same spell resolution, Fervor increases by 1 step for **each** such die.

A single cast may increase Fervor by multiple steps. There is no per-cast cap on escalation steps.

This is intentional: overcommitting more Fervor-tagged dice creates proportionally higher risk.

### Step Track
Each escalation step advances Fervor one position along the track: **d4 -> d6 -> d8 -> d10**.

If the resulting Fervor level would exceed the current Ingenuity cap, Burnout is triggered instead (see [Burnout](./burnout.md)).
