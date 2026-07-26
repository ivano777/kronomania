extends GutTest

# AuraGen key-pair determinism + spec range sanity. Generation is pure static
# (RNG seeded from hash(PRIVATE_KEY :: public_key)) — no scene, no autoloads.
# Rarity is seed-rolled luck; tier is a caller input applied as a draw-free
# post-transform, so it may never change the aura's identity.


## Serializes every spec field (textures by pixel-data hash) so two specs can
## be compared for exact equality.
func _fingerprint(spec: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append(str(spec["seed"]))
	parts.append(String(spec["name"]))
	parts.append(String(spec["rarity"]))
	parts.append(str(spec["tier"]))
	parts.append(str(spec["layer_potential"]))
	parts.append(_identity_fingerprint(spec))
	for layer in (spec["layers"] as Array):
		var keys: Array = (layer as Dictionary).keys()
		keys.sort()
		for k in keys:
			parts.append("%s=%s" % [k, str((layer as Dictionary)[k])])
	parts.append(str(spec["rot_deg_s"]))
	parts.append("%f/%f/%f" % [spec["pulse_hz"], spec["pulse_amp"], spec["intensity"]])
	parts.append(",".join(spec["mutations"]))
	return "|".join(parts)


## The tier-invariant part: name, palette, textures. Must be byte-identical
## for the same key at any tier.
func _identity_fingerprint(spec: Dictionary) -> String:
	var parts: Array[String] = [String(spec["name"])]
	var pal: Dictionary = spec["palette"]
	parts.append(String(pal["scheme"]))
	parts.append(String(pal["profile"]))
	parts.append(str(pal["inverted"]))
	for c in (pal["ramp"] as Array):
		parts.append((c as Color).to_html())
	parts.append((pal["glow"] as Color).to_html())
	for img in (spec["textures"] as Array):
		parts.append(str((img as Image).get_size()))
		parts.append(str(hash((img as Image).get_data())))
	return "|".join(parts)


func _has_opaque(img: Image) -> bool:
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				return true
	return false


func test_same_key_pair_same_spec() -> void:
	var a := AuraGen.generate_spec("stormcrown")
	var b := AuraGen.generate_spec("stormcrown")
	assert_eq(_fingerprint(a), _fingerprint(b),
			"same public key must regenerate the identical aura")


func test_different_public_keys_diverge() -> void:
	assert_ne(AuraGen.derive_seed("alpha"), AuraGen.derive_seed("beta"))
	assert_ne(_fingerprint(AuraGen.generate_spec("alpha")),
			_fingerprint(AuraGen.generate_spec("beta")))


func test_seed_binds_private_key() -> void:
	# Seed hashes the PRIVATE_KEY::public pair, not the public key alone.
	assert_ne(AuraGen.derive_seed("alpha"), "alpha".hash())


func test_tier_reveals_layers_monotonically() -> void:
	for key in ["stormcrown", "voidwake", "probe_7"]:
		var prev := 0
		for tier in range(1, 5):
			var spec := AuraGen.generate_spec(key, tier)
			assert_eq(int(spec["tier"]), tier)
			var shown := (spec["layers"] as Array).size()
			assert_true(shown >= prev, "layer count never shrinks as tier rises")
			prev = shown
		# Tier 4 reveals the full rolled potential.
		var full := AuraGen.generate_spec(key, 4)
		assert_eq((full["layers"] as Array).size(), int(full["layer_potential"]))


func test_tier_keeps_identity_and_scales_amplitude() -> void:
	for key in ["stormcrown", "voidwake", "probe_7"]:
		var t1 := AuraGen.generate_spec(key, 1)
		var t4 := AuraGen.generate_spec(key, 4)
		assert_eq(_identity_fingerprint(t1), _identity_fingerprint(t4),
				"name/palette/textures identical across tiers")
		assert_eq(String(t1["rarity"]), String(t4["rarity"]), "rarity tier-independent")
		assert_eq(",".join(t1["mutations"]), ",".join(t4["mutations"]),
				"mutation roll tier-independent")
		assert_true(float(t4["intensity"]) > float(t1["intensity"]),
				"intensity grows with tier")
		# First revealed layer exists at both tiers; its amplitude never shrinks.
		var l1: Dictionary = (t1["layers"] as Array)[0]
		var l4: Dictionary = (t4["layers"] as Array)[0]
		if l1.has("count"):
			assert_true(int(l4["count"]) >= int(l1["count"]), "count grows with tier")
		else:
			assert_true(float(l4["max_radius"]) >= float(l1["max_radius"]),
					"ripple radius grows with tier")


func test_spec_ranges_over_many_keys() -> void:
	for i in 40:
		var spec := AuraGen.generate_spec("probe_%d" % i)
		assert_true(spec["rarity"] in AuraGen.RARITIES, "known rarity")
		assert_between(int(spec["layer_potential"]), 3, 6, "layer potential")
		var texs: Array = spec["textures"]
		assert_between(texs.size(), 1, 4, "texture count")
		for t in texs:
			var img := t as Image
			assert_eq(img.get_width(), img.get_height(), "textures square")
			assert_between(img.get_width(), 7, 21, "texture size")
			assert_true(_has_opaque(img), "texture has visible pixels")
		var pal: Dictionary = spec["palette"]
		assert_eq((pal["ramp"] as Array).size(), 4, "palette ramp size")
		assert_true(pal["scheme"] in AuraGen.SCHEMES, "known scheme")
		assert_true(pal["profile"] in AuraGen.PROFILES, "known profile")
		var layers: Array = spec["layers"]
		assert_between(layers.size(), 1, 6, "layer count")
		for layer in layers:
			var l: Dictionary = layer
			assert_true(l["motion"] in AuraGen.MOTIONS, "known motion")
			if l["motion"] == "ripple":
				_check_ripple(l)
			else:
				assert_between(int(l["count"]), 3, 120, "particle count")
				assert_between(int(l["tex_idx"]), 0, texs.size() - 1, "texture index")
				assert_gt(float(l["lifetime"]), 0.0, "lifetime")
				assert_true(float(l["scale_max"]) >= float(l["scale_min"]),
						"scale range ordered")
		var muts: Array = spec["mutations"]
		assert_between(muts.size(), 0, 3, "mutation count")
		for m in muts:
			assert_true(m in AuraGen.MUTATIONS, "known mutation")
		assert_eq(muts.size(), _unique_count(muts), "mutations unique")
		assert_between(float(spec["pulse_hz"]), 0.3, 8.1, "pulse frequency")
		assert_between(float(spec["pulse_amp"]), 0.0, 0.45, "pulse amplitude")
		assert_between(float(spec["intensity"]), 0.2, 2.9, "intensity")
		assert_between(float(spec["rot_deg_s"]), -25.0, 25.0, "aura rotation")


func _check_ripple(l: Dictionary) -> void:
	assert_between(float(l["max_radius"]), 24.0, 110.0, "ripple radius")
	assert_gt(float(l["interval"]), 0.0, "ripple interval")
	assert_gt(float(l["speed"]), 0.0, "ripple speed")
	assert_between(int(l["color_idx"]), 0, 3, "ripple color index")
	assert_true(l["geometry"] in AuraGen.GEOMETRIES, "known ripple geometry")
	assert_between(int(l["sides"]), 3, 8, "ripple sides")
	var jag: Array = l["jag"]
	if l["geometry"] == "jagged":
		assert_eq(jag.size(), AuraGen.JAG_SAMPLES, "jag profile length")
		for v in jag:
			assert_between(float(v), -0.29, 0.29, "jag sample bounded")
	else:
		assert_eq(jag.size(), 0, "jag empty unless jagged")


func _unique_count(arr: Array) -> int:
	var seen := {}
	for v in arr:
		seen[v] = true
	return seen.size()


## Rare rolls must actually occur: scan a fixed key set (deterministic — same
## seeds forever) and require every rarity, at least one jagged ripple and at
## least one mutated aura.
func test_rare_paths_reachable() -> void:
	var jagged := 0
	var mutated := 0
	var rarities := {}
	for i in 300:
		var spec := AuraGen.generate_spec("scan_%d" % i)
		rarities[spec["rarity"]] = true
		if not (spec["mutations"] as Array).is_empty():
			mutated += 1
		for layer in (spec["layers"] as Array):
			var l: Dictionary = layer
			if l["motion"] == "ripple" and l["geometry"] == "jagged":
				jagged += 1
	assert_gt(jagged, 0, "jagged ripple geometry never rolled in 300 keys")
	assert_gt(mutated, 0, "no mutation rolled in 300 keys")
	for r in AuraGen.RARITIES:
		assert_true(rarities.has(r), "rarity '%s' never rolled in 300 keys" % r)
