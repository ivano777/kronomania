# Initiative and Speed

The game does not rely on a fixed initiative list.
Action timing is determined by **Velocity Threshold (VT)**.

## Velocity Threshold

VT is a **static authored value belonging to the enemy or target**.
It represents the timing pressure of the encounter — how demanding it is to act quickly against this opponent.

The actor rolls their action.
The final action total is compared against the **target's VT**:
- **>= VT → Fast** (resolves in the Fast Phase)
- **< VT → Slow** (resolves in the Slow Phase)

The player character has **no authored VT of their own**.
Player timing is determined entirely by the action roll vs the enemy's static VT.

## VT as a Target Property

VT belongs to the enemy, not to the acting character.

The enemy's speed is encoded in the VT value itself — a high VT means a fast enemy, a low VT means a slow one.
Only the player's action roll is compared to the enemy's VT.
The enemy does not roll to determine its own timing; its phase position is implicit in the VT.

- **Player Fast** (roll >= VT) → player acts before the enemy.
- **Player Slow** (roll < VT) → enemy acts before the player.

Typical VT ranges by enemy type:

| Type | VT |
|---|---|
| Slow / Horde | 10 |
| Average / Veteran | 12–14 |
| Fast / Boss | 15–18 |
| Extreme / Superhuman | 20+ |

## Fast and Slow

Slow does not automatically mean failure.
It means the action resolves later in the round, after Fast actions have landed.

## Round Flow

A typical round has four broad phases:
1. Declared actions
2. Fast resolution
3. Threat resolution
4. Slow resolution

## Timing vs Success

VT answers **when**.
Guard and opposition answer **whether**.
