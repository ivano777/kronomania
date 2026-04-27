extends VBoxContainer

@onready var _toggle: Button = $ToggleButton
@onready var _panel: VBoxContainer = $Panel
@onready var _status: Label = $Panel/StatusLabel
@onready var _pts_minus: Button = $Panel/PointsRow/PointsMinusBtn
@onready var _pts_label: Label = $Panel/PointsRow/PointsLabel
@onready var _pts_plus: Button = $Panel/PointsRow/PointsPlusBtn
@onready var _pts_max: Button = $Panel/PointsRow/PointsSetMaxBtn
@onready var _budget_reset: Button = $Panel/BudgetResetBtn
@onready var _reset_all: Button = $Panel/ResetAllBtn

var _tier_btns: Array = []


func _ready() -> void:
	_tier_btns = [
		$Panel/TierRow/Tier1Btn,
		$Panel/TierRow/Tier2Btn,
		$Panel/TierRow/Tier3Btn,
		$Panel/TierRow/Tier4Btn,
	]
	_toggle.pressed.connect(_on_toggle)
	_pts_minus.pressed.connect(_on_pts_minus)
	_pts_plus.pressed.connect(_on_pts_plus)
	_pts_max.pressed.connect(_on_pts_max)
	for i in 4:
		_tier_btns[i].pressed.connect(_on_tier_pressed.bind(i + 1))
	_budget_reset.pressed.connect(_on_budget_reset)
	_reset_all.pressed.connect(_on_reset_all)
	_sync()
	visible = DebugManager.enabled
	DebugManager.debug_mode_changed.connect(func(en: bool) -> void: visible = en)


func _on_toggle() -> void:
	_panel.visible = !_panel.visible
	_toggle.text = "★ Prog ▾" if _panel.visible else "★ Prog ▸"


func _on_pts_minus() -> void:
	PlayerProgression.debug_set_points(PlayerProgression.available_points - 1)
	_sync()


func _on_pts_plus() -> void:
	PlayerProgression.debug_set_points(PlayerProgression.available_points + 1)
	_sync()


func _on_pts_max() -> void:
	PlayerProgression.debug_set_points(99)
	_sync()


func _on_tier_pressed(t: int) -> void:
	PlayerProgression.debug_set_tier(t)
	_sync()


func _on_budget_reset() -> void:
	PlayerProgression.tier_combat_spent = 0
	PlayerProgression.tier_flavor_spent = 0
	_sync()


func _on_reset_all() -> void:
	PlayerProgression.reset()
	_sync()


func _sync() -> void:
	var pts: int = PlayerProgression.available_points
	var tier: int = PlayerProgression.get_tier()
	_status.text = "Points: %d  Tier: %d" % [pts, tier]
	_pts_label.text = "Pts: %d" % pts
	for i in 4:
		_tier_btns[i].text = "[T%d]" % (i + 1) if tier == i + 1 else "T%d" % (i + 1)
	var scene: Node = get_tree().current_scene
	if scene.has_method("_refresh"):
		scene._refresh()
