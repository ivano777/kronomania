# NodeData — immutable configuration for a single Constellation node.
# Set in .tres files; referenced by CombatantData.starting_nodes.
class_name NodeData
extends Resource

## Display name shown in the Constellation UI and logs.
@export var node_name: String = ""

## Category: "Core" | "Training" | "Ability" | "Flavor"
@export var category: String = "Training"

## Effect type key used by CombatManager to apply the effect.
## Current values: "training_keep"
@export var effect_type: String = ""

## Numeric value for the effect (e.g. keep grade: 1 or 2).
@export_range(0, 4) var effect_value: int = 0

## Human-readable description shown in the Constellation UI.
@export_multiline var description: String = ""

## Point cost to unlock this node.
@export_range(1, 5) var unlock_cost: int = 1

## All nodes in this array must be unlocked before this node can be purchased (AND logic).
@export var prerequisites: Array[NodeData] = []

## SpellData granted when this node is unlocked (cantrips and true spells).
@export var spells: Array[SpellData] = []

## Bonus effects applied at spell resolution when a spell's tags match.
@export var bonus_effects: Array[SpellBonusEffect] = []
