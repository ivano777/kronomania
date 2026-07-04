class_name CombatantState
extends RefCounted

# Per-combat runtime state for a single combatant (player or enemy).
#
# Extracted verbatim from CombatManager (Phase 1 of the CombatManager refactor). This is the
# mutable per-combat state container; CombatantData (.tres) remains immutable config. All
# combat logic lives in CombatManager and the combat/* modules — this class holds data plus
# trivial pool accessors only.

var data: CombatantData
var current_wounds: int = 0
var max_wounds: int     = 3
var is_defeated: bool   = false
var weapon_override: EquipmentData = null      # main-hand override; null = use data.equipped_weapon
var off_hand_override: EquipmentData = null    # off-hand override; null = no off-hand equipped
var node_levels: Dictionary = {}           # NodeData → int; runtime copy from PlayerProgression for player
var tier_override: int = 0                 # when > 0, overrides data.tier (used for player Tier from Constellation)
# Per-pool guard state (Stance / Resolve / Stamina).
var stance_guard: int   = 0
var resolve_guard: int  = 0
var stamina_guard: int  = 0
var stance_rolled: bool  = false
var resolve_rolled: bool = false
var stamina_rolled: bool = false
# Magic state — player only; resets to base each combat.
var fervor_size: int    = 4     # current Fervor die face (4/6/8/10); starts at d4
var is_burned_out: bool = false # blocks true spells when true
var has_minor_studies: bool = false  # derived from unlocked_nodes in start_combat()
var has_spellcasting: bool  = false  # derived from unlocked_nodes in start_combat()
var known_spells: Array   = []  # Array[SpellData] — non-cantrip spells, player only
var known_cantrips: Array = []  # Array[SpellData] — cantrip spells, player only
var space_domination_active: bool = false  # Melee L2: Advantage on first Stamina guard roll each combat
var item_action_charges: Dictionary = {}   # action_key → remaining uses (from ActionModifier.uses_per_rest)
var active_statuses: Array[CombatStatus] = []
var interrupt_handlers: Array[InterruptHandler] = []
## Single-use debuffs queued by SpellOutcomeEffect; consumed on the next guard roll
## for the matching pool. { "<pool>": { "flat": int, "keep": int } }
var pending_guard_debuffs: Dictionary = {}

func init(d: CombatantData) -> void:
	data = d
	current_wounds = 0
	max_wounds = d.max_wounds + (d.equipped_weapon.max_wounds_bonus if d.equipped_weapon else 0)
	is_defeated = false
	node_levels.clear()
	for n in d.starting_nodes:
		if n is NodeData:
			node_levels[n as NodeData] = 1
	fervor_size = 4
	is_burned_out = false
	has_minor_studies = false
	has_spellcasting = false
	space_domination_active = false
	active_statuses = []
	interrupt_handlers = []
	pending_guard_debuffs = {}
	reset_guard()

func reset_guard() -> void:
	stance_guard = 0;  resolve_guard = 0;  stamina_guard = 0
	stance_rolled = false; resolve_rolled = false; stamina_rolled = false

func get_guard(pool: String) -> int:
	match pool:
		"stance":  return stance_guard
		"resolve": return resolve_guard
		"stamina": return stamina_guard
	return 0

func set_guard_val(pool: String, value: int) -> void:
	match pool:
		"stance":  stance_guard  = value
		"resolve": resolve_guard = value
		"stamina": stamina_guard = value

func is_pool_rolled(pool: String) -> bool:
	match pool:
		"stance":  return stance_rolled
		"resolve": return resolve_rolled
		"stamina": return stamina_rolled
	return false

func set_pool_rolled(pool: String, value: bool) -> void:
	match pool:
		"stance":  stance_rolled  = value
		"resolve": resolve_rolled = value
		"stamina": stamina_rolled = value
