extends RefCounted
class_name DoorWallShadowBlockingTest
## Per the follow-up request ("also treat walls with doors like normal
## walls for the purpose of shadows"): the PRIMARY sun/moon shadow
## silhouette already treated a door tile ("d") exactly like the wall
## around it (SHADOW_CASTING_CHARS includes "d"), but the SECONDARY
## torch/lamp system's own _has_line_of_sight() and its two wall-run
## merge collectors still keyed off plain WALL_MATERIAL_CHARS, which
## deliberately excludes "d" (so a door doesn't fracture a building's
## footprint into two separate buildings for roof/footprint purposes —
## a completely different, still-valid concern). That meant a lit torch
## or lamp could see straight through a closed door as if it were a
## window, lighting up whatever's on the other side and never
## redarkening it. The fix: a new LIGHT_BLOCKING_WALL_CHARS constant
## (WALL_MATERIAL_CHARS + "d"), used only by the shadow/LOS call sites.
##
## Case 1: "d" is in the new LIGHT_BLOCKING_WALL_CHARS set (the constant
## this whole fix hinges on actually contains what it's supposed to).
## Case 2: baseline — a plain, doorless 3-tile wall run still blocks LOS
## from a lamp on one side to a tile just past its far side (unchanged
## from before this fix, confirms no regression to ordinary walls).
## Case 3: replacing the SAME run's middle tile with a door ("d") now
## ALSO blocks LOS through it — before this fix this would have been
## visible straight through the "gap".
## Case 4: consequently, that same tile now genuinely needs redarkening
## (the lamp's own light doesn't reach it) — the actual on-screen effect
## the request is about, not just the raw LOS boolean.

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

	checks.append(["Case 1: 'd' (door) is in LIGHT_BLOCKING_WALL_CHARS", "d" in ow.LIGHT_BLOCKING_WALL_CHARS])

	for dy in range(-ow.STATIC_LAMP_SHADOW_RANGE_TILES - 2, ow.STATIC_LAMP_SHADOW_RANGE_TILES + 3):
		for dx in range(-ow.STATIC_LAMP_SHADOW_RANGE_TILES - 2, ow.STATIC_LAMP_SHADOW_RANGE_TILES + 3):
			ow.tile_chars[ow.player.grid_pos + Vector2i(dx, dy)] = "."

	var row: int = ow.player.grid_pos.y
	var wall_west: Vector2i = ow.player.grid_pos
	var wall_run: Array[Vector2i] = [wall_west, wall_west + Vector2i(1, 0), wall_west + Vector2i(2, 0)]
	for c in wall_run:
		ow.tile_chars[c] = "B"
	var lamp_coords: Vector2i = Vector2i(wall_west.x - 4, row)
	var tile_past_wall: Vector2i = Vector2i(wall_run[2].x + 1, row)

	## --- Case 2: baseline, plain wall run (no door yet).
	checks.append(["Case 2: a plain doorless wall run still blocks LOS to a tile just past it (no regression to ordinary walls)", not ow._has_line_of_sight(lamp_coords, tile_past_wall)])

	## --- Case 3/4: swap the run's middle tile for a door.
	ow.tile_chars[wall_run[1]] = "d"
	checks.append(["Case 3: a door in the middle of that same run now ALSO blocks LOS through it, same as before the swap", not ow._has_line_of_sight(lamp_coords, tile_past_wall)])

	ow.static_lamp_coords.clear()
	ow.static_lamp_coords.append(lamp_coords)
	ow._apply_static_lamp_secondary_shadows()
	ow._refresh_light_occlusion()
	checks.append(["Case 4: the tile just past the door-in-a-wall genuinely needs redarkening -- the lamp's own light doesn't reach through the door", ow._tile_needs_redarkening(tile_past_wall)])

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
	print("RESULT (Door-in-Wall Shadow Blocking): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
