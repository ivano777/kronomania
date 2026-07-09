extends GutTest

# Equip-requirements rework: casting is gated by equipment, not tier caps.
# Cantrips need truly empty hands OR an equipped Magic Focus; true spells always
# need a Magic Focus. Deterministic: pure CombatMath statics on a hand-built state,
# plus the CombatManager choose-guards (blocked paths only — no coroutine fired).

const _PLAYER_DATA  = preload("res://resources/data/player_default.tres")
const _GRUNT_DATA   = preload("res://resources/data/enemy_grunt.tres")
const _IRON_SWORD   = preload("res://resources/data/weapons/iron_sword.tres")
const _HEATER_SHIELD = preload("res://resources/data/weapons/heater_shield.tres")
const _ARCANE_FOCUS = preload("res://resources/data/weapons/arcane_focus.tres")
const _WIZARD_STAFF = preload("res://resources/data/weapons/wizard_staff.tres")
const _ARCANE_MISSILE = preload("res://resources/data/spells/arcane_missile.tres")
const _ARCANE_BOLT    = preload("res://resources/data/spells/arcane_bolt.tres")

var _state: CombatantState


func before_each() -> void:
	_state = CombatantState.new()
	_state.init(_PLAYER_DATA)
	_state.weapon_override = null
	_state.off_hand_override = null


# ── CombatMath gating matrix ─────────────────────────────────────────────────

func test_empty_hands_cantrip_only() -> void:
	assert_true(CombatMath.can_channel_cantrips(_state), "empty hands channel cantrips")
	assert_false(CombatMath.can_channel_spells(_state), "empty hands do NOT channel true spells")


func test_sword_and_empty_offhand_blocks_all_casting() -> void:
	_state.weapon_override = _IRON_SWORD
	assert_false(CombatMath.can_channel_cantrips(_state), "a held sword blocks cantrips")
	assert_false(CombatMath.can_channel_spells(_state), "a held sword blocks true spells")


func test_sword_plus_focus_channels_everything() -> void:
	_state.weapon_override = _IRON_SWORD
	_state.off_hand_override = _ARCANE_FOCUS
	assert_true(CombatMath.can_channel_cantrips(_state), "off-hand focus channels cantrips")
	assert_true(CombatMath.can_channel_spells(_state), "off-hand focus channels true spells")


func test_focus_only_channels_everything() -> void:
	_state.weapon_override = _ARCANE_FOCUS
	assert_true(CombatMath.can_channel_cantrips(_state), "main-hand focus channels cantrips")
	assert_true(CombatMath.can_channel_spells(_state), "main-hand focus channels true spells")


func test_two_handed_staff_channels_everything() -> void:
	_state.weapon_override = _WIZARD_STAFF
	assert_true(CombatMath.can_channel_cantrips(_state), "2H staff (MagicFocus) channels cantrips")
	assert_true(CombatMath.can_channel_spells(_state), "2H staff (MagicFocus) channels true spells")


func test_shield_is_not_a_conduit() -> void:
	_state.off_hand_override = _HEATER_SHIELD
	assert_false(CombatMath.can_channel_cantrips(_state), "a shield alone is not empty hands")
	assert_false(CombatMath.can_channel_spells(_state), "a shield is not a Magic Focus")


# ── CombatManager choose-guards (defense in depth, blocked paths only) ───────

func test_player_chose_spell_blocked_without_focus() -> void:
	get_node("/root/PlayerProgression").reset()
	CombatManager.start_combat(_PLAYER_DATA, [_GRUNT_DATA])
	CombatManager.debug_set_player_weapon(null)  # bare hands: cantrip-legal, spell-illegal
	assert_true(CombatManager._waiting_for_player, "combat waits for player input")
	CombatManager.player_chose_spell(_ARCANE_MISSILE)
	assert_true(CombatManager._waiting_for_player,
		"spell without a Magic Focus is rejected — still waiting for player")


func test_player_chose_cantrip_blocked_holding_sword() -> void:
	get_node("/root/PlayerProgression").reset()
	CombatManager.start_combat(_PLAYER_DATA, [_GRUNT_DATA])
	CombatManager.debug_set_player_weapon(_IRON_SWORD)
	assert_true(CombatManager._waiting_for_player, "combat waits for player input")
	CombatManager.player_chose_cantrip(_ARCANE_BOLT)
	assert_true(CombatManager._waiting_for_player,
		"cantrip while holding a sword is rejected — still waiting for player")
