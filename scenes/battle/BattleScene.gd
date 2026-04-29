# BattleScene — root scene for 1vN combat.
# Wires CombatManager signals to dynamically spawned HUD nodes.
extends Node2D

# ── Combatant data ────────────────────────────────────────────────────────────
const PLAYER_DATA := preload("res://resources/data/player_default.tres")

const ENEMY_HUD_SCENE := preload("res://scenes/battle/CombatantHUD.tscn")
const ENEMY_VIS_SCENE := preload("res://scenes/battle/Combatant.tscn")

# ── Debug scenes (remove path + add_child call to strip at release) ───────────
const _DBG_WEAPON_SEL  := "res://scenes/debug/DebugWeaponSelector.tscn"
const _DBG_FERVOR_DISP := "res://scenes/debug/DebugFervorDisplay.tscn"
var _dbg_fervor_disp = null

# ── Node references ───────────────────────────────────────────────────────────
@onready var _player_hud:            CombatantHUD  = $UILayer/PlayerHUD
@onready var _player_visual:         Combatant     = $WorldLayer/PlayerVisual
@onready var _enemies_hud_container: HBoxContainer = $UILayer/EnemiesHUDContainer
@onready var _round_hud:             RoundHUD      = $UILayer/RoundHUD
@onready var _defeat_panel:          Panel         = $UILayer/DefeatPanel
@onready var _result_label:          Label         = $UILayer/DefeatPanel/PanelContent/ResultLabel

# ── Enemy runtime arrays ──────────────────────────────────────────────────────
var _enemies_data: Array      # Array[CombatantData]
var _enemy_huds: Array        # Array[CombatantHUD]
var _enemy_visuals: Array     # Array[Combatant]
var _enemy_defeated: Array    # Array[bool]
var _target_index: int = 0
var _enemy_anchors: Array     # Array[Marker2D] — built in _ready
var _ambush_base_disadvantage: int = 0


func _ready() -> void:
	_enemies_data = DungeonManager.current_enemies()
	if _enemies_data.is_empty():
		get_tree().change_scene_to_file("res://scenes/main_menu/MainMenuScene.tscn")
		return
	_ambush_base_disadvantage = DungeonManager.ambush_disadvantage

	_enemy_anchors = [
		$WorldLayer/EnemyAnchor1,
		$WorldLayer/EnemyAnchor2,
		$WorldLayer/EnemyAnchor3,
	]

	_defeat_panel.hide()

	# Player side.
	_player_visual.setup(PLAYER_DATA, true)
	_player_hud.setup(PLAYER_DATA, true)
	var _eff_weapon: EquipmentData = PlayerProgression.equipped_weapon \
		if PlayerProgression.equipped_weapon != null else PLAYER_DATA.equipped_weapon
	_player_hud.set_weapon_display(_eff_weapon)

	# Spawn one HUD into UILayer and one Combatant visual into WorldLayer per enemy.
	for i in _enemies_data.size():
		var ed: CombatantData = _enemies_data[i] as CombatantData

		var hud: CombatantHUD = ENEMY_HUD_SCENE.instantiate() as CombatantHUD
		_enemies_hud_container.add_child(hud)

		var vis: Combatant = ENEMY_VIS_SCENE.instantiate() as Combatant
		$WorldLayer.add_child(vis)
		vis.global_position = (_enemy_anchors[i] as Marker2D).global_position

		hud.setup(ed, false)
		hud.set_weapon_display(ed.equipped_weapon)
		vis.setup(ed, false)

		_enemy_huds.append(hud)
		_enemy_visuals.append(vis)
		_enemy_defeated.append(false)

		# Click on enemy HUD to select that enemy as the target.
		hud.mouse_filter = Control.MOUSE_FILTER_STOP
		var idx := i
		hud.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed \
					and event.button_index == MOUSE_BUTTON_LEFT \
					and not _enemy_defeated[idx]:
				_select_target(idx)
		)

	_select_target(0)

	# Connect RoundHUD action buttons/selections.
	_round_hud.strike_pressed.connect(_on_strike_pressed)
	_round_hud.cantrip_selected.connect(_on_cantrip_selected)
	_round_hud.spell_selected.connect(_on_spell_selected)
	_round_hud.wound_degrade_chosen.connect(_on_wound_degrade_chosen)

	_round_hud.set_spell_lists(
		PlayerProgression.get_known_spells(),
		PlayerProgression.get_known_cantrips()
	)

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

	# Debug widgets — added to UILayer so they render as Controls correctly.
	if ResourceLoader.exists(_DBG_WEAPON_SEL):
		$UILayer.add_child((load(_DBG_WEAPON_SEL) as PackedScene).instantiate())
	if ResourceLoader.exists(_DBG_FERVOR_DISP):
		_dbg_fervor_disp = (load(_DBG_FERVOR_DISP) as PackedScene).instantiate()
		$UILayer.add_child(_dbg_fervor_disp)

	CombatManager.start_combat(PLAYER_DATA, _enemies_data)


# ── Target selection ──────────────────────────────────────────────────────────

func _select_target(idx: int) -> void:
	_target_index = idx
	for i in _enemy_huds.size():
		_enemy_huds[i].modulate = Color(1.3, 1.3, 0.6) if i == idx else Color(1.0, 1.0, 1.0)


func _auto_select_living_target() -> void:
	for i in _enemy_defeated.size():
		if not _enemy_defeated[i]:
			_select_target(i)
			return


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_log(text: String) -> void:
	_round_hud.add_log(text)


func _on_round_started(round_num: int) -> void:
	_round_hud.set_round(round_num)


func _on_phase_changed(phase_name: String) -> void:
	_round_hud.set_phase(phase_name)


func _on_wounds_changed(is_player: bool, enemy_index: int, current: int, max_wounds: int) -> void:
	if is_player:
		_player_hud.set_wounds(current, max_wounds)
	else:
		_enemy_huds[enemy_index].set_wounds(current, max_wounds)
		if current >= max_wounds and not _enemy_defeated[enemy_index]:
			_enemy_defeated[enemy_index] = true
			_enemy_huds[enemy_index].modulate = Color(0.45, 0.45, 0.45)
			if enemy_index == _target_index:
				_auto_select_living_target()


func _on_guard_changed(is_player: bool, enemy_index: int, pool: String, guard_value: int) -> void:
	if is_player:
		_player_hud.set_guard(pool, guard_value)
	else:
		_enemy_huds[enemy_index].set_guard(pool, guard_value)


func _on_combat_ended(winner_name: String) -> void:
	_round_hud.disable_strike()
	_round_hud.disable_magic()
	if winner_name != PLAYER_DATA.combatant_name:
		DungeonManager.on_defeat()
		if SaveManager.active_slot > 0:
			SaveManager.delete_slot(SaveManager.active_slot)
		_result_label.text = "Defeated by %s..." % winner_name
		_defeat_panel.show()
		await get_tree().create_timer(1.5).timeout
		_teardown_signals()
		get_tree().change_scene_to_file("res://scenes/main_menu/MainMenuScene.tscn")
	else:
		DungeonManager.on_victory()
		if DungeonManager.was_last_fight_chained():
			_result_label.text = "Another enemy approaches..."
			_defeat_panel.show()
			await get_tree().create_timer(1.5).timeout
			_teardown_signals()
			get_tree().change_scene_to_file("res://scenes/battle/BattleScene.tscn")
		elif DungeonManager.has_next_enemy():
			_result_label.text = "Victory!  Return to camp."
			_defeat_panel.show()
			await get_tree().create_timer(1.5).timeout
			_teardown_signals()
			get_tree().change_scene_to_file("res://scenes/campfire/CampfireScene.tscn")
		else:
			_result_label.text = "Run complete!  Victory!"
			_defeat_panel.show()
			await get_tree().create_timer(1.5).timeout
			_teardown_signals()
			get_tree().change_scene_to_file("res://scenes/main_menu/MainMenuScene.tscn")


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
	CombatManager.player_chose_strike(
		_round_hud.get_net_advantage() + _ambush_base_disadvantage,
		_round_hud.get_target_pool(),
		_round_hud.get_brutal_trade(),
		_target_index
	)


func _on_cantrip_selected(spell: SpellData) -> void:
	CombatManager.player_chose_cantrip(spell, _target_index)


func _on_spell_selected(spell: SpellData) -> void:
	CombatManager.player_chose_spell(spell, _target_index)


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
	if _dbg_fervor_disp:
		CombatManager.fervor_changed.disconnect(_dbg_fervor_disp._on_fervor_changed)
