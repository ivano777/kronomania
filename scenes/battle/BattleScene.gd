# BattleScene — root scene for 1vN combat.
# Wires CombatManager signals to dynamically spawned HUD nodes.
extends Node2D

# ── Combatant data ────────────────────────────────────────────────────────────
const PLAYER_DATA := preload("res://resources/data/player_default.tres")

const ENEMY_HUD_SCENE := preload("res://scenes/battle/CombatantHUD.tscn")
const ENEMY_VIS_SCENE := preload("res://scenes/battle/Combatant.tscn")

# ── Debug scenes (remove path + add_child call to strip at release) ───────────
const _DBG_WEAPON_SEL    := "res://scenes/debug/DebugWeaponSelector.tscn"
const _DBG_FERVOR_DISP   := "res://scenes/debug/DebugFervorDisplay.tscn"
const _DBG_COMBAT_CTRL   := "res://scenes/debug/DebugCombatControl.tscn"
const _DBG_ATTACK_FX     := "res://scenes/debug/DebugAttackFX.tscn"
var _dbg_fervor_disp = null

## Seconds CombatManager pauses after each attack so the presentation can play out.
## Must exceed windup + hold + restore (~0.95s) or consecutive attacks overlap.
const ATTACK_PACING_S := 1.1

## Player pose chosen at action confirm, consumed when CombatManager emits
## combatant_attacking(true, …) at actual resolution time (slow enemies act first).
var _pending_player_anim: String = ""
var _pending_player_fallback: String = "attack_melee"
var _pending_player_lunge: bool = true

# ── Node references ───────────────────────────────────────────────────────────
@onready var _player_hud:            CombatantHUD  = $UILayer/PlayerHUD
@onready var _player_visual:         Combatant     = $WorldLayer/PlayerVisual
@onready var _presenter:             AttackPresenter = $AttackPresenter
@onready var _dim_overlay:           TextureRect   = $WorldLayer/DimOverlay
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

	# CC0 arena background (import_env.py output); ColorRect fallback stays on miss.
	var bg_tex := SpriteRegistry.get_background("battle")
	if bg_tex != null:
		var bg_rect := TextureRect.new()
		bg_rect.texture = bg_tex
		bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		$WorldLayer/Background.add_child(bg_rect)

	# Player side.
	_player_visual.setup(PLAYER_DATA, true)
	_player_hud.setup(PLAYER_DATA, true)
	var _eff_weapon: EquipmentData = PlayerProgression.main_hand \
		if PlayerProgression.main_hand != null else PLAYER_DATA.equipped_weapon
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
		TooltipManager.attach(hud, ed)

	_select_target(0)

	# Connect RoundHUD action signals.
	_round_hud.strike_confirmed.connect(_on_strike_confirmed)
	_round_hud.cantrip_selected.connect(_on_cantrip_selected)
	_round_hud.spell_selected.connect(_on_spell_selected)
	_round_hud.wound_degrade_chosen.connect(_on_wound_degrade_chosen)
	_round_hud.burnout_prevent_chosen.connect(_on_burnout_prevent_chosen)
	_round_hud.auto_attack_requested.connect(_on_auto_attack_requested)

	# Attack presentation (DD-style): presenter drives dim/emphasis/impact tweens;
	# pacing gives each attack room to play out before the next one starts.
	_presenter.setup($WorldLayer, _dim_overlay, Vector2(320, 235))
	CombatManager.attack_pacing_s = ATTACK_PACING_S

	# Connect CombatManager signals.
	CombatManager.log_message.connect(_on_log)
	CombatManager.round_started.connect(_on_round_started)
	CombatManager.phase_changed.connect(_on_phase_changed)
	CombatManager.wounds_changed.connect(_on_wounds_changed)
	CombatManager.combatant_attacking.connect(_on_combatant_attacking)
	CombatManager.attack_resolved.connect(_on_attack_resolved)
	CombatManager.guard_changed.connect(_on_guard_changed)
	CombatManager.combat_ended.connect(_on_combat_ended)
	CombatManager.player_intents_available.connect(_on_intents_available)
	CombatManager.player_magic_available.connect(_on_player_magic_available)
	CombatManager.fervor_changed.connect(_on_fervor_changed)
	CombatManager.player_massive_incoming.connect(_on_player_massive_incoming)
	CombatManager.player_burnout_imminent.connect(_on_player_burnout_imminent)
	CombatManager.player_defense_incoming.connect(_on_defense_incoming)
	CombatManager.player_defense_item_choice.connect(_on_defense_item_choice)

	# Debug widgets — added to UILayer so they render as Controls correctly.
	if ResourceLoader.exists(_DBG_WEAPON_SEL):
		$UILayer.add_child((load(_DBG_WEAPON_SEL) as PackedScene).instantiate())
	if ResourceLoader.exists(_DBG_FERVOR_DISP):
		_dbg_fervor_disp = (load(_DBG_FERVOR_DISP) as PackedScene).instantiate()
		$UILayer.add_child(_dbg_fervor_disp)
	if ResourceLoader.exists(_DBG_COMBAT_CTRL):
		$UILayer.add_child((load(_DBG_COMBAT_CTRL) as PackedScene).instantiate())
	if ResourceLoader.exists(_DBG_ATTACK_FX):
		$UILayer.add_child((load(_DBG_ATTACK_FX) as PackedScene).instantiate())

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


func _on_wounds_changed(is_player: bool, enemy_index: int, current: int, max_wounds: int, is_initial: bool) -> void:
	if is_player:
		_player_hud.set_wounds(current, max_wounds)
	else:
		_enemy_huds[enemy_index].set_wounds(current, max_wounds)
		if current >= max_wounds and not _enemy_defeated[enemy_index]:
			_enemy_defeated[enemy_index] = true
			_enemy_huds[enemy_index].modulate = Color(0.45, 0.45, 0.45)
			if enemy_index == _target_index:
				_auto_select_living_target()
	if is_initial:
		return  # display sync only — no real attack happened, don't react
	var vis: Combatant = _player_visual if is_player else _enemy_visuals[enemy_index]
	if current >= max_wounds:
		vis.play_die()
	else:
		vis.play_hurt()


func _on_combatant_attacking(is_player: bool, enemy_index: int) -> void:
	if is_player:
		# Player attack resolving NOW (after slow enemies) — start the windup
		# with the pose remembered at action confirm.
		var anim := _pending_player_anim if _pending_player_anim != "" else _pending_player_fallback
		_player_visual.play_attack(anim, _pending_player_fallback)
		_presenter.begin_windup(_player_visual, _enemy_visuals[enemy_index],
			_all_visuals(), _pending_player_lunge)
		return
	var attacker: Combatant = _enemy_visuals[enemy_index]
	var e_weapon: EquipmentData = (_enemies_data[enemy_index] as CombatantData).equipped_weapon
	var e_anim: String = e_weapon.attack_anim if e_weapon != null else ""
	attacker.play_attack(e_anim if e_anim != "" else "attack_melee")
	_presenter.begin_windup(attacker, _player_visual, _all_visuals())


func _on_attack_resolved(attacker_is_player: bool, enemy_index: int, _target_pool: String,
		did_breach: bool, is_massive: bool, wounds_dealt: int, defender_defeated: bool) -> void:
	var target: Combatant = _enemy_visuals[enemy_index] if attacker_is_player else _player_visual
	_presenter.play_impact(target, did_breach, is_massive, wounds_dealt, defender_defeated)


func _all_visuals() -> Array:
	var all := [_player_visual]
	all.append_array(_enemy_visuals)
	return all


## Remembers the pose for the player's next attack; consumed by
## _on_combatant_attacking(true, …) when the attack actually resolves.
func _set_pending_player_pose(anim: String, fallback: String, lunge: bool) -> void:
	_pending_player_anim = anim
	_pending_player_fallback = fallback
	_pending_player_lunge = lunge


func _on_guard_changed(is_player: bool, enemy_index: int, pool: String, guard_value: int) -> void:
	if is_player:
		_player_hud.set_guard(pool, guard_value)
	else:
		_enemy_huds[enemy_index].set_guard(pool, guard_value)


func _on_combat_ended(winner_name: String) -> void:
	_round_hud.disable_actions()
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


func _on_intents_available(intents: Array[String]) -> void:
	_round_hud.show_intents(intents)


func _on_player_magic_available(can_cantrip: bool, can_cast_spell: bool) -> void:
	_round_hud.enable_magic(can_cantrip, can_cast_spell)


func _on_fervor_changed(is_player: bool, fervor_size: int, fervor_cap: int, is_burned_out: bool) -> void:
	if is_player:
		_player_hud.set_fervor(fervor_size, fervor_cap, is_burned_out)


func _on_player_massive_incoming(charges_left: int) -> void:
	_round_hud.show_massive_prompt(charges_left)


func _on_player_burnout_imminent(charges_left: int) -> void:
	_round_hud.show_burnout_prompt(charges_left)


func _on_defense_incoming(attacker_name: String, attack_total: int, target_pool: String) -> void:
	_round_hud.show_defense_overlay(attacker_name, attack_total, target_pool)


func _on_defense_item_choice(options: Array) -> void:
	_round_hud.show_defense_item_choice(options)


func _on_wound_degrade_chosen(use_charge: bool) -> void:
	CombatManager.player_chose_degrade_wound(use_charge)


func _on_burnout_prevent_chosen(use_charge: bool) -> void:
	CombatManager.player_chose_prevent_burnout(use_charge)


func _on_auto_attack_requested() -> void:
	_set_pending_player_pose("", "attack_melee", true)
	CombatManager.player_auto_execute_attack(
		_target_index,
		_round_hud.get_net_advantage() + _ambush_base_disadvantage
	)


func _on_strike_confirmed(pool: String, brutal_trade: bool, source_weapon: EquipmentData) -> void:
	var anim: String = source_weapon.attack_anim if source_weapon != null else ""
	_set_pending_player_pose(anim, "attack_melee", true)
	CombatManager.player_chose_strike(
		_round_hud.get_net_advantage() + _ambush_base_disadvantage,
		pool,
		brutal_trade,
		_target_index,
		source_weapon
	)


func _on_cantrip_selected(spell: SpellData, source_weapon: EquipmentData) -> void:
	_set_pending_player_pose(spell.attack_anim, "cast_spell", false)
	CombatManager.player_chose_cantrip(spell, _target_index, source_weapon)


func _on_spell_selected(spell: SpellData, source_weapon: EquipmentData) -> void:
	_set_pending_player_pose(spell.attack_anim, "cast_spell", false)
	CombatManager.player_chose_spell(spell, _target_index, source_weapon)


# ── Debug (DebugAttackFX widget) ──────────────────────────────────────────────

## Replays the attack presentation with a mock payload — no CombatManager involvement.
## kind: "hit" | "massive" | "blocked" | "kill".
func debug_replay_attack(kind: String) -> void:
	var target: Combatant = _enemy_visuals[_target_index]
	match kind:
		"massive":
			_presenter.debug_replay(_player_visual, target, _all_visuals(), true, true, 2, false)
		"blocked":
			_presenter.debug_replay(_player_visual, target, _all_visuals(), false, false, 0, false)
		"kill":
			await _presenter.debug_replay(_player_visual, target, _all_visuals(), true, false, 1, true)
			target.fade_name_label(1.0)  # replay only — undo the death label fade
			target.play_idle()
		_:
			_presenter.debug_replay(_player_visual, target, _all_visuals(), true, false, 1, false)


func _teardown_signals() -> void:
	CombatManager.log_message.disconnect(_on_log)
	CombatManager.round_started.disconnect(_on_round_started)
	CombatManager.phase_changed.disconnect(_on_phase_changed)
	CombatManager.wounds_changed.disconnect(_on_wounds_changed)
	CombatManager.combatant_attacking.disconnect(_on_combatant_attacking)
	CombatManager.attack_resolved.disconnect(_on_attack_resolved)
	CombatManager.guard_changed.disconnect(_on_guard_changed)
	CombatManager.combat_ended.disconnect(_on_combat_ended)
	CombatManager.player_intents_available.disconnect(_on_intents_available)
	CombatManager.player_magic_available.disconnect(_on_player_magic_available)
	CombatManager.fervor_changed.disconnect(_on_fervor_changed)
	CombatManager.player_massive_incoming.disconnect(_on_player_massive_incoming)
	CombatManager.player_burnout_imminent.disconnect(_on_player_burnout_imminent)
	CombatManager.player_defense_incoming.disconnect(_on_defense_incoming)
	CombatManager.player_defense_item_choice.disconnect(_on_defense_item_choice)
	if _dbg_fervor_disp:
		CombatManager.fervor_changed.disconnect(_dbg_fervor_disp._on_fervor_changed)
