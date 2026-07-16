# Defense and Guard

## Three Defensive Pools
- **Stance** -> from Negation
- **Resolve** -> from Ingenuity
- **Stamina** -> from Dominion

If unspecified, default to **Stance**.

## Triggering Defense
A hostile action triggers the relevant defense roll.
The defender:
1. builds the pool from the relevant defensive stat
2. rolls
3. applies Keep
4. applies Flat if relevant
5. creates Guard from the final total

## Guard Is Active
Guard is rolled, generated, and consumed.
It is not a passive armor value.

## One Roll per Pool per Turn
Each defense pool may normally be rolled once per stat per round.

Once rolled, that pool remains active and absorbs pressure until:
- it is depleted (Guard reaches 0 or lower), or
- the round ends.

If the same pool is pressured again in the same round, do not re-roll it by default — the existing Guard value absorbs the new pressure.

Features or nodes may explicitly allow extra rolls or exceptions.

## Multiple Different Pools in One Turn
If a character must roll different defense pools in the same round,
each additional defensive roll takes cumulative disadvantage.

> _Prototype status: cumulative disadvantage on 2nd+ pools is **deferred** — not yet implemented in code (tracked in `docs/project-status.md` → Future). Each pool currently rolls independently, with no stacking penalty._

## Guard Reset
Guard resets at the **start of each new round**.
Any remaining Guard from the previous round does not carry over.

## Consuming Guard
When hostile pressure hits a Guard pool:
- subtract the hostile total from current Guard
- if Guard remains above 0, the pool still holds
- if Guard reaches 0 or lower, the defense is breached

## Defense Keep and Defense Nodes

Each pool's Keep grade equals the purchased level of its branch defense node
(the training grade is the floor; enemies use training only):
- **Stance** → Stance Guard (Negation)
- **Resolve** → Resolve Guard (Ingenuity)
- **Stamina** → Stamina Guard (Dominion)

Level 1 of each defense node is granted free at run start. Higher levels also
carry a branch-flavored rider:

| Node | L2 rider | L3 rider |
|---|---|---|
| Stamina Guard (Dominion) | +1 Max Wounds | — |
| Resolve Guard (Ingenuity) | Magic Shield, 1 charge | Magic Shield, 2 charges |
| Stance Guard (Negation) | +2 flat on Stance guard | +1 Negation die on every defense pool |

Rider scope rule: wound-layer riders are global, charge actives are global by
trigger, passive number riders stay on the home pool until L3.

## Magic Shield (Resolve Guard L2+)

When any of the player's guards **would break** (incoming total >= current Guard),
the player may spend a Magic Shield charge BEFORE the breach commits:
1. roll N Ingenuity-size dice, where N = Resolve Guard purchased level;
2. add the total to that pool's current Guard;
3. re-check the breach — the shield can fail.

Rules:
- Works on **every** pool — protecting the caster's weak pools is its point.
- One prompt per attack; it never auto-fires (the player judges the odds).
- Guard-layer only: effects that deal wounds directly without pressuring a
  Guard pool cannot be shielded.
- Charges per combat: L2 = 1, L3 = 2.

## Negation Cross-Pool Die (Stance Guard L3)

Stance Guard L3 adds one Negation-size die to **every** defense pool roll.
The die is added (the pool grows by one die), not substituted. Keep is
unchanged — the extra die contributes through keep selection.
