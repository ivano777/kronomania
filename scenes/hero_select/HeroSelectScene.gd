# HeroSelectScene — dedicated hero-variant picker shown after New Game setup
# (name + slot), before the run's first Campfire. Records the choice into
# PlayerProgression.hero_sprite; the save file itself is written at Campfire.
# All UI is built in code; the .tscn only carries the root Control + script.
extends Control

# key = folder under assets/sprites/combatants/ and the PlayerProgression.hero_sprite value.
const _HERO_CHOICES: Array[Dictionary] = [
	{"key": "player",  "label": "Warrior",    "blurb": "A seasoned blade. The steady default."},
	{"key": "heroine", "label": "Warrioress", "blurb": "A green recruit with steel to prove."},
]

# One idle-loop driver per hero card, advanced in _process.
# Each: {rect: TextureRect, tex: Array[Texture2D], fps: float, t: float, idx: int}
var _anim_previews: Array = []


func _ready() -> void:
	# Same darkened town backdrop as the main menu, for continuity.
	var bg_tex := SpriteRegistry.get_background("menu")
	if bg_tex != null:
		var bg_rect := TextureRect.new()
		bg_rect.texture = bg_tex
		bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg_rect.modulate = Color(0.42, 0.42, 0.52)
		add_child(bg_rect)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_top", "margin_left", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "♦  CHOOSE YOUR HERO  ♦"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 48)
	vbox.add_child(row)

	for choice in _HERO_CHOICES:
		row.add_child(_build_hero_card(choice))

	vbox.add_child(HSeparator.new())

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(_on_back)
	vbox.add_child(back_btn)


func _build_hero_card(choice: Dictionary) -> Control:
	var key: String = choice["key"]
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)

	var preview := TextureRect.new()
	# 640x360 viewport — keep the whole card (preview + label + button) on screen.
	preview.custom_minimum_size = Vector2(88, 104)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_setup_idle_preview(preview, key)
	col.add_child(preview)

	var name_lbl := Label.new()
	name_lbl.text = str(choice["label"])
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_lbl)

	var blurb := Label.new()
	blurb.text = str(choice["blurb"])
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(160, 0)
	col.add_child(blurb)

	var choose_btn := Button.new()
	choose_btn.text = "Choose"
	choose_btn.pressed.connect(_on_choose.bind(key))
	col.add_child(choose_btn)

	return col


# Loads the idle frames for a hero into a TextureRect and registers a driver so
# _process cycles them as a looping animation. No-op if the art is missing.
func _setup_idle_preview(rect: TextureRect, hero_key: String) -> void:
	var frames := SpriteRegistry.get_combatant_frames(hero_key)
	if frames == null or not frames.has_animation("idle") \
			or frames.get_frame_count("idle") == 0:
		return
	var textures: Array = []
	for i in frames.get_frame_count("idle"):
		textures.append(frames.get_frame_texture("idle", i))
	rect.texture = textures[0]
	_anim_previews.append({
		"rect": rect,
		"tex": textures,
		"fps": maxf(frames.get_animation_speed("idle"), 1.0),
		"t": 0.0,
		"idx": 0,
	})


func _process(delta: float) -> void:
	for p in _anim_previews:
		var textures: Array = p["tex"]
		if textures.size() <= 1:
			continue
		p["t"] += delta
		var frame_time := 1.0 / float(p["fps"])
		while p["t"] >= frame_time:
			p["t"] -= frame_time
			p["idx"] = (int(p["idx"]) + 1) % textures.size()
			(p["rect"] as TextureRect).texture = textures[p["idx"]]


# Records the chosen variant. Kept separate from scene navigation so tests can
# exercise the choice without triggering a scene change.
func _apply_choice(hero_key: String) -> void:
	PlayerProgression.hero_sprite = hero_key


func _on_choose(hero_key: String) -> void:
	_apply_choice(hero_key)
	get_tree().change_scene_to_file("res://scenes/campfire/CampfireScene.tscn")


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/MainMenuScene.tscn")
