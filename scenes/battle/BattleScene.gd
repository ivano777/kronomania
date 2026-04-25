# BattleScene — root scene for the 1v1 combat prototype.
# Wires CombatManager signals to HUD nodes and kicks off combat.
extends Control

# ── Combatant data (loaded from .tres resources) ──────────────────────────────
const PLAYER_DATA := preload("res://resources/data/player_default.tres")
const ENEMY_DATA  := preload("res://resources/data/enemy_grunt.tres")

# ── Debug scenes (remove path + add_child call to strip at release) ───────────
const _DBG_WEAPON_SEL   := "res://scenes/debug/DebugWeaponSelector.tscn"
const _DBG_FERVOR_DISP  := "res://scenes/debug/DebugFervorDisplay.tscn"

# ── Node references ───────────────────────────────────────────────────────────
@onready var _player_hud:    CombatantHUD = $GameLayout/PlayerSide/PlayerHUD
@onready var _enemy_hud:     CombatantHUD = $GameLayout/EnemySide/EnemyHUD
@onready var _player_visual: Combatant    = $GameLayout/PlayerSide/PlayerVisual
@onready var _enemy_visual:  Combatant    = $GameLayout/EnemySide/EnemyVisual
@onready var _round_hud:     RoundHUD     = $GameLayout/CenterPanel/RoundHUD
@onready var _defeat_panel:  Panel        = $DefeatPanel
@onready var _result_label:  Label        = $DefeatPanel/PanelContent/ResultLabel
@onready var _restart_btn:   Button       = $DefeatPanel/PanelContent/RestartButton
@onready var _debug_equip                 = $DebugEquipmentDisplay if has_node("DebugEquipmentDisplay") else null


func _ready() -> void:
	_defeat_panel.hide()

	# Set up visuals.
	_player_visual.setup(PLAYER_DATA, true)
	_enemy_visual.setup(ENEMY_DATA, false)

	# Set up HUDs with initial data. Player HUD shows the Fervor row.
	_player_hud.setup(PLAYER_DATA, true)
	_enemy_hud.setup(ENEMY_DATA, false)

	if _debug_equip:
		_debug_equip.setup(PLAYER_DATA, ENEMY_DATA)

	# Connect RoundHUD action buttons/selections.
	_round_hud.strike_pressed.connect(_on_strike_pressed)
	_round_hud.cantrip_selected.connect(_on_cantrip_selected)
	_round_hud.spell_selected.connect(_on_spell_selected)
	_round_hud.wound_degrade_chosen.connect(_on_wound_degrade_chosen)

	# Pass known spells to RoundHUD before combat starts.
	_round_hud.set_spell_lists(
		PlayerProgression.get_known_spells(),
		PlayerProgression.get_known_cantrips()
	)

	# Connect restart button.
	_restart_btn.pressed.connect(_on_restart_pressed)

	# Constellation navigation button (top-right corner, always accessible).
	var c_btn := Button.new()
	c_btn.text = "Constellation"
	c_btn.anchor_left   = 1.0
	c_btn.anchor_right  = 1.0
	c_btn.anchor_top    = 0.0
	c_btn.anchor_bottom = 0.0
	c_btn.offset_left   = -150.0
	c_btn.offset_top    = 10.0
	c_btn.offset_right  = -10.0
	c_btn.offset_bottom = 44.0
	c_btn.pressed.connect(_on_constellation_pressed)
	add_child(c_btn)

	# Connect CombatManager signals.
	CombatManager.log_message.connect(_on_log)
	CombatManager.round_started.connect(_on_round_started)
	CombatManager.phase_changed.connect(_on_phase_changed)
	CombatManager.wounds_changed.connect(_on_wounds_changed)
	CombatManager.guard_changed.connect(_on_guard_changed)
	CombatManager.combat_ended.connect(_on_combat_ended)
	CombatManager.player_action_required.connect(_on_player_action_required)
	CombatManager.player_magic_available.connect(_on_player_magic_available)
	CombatManager.fervor_changed.connect(_on_fervor_changed)
	CombatManager.player_massive_incoming.connect(_on_player_massive_incoming)

	# Debug widgets — instantiated at runtime; safe to remove with the consts above.
	if ResourceLoader.exists(_DBG_WEAPON_SEL):
		add_child((load(_DBG_WEAPON_SEL) as PackedScene).instantiate())
	if ResourceLoader.exists(_DBG_FERVOR_DISP):
		add_child((load(_DBG_FERVOR_DISP) as PackedScene).instantiate())

	# Start combat.
	CombatManager.start_combat(PLAYER_DATA, ENEMY_DATA)


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_log(text: String) -> void:
	_round_hud.add_log(text)


func _on_round_started(round_num: int) -> void:
	_round_hud.set_round(round_num)


func _on_phase_changed(phase_name: String) -> void:
	_round_hud.set_phase(phase_name)


func _on_wounds_changed(is_player: bool, current: int, max_wounds: int) -> void:
	if is_player:
		_player_hud.set_wounds(current, max_wounds)
	else:
		_enemy_hud.set_wounds(current, max_wounds)


func _on_guard_changed(is_player: bool, pool: String, guard_value: int) -> void:
	if is_player:
		_player_hud.set_guard(pool, guard_value)
	else:
		_enemy_hud.set_guard(pool, guard_value)


func _on_combat_ended(winner_name: String) -> void:
	_round_hud.disable_strike()
	_round_hud.disable_magic()
	_result_label.text = "Winner: %s" % winner_name
	_defeat_panel.show()


func _on_player_action_required() -> void:
	_round_hud.enable_strike()


func _on_player_magic_available(can_cantrip: bool, can_cast_spell: bool) -> void:
	_round_hud.enable_magic(can_cantrip, can_cast_spell)


func _on_fervor_changed(is_player: bool, fervor_size: int, fervor_cap: int, is_burned_out: bool) -> void:
	if is_player:
		_player_hud.set_fervor(fervor_size, fervor_cap, is_burned_out)


func _on_player_massive_incoming(charges_left: int) -> void:
	_round_hud.show_massive_prompt(charges_left)


func _on_wound_degrade_chosen(use_charge: bool) -> void:
	CombatManager.player_chose_degrade_wound(use_charge)


func _on_strike_pressed() -> void:
	CombatManager.player_chose_strike(_round_hud.get_net_advantage(), _round_hud.get_target_pool(), _round_hud.get_brutal_trade())


func _on_cantrip_selected(spell: SpellData) -> void:
	CombatManager.player_chose_cantrip(spell)


func _on_spell_selected(spell: SpellData) -> void:
	CombatManager.player_chose_spell(spell)


func _on_restart_pressed() -> void:
	_teardown_signals()
	get_tree().reload_current_scene()


func _on_constellation_pressed() -> void:
	_teardown_signals()
	get_tree().change_scene_to_file("res://scenes/constellation/ConstellationScene.tscn")


func _teardown_signals() -> void:
	CombatManager.log_message.disconnect(_on_log)
	CombatManager.round_started.disconnect(_on_round_started)
	CombatManager.phase_changed.disconnect(_on_phase_changed)
	CombatManager.wounds_changed.disconnect(_on_wounds_changed)
	CombatManager.guard_changed.disconnect(_on_guard_changed)
	CombatManager.combat_ended.disconnect(_on_combat_ended)
	CombatManager.player_action_required.disconnect(_on_player_action_required)
	CombatManager.player_magic_available.disconnect(_on_player_magic_available)
	CombatManager.fervor_changed.disconnect(_on_fervor_changed)
	CombatManager.player_massive_incoming.disconnect(_on_player_massive_incoming)
