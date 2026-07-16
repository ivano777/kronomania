# AttackPresenter — Darkest-Dungeon-style attack presentation.
# Owns the dim overlay, emphasis/lunge/recoil tweens, impact burst and damage
# popups over Combatant visuals. Purely presentational: reads CombatManager
# signals routed through BattleScene, never touches combat state.
class_name AttackPresenter
extends Node

# ── Tunables ──────────────────────────────────────────────────────────────────
const WINDUP_S := 0.25          # attacker lunge duration; impact syncs to its apex
const TRAVEL_S := 0.18          # projectile flight time (windup apex → impact)
const RELEASE_HOLD_S := 0.45    # pause at impact before everything restores
const BLOCK_FX := "BlockSpark"  # shared clip on the defender when a hit is blocked
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

# ── FX intensity (die size → scale, node level → count, rarity → aura) ───────
## Muted 4-step rarity auras: tint applied to slash/projectile clips.
const RARITY_TINTS := {
	"common": Color.WHITE,
	"fine":   Color(0.78, 0.88, 1.0),   # steel-blue
	"arcane": Color(0.86, 0.72, 1.0),   # violet
	"relic":  Color(1.0, 0.86, 0.55),   # gold
}
const RARITY_SCALE_BONUS := {
	"common": 0.0, "fine": 0.05, "arcane": 0.10, "relic": 0.15,
}
## Cluster anchor offsets for multi-instance FX (governing node level 1..3).
## Anchors are fixed; projectile flights add small random jitter on top —
## visual-only randomness, combat state never reads it.
const FX_COUNT_OFFSETS: Array[Vector2] = [Vector2.ZERO, Vector2(9, -7), Vector2(-8, 6)]
## Launch gap inside a projectile volley; later launches fly faster so the
## whole volley still arrives together after TRAVEL_S.
const PROJECTILE_STAGGER_S := 0.05

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


## Effect clip a breach impact plays: the action's own clip, else the generic burst.
static func impact_clip_name(impact_fx: String) -> String:
	return impact_fx if impact_fx != "" else "ImpactBurst"


## Projectile clips are authored facing RIGHT; flying left means mirroring.
static func projectile_flip_h(from_x: float, to_x: float) -> bool:
	return to_x < from_x


## Governing stat die size → FX sprite scale: d4 0.85 · d6 1.0 · d8 1.15 ·
## d10 1.3 · d12 1.45 (clamped for out-of-track sizes).
static func fx_scale_for_die(die_size: int) -> float:
	return clampf(0.85 + 0.075 * float(die_size - 4), 0.85, 1.45)


## Governing node level → number of FX instances. 0 (no node / enemies) → 1.
static func fx_count_for_level(level: int) -> int:
	return clampi(level, 1, 3)


## Item rarity → aura tint on slash/projectile clips. Unknown rarity = untinted.
static func rarity_tint(rarity: String) -> Color:
	return RARITY_TINTS.get(rarity, Color.WHITE)


## Item rarity → small additive FX scale bonus.
static func rarity_scale_bonus(rarity: String) -> float:
	return RARITY_SCALE_BONUS.get(rarity, 0.0)


# ── Presentation phases ───────────────────────────────────────────────────────

## Starts the windup: dim in, de-emphasize bystanders, emphasize attacker+target,
## lunge attacker toward target (skipped for casts). `windup_fx` names a shared
## effect clip spawned on the attacker (weapon glow, gathering magic); "" = none.
## `fx_scale` (stat die + rarity) sizes the clip, `fx_count` (governing node
## level) clusters extra instances.
## Re-entrant: a new windup first kills live tweens and snap-restores the
## previous participants.
func begin_windup(attacker: Combatant, target: Combatant, others: Array, lunge: bool = true,
		windup_fx: String = "", fx_scale: float = 1.0, fx_count: int = 1) -> void:
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

	# Attacker-side effect (weapon glow / gathering magic) — parented to the
	# attacker so it rides the lunge/emphasis motion. No rarity tint here;
	# auras belong to the slash/projectile clips.
	_spawn_fx_multi(Vector2.ZERO, windup_fx, fx_count, 15, attacker, fx_scale)


## Plays the impact beat: waits for the lunge apex if a windup is running,
## flies `projectile_fx` from attacker to target if set (windup path only),
## then recoil + impact effect + white flash + popup, holds, and restores
## everything to its snapshot. `impact_fx` names the shared effect clip played
## on the target on breach ("" = generic "ImpactBurst"); blocked hits play the
## generic BLOCK_FX instead (always plain — the block belongs to the defender).
## `fx_scale`/`fx_count` size and cluster the impact clips; `fx_tint` is the
## item-rarity aura on the impact + projectile clips.
## Safe to call with no preceding windup (echo / mind-detonation): impact-only.
func play_impact(target: Combatant, did_breach: bool, is_massive: bool,
		wounds: int, defeated: bool, impact_fx: String = "",
		projectile_fx: String = "", fx_scale: float = 1.0, fx_count: int = 1,
		fx_tint: Color = Color.WHITE) -> void:
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
		# Projectile leg: fly a volley (one per fx_count, matching the impact
		# cluster) from the attacker's apex to the target, delaying the impact
		# by TRAVEL_S. Windup path only — impact-only entries (echo /
		# detonation) have no attacker to launch from.
		if projectile_fx != "" and _windup_attacker != null \
				and is_instance_valid(_windup_attacker):
			await _fly_projectiles(_windup_attacker.global_position,
				target.global_position, projectile_fx, fx_count, fx_scale, fx_tint)
			if gen != _gen:
				return
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
		_spawn_fx_multi(target.global_position, impact_clip_name(impact_fx),
			fx_count, 15, null, fx_scale, fx_tint)
		target.flash()
	else:
		_spawn_fx(target.global_position, BLOCK_FX)
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
		did_breach: bool, is_massive: bool, wounds: int, kill_beat: bool,
		windup_fx: String = "", impact_fx: String = "", projectile_fx: String = "",
		fx_scale: float = 1.0, fx_count: int = 1, fx_tint: Color = Color.WHITE) -> void:
	begin_windup(attacker, target, others, true, windup_fx, fx_scale, fx_count)
	await play_impact(target, did_breach, is_massive, wounds, kill_beat, impact_fx,
		projectile_fx, fx_scale, fx_count, fx_tint)


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


## Spawns a one-shot shared effect clip at `pos`. Self-terminating: plays once
## (loop forced off so a stray looping clip can't linger) and frees itself, so
## it needs no generation guard. "" or missing clip = no-op (degrades gracefully).
## With `parent` set, the clip is attached to that node with `pos` as local
## offset (rides the attacker's motion); z stays absolute so parent emphasis z
## can't push FX over popups.
func _spawn_fx(pos: Vector2, clip_name: String, z: int = 15, parent: Node2D = null,
		fx_scale: float = 1.0, tint: Color = Color.WHITE) -> void:
	if _world_layer == null or clip_name == "":
		return
	var frames := SpriteRegistry.get_effect_frames(clip_name)
	if frames == null:
		return  # asset not authored yet — feature degrades gracefully
	var fx := AnimatedSprite2D.new()
	fx.sprite_frames = frames
	fx.z_index = z
	fx.z_as_relative = false
	fx.scale = Vector2.ONE * fx_scale
	fx.modulate = tint
	if parent != null:
		parent.add_child(fx)
		fx.position = pos
	else:
		_world_layer.add_child(fx)
		fx.global_position = pos
	fx.sprite_frames.set_animation_loop("default", false)
	fx.animation_finished.connect(fx.queue_free)
	fx.play("default")


## Spawns `count` instances of a clip as a fixed-offset cluster (extras render
## smaller, reading as secondary particles). Count clamps to the offset table.
func _spawn_fx_multi(pos: Vector2, clip_name: String, count: int, z: int = 15,
		parent: Node2D = null, fx_scale: float = 1.0, tint: Color = Color.WHITE) -> void:
	for i in mini(maxi(count, 1), FX_COUNT_OFFSETS.size()):
		var inst_scale := fx_scale * (1.0 if i == 0 else 0.75)
		_spawn_fx(pos + FX_COUNT_OFFSETS[i] * fx_scale, clip_name, z, parent,
			inst_scale, tint)


## Flies `count` copies of a looping projectile clip from `from` to the target
## cluster anchors (the same points the impact clips will spawn on), with a
## small random spread so parallel bolts never overlap visually. Launches are
## staggered but later bolts fly faster — the volley arrives together, so the
## total leg stays TRAVEL_S and attack pacing is unaffected. Movement tweens
## register as live tweens (killed by a re-entrant windup); cleanup runs off a
## timer so no sprite outlives its flight.
func _fly_projectiles(from: Vector2, to: Vector2, clip_name: String, count: int = 1,
		fx_scale: float = 1.0, tint: Color = Color.WHITE) -> void:
	if _world_layer == null or clip_name == "":
		return
	var frames := SpriteRegistry.get_effect_frames(clip_name)
	if frames == null:
		return  # asset not authored yet — impact just lands immediately
	var n := mini(maxi(count, 1), FX_COUNT_OFFSETS.size())
	var flock: Array[AnimatedSprite2D] = []
	for i in n:
		if i > 0:
			await get_tree().create_timer(PROJECTILE_STAGGER_S).timeout
		var start := from + Vector2(randf_range(-3.0, 3.0), randf_range(-6.0, 6.0))
		var end := to + FX_COUNT_OFFSETS[i] * fx_scale \
				+ Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
		var fx := AnimatedSprite2D.new()
		fx.sprite_frames = frames
		fx.z_index = 15
		fx.z_as_relative = false
		fx.flip_h = projectile_flip_h(start.x, end.x)
		fx.scale = Vector2.ONE * (fx_scale if i == 0 else fx_scale * 0.85)
		fx.modulate = tint
		_world_layer.add_child(fx)
		fx.global_position = start
		fx.play("default")
		flock.append(fx)
		var t := _make_tween()
		t.tween_property(fx, "global_position", end,
			maxf(TRAVEL_S - i * PROJECTILE_STAGGER_S, 0.06))
	# Elapsed so far: (n-1) staggers — wait out the shared arrival tick.
	await get_tree().create_timer(maxf(TRAVEL_S - (n - 1) * PROJECTILE_STAGGER_S, 0.06)).timeout
	for fx in flock:
		if is_instance_valid(fx):
			fx.queue_free()


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
