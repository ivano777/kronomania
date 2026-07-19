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
## Must exceed windup + projectile travel + hold + restore (~1.1s) or
## consecutive attacks overlap.
const ATTACK_PACING_S := 1.25

## Player pose chosen at action confirm, consumed when CombatManager emits
## combatant_attacking(true, …) at actual resolution time (slow enemies act first).
var _pending_player_anim: String = ""
var _pending_player_fallback: String = "attack_melee"
var _pending_player_lunge: bool = true
var _pending_player_windup_fx: String = ""
var _pending_player_impact_fx: String = ""
var _pending_player_projectile_fx: String = ""
var _pending_player_rarity: String = "common"
## True when the pending action is an Auto attack: the scene doesn't know which
## weapon the auto-picker will choose, so FX are pulled from
## CombatManager.player_strike_weapon_resolved at combatant_attacking time.
var _pending_player_fx_from_auto: bool = false

## Impact/projectile FX per attacker side: remembered at windup, read at
## attack_resolved. Deliberately not cleared after use — impacts with no
## preceding windup (echo, mind detonation) reuse the caster's last clip, which
## reads correctly for echoed spells and degrades to the generic burst otherwise.
var _player_impact_fx: String = ""
var _enemy_impact_fx: String = ""
var _player_projectile_fx: String = ""
var _enemy_projectile_fx: String = ""

## FX intensity per attacker side, computed at windup from CombatManager's
## fx_attack_* facts (stat die → scale, node level → count) + item rarity
## (aura tint + scale bonus). Same not-cleared policy as the FX names above.
var _player_fx_scale: float = 1.0
var _player_fx_count: int = 1
var _player_fx_tint: Color = Color.WHITE
var _enemy_fx_scale: float = 1.0
var _enemy_fx_count: int = 1
var _enemy_fx_tint: Color = Color.WHITE

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
var _signals_torn_down := false
var _dummy_attack_btn: Button = null  # training room only


func _ready() -> void:
	_enemies_data = DungeonManager.current_enemies()
	if _enemies_data.is_empty():
		get_tree().change_scene_to_file(DebugManager.nav_target("res://scenes/main_menu/MainMenuScene.tscn"))
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
	_round_hud.shield_chosen.connect(_on_shield_chosen)
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
	CombatManager.player_shield_opportunity.connect(_on_player_shield_opportunity)
	CombatManager.player_defense_incoming.connect(_on_defense_incoming)
	CombatManager.player_defense_item_choice.connect(_on_defense_item_choice)

	# Debug widgets — added to UILayer so they render as Controls correctly.
	# Bottom-left widgets stack inside one dock so the container drives layout
	# (hand-tuned .tscn offsets can't overlap or push them offscreen).
	var dbg_dock := VBoxContainer.new()
	dbg_dock.name = "DebugDock"
	dbg_dock.anchor_left = 0.0
	dbg_dock.anchor_top = 1.0
	dbg_dock.anchor_right = 0.0
	dbg_dock.anchor_bottom = 1.0
	dbg_dock.offset_left = 5.0
	dbg_dock.offset_top = -5.0
	dbg_dock.offset_right = 5.0
	dbg_dock.offset_bottom = -5.0
	dbg_dock.grow_horizontal = Control.GROW_DIRECTION_END
	dbg_dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	$UILayer.add_child(dbg_dock)
	for dbg_path in [_DBG_ATTACK_FX, _DBG_COMBAT_CTRL, _DBG_WEAPON_SEL]:
		if ResourceLoader.exists(dbg_path):
			dbg_dock.add_child((load(dbg_path) as PackedScene).instantiate())
	if ResourceLoader.exists(_DBG_FERVOR_DISP):
		_dbg_fervor_disp = (load(_DBG_FERVOR_DISP) as PackedScene).instantiate()
		$UILayer.add_child(_dbg_fervor_disp)

	# Training-room controls — bottom strip between PlayerHUD (ends x184) and
	# RoundHUD (starts x448): Esc hint + dummy-attack toggle.
	if DungeonManager.training_mode:
		var box := HBoxContainer.new()
		box.anchor_left = 0.0
		box.anchor_right = 0.0
		box.anchor_top = 1.0
		box.anchor_bottom = 1.0
		box.offset_left = 192.0
		box.offset_right = 444.0
		box.offset_top = -26.0
		box.offset_bottom = -4.0
		box.add_theme_constant_override("separation", 8)
		$UILayer.add_child(box)

		var hint := Label.new()
		hint.text = "TRAINING · Esc leaves"
		hint.modulate = Color(0.85, 0.80, 0.70, 0.85)
		hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(hint)

		_dummy_attack_btn = Button.new()
		_dummy_attack_btn.toggle_mode = true
		_dummy_attack_btn.button_pressed = DungeonManager.training_dummy_attacks
		_dummy_attack_btn.toggled.connect(_on_dummy_attacks_toggled)
		box.add_child(_dummy_attack_btn)
		_refresh_dummy_attack_btn()

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
	_refresh_status_icons()


func _on_phase_changed(phase_name: String) -> void:
	_round_hud.set_phase(phase_name)
	_refresh_status_icons()


# Statuses have no dedicated change signal (mutations stay inside StatusOps);
# every mutation happens inside a flow that emits one of the hooked signals, so
# a poll-refresh here keeps the HUD squares current without touching the spine.
func _refresh_status_icons() -> void:
	_player_hud.set_statuses(CombatManager.get_active_statuses(true))
	for i in _enemy_huds.size():
		(_enemy_huds[i] as CombatantHUD).set_statuses(CombatManager.get_active_statuses(false, i))


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
		# with the pose + FX remembered at action confirm.
		if _pending_player_fx_from_auto:
			# Auto attack: weapon was picked inside CombatManager; read the
			# resolved one so its FX still play.
			var auto_w: EquipmentData = CombatManager.player_strike_weapon_resolved
			_pending_player_windup_fx = auto_w.windup_fx if auto_w != null else ""
			_pending_player_impact_fx = auto_w.impact_fx if auto_w != null else ""
			_pending_player_projectile_fx = auto_w.projectile_fx if auto_w != null else ""
			_pending_player_rarity = auto_w.rarity if auto_w != null else "common"
		var anim := _pending_player_anim if _pending_player_anim != "" else _pending_player_fallback
		_player_visual.play_attack(anim, _pending_player_fallback)
		_player_impact_fx = _pending_player_impact_fx
		_player_projectile_fx = _pending_player_projectile_fx
		_player_fx_scale = AttackPresenter.fx_scale_for_die(CombatManager.fx_attack_die_size) \
				+ AttackPresenter.rarity_scale_bonus(_pending_player_rarity)
		_player_fx_count = AttackPresenter.fx_count_for_level(CombatManager.fx_attack_node_level)
		_player_fx_tint = AttackPresenter.rarity_tint(_pending_player_rarity)
		_presenter.begin_windup(_player_visual, _enemy_visuals[enemy_index],
			_all_visuals(), _pending_player_lunge, _pending_player_windup_fx,
			_player_fx_scale, _player_fx_count)
		return
	var attacker: Combatant = _enemy_visuals[enemy_index]
	var e_weapon: EquipmentData = (_enemies_data[enemy_index] as CombatantData).equipped_weapon
	var e_anim: String = e_weapon.attack_anim if e_weapon != null else ""
	attacker.play_attack(e_anim if e_anim != "" else "attack_melee")
	_enemy_impact_fx = e_weapon.impact_fx if e_weapon != null else ""
	_enemy_projectile_fx = e_weapon.projectile_fx if e_weapon != null else ""
	var e_rarity: String = e_weapon.rarity if e_weapon != null else "common"
	_enemy_fx_scale = AttackPresenter.fx_scale_for_die(CombatManager.fx_attack_die_size) \
			+ AttackPresenter.rarity_scale_bonus(e_rarity)
	_enemy_fx_count = AttackPresenter.fx_count_for_level(CombatManager.fx_attack_node_level)
	_enemy_fx_tint = AttackPresenter.rarity_tint(e_rarity)
	_presenter.begin_windup(attacker, _player_visual, _all_visuals(), true,
		e_weapon.windup_fx if e_weapon != null else "",
		_enemy_fx_scale, _enemy_fx_count)


func _on_attack_resolved(attacker_is_player: bool, enemy_index: int, _target_pool: String,
		did_breach: bool, is_massive: bool, wounds_dealt: int, defender_defeated: bool) -> void:
	_refresh_status_icons()
	var target: Combatant = _enemy_visuals[enemy_index] if attacker_is_player else _player_visual
	var impact_fx := _player_impact_fx if attacker_is_player else _enemy_impact_fx
	var projectile_fx := _player_projectile_fx if attacker_is_player else _enemy_projectile_fx
	var fx_scale := _player_fx_scale if attacker_is_player else _enemy_fx_scale
	var fx_count := _player_fx_count if attacker_is_player else _enemy_fx_count
	var fx_tint := _player_fx_tint if attacker_is_player else _enemy_fx_tint
	_presenter.play_impact(target, did_breach, is_massive, wounds_dealt, defender_defeated,
		impact_fx, projectile_fx, fx_scale, fx_count, fx_tint)


func _all_visuals() -> Array:
	var all := [_player_visual]
	all.append_array(_enemy_visuals)
	return all


## Remembers the pose + shared FX clips for the player's next attack; consumed
## by _on_combatant_attacking(true, …) when the attack actually resolves.
func _set_pending_player_pose(anim: String, fallback: String, lunge: bool,
		windup_fx: String = "", impact_fx: String = "", projectile_fx: String = "",
		rarity: String = "common") -> void:
	_pending_player_anim = anim
	_pending_player_fallback = fallback
	_pending_player_lunge = lunge
	_pending_player_windup_fx = windup_fx
	_pending_player_impact_fx = impact_fx
	_pending_player_projectile_fx = projectile_fx
	_pending_player_rarity = rarity
	_pending_player_fx_from_auto = false


func _on_guard_changed(is_player: bool, enemy_index: int, pool: String, guard_value: int) -> void:
	if is_player:
		_player_hud.set_guard(pool, guard_value)
	else:
		_enemy_huds[enemy_index].set_guard(pool, guard_value)


func _on_combat_ended(winner_name: String) -> void:
	_round_hud.disable_actions()
	if DungeonManager.training_mode:
		# Training room: outside the run flow — no points, no run advance,
		# and defeat must NOT delete the save slot.
		_result_label.text = "Training over — well struck!" \
				if winner_name == PLAYER_DATA.combatant_name \
				else "Knocked out by a training dummy..."
		_defeat_panel.show()
		await get_tree().create_timer(1.5).timeout
		_leave_training()
		return
	if winner_name != PLAYER_DATA.combatant_name:
		DungeonManager.on_defeat()
		if SaveManager.active_slot > 0:
			SaveManager.delete_slot(SaveManager.active_slot)
		_result_label.text = "Defeated by %s..." % winner_name
		_defeat_panel.show()
		await get_tree().create_timer(1.5).timeout
		_teardown_signals()
		get_tree().change_scene_to_file(DebugManager.nav_target("res://scenes/main_menu/MainMenuScene.tscn"))
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
			get_tree().change_scene_to_file(DebugManager.nav_target("res://scenes/campfire/CampfireScene.tscn"))
		else:
			_result_label.text = "Run complete!  Victory!"
			_defeat_panel.show()
			await get_tree().create_timer(1.5).timeout
			_teardown_signals()
			get_tree().change_scene_to_file(DebugManager.nav_target("res://scenes/main_menu/MainMenuScene.tscn"))


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


func _on_player_shield_opportunity(
		charges_left: int, incoming: int, guard: int, dice_count: int, die_size: int
) -> void:
	_round_hud.show_shield_prompt(charges_left, incoming, guard, dice_count, die_size)


func _on_shield_chosen(use_charge: bool) -> void:
	CombatManager.player_chose_magic_shield(use_charge)


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
	_pending_player_fx_from_auto = true
	CombatManager.player_auto_execute_attack(
		_target_index,
		_round_hud.get_net_advantage() + _ambush_base_disadvantage
	)


func _on_strike_confirmed(pool: String, brutal_trade: bool, source_weapon: EquipmentData) -> void:
	var anim: String = source_weapon.attack_anim if source_weapon != null else ""
	var windup_fx: String = source_weapon.windup_fx if source_weapon != null else ""
	var impact_fx: String = source_weapon.impact_fx if source_weapon != null else ""
	var projectile_fx: String = source_weapon.projectile_fx if source_weapon != null else ""
	var rarity: String = source_weapon.rarity if source_weapon != null else "common"
	_set_pending_player_pose(anim, "attack_melee", true, windup_fx, impact_fx, projectile_fx, rarity)
	CombatManager.player_chose_strike(
		_round_hud.get_net_advantage() + _ambush_base_disadvantage,
		pool,
		brutal_trade,
		_target_index,
		source_weapon
	)


func _on_cantrip_selected(spell: SpellData, source_weapon: EquipmentData) -> void:
	# Rarity aura comes from the casting tool (the "used item"), not the spell.
	_set_pending_player_pose(spell.attack_anim, "cast_spell", false,
		spell.windup_fx, spell.impact_fx, spell.projectile_fx,
		source_weapon.rarity if source_weapon != null else "common")
	CombatManager.player_chose_cantrip(spell, _target_index, source_weapon)


func _on_spell_selected(spell: SpellData, source_weapon: EquipmentData) -> void:
	_set_pending_player_pose(spell.attack_anim, "cast_spell", false,
		spell.windup_fx, spell.impact_fx, spell.projectile_fx,
		source_weapon.rarity if source_weapon != null else "common")
	CombatManager.player_chose_spell(spell, _target_index, source_weapon)


# ── Debug (DebugAttackFX widget) ──────────────────────────────────────────────

## Replays the attack presentation with a mock payload — no CombatManager involvement.
## Uses the equipped main-hand's FX clips so the shared-FX layer is exercisable too.
## kind: "hit" | "massive" | "blocked" | "kill".
func debug_replay_attack(kind: String) -> void:
	var target: Combatant = _enemy_visuals[_target_index]
	var w: EquipmentData = PlayerProgression.main_hand
	var wfx: String = w.windup_fx if w != null else ""
	var ifx: String = w.impact_fx if w != null else ""
	var pfx: String = w.projectile_fx if w != null else ""
	# Replay intensity mirrors a live strike: martial-arts level for count,
	# progression dominion for scale, main-hand rarity for the aura.
	var rarity: String = w.rarity if w != null else "common"
	var fx_scale := AttackPresenter.fx_scale_for_die(PLAYER_DATA.dominion_size) \
			+ AttackPresenter.rarity_scale_bonus(rarity)
	var fx_count := AttackPresenter.fx_count_for_level(
		PlayerProgression.get_node_level_by_id("dom_martial_arts"))
	var fx_tint := AttackPresenter.rarity_tint(rarity)
	match kind:
		"massive":
			_presenter.debug_replay(_player_visual, target, _all_visuals(), true, true, 2, false, wfx, ifx, pfx, fx_scale, fx_count, fx_tint)
		"blocked":
			_presenter.debug_replay(_player_visual, target, _all_visuals(), false, false, 0, false, wfx, ifx, pfx, fx_scale, fx_count, fx_tint)
		"kill":
			await _presenter.debug_replay(_player_visual, target, _all_visuals(), true, false, 1, true, wfx, ifx, pfx, fx_scale, fx_count, fx_tint)
			target.fade_name_label(1.0)  # replay only — undo the death label fade
			target.play_idle()
		_:
			_presenter.debug_replay(_player_visual, target, _all_visuals(), true, false, 1, false, wfx, ifx, pfx, fx_scale, fx_count, fx_tint)


## Training room: Esc leaves immediately, mid-round included.
func _input(event: InputEvent) -> void:
	if not DungeonManager.training_mode:
		return
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_leave_training()


func _on_dummy_attacks_toggled(pressed: bool) -> void:
	DungeonManager.training_dummy_attacks = pressed
	_refresh_dummy_attack_btn()


func _refresh_dummy_attack_btn() -> void:
	if _dummy_attack_btn != null:
		_dummy_attack_btn.text = "▼ Dummy attacks: ON" \
				if DungeonManager.training_dummy_attacks else "▶ Dummy attacks: OFF"


func _leave_training() -> void:
	_teardown_signals()
	DungeonManager.end_training()
	get_tree().change_scene_to_file(DebugManager.nav_target("res://scenes/campfire/CampfireScene.tscn"))


func _teardown_signals() -> void:
	# Idempotent: Esc-leave can race the combat-ended teardown (both paths
	# call this); a second disconnect pass would error.
	if _signals_torn_down:
		return
	_signals_torn_down = true
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
	CombatManager.player_shield_opportunity.disconnect(_on_player_shield_opportunity)
	CombatManager.player_defense_incoming.disconnect(_on_defense_incoming)
	CombatManager.player_defense_item_choice.disconnect(_on_defense_item_choice)
	if _dbg_fervor_disp:
		CombatManager.fervor_changed.disconnect(_dbg_fervor_disp._on_fervor_changed)
