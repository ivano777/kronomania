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
