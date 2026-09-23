extends RefCounted
class_name StaticLampTest
## Per the request ("add 2 static lamps in the village in the marked
## locations, these should come on at night time and cast secondary
## shadows around them"): covers the new fixed-position lamp feature —
## Overworld.static_lamp_coords (populated in _build_map()), the lamp's
## day/night glow sprite (_static_lamp_glow_sprites, faded by
## _update_shadow_angles() off GameState's own night_darkness curve),
## and its own independent secondary-shadow pass
## (_apply_static_lamp_secondary_shadows(), a per-lamp mirror of
## _apply_light_source_secondary_shadows() built for the player's own
## carried light).
##
## Case 1 confirms both authored "l" tiles on giessingen_village were
## picked up into static_lamp_coords. Case 2 confirms a lamp tile blocks
## movement, same as the well. Case 3 confirms the glow is fully faded
## by day and clearly lit by night. Case 4 confirms an eligible object
## (an injected tree) right next to a lit lamp at night gets its own
## pooled shadow sprite, sourced from that LAMP's position (not the
## player's, which is elsewhere on the map). Case 5 confirms that same
## tree's shadow sprite is hidden again once it's day (lamp unlit).
## Case 6 confirms this whole feature never touched the pre-existing,
## player-only _light_shadow_sprites/_light_wall_shadow_nodes pools.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()

	## Deep night core (23:00) so the lamps have a genuine dark backdrop
	## to "come on" against once loaded.
	GameState.time_minutes = 23 * 60
	GameState.pending_map_path = "res://data/maps/giessingen_village.tres"
	var ow = load("res://scenes/Overworld.tscn").instantiate()
	tree.get_root().add_child(ow)
	tree.current_scene = ow
	for i in range(10):
		await tree.process_frame

	## --- Case 1: both authored lamps were picked up.
	checks.append(["Case 1: static_lamp_coords has exactly the 2 authored lamp tiles", ow.static_lamp_coords.size() == 2])
	var lamp_coords: Vector2i = ow.static_lamp_coords[0] if ow.static_lamp_coords.size() > 0 else Vector2i(-1, -1)
	checks.append(["Case 1: the first lamp's own map tile really is STATIC_LAMP_CHAR", ow.tile_chars.get(lamp_coords, "") == ow.STATIC_LAMP_CHAR])

	## --- Case 2: a lamp blocks movement, same as the well.
	checks.append(["Case 2: STATIC_LAMP_CHAR is in BLOCKED, same as the well", ow.BLOCKED.has(ow.STATIC_LAMP_CHAR)])
	checks.append(["Case 2: is_walkable() genuinely refuses a lamp's own tile", not ow.is_walkable(lamp_coords)])

	## --- Case 3: glow fade tracks night_darkness.
	GameState.time_minutes = 13 * 60   ## broad daylight
	ow._update_shadow_angles()
	var glow_day: Sprite2D = ow._static_lamp_glow_sprites.get(lamp_coords)
	checks.append(["Case 3: the lamp's glow sprite exists", glow_day != null])
	if glow_day != null:
		checks.append(["Case 3: ...and is fully faded out by day", is_zero_approx(glow_day.modulate.a)])
	GameState.time_minutes = 23 * 60   ## deep night
	ow._update_shadow_angles()
	var glow_night: Sprite2D = ow._static_lamp_glow_sprites.get(lamp_coords)
	if glow_night != null:
		checks.append(["Case 3: ...and clearly lit by night", glow_night.modulate.a > 0.5])

	## --- Case 4: a tree right next to the (now lit) lamp gets its own
	## lamp-sourced secondary shadow.
	var tree_coords: Vector2i = lamp_coords + Vector2i(1, 0)
	var previous_ch: String = ow.tile_chars.get(tree_coords, ".")
	ow.tile_chars[tree_coords] = "T"
	ow._apply_static_lamp_secondary_shadows()
	var lamp_sprites: Dictionary = ow._static_lamp_tile_shadow_sprites.get(0, {})
	checks.append(["Case 4: a tree beside a lit static lamp gets a pooled lamp-shadow sprite", lamp_sprites.has(tree_coords)])
	if lamp_sprites.has(tree_coords):
		var spr: Sprite2D = lamp_sprites[tree_coords]
		checks.append(["Case 4: ...and it's genuinely visible", spr.visible])
		checks.append(["Case 4: ...using the real tree shadow texture", spr.texture == ow.SHADOW_TEXTURE_TREE])

	## --- Case 5: by day, the same lamp casts no shadows at all (it's
	## off) -- the tree's pooled sprite (if any survives from Case 4)
	## must not be left visible.
	GameState.time_minutes = 13 * 60
	ow._apply_static_lamp_secondary_shadows()
	var lamp_sprites_day: Dictionary = ow._static_lamp_tile_shadow_sprites.get(0, {})
	var day_sprite: Sprite2D = lamp_sprites_day.get(tree_coords)
	checks.append(["Case 5: by day, the (unlit) lamp's own tree shadow is hidden again", day_sprite == null or not day_sprite.visible])
	ow.tile_chars[tree_coords] = previous_ch

	## --- Case 6: the pre-existing player-only pools are untouched by
	## any of the above -- still present, still their own separate dict/
	## array, never merged with the static-lamp ones.
	checks.append(["Case 6: the player's own _light_shadow_sprites pool still exists, separate from the lamps' own", ow._light_shadow_sprites != null and typeof(ow._light_shadow_sprites) == TYPE_DICTIONARY])
	checks.append(["Case 6: the player's own _light_wall_shadow_nodes pool is still a plain Array (per-lamp pools are Dictionary-keyed instead)", typeof(ow._light_wall_shadow_nodes) == TYPE_ARRAY])
	checks.append(["Case 6: the static lamps' own wall-shadow pool is Dictionary-keyed by lamp index, not merged into _light_wall_shadow_nodes", typeof(ow._static_lamp_wall_shadow_nodes) == TYPE_DICTIONARY])

	ow.queue_free()
	for i in range(3):
		await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Static Lamps): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
