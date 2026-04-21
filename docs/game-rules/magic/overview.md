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
The **Spellcasting** node (prerequisite: Minor Studies) unlocks the real Fervor die and the ability to cast true spells.
True spells are not granted by the Spellcasting node itself — they are granted by **spell school nodes**.

### Spell Schools
Spell schools are tiered node chains (e.g. Fire Magic I → II → III → IV).
Each tier grants:
- one or more **SpellData** entries (spells unlocked on purchase)
- optional **bonus effects** applying to spells with matching tags (e.g. "+1 pool to fire-tagged spells")

Prerequisites for school tiers combine:
- the previous tier of the same school
- specific **Core stat nodes** (e.g. Dominion d8 required for Fire Magic III)

A character without the Spellcasting node cannot cast true spells from school nodes, even if a school node is unlocked.
