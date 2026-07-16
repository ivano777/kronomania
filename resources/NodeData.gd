# NodeData — immutable configuration for a Constellation node, with multi-level support.
# Each level's mechanical data lives in a NodeLevelData sub-resource.
# Set in .tres files; referenced by PlayerProgression.ALL_NODES and CombatantData.starting_nodes.
class_name NodeData
extends Resource

## Stable unique identifier used in prerequisite references across nodes.
@export var node_id: String = ""

## Display name shown in the Constellation UI.
@export var display_name: String = ""

## Category: "Core" | "Training" | "Ability" | "Flavor"
@export var category: String = "Training"

## Branch this node's spend counts toward: "dominion" | "negation" | "ingenuity" | "".
## "" (Flavor nodes) counts toward no branch-spend gate.
@export var branch: String = ""

## Flavour description shared across all levels.
@export_multiline var base_description: String = ""

## Optional icon shown in the Constellation UI.
@export var icon: Texture2D

## Maximum level this node can reach (1 for all current single-upgrade nodes).
@export_range(1, 10) var max_levels: int = 1

## Per-level data ordered by level (index 0 = Level 1, index max_levels-1 = Level max_levels).
@export var levels_data: Array[NodeLevelData] = []
