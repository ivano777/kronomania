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

## Node Costs

Each node upgrade (unlocking a level) normally costs **1 Combat slot** from the current tier budget.

**Exception — Core nodes cost 2 Combat slots per upgrade.** All nodes with category **Core** (stat-size upgrades for Dominion, Negation, and Ingenuity) consume 2 slots per level-up. This taxes "must-take" stat growth to create meaningful build tradeoffs and encourage multi-path exploration.

| Category | Slots per upgrade |
|---|---|
| Core | 2 |
| Training | 1 |
| Ability | 1 |
| Flavor | 1 (from Flavor budget, not Combat budget) |

A Core node with `max_level = 3` costs 6 Combat slots total — more than one tier's full budget — to fully max.

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

Bare hands are always available as implicit equipment at full Tier (items never
cap Tier — expressed dice are throttled by keep grades). The Unarmed Combat node
is tiered: each grade unlocks unarmed-specific skills, abilities, or bonuses.

| Node | May Unlock |
|---|---|
| Unarmed Combat (Unlock / Grade 0) | basic unarmed strikes |
| Unarmed Combat I (Grade 1) | additional unarmed skills |
| Unarmed Combat II (Grade 2) | advanced unarmed skills |

*The per-grade skill lists are part of the deferred skill-tree requirement rework.*

Bare hands carry no weapon tags and cannot satisfy tag prerequisites on skills.
Truly empty hands (both slots) do count as a casting conduit for cantrips —
see [Equipment — Tags](../core/equipment.md).
