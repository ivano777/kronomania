# BattleScene — root scene for the 1v1 combat prototype.
# Wires CombatManager signals to HUD nodes and kicks off combat.
extends Control

# ── Combatant data (loaded from .tres resources) ──────────────────────────────
const PLAYER_DATA := preload("res://resources/data/player_default.tres")
const ENEMY_DATA  := preload("res://resources/data/enemy_grunt.tres")

# ── Node references ───────────────────────────────────────────────────────────
@onready var _player_hud:    CombatantHUD = $GameLayout/PlayerSide/PlayerHUD
@onready var _enemy_hud:     CombatantHUD = $GameLayout/EnemySide/EnemyHUD
@onready var _player_visual: Combatant    = $GameLayout/PlayerSide/PlayerVisual
@onready var _enemy_visual:  Combatant    = $GameLayout/EnemySide/EnemyVisual
@onready var _round_hud:     RoundHUD     = $GameLayout/CenterPanel/RoundHUD
@onready var _defeat_panel:  Panel        = $DefeatPanel
@onready var _result_label:  Label        = $DefeatPanel/PanelContent/ResultLabel
@onready var _restart_btn:   Button       = $DefeatPanel/PanelContent/RestartButton


func _ready() -> void:
	_defeat_panel.hide()

	# Set up visuals.
	_player_visual.setup(PLAYER_DATA, true)
	_enemy_visual.setup(ENEMY_DATA, false)

	# Set up HUDs with initial data.
	_player_hud.setup(PLAYER_DATA)
	_enemy_hud.setup(ENEMY_DATA)

	# Connect RoundHUD strike button.
	_round_hud.strike_pressed.connect(_on_strike_pressed)

	# Connect restart button.
	_restart_btn.pressed.connect(_on_restart_pressed)

	# Connect CombatManager signals.
	CombatManager.log_message.connect(_on_log)
	CombatManager.round_started.connect(_on_round_started)
	CombatManager.phase_changed.connect(_on_phase_changed)
	CombatManager.wounds_changed.connect(_on_wounds_changed)
	CombatManager.guard_changed.connect(_on_guard_changed)
	CombatManager.combat_ended.connect(_on_combat_ended)
	CombatManager.player_action_required.connect(_on_player_action_required)

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


func _on_guard_changed(is_player: bool, guard_value: int) -> void:
	if is_player:
		_player_hud.set_guard(guard_value)
	else:
		_enemy_hud.set_guard(guard_value)


func _on_combat_ended(winner_name: String) -> void:
	_round_hud.disable_strike()
	_result_label.text = "Winner: %s" % winner_name
	_defeat_panel.show()


func _on_player_action_required() -> void:
	_round_hud.enable_strike()


func _on_strike_pressed() -> void:
	CombatManager.player_chose_strike()


func _on_restart_pressed() -> void:
	# Disconnect signals before reload to avoid duplicate connections.
	CombatManager.log_message.disconnect(_on_log)
	CombatManager.round_started.disconnect(_on_round_started)
	CombatManager.phase_changed.disconnect(_on_phase_changed)
	CombatManager.wounds_changed.disconnect(_on_wounds_changed)
	CombatManager.guard_changed.disconnect(_on_guard_changed)
	CombatManager.combat_ended.disconnect(_on_combat_ended)
	CombatManager.player_action_required.disconnect(_on_player_action_required)

	get_tree().reload_current_scene()
