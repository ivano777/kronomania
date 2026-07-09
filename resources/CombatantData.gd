# CombatantData — immutable configuration for a single combatant.
# Set in .tres files; loaded at runtime by BattleScene.
# Does NOT hold runtime state (wounds, guard). That lives in CombatManager.
class_name CombatantData
extends Resource

## Display name shown in the HUD and combat log.
@export var combatant_name: String = "Unknown"

## Tier determines base pool size: Tier 1 = 1 die, Tier 2 = 2 dice, etc.
@export_range(1, 4) var tier: int = 1

## Dominion die face used for offensive rolls (d4=4, d6=6, d8=8, d10=10).
@export_enum("4", "6", "8", "10") var dominion_size: int = 4

## Negation die face used for Stance defense rolls.
@export_enum("4", "6", "8", "10") var negation_size: int = 4

## Ingenuity die face used for Resolve defense rolls.
@export_enum("4", "6", "8", "10") var ingenuity_size: int = 4

## Training grade for Keep: N = keep N dice (1 = keep 1, 2 = keep 2, 3 = keep 3).
@export_range(1, 3) var keep_grade: int = 1

## Velocity Threshold: static timing threshold authored on the ENEMY only.
## Only the player's action roll is compared to the enemy's VT.
## Player >= VT → Fast (acts first); Player < VT → Slow (enemy acts first).
## This field has no effect on player combatants.
@export_range(1, 25) var velocity_threshold: int = 12

## Maximum Wounds before Defeat.
@export_range(1, 6) var max_wounds: int = 3

## Optional equipped weapon. Applies Forging/Warding flat bonuses,
## Fortitude max-wounds bonus, Surge/Drain pool modifier, and stores tags.
@export var equipped_weapon: EquipmentData = null

## Constellation nodes this combatant starts with.
## keep_grade above is used as fallback when no Training node provides a value.
@export var starting_nodes: Array[NodeData] = []

## Fallback action modifiers used when no weapon is equipped or weapon lacks the action key.
@export var bare_hands_actions: Array[ActionModifier] = []


## Returns the bare-hands modifier for action_key. Uses stored entry if present; otherwise
## returns a named zero-stat stub so every creature always has bare-hands coverage.
func get_bare_hands_modifier(action_key: String) -> ActionModifier:
	for mod in bare_hands_actions:
		if mod.action_key == action_key:
			return mod
	var stub := ActionModifier.new()
	stub.action_key = action_key
	stub.action_name = "Bare Hands"
	return stub
