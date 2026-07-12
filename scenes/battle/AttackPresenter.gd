# AttackPresenter — Darkest-Dungeon-style attack presentation.
# Owns the dim overlay, emphasis/lunge/recoil tweens, impact burst and damage
# popups over Combatant visuals. Purely presentational: reads CombatManager
# signals routed through BattleScene, never touches combat state.
class_name AttackPresenter
extends Node

# ── Tunables ──────────────────────────────────────────────────────────────────
const WINDUP_S := 0.25          # attacker lunge duration; impact syncs to its apex
const RELEASE_HOLD_S := 0.45    # pause at impact before everything restores
const DEATH_EXTRA_HOLD_S := 0.3 # extra dim hold for the collapse beat
const DIM_IN_S := 0.15
const DIM_OUT_S := 0.25
const RESTORE_S := 0.2
const LUNGE_PX := 24.0
const RECOIL_PX := 10.0
const ATTACKER_SCALE := 1.2
const TARGET_SCALE := 1.1
const ATTACKER_LANE_WEIGHT := 0.2
const TARGET_LANE_WEIGHT := 0.12
const DIM_CENTER_ALPHA := 0.75
const DIM_EDGE_ALPHA := 0.35
const NONPARTICIPANT_GRAY := Color(0.45, 0.45, 0.45, 1.0)
const POPUP_RISE_PX := 12.0
const POPUP_FADE_S := 0.7

const COLOR_WOUND := Color.WHITE
const COLOR_MASSIVE := Color(1.0, 0.6, 0.2)
const COLOR_BLOCKED := Color(0.6, 0.6, 0.6)

# ── Wiring (set once by BattleScene) ─────────────────────────────────────────
var _world_layer: Node2D = null
var _dim_overlay: TextureRect = null
var _center_lane := Vector2(320, 235)

# ── Per-attack state ──────────────────────────────────────────────────────────
var _snapshots: Dictionary = {}          # Combatant → {pos, scale, z, modulate}
var _live_tweens: Array[Tween] = []
var _windup_started_msec: int = -1
var _windup_attacker: Combatant = null
var _windup_target: Combatant = null
## Generation counter: bumped on every new presentation entry (windup or
## impact-only) and on release. Coroutines re-check it after each await and
## abort when stale, so an overlapping attack can never resume an old
## choreography against the new one's snapshots.
var _gen: int = 0


func setup(world_layer: Node2D, dim_overlay: TextureRect, center_lane: Vector2) -> void:
	_world_layer = world_layer
	_dim_overlay = dim_overlay
	_center_lane = center_lane
	if _dim_overlay != null:
		_dim_overlay.texture = _build_dim_texture()
		_dim_overlay.modulate.a = 0.0


# ── Pure helpers (unit-tested) ────────────────────────────────────────────────

static func popup_text(did_breach: bool, is_massive: bool, wounds: int) -> String:
	if not did_breach:
		return "Blocked"
	if is_massive:
		return "-%d MASSIVE" % wounds
	if wounds == 0:
		# Wound-suppressing discipline cast (Mind Rend / Time Lock): breach lands
		# but the wound is suppressed. Unreachable from _resolve_attack breaches.
		return "Breached!"
	return "-%d" % wounds


static func popup_color(did_breach: bool, is_massive: bool) -> Color:
	if not did_breach:
		return COLOR_BLOCKED
	if is_massive:
		return COLOR_MASSIVE
	return COLOR_WOUND


## Point `weight` of the way from `from` toward `center_lane` (0 = stay, 1 = lane).
static func emphasis_offset(from: Vector2, center_lane: Vector2, weight: float) -> Vector2:
	return from.lerp(center_lane, weight)


# ── Presentation phases ───────────────────────────────────────────────────────

## Starts the windup: dim in, de-emphasize bystanders, emphasize attacker+target,
## lunge attacker toward target (skipped for casts). Re-entrant: a new windup
## first kills live tweens and snap-restores the previous participants.
func begin_windup(attacker: Combatant, target: Combatant, others: Array, lunge: bool = true) -> void:
	if attacker == null or target == null:
		return
	_gen += 1
	_reset_presentation()
	_windup_attacker = attacker
	_windup_target = target
	_windup_started_msec = Time.get_ticks_msec()

	_snapshot(attacker)
	_snapshot(target)

	var t := _make_tween()
	if _dim_overlay != null:
		t.parallel().tween_property(_dim_overlay, "modulate:a", 1.0, DIM_IN_S)
	for o in others:
		var c := o as Combatant
		if c == null or c == attacker or c == target:
			continue
		_snapshot(c)
		t.parallel().tween_property(c, "modulate", NONPARTICIPANT_GRAY, DIM_IN_S)

	# Attacker emphasis + lunge.
	var atk_base: Vector2 = emphasis_offset(
		(_snapshots[attacker]["pos"] as Vector2), _center_lane, ATTACKER_LANE_WEIGHT)
	var atk_pos := atk_base
	if lunge:
		var dir: Vector2 = ((_snapshots[target]["pos"] as Vector2) - atk_base).normalized()
		atk_pos = atk_base + dir * LUNGE_PX
	attacker.z_index = 10
	t.parallel().tween_property(attacker, "scale", Vector2.ONE * ATTACKER_SCALE, WINDUP_S) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(attacker, "global_position", atk_pos, WINDUP_S) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Target emphasis.
	var tgt_pos: Vector2 = emphasis_offset(
		(_snapshots[target]["pos"] as Vector2), _center_lane, TARGET_LANE_WEIGHT)
	target.z_index = 9
	t.parallel().tween_property(target, "scale", Vector2.ONE * TARGET_SCALE, WINDUP_S) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(target, "global_position", tgt_pos, WINDUP_S) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Plays the impact beat: waits for the lunge apex if a windup is running, then
## recoil + burst + popup, holds, and restores everything to its snapshot.
## Safe to call with no preceding windup (echo / mind-detonation): impact-only.
func play_impact(target: Combatant, did_breach: bool, is_massive: bool,
		wounds: int, defeated: bool) -> void:
	if target == null:
		return
	var had_windup := _windup_started_msec >= 0 and _windup_target == target
	var gen: int
	if had_windup:
		gen = _gen
		var elapsed := (Time.get_ticks_msec() - _windup_started_msec) / 1000.0
		var remaining := WINDUP_S - elapsed
		if remaining > 0.0:
			await get_tree().create_timer(remaining).timeout
			if gen != _gen:
				return  # a newer presentation took over while we waited
	else:
		# Impact with no matching windup (echo, detonation): clean entry —
		# hard-restore anything in flight FIRST so the snapshot below can
		# never capture a mid-tween (displaced) position.
		_gen += 1
		gen = _gen
		_reset_presentation()
		_snapshot(target)
		if _dim_overlay != null:
			var pulse := _make_tween()
			pulse.tween_property(_dim_overlay, "modulate:a", 1.0, DIM_IN_S)

	if did_breach:
		_recoil(target, defeated)
		_spawn_burst(target.global_position)
	_spawn_popup(target.global_position, popup_text(did_breach, is_massive, wounds),
		popup_color(did_breach, is_massive))
	if defeated:
		target.fade_name_label()

	var hold := RELEASE_HOLD_S + (DEATH_EXTRA_HOLD_S if defeated else 0.0)
	await get_tree().create_timer(hold).timeout
	if gen != _gen:
		return  # superseded during the hold — the newer entry owns cleanup
	_release(defeated)


## Debug/replay entry: full windup→impact→release with mock payload.
func debug_replay(attacker: Combatant, target: Combatant, others: Array,
		did_breach: bool, is_massive: bool, wounds: int, kill_beat: bool) -> void:
	begin_windup(attacker, target, others)
	await play_impact(target, did_breach, is_massive, wounds, kill_beat)


# ── Internals ─────────────────────────────────────────────────────────────────

func _release(defeated: bool) -> void:
	# Own this cleanup: any other pending impact coroutine becomes stale.
	_gen += 1
	var t := _make_tween()
	if _dim_overlay != null:
		t.parallel().tween_property(_dim_overlay, "modulate:a", 0.0, DIM_OUT_S)
	for c in _snapshots.keys():
		var node := c as Combatant
		if node == null or not is_instance_valid(node):
			continue
		var snap: Dictionary = _snapshots[c]
		node.z_index = snap["z"] as int
		if defeated and node == _windup_target:
			# Dead node: die anim stays frozen; just put it back on its anchor.
			node.global_position = snap["pos"] as Vector2
			node.scale = snap["scale"] as Vector2
			continue
		t.parallel().tween_property(node, "global_position", snap["pos"] as Vector2, RESTORE_S)
		t.parallel().tween_property(node, "scale", snap["scale"] as Vector2, RESTORE_S)
		t.parallel().tween_property(node, "modulate", snap["modulate"] as Color, RESTORE_S)
	t.finished.connect(_hard_restore)
	_windup_started_msec = -1
	_windup_attacker = null
	_windup_target = null


## Snap everything back to exact snapshot values (float-drift proof) and clear state.
func _hard_restore() -> void:
	for c in _snapshots.keys():
		var node := c as Combatant
		if node == null or not is_instance_valid(node):
			continue
		var snap: Dictionary = _snapshots[c]
		node.global_position = snap["pos"] as Vector2
		node.scale = snap["scale"] as Vector2
		node.z_index = snap["z"] as int
		node.modulate = snap["modulate"] as Color
	_snapshots.clear()


## Kills live tweens and hard-restores previous participants (re-entrancy guard).
func _reset_presentation() -> void:
	for t in _live_tweens:
		if t != null and t.is_valid():
			t.kill()
	_live_tweens.clear()
	_hard_restore()
	if _dim_overlay != null:
		_dim_overlay.modulate.a = 0.0
	_windup_started_msec = -1
	_windup_attacker = null
	_windup_target = null


func _snapshot(c: Combatant) -> void:
	if c == null or _snapshots.has(c):
		return
	_snapshots[c] = {
		"pos": c.global_position,
		"scale": c.scale,
		"z": c.z_index,
		"modulate": c.modulate,
	}


func _make_tween() -> Tween:
	var t := create_tween()
	_live_tweens.append(t)
	return t


func _recoil(target: Combatant, defeated: bool) -> void:
	if _snapshots.has(target):
		var away: Vector2 = (target.global_position - _center_lane).normalized()
		if away == Vector2.ZERO:
			away = Vector2.RIGHT
		var t := _make_tween()
		t.tween_property(target, "global_position",
			target.global_position + away * RECOIL_PX, 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if not defeated:
			t.tween_property(target, "global_position",
				emphasis_offset(_snapshots[target]["pos"] as Vector2, _center_lane, TARGET_LANE_WEIGHT),
				0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func _spawn_burst(pos: Vector2) -> void:
	if _world_layer == null:
		return
	var frames := SpriteRegistry.get_effect_frames("ImpactBurst")
	if frames == null:
		return  # asset not authored yet — feature degrades gracefully
	var fx := AnimatedSprite2D.new()
	fx.sprite_frames = frames
	fx.z_index = 15
	_world_layer.add_child(fx)
	fx.global_position = pos
	fx.sprite_frames.set_animation_loop("default", false)
	fx.animation_finished.connect(fx.queue_free)
	fx.play("default")


func _spawn_popup(pos: Vector2, text: String, color: Color) -> void:
	if _world_layer == null:
		return
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.z_index = 20
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_world_layer.add_child(label)
	label.global_position = pos + Vector2(-label.size.x / 2.0, -40.0)
	var t := create_tween()
	t.parallel().tween_property(label, "global_position:y", label.global_position.y - POPUP_RISE_PX, POPUP_FADE_S)
	t.parallel().tween_property(label, "modulate:a", 0.0, POPUP_FADE_S)
	t.finished.connect(label.queue_free)


func _build_dim_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, DIM_CENTER_ALPHA))
	g.set_color(1, Color(0, 0, 0, DIM_EDGE_ALPHA))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 640
	tex.height = 360
	return tex
