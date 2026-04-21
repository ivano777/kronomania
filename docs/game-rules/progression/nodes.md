# Nodes

Nodes are the smallest meaningful progression units in the system.

A node may:
- raise stable stats
- improve training grade
- unlock cantrips or spells
- add utility
- add flavor
- create an exception to baseline rules

## Nodes and Keep
Training nodes often define:
- whether a discipline is unlocked
- what Keep grade that discipline uses

## Nodes and Exceptions
Baseline rules stay simple.
Exceptions usually live in nodes.

## Prerequisites
A node may require one or more other nodes to be unlocked before it can be purchased.
All listed prerequisites must be satisfied simultaneously — they are AND conditions.

Examples:
- A spell school tier may require the previous school tier AND a Core stat node.
- The Spellcasting node requires Minor Studies.

## Spell School Nodes
Spell school nodes grant:
- `spells: Array[SpellData]` — one or more spells unlocked on purchase
- `bonus_effects: Array[SpellBonusEffect]` — optional bonuses applied at spell resolution

`SpellBonusEffect` fields: `tag` (matches spell tags), `bonus_type` (`"pool"` or `"keep"`), `value` (integer), `stat` (which stat the pool/keep bonus applies to).

Bonuses are cumulative across all unlocked nodes and apply only to spells whose tags match.

## Minor Studies
Minor Studies unlocks cantrip use and directly grants a set of generic cantrips.
*Deferred: grade tiers (Minor Studies I / II) and Ingenuity-based slot formula.*

## Unarmed Combat Node Pattern

Bare hands are always available as implicit equipment with **Potency 1** (Tier expression capped at 1).
The Unarmed Combat node is tiered. Each tier raises the bare-hands Potency cap by 1 step and may unlock unarmed-specific skills, abilities, or features.

Use this progression consistently:

| Node | Potency Cap | May Unlock |
|---|---|---|
| Unarmed Combat (Unlock / Grade 0) | 2 | basic unarmed strikes |
| Unarmed Combat I (Grade 1) | 3 | additional unarmed skills |
| Unarmed Combat II (Grade 2) | 4 (full Tier at T4) | advanced unarmed skills |

Bare hands carry no weapon tags and cannot satisfy tag prerequisites on skills.
