# Spell Resolution

True spells use the shared action engine with the Fervor subsystem layered on top.

## Full Resolution Order

1. **Conduit check:** true spells require an equipped `[MagicFocus]` item (empty hands are not enough — see [Equipment — Tags](../core/equipment.md)). Then determine the **normal spell pool** from full Tier (+ Advantage/Disadvantage) plus the chosen casting tool's bonuses; items never cap Tier (see [Ingenuity Branch Rework](../ingenuity-rework-overview.md)).
2. Split the normal pool into **aspect dice** and **Ingenuity-tagged dice** per the spell's `aspect_dice` count.
   - `aspect_dice` dice use the spell's `aspect_stat` die size.
   - The remaining `(Tier − aspect_dice)` dice use Ingenuity die size and are **Fervor-tagged**.
   - Pure-Ingenuity spells (`aspect_dice = 0`) treat all pool dice as Ingenuity-tagged.
3. **Roll** all normal pool dice combined.
4. Apply normal **Keep** (best `keep_count` from the combined pool, regardless of type).
5. **Roll the real Fervor die** (additive, post-Keep, cannot be discarded).
6. **Sum**: kept total + Fervor die result.
7. Apply **Flat modifiers** (from spell `flat_bonus` + school bonus effects).
8. **Resolve outcome** (compare against Guard, apply effects).
9. After resolution, count **escalation steps**: one step per Ingenuity-tagged die (pre-Keep) that rolled its maximum, plus one step if the Fervor die rolled its maximum. A single cast may escalate Fervor by multiple steps.
10. If the new Fervor level would exceed the current Ingenuity cap, the caster enters **Burnout**.
11. The Fervor value is clamped at the cap; it does not rise above it.

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
