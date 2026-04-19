# Wounds and Massive Damage

This file defines breach severity once Guard fails.

## Broken Guard
If hostile pressure reduces Guard to 0 or less:
- the target suffers **1 Wound**

## Massive Overflow
If overflow beyond broken Guard exceeds the relevant defensive Size,
the result becomes **massive**.

A result is **Massive** when:

**(final total - relevant Guard) > relevant defensive Size**

Where "relevant defensive Size" is the numeric face value of the triggered defensive stat (e.g., d8 = 8, d10 = 10).

Default direct-harm consequence of a massive result:
- **2 Wounds** instead of 1

The same massive-threshold logic applies consistently to:
- direct damage overflow
- stronger soft CC outcomes (see [Soft CC](./soft-cc.md))
- severe magical effects
- any other rule that would otherwise use vague "critical" language

## Player Character Wounds and Defeat

Player characters start with:
- **Max Wounds = 3**

Some nodes or features may increase Max Wounds.

**Defeat condition:** when accumulated Wounds >= Max Wounds, the character is **Defeated**.

## Enemy Wounds Guideline

Enemies do not need the same structured tracking as player characters.
A general guideline:
- Minor enemies: treat 1 Wound as defeat.
- Standard enemies: 2–3 Wounds before defeat.
- Major / boss enemies: 4+ Wounds, or use a tiered threshold instead.

The exact values are set per encounter or enemy type, not as a global baseline.
