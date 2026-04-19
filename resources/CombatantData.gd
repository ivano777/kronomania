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
@export_enum("4", "6", "8", "10") var dominion_size: int = 6

## Negation die face used for Stance defense rolls.
@export_enum("4", "6", "8", "10") var negation_size: int = 6

## Training grade for Keep: 0 → keep 1, 1 → keep 2, 2 → keep 3.
@export_range(0, 2) var keep_grade: int = 0

## Velocity Threshold: rolls >= VT are Fast; rolls < VT are Slow.
@export_range(1, 25) var velocity_threshold: int = 12

## Maximum Wounds before Defeat.
@export_range(1, 6) var max_wounds: int = 3
