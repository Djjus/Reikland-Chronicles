extends RefCounted
class_name SecondaryLightShadowTest
## Per the request ("add secondary shadows for light sources. objects
## with no line of sight or that cast shadows already should all be
## included"): Overworld._apply_light_source_secondary_shadows() —
## the carried light source's own short-range, radial shadow layer,
## on top of the long/slow sun-moon sweep _update_shadow_angles()
## already handles.
##
## Case 1 confirms an eligible object (an injected tree tile) within
## the light's own capped shadow range gets a genuine, visible pooled
## shadow sprite, using the tree shadow texture, rotated to point AWAY
## from the light (a due-EAST object's shadow should point further
## east, landing at ~PI/2 — the same "-90°/-PI/2 natural up"
## correction the sun/moon sweep already uses). Case 2 confirms an
## object well outside the capped range never gets a sprite at all.
## Case 3 confirms a plain, non-eligible tile (grass) never gets one
## either. Case 4 confirms turning the light off hides every pooled
## sprite (none left visible). Case 5 confirms turning it back on
## reuses the SAME pooled node rather than creating a new one. Case 6
## spot-checks SECONDARY_LIGHT_SHADOW_CHARS' own composition: it
## includes objects that already cast a primary shadow (a tree) AND
## line-of-sight-blocking objects that previously cast none at all (a
## standing stone), while deliberately excluding water even though
## water blocks movement too.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.inventory.clear()
	pc.equipped_weapon = ""
	pc.equipped_offhand = ""
	pc.inventory.append("Lantern")
	pc.equipped_weapon = "Lantern"
	pc.light_mode = "on"
	pc.light_fuel_minutes = 200.0

	## Deep night core (22:30) so _light_source_effective() has a
	## genuine dark backdrop to work against once the lantern is lit.
	GameState.time_minutes = 22 * 60 + 30
	GameState.pending_map_path = "res://data/maps/giessingen_village.tres"
	var ow = load("res://scenes/Overworld.tscn").instantiate()
	tree.get_root().add_child(ow)
	tree.current_scene = ow
	for i in range(10):
		await tree.process_frame

	checks.append(["setup: light_shadow_container exists after map load", ow.light_shadow_container != null])
	var radius: int = pc.get_active_light_radius_tiles()
	checks.append(["setup: a lit Lantern genuinely has a real radius (> 0)", radius > 0])

	## Per the "secondary lights should remove both primary and secondary
	## shadows within their light LOS" follow-up: the real village map
	## carries 2 static lamps whose own 10-tile LOS can genuinely reach
	## the player's own default spawn point, which would now legitimately
	## suppress the player-light shadows this test is specifically
	## exercising (a different, dedicated concern — see
	## secondary_light_lights_combine_test.gd). Cleared here so this file
	## stays a clean, isolated test of the player's own carried light,
	## unaffected by whichever real lamps happen to be nearby on this map.
	ow.static_lamp_coords.clear()

	## --- Case 1: inject a synthetic tree tile 2 squares due EAST of
	## the player, safely inside SECONDARY_LIGHT_SHADOW_MAX_RANGE_TILES.
	var east_coords: Vector2i = ow.player.grid_pos + Vector2i(2, 0)
	ow.tile_chars[east_coords] = "T"
	ow._apply_light_source_secondary_shadows()
	checks.append(["Case 1: a tree within the light's own shadow range gets a pooled light-shadow sprite", ow._light_shadow_sprites.has(east_coords)])
	if ow._light_shadow_sprites.has(east_coords):
		var spr: Sprite2D = ow._light_shadow_sprites[east_coords]
		checks.append(["Case 1: ...and it's genuinely visible", spr.visible])
		checks.append(["Case 1: ...using the real tree shadow texture", spr.texture == ow.SHADOW_TEXTURE_TREE])
		checks.append(["Case 1: a due-EAST object's shadow rotation lands near PI/2 (points further east, away from the light)", is_equal_approx(spr.rotation, PI / 2.0)])

	## --- Case 2: an eligible object well beyond the capped shadow
	## range never gets a sprite, even though it's the same char.
	var far_coords: Vector2i = ow.player.grid_pos + Vector2i(ow.SECONDARY_LIGHT_SHADOW_MAX_RANGE_TILES + 10, 0)
	ow.tile_chars[far_coords] = "T"
	ow._apply_light_source_secondary_shadows()
	checks.append(["Case 2: an eligible object well outside the shadow's own capped range gets no light-shadow sprite at all", not ow._light_shadow_sprites.has(far_coords)])

	## --- Case 3: a plain, non-eligible tile (grass) right next to the
	## player never gets a VISIBLE sprite. Checked via visibility, not
	## dictionary-key absence — the real map may have already had some
	## other eligible tile at this exact spot during setup's own
	## process_frame waits (before this override), leaving a pooled-but-
	## now-correctly-hidden sprite behind, which is the intended reuse
	## behaviour (see Case 5), not a bug.
	var grass_coords: Vector2i = ow.player.grid_pos + Vector2i(0, 1)
	ow.tile_chars[grass_coords] = "."
	ow._apply_light_source_secondary_shadows()
	var grass_sprite: Sprite2D = ow._light_shadow_sprites.get(grass_coords)
	checks.append(["Case 3: a plain, non-shadow-casting tile (grass) never has a VISIBLE light-shadow sprite", grass_sprite == null or not grass_sprite.visible])

	## --- Case 4: turning the light off hides every pooled sprite.
	pc.light_mode = "off"
	ow._apply_light_source_secondary_shadows()
	var any_visible := false
	for coords in ow._light_shadow_sprites:
		if ow._light_shadow_sprites[coords].visible:
			any_visible = true
	checks.append(["Case 4: turning the light off hides every pooled light-shadow sprite -- none left visible", not any_visible])

	## --- Case 5: relighting reuses the same pooled node.
	pc.light_mode = "on"
	var sprite_before: Sprite2D = ow._light_shadow_sprites.get(east_coords)
	ow._apply_light_source_secondary_shadows()
	checks.append(["Case 5: relighting brings the still-in-range tree's shadow back visible", ow._light_shadow_sprites.has(east_coords) and ow._light_shadow_sprites[east_coords].visible])
	checks.append(["Case 5: ...reusing the SAME pooled Sprite2D node rather than creating a new one", ow._light_shadow_sprites.get(east_coords) == sprite_before])

	## --- Case 6: SECONDARY_LIGHT_SHADOW_CHARS' own composition.
	checks.append(["Case 6: a standing stone ('o') is eligible even though it never cast a primary shadow before this", ow.SECONDARY_LIGHT_SHADOW_CHARS.has("o") and not ow.SHADOW_CASTING_CHARS.has("o")])
	checks.append(["Case 6: water ('~') is deliberately excluded even though it blocks movement too", not ow.SECONDARY_LIGHT_SHADOW_CHARS.has("~")])
	checks.append(["Case 6: a tree ('T') -- already a primary shadow-caster -- is eligible", ow.SECONDARY_LIGHT_SHADOW_CHARS.has("T")])
	checks.append(["Case 6: a fence ('I') is eligible", ow.SECONDARY_LIGHT_SHADOW_CHARS.has("I")])
	checks.append(["Case 6: the well ('W') -- solid, blocks movement, never had a primary shadow -- is eligible", ow.SECONDARY_LIGHT_SHADOW_CHARS.has("W")])

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
	print("RESULT (Secondary Light Source Shadows): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
