# CombatantHUD — displays one combatant's name, wound slots, current Guard, and Fervor (player only).
class_name CombatantHUD
extends VBoxContainer

const COLOR_WOUND_EMPTY  := Color(0.25, 0.25, 0.25, 1.0)
const COLOR_WOUND_FILLED := Color(0.85, 0.10, 0.10, 1.0)
const COLOR_WOUND_HIDDEN := Color(0.0, 0.0, 0.0, 0.0)

# Stub status squares — one per active status, colored by status_id.
# Replaced by real pixel icons later (assets/sprites/icons/statuses/).
const STATUS_SQUARE_SIZE := Vector2(9, 9)
const STATUS_COLORS := {
	"hex_marked":              Color(0.65, 0.25, 0.90, 1.0),  # purple
	"time_locked":             Color(0.20, 0.80, 0.90, 1.0),  # cyan
	"echoing_spell":           Color(0.55, 0.90, 0.30, 1.0),  # green
	"mind_detonation_primed":  Color(0.95, 0.55, 0.15, 1.0),  # orange
}
const STATUS_COLOR_FALLBACK := Color(0.75, 0.75, 0.75, 1.0)

@onready var _name_label:     Label         = $NameLabel
@onready var _wound_slots:    HBoxContainer = $WoundsRow/WoundSlots
@onready var _stance_value:   Label         = $StanceRow/StanceValue
@onready var _resolve_value:  Label         = $ResolveRow/ResolveValue
@onready var _stamina_value:  Label         = $StaminaRow/StaminaValue
@onready var _fervor_row:     HBoxContainer = $FervorRow
@onready var _fervor_value:   Label         = $FervorRow/FervorValue
@onready var _status_row:     HBoxContainer = $StatusRow

var _slot_nodes: Array[ColorRect] = []
var _max_wounds: int = 3
var _weapon_label: Label
var _status_signature: String = ""


func _ready() -> void:
	for child in _wound_slots.get_children():
		if child is ColorRect:
			_slot_nodes.append(child as ColorRect)
	_weapon_label = Label.new()
	add_child(_weapon_label)


# Call once after instantiation to bind combatant data.
# show_fervor: pass true for the player HUD to enable the Fervor row.
func setup(data: CombatantData, show_fervor: bool = false) -> void:
	_name_label.text = data.combatant_name
	_max_wounds = data.max_wounds
	_refresh_wounds(0)
	set_guard("stance",  0)
	set_guard("resolve", 0)
	set_guard("stamina", 0)
	_fervor_row.visible = show_fervor


# Update wound slot display. current = wounds taken so far.
func set_wounds(current: int, max_wounds: int) -> void:
	_max_wounds = max_wounds
	_refresh_wounds(current)


# Update the guard value label for a specific pool.
func set_guard(pool: String, value: int) -> void:
	match pool:
		"stance":  _stance_value.text  = str(value)
		"resolve": _resolve_value.text = str(value)
		"stamina": _stamina_value.text = str(value)


func set_weapon_display(weapon: EquipmentData) -> void:
	if weapon == null:
		_weapon_label.text = ""
		return
	var tags := ", ".join(Array(weapon.tags)) if weapon.tags.size() > 0 else "—"
	_weapon_label.text = "%s  [%s]" % [weapon.item_name, tags]


# Rebuild the status squares row. One colored square per active status; hover
# shows the status tooltip. Skips the rebuild when nothing changed so a square
# being hovered isn't freed under the cursor by the frequent refresh calls.
func set_statuses(statuses: Array) -> void:
	var signature := ""
	for s in statuses:
		var status := s as CombatStatus
		signature += "%s:%d;" % [status.status_id, status.duration_rounds]
	if signature == _status_signature:
		return
	_status_signature = signature

	for child in _status_row.get_children():
		child.queue_free()

	_status_row.visible = not statuses.is_empty()
	for s in statuses:
		var status := s as CombatStatus
		var square := ColorRect.new()
		square.custom_minimum_size = STATUS_SQUARE_SIZE
		square.color = STATUS_COLORS.get(status.status_id, STATUS_COLOR_FALLBACK) as Color
		square.mouse_filter = Control.MOUSE_FILTER_PASS
		_status_row.add_child(square)
		TooltipManager.attach_hover(square, status)


# Update the Fervor row. Only meaningful for the player HUD.
func set_fervor(size: int, cap: int, is_burned_out: bool) -> void:
	var burnout_tag := "  [BURNOUT]" if is_burned_out else ""
	_fervor_value.text = "d%d / d%d%s" % [size, cap, burnout_tag]


func _refresh_wounds(current: int) -> void:
	# Grow the slot pool if max_wounds exceeds the baked-in scene nodes.
	while _slot_nodes.size() < _max_wounds:
		var slot := ColorRect.new()
		slot.custom_minimum_size = Vector2(10, 10)
		_wound_slots.add_child(slot)
		_slot_nodes.append(slot)

	for i in _slot_nodes.size():
		var slot := _slot_nodes[i]
		if i < _max_wounds:
			slot.visible = true
			slot.color = COLOR_WOUND_FILLED if i < current else COLOR_WOUND_EMPTY
		else:
			slot.visible = false
