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
