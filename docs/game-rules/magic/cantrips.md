# Cantrips

Cantrips are safe minor-magic actions unlocked through **Minor Studies**.

They do not use the Fervor subsystem.

## Access
A character needs **Minor Studies** (or the **Spellcasting** node) to access the magic action menu and use cantrips.

## Known Cantrips
Cantrips are granted by nodes, not by a formula:
- **Minor Studies** directly grants the generic cantrips on unlock: Arcane Bolt (vs Stance) and Arcane Touch (vs Resolve).

A character knows all cantrips granted by their unlocked nodes. There is no slot limit in the current prototype.

*Deferred: cantrip count formula (Ingenuity-based slot cap) and Minor Studies grade tiers.*

## Pool Building
Cantrips use normal Tier-based pool building: base pool size = full Tier plus the chosen **casting tool**'s bonuses (items never cap Tier). **Conduit requirement:** cantrips need truly empty hands (both slots) OR an equipped `[MagicFocus]` item — see [Ingenuity Branch Rework](../ingenuity-rework-overview.md) → Casting implement system.
The die Size comes from the relevant stat or action rule (default: Ingenuity).
Normal Keep, Advantage, and Disadvantage rules apply.
Cantrips do not use real Fervor dice.

## Action Behavior
Cantrips:
- follow normal VT timing (compare result against Velocity Threshold)
- pressure the appropriate defense pool
- fail if they do not overcome the relevant Guard
- do not use Fervor dice and do not escalate Fervor
- remain available during Burnout
