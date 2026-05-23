# Legacy Archive

This appendix stores abandoned or superseded ideas that may still be useful as future optional modules.

Nothing here overrides the active rules.

---

## Removed in Phase B2: Fire Magic and Arcane Schools

The following spell school nodes and their associated spells were removed when the Ingenuity branch was reworked around the Spellcasting node (L1–L3). The designs are preserved here in case they inform future modular content.

### Fire Magic I–IV

A tiered school granting fire-tagged spells and `SpellBonusEffect` bonuses:
- **Fire Magic I** (T1, prereq: spellcasting): granted Sparks (cantrip, vs Stance, Ingenuity, tags: fire)
- **Fire Magic II** (T2, prereq: fire_magic_1 + spellcasting + dom_core L1): granted Fire Orb (true spell, vs Stance, pure Ingenuity); +1 pool to all fire spells
- **Fire Magic III** (T2, prereq: fire_magic_2 + dom_core L2): granted Fireball (aspect_stat=dominion, aspect_dice=1, vs Stance)
- **Fire Magic IV** (T4, prereq: fire_magic_3): granted Wall of Fire (dominion aspect, vs Stance) + Meteor (aspect_dice=2, vs Stance); +1 keep to all fire spells

### Arcane I–III

A tiered school granting arcane-tagged spells:
- **Arcane I** (T2, prereq: spellcasting + ing_core L1): granted Arcane Missile (pure Ingenuity, vs Stance)
- **Arcane II** (T2, prereq: arcane_1): granted Mind Spike (pure Ingenuity, vs Resolve)
- **Arcane III** (T3, prereq: arcane_2): granted Void Bolt (pure Ingenuity, flat+2, vs Stance)

### Why removed

The school system created too many required gate nodes before accessing useful spells (e.g. 4 nodes to reach Meteor). The Spellcasting L1-L3 redesign collapses the core arcane path into a single multi-level node that grants spells directly and upgrades them progressively via SpellOutcomeEffects.
