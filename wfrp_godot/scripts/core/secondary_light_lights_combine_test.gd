extends RefCounted
class_name SecondaryLightLightsCombineTest
## Per the follow-up request ("Secondary lights should remove both
## primary and secondary shadows within their light LOS" — clarifying
## that "multiple secondary lights combine" was specifically about
## shadow removal, not brightness): a tile lit by TWO secondary light
## sources (the player's own carried light and a static lamp) should
## show NO secondary shadow from either one there — a second light's
## own reach "fills in" what would otherwise be a shadow cast by the
## first, the same real-world approximation this project's primary
## sun/moon shadow already gets suppressed by under a single light.
##
## Case 1: a tree within the player's own light range, but OUTSIDE any
## lamp's reach, still gets the player's own real shadow (the baseline —
## nothing should change when there's genuinely only one light).
## Case 2: the SAME tree, once a synthetic lamp is placed close enough
## for its own LOS to reach that tile too, loses its player-light
## shadow — suppressed by the lamp's own overlapping reach.
## Case 3: symmetric case — a tree within a lamp's own shadow range,
## but ALSO within the player's light LOS, loses ITS lamp-cast shadow
## too (the player's torch fills it in instead).
## Case 4: a lamp's own shadow is unaffected by a SECOND, more distant
## lamp that doesn't actually reach that tile — confirms this is a
## genuine reach check, not a blanket "any other lamp exists" rule.
## Case 5/6 cover the OTHER shadow shape this system draws — a merged
## WALL-run polygon, not a per-tile blob. Per the real bug report (the
## first version of this fix only excluded a wall's own SOURCE tile
## from consideration, which does nothing: the shadow it casts lands on
## GROUND tiles away from the wall, not on the wall's own tile — so the
## merged polygon kept rendering in full even squarely inside another
## light's reach). Case 5 is the baseline (an isolated wall run's
## shadow renders normally); Case 6 confirms a nearby lamp's own disc
## now genuinely clips that merged polygon down to nothing.

static func _has_nonempty_polygon(nodes: Array) -> bool:
	for node in nodes:
		if node.polygon.size() > 0:
			return true
	return false

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

	GameState.time_minutes = 22 * 60 + 30
	GameState.pending_map_path = "res://data/maps/giessingen_village.tres"
	var ow = load("res://scenes/Overworld.tscn").instantiate()
	tree.get_root().add_child(ow)
	tree.current_scene = ow
	for i in range(10):
		await tree.process_frame

	## Start from a clean slate -- no real map lamps interfering -- and
	## place our own synthetic ones exactly where each case needs them.
	ow.static_lamp_coords.clear()

	## --- Case 1: baseline, no lamp anywhere near.
	var tree_coords: Vector2i = ow.player.grid_pos + Vector2i(2, 0)
	ow.tile_chars[tree_coords] = "T"
	ow._apply_light_source_secondary_shadows()
	var spr1: Sprite2D = ow._light_shadow_sprites.get(tree_coords)
	checks.append(["Case 1: with no lamp nearby, the player's own light casts a real, visible shadow on the tree", spr1 != null and spr1.visible])

	## --- Case 2: a synthetic lamp placed right next to that same tree
	## (well within STATIC_LAMP_SHADOW_RANGE_TILES/its own LOS) should
	## now suppress the player's light-shadow there.
	ow.static_lamp_coords.append(tree_coords + Vector2i(1, 0))
	ow._apply_light_source_secondary_shadows()
	var spr2: Sprite2D = ow._light_shadow_sprites.get(tree_coords)
	checks.append(["Case 2: once a lamp's own LOS also reaches that tile, the player's light-shadow there is suppressed", spr2 == null or not spr2.visible])

	## --- Case 3: symmetric -- a tree within a lamp's own shadow range
	## that's ALSO within the player's own light LOS should lose its
	## LAMP-cast shadow (the player's torch fills it in instead). Reuse
	## the same lamp+tree pairing from Case 2 (both are already within
	## the player's own light radius from setup).
	ow._apply_static_lamp_secondary_shadows()
	var lamp_tile_sprites: Dictionary = ow._static_lamp_tile_shadow_sprites.get(0, {})
	var spr3: Sprite2D = lamp_tile_sprites.get(tree_coords)
	checks.append(["Case 3: that same tree's LAMP-cast shadow is likewise suppressed -- the player's own light reaches it too", spr3 == null or not spr3.visible])

	## --- Case 4: a genuinely distant second lamp that can't reach this
	## tile at all must NOT suppress anything -- confirms this is a real
	## reach/LOS check, not "suppress whenever more than one lamp exists
	## on the map."
	ow.static_lamp_coords.clear()
	var near_lamp: Vector2i = ow.player.grid_pos + Vector2i(20, 0)
	var far_lamp: Vector2i = ow.player.grid_pos + Vector2i(-40, -40)
	ow.static_lamp_coords.append(near_lamp)
	ow.static_lamp_coords.append(far_lamp)
	var isolated_tree: Vector2i = near_lamp + Vector2i(1, 0)
	ow.tile_chars[isolated_tree] = "T"
	## Keep this tree well outside the player's own light radius so only
	## the near lamp's own shadow is in play for this check.
	ow._apply_static_lamp_secondary_shadows()
	var near_lamp_sprites: Dictionary = ow._static_lamp_tile_shadow_sprites.get(0, {})
	var spr4: Sprite2D = near_lamp_sprites.get(isolated_tree)
	checks.append(["Case 4: an unrelated, genuinely-distant second lamp does not suppress a shadow it can't actually reach", spr4 != null and spr4.visible])

	## --- Case 5: baseline -- an isolated 3-tile wall run near the
	## player casts a real, non-empty merged wall-shadow polygon with no
	## lamp anywhere nearby. The real village map has plenty of its own
	## building walls within the player's 8-tile shadow range (this is
	## the village center) -- cleared to plain grass first so the ONLY
	## wall material left in range is the synthetic run this case is
	## actually testing, otherwise a real building's own untouched
	## shadow elsewhere in range would make "some non-empty polygon
	## exists" trivially true regardless of whether THIS fix works.
	ow.static_lamp_coords.clear()
	for dy in range(-ow.SECONDARY_LIGHT_SHADOW_MAX_RANGE_TILES, ow.SECONDARY_LIGHT_SHADOW_MAX_RANGE_TILES + 1):
		for dx in range(-ow.SECONDARY_LIGHT_SHADOW_MAX_RANGE_TILES, ow.SECONDARY_LIGHT_SHADOW_MAX_RANGE_TILES + 1):
			ow.tile_chars[ow.player.grid_pos + Vector2i(dx, dy)] = "."
	var wall_base: Vector2i = ow.player.grid_pos + Vector2i(2, 0)
	var wall_run: Array[Vector2i] = [wall_base, wall_base + Vector2i(0, 1), wall_base + Vector2i(0, -1)]
	for c in wall_run:
		ow.tile_chars[c] = "B"
	ow._apply_light_source_secondary_shadows()
	checks.append(["Case 5: with no lamp nearby, an isolated wall run casts a real, non-empty merged shadow polygon", _has_nonempty_polygon(ow._light_wall_shadow_nodes)])

	## --- Case 6: the SAME wall run, once a lamp's own disc also covers
	## it, should have its merged wall-shadow polygon clipped down to
	## nothing -- not just have its source wall tiles excluded (which
	## the first, buggy version of this fix did, with no visible effect,
	## since the shadow's own footprint lands away from the wall tiles
	## themselves).
	ow.static_lamp_coords.append(wall_base + Vector2i(2, 5))
	ow._apply_light_source_secondary_shadows()
	checks.append(["Case 6: once a lamp's own disc also covers the wall run's shadow footprint, the merged polygon is clipped to nothing", not _has_nonempty_polygon(ow._light_wall_shadow_nodes)])

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
	print("RESULT (Secondary Lights Combine — cross-light shadow suppression): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
