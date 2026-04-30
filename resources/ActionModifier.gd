class_name ActionModifier
extends Resource

@export var action_key: String = ""
@export var action_name: String = ""
## Caps the effective tier for this action. 0 = uncapped.
@export var tier_cap: int = 0
@export var flat_bonus: int = 0
@export var keep_bonus: int = 0
@export var pool_bonus: int = 0
## Derived-action stub: parent action whose modifiers scale into this one.
@export var parent_action_key: String = ""
## Derivation ratio applied to parent's bonuses (floor). 0.0 = not derived.
@export var derivation_ratio: float = 0.0
## Rest type for limited-use actions: "" = passive, "combat" | "short" | "long".
@export var rest_type: String = ""
## Uses available per rest. 0 = passive/unlimited.
@export var uses_per_rest: int = 0
