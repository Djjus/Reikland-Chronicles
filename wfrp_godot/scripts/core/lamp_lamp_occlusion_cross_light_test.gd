extends RefCounted
class_name LampLampOcclusionCrossLightTest
## Per the real bug report ("the lamps stand either side of the
## southern house, and are casting shadow on each other, that should
## NOT be happening"): the previous cross-light fixes (secondary_light_
## lights_combine_test.gd) only covered the WALL-SHADOW POLYGON half of
## this feature. This test targets the OTHER half — the LOS-blocked-tile
## occlusion redarkening _refresh_light_occlusion() paints back over the
## night overlay's reveal.
##
## The real village map's two static lamps sit on the exact same ROW as
## the small building between them, so each lamp's own line to the far
## side of that building is nearly collinear with the wall — meaning
## each lamp can only ever get LOS to the wall's own NEAR edge, never
## see past it, and unconditionally marks every tile behind it (from
## that lamp's own point of view) as "blocked" and due for redarkening.
## That was fine when only one light existed, but with a second lamp
## standing on the FAR side with perfectly clear LOS to that same
## ground, the old code redarkened it anyway — painting solid night
## black right back over a tile the other lamp was correctly lighting.
## Reproduces that exact collinear-flanking geometry synthetically
## (rather than depending on the real map's specific layout, which can
## change) via a 3-tile wall run with a lamp directly in line on each
## side, then confirms the ground tile just past the NEAR lamp's own
## blind side — which the FAR lamp can plainly see — is no longer
## treated as needing redarkening.
##
## Case 1: baseline — with only the WEST lamp active, the tile just
## east of the wall run (which that lamp's own LOS can't reach, past
## its own wall) correctly counts as blocked/in need of redarkening.
## Case 2: once the EAST lamp (flanking the wall run's far side, with
## clear LOS back to that same tile) is also active, that tile is no
## longer treated as blocked — the east lamp's own reach fills it in.
## Case 3: with only the EAST lamp active, a tile just west of the wall
## run — unreachable from the east lamp's own collinear LOS either — is
## correctly blocked on its own (the west-side mirror of Case 1).
## Case 4: adding the WEST lamp back fills that same tile in, mirroring
## Case 2.
## Case 5: a tile genuinely unreachable by EITHER lamp (blocked from the
## west lamp by a wall, and out of the east lamp's own range entirely)
## still correctly counts as blocked — confirms this is a real "is ANY
## light's LOS reaching it" check, not a blanket "some other lamp
## exists" pass.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.inventory.clear()
	pc.equipped_weapon = ""
	pc.equipped_offhand = ""
	## No player light source at all -- isolating strictly to the two
	## lamps' own cross-light interaction, same as the real bug report's
	## scenario (night-time village, static lamps only).

	GameState.time_minutes = 23 * 60
	GameState.pending_map_path = "res://data/maps/giessingen_village.tres"
	var ow = load("res://scenes/Overworld.tscn").instantiate()
	tree.get_root().add_child(ow)
	tree.current_scene = ow
	for i in range(10):
		await tree.process_frame

	## Clear the real map's own walls out of range so only this test's
	## synthetic geometry is in play -- same isolation rationale as
	## secondary_light_lights_combine_test.gd's Case 5/6.
	for dy in range(-ow.STATIC_LAMP_SHADOW_RANGE_TILES - 2, ow.STATIC_LAMP_SHADOW_RANGE_TILES + 3):
		for dx in range(-ow.STATIC_LAMP_SHADOW_RANGE_TILES - 2, ow.STATIC_LAMP_SHADOW_RANGE_TILES + 3):
			ow.tile_chars[ow.player.grid_pos + Vector2i(dx, dy)] = "."

	## A 3-tile wall run on the player's own row, with one lamp collinear
	## on each side -- exactly the real "lamp / wall / wall / wall / lamp,
	## all same row" layout that made each lamp only ever see the wall's
	## own near edge.
	var row: int = ow.player.grid_pos.y
	var wall_west: Vector2i = ow.player.grid_pos + Vector2i(0, 0)
	var wall_run: Array[Vector2i] = [wall_west, wall_west + Vector2i(1, 0), wall_west + Vector2i(2, 0)]
	for c in wall_run:
		ow.tile_chars[c] = "B"
	var west_lamp: Vector2i = Vector2i(wall_west.x - 4, row)
	var east_lamp: Vector2i = Vector2i(wall_run[2].x + 4, row)
	var tile_east_of_wall: Vector2i = Vector2i(wall_run[2].x + 1, row)
	var tile_west_of_wall: Vector2i = Vector2i(wall_west.x - 1, row)

	ow.static_lamp_coords.clear()
	ow.static_lamp_coords.append(west_lamp)
	ow._apply_static_lamp_secondary_shadows()
	ow._refresh_light_occlusion()
	checks.append(["Case 1: with only the west lamp active, the tile just past the wall's far (east) side is correctly blocked/in need of redarkening", not ow._tile_lit_by_any_secondary_light(tile_east_of_wall)])

	ow.static_lamp_coords.append(east_lamp)
	ow._apply_static_lamp_secondary_shadows()
	ow._refresh_light_occlusion()
	checks.append(["Case 2: once the east lamp (with clear LOS back to that same tile) is also active, that tile is no longer treated as blocked", ow._tile_lit_by_any_secondary_light(tile_east_of_wall)])

	## --- Case 3: symmetric -- with ONLY the east lamp active (west
	## removed), the tile just past the wall's near (west) side -- which
	## the east lamp's own collinear LOS can't reach past the wall
	## either -- correctly counts as blocked on its own.
	ow.static_lamp_coords.clear()
	ow.static_lamp_coords.append(east_lamp)
	ow._apply_static_lamp_secondary_shadows()
	ow._refresh_light_occlusion()
	checks.append(["Case 3: with only the east lamp active, the tile just past the wall's near (west) side is correctly blocked on its own", not ow._tile_lit_by_any_secondary_light(tile_west_of_wall)])

	## --- Case 4: adding the west lamp back fills that same tile in --
	## the symmetric mirror of Case 2.
	ow.static_lamp_coords.append(west_lamp)
	ow._apply_static_lamp_secondary_shadows()
	ow._refresh_light_occlusion()
	checks.append(["Case 4: adding the west lamp back (with its own clear LOS to that tile) fills it in, mirroring Case 2", ow._tile_lit_by_any_secondary_light(tile_west_of_wall)])

	## --- Case 5: a tile that's genuinely unreachable by EITHER lamp
	## (blocked from the west lamp by a wall directly between them on a
	## straight vertical line, and simply too far away from the east lamp
	## to be in its STATIC_LAMP_SHADOW_RANGE_TILES reach at all) must
	## still correctly count as blocked. Deliberately a straight-line
	## block rather than a 4-sided "box" -- a tile boxed on all 4
	## orthogonal sides can still be seen on the diagonal by Bresenham
	## LOS (it doesn't check the two corner cells a diagonal ray passes
	## between), which is a separate, pre-existing LOS quirk unrelated to
	## this fix and not what this case is trying to exercise.
	var unreachable_tile: Vector2i = Vector2i(west_lamp.x, west_lamp.y - 6)
	ow.tile_chars[Vector2i(west_lamp.x, west_lamp.y - 3)] = "B"
	checks.append(["Case 5 setup: the unreachable tile is genuinely too far from the east lamp to be in its own shadow range", Vector2(unreachable_tile - east_lamp).length() > float(ow.STATIC_LAMP_SHADOW_RANGE_TILES)])
	ow._apply_static_lamp_secondary_shadows()
	ow._refresh_light_occlusion()
	checks.append(["Case 5: a tile genuinely unreachable by either lamp's own LOS still correctly counts as blocked", not ow._tile_lit_by_any_secondary_light(unreachable_tile)])

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
	print("RESULT (Lamp-vs-Lamp Occlusion Cross-Light): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
