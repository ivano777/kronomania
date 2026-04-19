# Burnout

Burnout happens when Fervor would rise above the caster's **current modified Ingenuity** cap.

## Trigger
The spell that causes overflow still resolves.
After that:
- Fervor escalation is checked
- if it would exceed the current Ingenuity cap, Burnout begins
- the Fervor value is clamped at the cap and does not rise above it

Burnout is a state transition triggered after spell resolution or an explicit Fervor-escalating effect. It is **not** triggered by passive state drift.

### Ingenuity Reduction and Burnout
If a temporary effect lowers Ingenuity and the Fervor cap shrinks:
- Fervor is clamped to the new cap immediately.
- This clamp-down does **not** trigger Burnout if the actor was not already in Burnout.
- If the actor was already in Burnout, they remain in Burnout until a valid recovery effect removes it.
- See [Fervor — Ingenuity Reduction Interaction](./fervor.md#ingenuity-reduction-interaction) for the full rule.

## Baseline Burnout State
During Burnout:
- true spells are blocked
- cantrips remain available
- Fervor stays at the Size it had reached

Burnout is a spellcasting lock, not a full action lock.

## Exception Space
Nodes may override baseline Burnout.

Example pattern:
- allow true spellcasting during Burnout
- each such spell causes 1 Wound
- if Fervor rolls maximum again during that cast, cause +1 additional Wound
