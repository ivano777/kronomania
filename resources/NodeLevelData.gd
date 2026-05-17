# NodeLevelData — per-level mechanical data for a Constellation node.
# Nested sub-resource inside NodeData.levels_data.
class_name NodeLevelData
extends Resource

## 1-based level number this entry describes.
@export var level_index: int = 1

## Slot cost to purchase this level (2 for Core nodes, 1 for others).
@export_range(1, 5) var cost: int = 1

## Minimum player Tier required before this level may be purchased.
@export_range(1, 4) var required_tier: int = 1

## Prerequisite nodes required to unlock this level.
## Each entry: {"node_id": String, "required_level": int}. All must be satisfied.
@export var prerequisites: Array = []

## Human-readable description of the effect granted at this level.
@export_multiline var level_effect_description: String = ""

## Effect type key used by CombatManager to apply the mechanical effect.
@export var effect_type: String = ""

## Numeric value for the effect (stat die face, keep grade, flat bonus, etc.).
@export var effect_value: int = 0

## Stat name this effect targets (e.g. "dominion"), if applicable.
@export var stat: String = ""

## Weapon tags that must all be present on the equipped weapon for this effect to apply.
## Empty = no weapon restriction.
@export var weapon_tags: PackedStringArray = []

## Number of uses per combat for reactive abilities (0 = passive / unlimited).
@export var uses_per_combat: int = 0

## Spells and cantrips granted when this level is reached.
@export var spells: Array[SpellData] = []

## Spell bonus effects applied at spell resolution when a spell's tags match.
@export var bonus_effects: Array[SpellBonusEffect] = []

## Post-resolution spell effects (debuffs, status application) dispatched after
## the attack outcome is determined. Empty on all existing nodes; wired in Group B.
@export var outcome_effects: Array[SpellOutcomeEffect] = []
