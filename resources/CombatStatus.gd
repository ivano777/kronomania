class_name CombatStatus extends Resource

## Temporary state applied to a combatant during combat.
## HARD RULE: data only. Zero functional methods. All processing logic
## lives in CombatManager._process_statuses_hook(), never here.

@export var status_id: String = ""

## Rounds remaining. -1 = permanent until explicitly removed.
@export var duration_rounds: int = 1

## Stat overrides applied by _stat_size() before the base value.
## Example: { "ingenuity_size": 12 }
@export var stat_overrides: Dictionary = {}

## Custom escalation threshold for Fervor. 0 = use FERVOR_TRACK default.
@export var escalation_threshold: int = 0

## Node that applied this status. Used for debug and UI only.
@export var source_node_id: String = ""
