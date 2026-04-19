# Spell Resolution

True spells use the shared action engine with the Fervor subsystem layered on top.

## Full Resolution Order

1. Determine the **normal spell pool** from Tier.
2. Apply **Advantage / Disadvantage / Desperation** to the normal pool.
3. Apply **substitutions** to the normal pool (convert applicable dice to Ingenuity-based Fervor-tagged dice).
4. **Roll** the normal pool.
5. Apply normal **Keep**.
6. **Roll the real Fervor dice** (additive, not part of the normal pool).
7. **Sum**: kept normal total + total of all real Fervor dice.
8. Apply **Flat modifiers**.
9. **Resolve outcome** (compare against Guard, apply effects).
10. After resolution, check all **Fervor-tagged dice**: for each one that rolled its maximum value, increase Fervor by 1 step. If multiple Fervor-tagged dice rolled maximum, Fervor increases by 1 step per die — a single cast may increase Fervor by multiple steps (see [Fervor — General Escalation Rule](./fervor.md#general-escalation-rule)).
11. If the new Fervor level would exceed the current Ingenuity cap, the caster enters **Burnout**.
12. The Fervor value is clamped at the cap; it does not rise above it.

## Timing
True spells follow normal VT timing.

## Defense Targeting
Typical mapping:
- direct magical force -> **Stance**
- mental / control pressure -> **Resolve**
- bodily overpowering / draining / transformation -> **Stamina**

## Failure
A spell fails as an effect if it does not overcome the relevant Guard or target condition.

## Desperation and Fervor Dice
Desperation applies to the **normal pool only**.
Real Fervor dice are still rolled as additive dice afterward, unaffected by Desperation.
Substitution dice are part of the normal pool and are affected by Desperation like any other normal pool dice.

## Notes
- See [Fervor](./fervor.md) for escalation rules and the distinction between real Fervor dice and substitution dice.
- See [Burnout](./burnout.md) for what happens when Burnout is triggered.
