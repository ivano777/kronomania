# Magic Overview

Magic uses the same shared action engine as the rest of the game, but true spellcasting adds the **Fervor** subsystem.

The system distinguishes between:
- **True Spells**
- **Cantrips**

True spells are riskier and stronger.
Cantrips are safer and simpler.

## Spellcasting Node Structure

### Cantrip Access
The **Minor Studies** node unlocks cantrip use and directly grants a set of generic cantrips (see [Cantrips](./cantrips.md)).
Additional cantrips may be granted by spell school nodes.
Cantrips do not require the Spellcasting node.

### True Spellcasting Access
The **Spellcasting** node (L1-L3, prerequisite: Minor Studies) unlocks the real Fervor die and directly grants true spells:
- **L1**: grants Arcane Missile (vs Stance) and Arcane Mark (vs Resolve)
- **L2**: all arcane spells gain Keep 2; Arcane Missile +1 flat; Arcane Mark breach → enemy Stance flat −2
- **L3**: all arcane spells gain Keep 3; Arcane Missile +2 flat total; Arcane Mark breach also → enemy Stance keep −1 (Frattura Totale)

Progressive keep bonuses are applied via `SpellBonusEffect` entries on each node level and stack additively.
