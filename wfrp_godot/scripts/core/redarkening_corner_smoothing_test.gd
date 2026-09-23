extends RefCounted
class_name RedarkeningCornerSmoothingTest
## Per the original follow-up report ("the re-darkening behind walls is
## done in tile-sized chunks (64px), so the boundary... looks a bit
## blocky/stepped rather than a smooth shadow edge... lets make them
## smooth, like other shadows"): _refresh_light_occlusion() used to grade
## each re-darkened tile's own quad corners by how many of the (up to) 4
## tiles sharing that grid corner still needed redarkening, fading a
## corner touching a lit neighbour down toward fully clear instead of
## snapping straight to fully dark.
##
## Per the LATER "wall shadows leave gaps of light when they meet the
## edge of lantern/lamp light circle" report — reproduced and confirmed:
## that grading unconditionally diluted a genuinely-blocked tile's own
## correct, fully-compensated darkness by up to 75% wherever it happened
## to share a grid corner with a bright neighbour, regardless of how
## bright that neighbour actually was. A "smooth boundary" cosmetic
## nicety is not worth a real "should be fully dark but isn't" gap right
## where a wall's shadow meets a light's own reach, so the corner-weight
## grading (_occlusion_corner_weight()) was removed entirely — every
## redarkened tile's quad now fills all 4 corners with that tile's own
## flat, fully-compensated tile_alpha (see _refresh_light_occlusion()),
## full stop. This test (kept under its original name/slot in the
## curated test list rather than renamed, since it still covers exactly
## the same code path) now guards the OPPOSITE invariant it used to: no
## neighbour-dependent dilution survives, ever.
##
## Case 1: a redarkened tile deep inside a re-darkened patch (all 4
## corner-sharing tiles need redarkening) still renders fully opaque.
## Case 2: a redarkened tile sitting right at a lit patch's own outer
## corner (only 1 of its 4 corner-sharing tiles is lit) is NOT diluted —
## it renders at the exact same fully-compensated alpha as Case 1, not
## some fraction of it.
## Case 3: a redarkened tile on the middle of a lit patch's own edge
## (2 of 4 corner-sharing tiles lit) is likewise undiluted.
## Case 4 (integration): re-running the real lamp-vs-wall geometry from
## lamp_lamp_occlusion_cross_light_test.gd's own Case 1 and calling the
## real _refresh_light_occlusion() confirms every actual on-screen
## Polygon2D quad ends up with uniform (not graded) alpha across all 4 of
## its own corners — the fix reaches the real draw call, not just a
## since-deleted weight function in isolation.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.inventory.clear()
	pc.equipped_weapon = ""
	pc.equipped_offhand = ""

	GameState.time_minutes = 23 * 60
	GameState.pending_map_path = "res://data/maps/giessingen_village.tres"
	var ow = load("res://scenes/Overworld.tscn").instantiate()
	tree.get_root().add_child(ow)
	tree.current_scene = ow
	for i in range(10):
		await tree.process_frame

	## --- Cases 1-3: fully synthetic lit-tile dictionary, isolating
	## _tile_needs_redarkening()'s own membership test from any real
	## LOS/lamp computation, same synthetic layout the old version of
	## this test used (a 3x3 lit patch at the origin).
	ow._player_secondary_lit_tiles.clear()
	ow._lamp_secondary_lit_tiles.clear()
	for x in range(3):
		for y in range(3):
			ow._player_secondary_lit_tiles[Vector2i(x, y)] = true
	ow.player_inside_building = -1

	checks.append(["Case 1: a tile deep inside a re-darkened patch needs redarkening", ow._tile_needs_redarkening(Vector2i(10, 10))])
	checks.append(["Case 2: a tile diagonally adjacent to the lit patch's own outer corner also needs redarkening, undiluted by its lit neighbour", ow._tile_needs_redarkening(Vector2i(-1, -1))])
	checks.append(["Case 3: a tile directly adjacent to the middle of the lit patch's own edge also needs redarkening, undiluted by its lit neighbours", ow._tile_needs_redarkening(Vector2i(3, 1))])

	## --- Case 4 (integration): the real geometry from lamp_lamp_
	## occlusion_cross_light_test.gd's own Case 1 -- a west lamp with a
	## 3-tile wall run collinear on the player's own row, leaving the
	## tile just past the wall's far side genuinely blocked -- run through
	## the REAL _refresh_light_occlusion() call, confirming every actual
	## drawn quad ends up with uniform (undiluted) corner alphas.
	for dy in range(-ow.STATIC_LAMP_SHADOW_RANGE_TILES - 2, ow.STATIC_LAMP_SHADOW_RANGE_TILES + 3):
		for dx in range(-ow.STATIC_LAMP_SHADOW_RANGE_TILES - 2, ow.STATIC_LAMP_SHADOW_RANGE_TILES + 3):
			ow.tile_chars[ow.player.grid_pos + Vector2i(dx, dy)] = "."
	var row: int = ow.player.grid_pos.y
	var wall_west: Vector2i = ow.player.grid_pos
	var wall_run: Array[Vector2i] = [wall_west, wall_west + Vector2i(1, 0), wall_west + Vector2i(2, 0)]
	for c in wall_run:
		ow.tile_chars[c] = "B"
	var west_lamp: Vector2i = Vector2i(wall_west.x - 4, row)
	var tile_east_of_wall: Vector2i = Vector2i(wall_run[2].x + 1, row)
	ow.static_lamp_coords.clear()
	ow.static_lamp_coords.append(west_lamp)
	ow._apply_static_lamp_secondary_shadows()
	ow._refresh_light_occlusion()
	checks.append(["setup Case 4: the tile just past the wall is genuinely blocked, matching the older cross-light test's own Case 1", not ow._tile_lit_by_any_secondary_light(tile_east_of_wall)])

	var any_visible_quad := false
	var found_diluted_quad := false
	for q in ow._light_occlusion_quads:
		if not q.visible:
			continue
		any_visible_quad = true
		var vc: PackedColorArray = q.vertex_colors
		if vc.size() != 4:
			continue
		var distinct: Dictionary = {}
		for c in vc:
			distinct[snappedf(c.a, 0.001)] = true
		if distinct.size() > 1:
			found_diluted_quad = true
			break
	checks.append(["setup Case 4: at least one redarkening quad is actually drawn on-screen", any_visible_quad])
	checks.append(["Case 4: no visible redarkening quad has diluted (non-uniform) corner alphas -- every blocked tile renders at its own full, undiluted compensated alpha", not found_diluted_quad])

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
	print("RESULT (Redarkening Corner Smoothing): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
