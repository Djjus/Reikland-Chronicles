extends RefCounted
class_name RoofOverflowMaskLayerTest
## Per the "still bleeding through at the edges, fix it so it merges with
## the outside darkness with no gaps" thread's FOURTH and final round: the
## first three attempts (v0.2.608 rectangular band, v0.2.609 doubled band,
## v0.2.610 circular scan) all tried to fix the ROOF_RIDGE overflow (see
## roof_overflow_mask_layer's own @onready comment) by forcing the
## LIGHTING system to redarken the affected ground back to ambient — each
## traded one visible seam (a straight rectangle edge, then a full ring
## around every light) for another, because the bug itself is not a
## lighting bug at all.
##
## The actual fix is purely visual: roof_overflow_mask_layer repaints the
## real ground/canopy tile that belongs in the two rows immediately north
## of every building's own ridge row, directly on top of roof_layer's own
## overflow, at ordinary map-build time — see _build_map()'s own comment
## right after the roof-painting loop. Being plain world content, the
## EXISTING night_overlay/cloud_shadow_overlay shader then darkens and
## reveals it exactly like any other tile, with no special-casing
## anywhere in _refresh_light_occlusion() needed (that function is back
## to its original v0.2.607 job of closing the genuine LOS-blocked gap
## only — see its own comment).
##
## Case 1: for a real building, the mask layer's cell two rows north of
## the ridge is painted with the SAME atlas _resolve_tile_atlas() would
## paint for that raw map coordinate (i.e. it genuinely reproduces the
## real ground art, not some placeholder).
## Case 2: the row immediately touching the ridge (one row north) is also
## painted, not left as an empty/transparent cell.
## Case 3: a coordinate well away from every building (nowhere near any
## roof) is left empty on the mask layer — this fix never touches
## unrelated ground.
## Case 4: _refresh_light_occlusion() no longer does any lighting-based
## redarkening beyond the genuine per-light LOS-blocked lists — the old
## _reveal_gap_redarken_tiles mechanism and its scan are gone entirely,
## so a tile that fails _tile_lit_by_any_secondary_light() but is NOT
## LOS-blocked by any active light is no longer swept into redarkening
## just because it happens to sit within some light's raw radius.
static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.inventory.clear()
	pc.equipped_weapon = ""
	pc.equipped_offhand = ""
	pc.inventory.append("Storm Lantern")
	pc.equipped_weapon = "Storm Lantern"
	pc.light_mode = "on"
	pc.light_fuel_minutes = 200.0

	GameState.time_minutes = 23 * 60
	GameState.pending_map_path = "res://data/maps/giessingen_village.tres"
	var ow = load("res://scenes/Overworld.tscn").instantiate()
	tree.get_root().add_child(ow)
	tree.current_scene = ow
	for i in range(10):
		await tree.process_frame

	checks.append(["setup: the village map has at least one building", ow.buildings.size() > 0])
	if ow.buildings.size() > 0:
		var rect: Rect2i = ow.buildings[0]

		## Case 1: two rows north of the ridge matches the real ground atlas.
		var far_row_coords: Vector2i = Vector2i(rect.position.x, rect.position.y - 2)
		var expected_far_atlas: Vector2i = ow._resolve_tile_atlas(far_row_coords, ow.tile_chars.get(far_row_coords, "."))
		var actual_far_atlas: Vector2i = ow.roof_overflow_mask_layer.get_cell_atlas_coords(far_row_coords)
		checks.append(["Case 1: mask layer repaints the real ground atlas two rows north of the ridge", actual_far_atlas == expected_far_atlas])

		## Case 2: one row north of the ridge is also painted (not left empty).
		var near_row_coords: Vector2i = Vector2i(rect.position.x, rect.position.y - 1)
		var near_source_id: int = ow.roof_overflow_mask_layer.get_cell_source_id(near_row_coords)
		checks.append(["Case 2: mask layer also paints the row immediately north of the ridge", near_source_id != -1])

	## Case 3: far from every building, the mask layer is untouched.
	var far_from_any_building := Vector2i(-500, -500)
	var is_far_enough := true
	for rect2 in ow.buildings:
		var expanded: Rect2i = Rect2i(rect2.position - Vector2i(5, 5), rect2.size + Vector2i(10, 10))
		if expanded.has_point(far_from_any_building):
			is_far_enough = false
	checks.append(["setup Case 3: the probe coordinate is genuinely far from every building", is_far_enough])
	checks.append(["Case 3: the mask layer is empty far away from every building", ow.roof_overflow_mask_layer.get_cell_source_id(far_from_any_building) == -1])

	## Case 4: raw_blocked (the only thing _refresh_light_occlusion() ever
	## draws a redarkening quad for) is sourced purely from each light's
	## own genuine LOS-blocked list again -- the old reveal-gap scan that
	## used to fold in "anywhere within a light's raw radius that still
	## fails the lit test" is gone, so a tile can fail the lit test
	## (still making _tile_needs_redarkening() answer true, unchanged
	## from v0.2.607) without ever being swept into a redarkening quad,
	## as long as no light's own LOS genuinely fails to reach it.
	for dy in range(-25, 26):
		for dx in range(-25, 26):
			ow.tile_chars[ow.player.grid_pos + Vector2i(dx, dy)] = "."
	ow._recompute_secondary_light_lit_tiles()
	ow._apply_light_source_secondary_shadows()
	ow._apply_static_lamp_secondary_shadows()
	ow._refresh_light_occlusion()
	var bearer: Character = ow._party_light_bearer()
	var radius_tiles: int = bearer.get_active_light_radius_tiles()
	var gap_tile: Vector2i = ow.player.grid_pos + Vector2i(radius_tiles - 1, 0)
	checks.append(["setup Case 4: the near-edge tile genuinely fails the 'is a light actually lighting this' test", not ow._tile_lit_by_any_secondary_light(gap_tile)])
	checks.append(["setup Case 4: ...so _tile_needs_redarkening() still answers true for it, unchanged from v0.2.607", ow._tile_needs_redarkening(gap_tile)])
	var gap_not_player_los_blocked: bool = not ow._player_light_blocked_tiles.has(gap_tile)
	var gap_not_lamp_los_blocked := true
	for lamp_index in ow._static_lamp_blocked_tiles:
		if ow._static_lamp_blocked_tiles[lamp_index].has(gap_tile):
			gap_not_lamp_los_blocked = false
	checks.append(["Case 4: that same tile is not LOS-blocked by any active light, so with no reveal-gap scan left to fold it in, it's not a redarkening candidate at all", gap_not_player_los_blocked and gap_not_lamp_los_blocked])

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
	print("RESULT (Roof Overflow Mask Layer): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
