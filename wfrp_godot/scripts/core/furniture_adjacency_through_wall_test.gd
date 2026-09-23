extends RefCounted
class_name FurnitureAdjacencyThroughWallTest
## Regression test for the report ("player can open/search furniture
## from other side of closed doors, fix that too") — a follow-up to the
## same session's wall-VISIBILITY fix (see
## skill_any_resolved_crash_and_wall_leak_fix_v0.3.67.md), this time for
## INTERACTION range: _adjacent_furniture()/_adjacent_quest_chest()/
## _adjacent_stairs()/_is_near_chest() all used to gate their "in reach"
## check on raw Chebyshev distance 1 alone, with zero awareness of
## BattleGrid's wall_edges/impassable model — so a corridor cell that
## happens to sit Chebyshev-adjacent to a room's near-face row cell (the
## row _build_room_wall_edges() seals off with a wall_edge for every
## cell that ISN'T part of the door's own span — see that function's own
## comment) read as "near enough to search," even though a real sealed
## wall (or the still-closed door itself) sits directly between the two
## cells.
##
## Fixed by routing all four adjacency checks through one new shared
## helper, _has_clear_adjacency(), which adds a
## BattleGrid.has_clear_direct_path() check (already used elsewhere for
## movement/pathing — walks the one square between the two cells and
## checks both _edge_blocked()/_edge_blocked_diagonal() and plain
## impassable-tile blocking) on top of the distance check.
##
## This test proves the fix two ways:
## (a) Broadly: sweeps many freshly generated dungeons (each its own
##     disposable FieldEncounter, freed immediately after), finds every
##     sealed near-face/corridor cell pair _build_room_wall_edges() ever
##     produces (real geometry, not hand-built), and asserts
##     _has_clear_adjacency() correctly refuses every single one even
##     though they're all — by construction — Chebyshev distance 1 apart
##     (i.e. exactly what the old raw-distance check would have wrongly
##     allowed).
## (b) End to end, on one fresh dungeon picked for having such a pair:
##     injects a synthetic piece of furniture (and, in turn, a Quest
##     chest and stairs) onto the sealed-off cell, and confirms
##     _adjacent_furniture()/_adjacent_quest_chest()/_adjacent_stairs()
##     all report {} (unavailable) from the corridor side of that same
##     wall — the literal "Search the Cupboard" button the report's
##     screenshot showed wrongly enabled.
##
## Doesn't re-check the legitimate "furniture reachable once actually
## standing beside it, door open or not" path at all — that's already
## covered end to end by DungeonFurnitureSearchTest, which still passes
## unchanged after this fix (has_clear_direct_path only ever narrows a
## same-shape distance check, never widens it).

static func _sealed_pairs_for(fe, grid: BattleGrid) -> Array:
	var out: Array = []
	var scale: int = DungeonGenerator.CORRIDOR_SCALE
	for room in fe.dungeon_state.get("rooms", []):
		var anchor_v = room.get("door_pos")
		var dir_v = room.get("door_dir")
		var rect_v = room.get("rect")
		if anchor_v == null or dir_v == null or rect_v == null:
			continue
		var anchor: Vector2i = anchor_v
		var door_dir: Vector2i = dir_v
		var rect: Rect2i = rect_v
		if door_dir == Vector2i.ZERO:
			continue
		var perp: Vector2i = Vector2i(0, 1) if door_dir.x != 0 else Vector2i(1, 0)
		var near_face_start: Vector2i
		var width: int
		if door_dir.x != 0:
			near_face_start = Vector2i(anchor.x, rect.position.y)
			width = rect.size.y
		else:
			near_face_start = Vector2i(rect.position.x, anchor.y)
			width = rect.size.x
		var door_cell_set: Dictionary = {}
		for i in range(scale):
			door_cell_set[anchor + perp * i] = true

		for i in range(width):
			var face_cell: Vector2i = near_face_start + perp * i
			if door_cell_set.has(face_cell):
				continue
			var corridor_cell: Vector2i = face_cell - door_dir
			if not grid.cell_texture.has(corridor_cell):
				continue
			if not grid._edge_blocked(face_cell, corridor_cell):
				continue   ## should never happen given _build_room_wall_edges, but stay defensive
			out.append({"room": room, "interior": face_cell, "corridor": corridor_cell})
	return out

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []
	await tree.process_frame
	await tree.process_frame

	var themes: Array[String] = ["sewer", "cave"]
	var pairs_checked := 0
	var leaks_found := 0

	## (a) Broad sweep, disposable FieldEncounter per attempt.
	for attempt in range(24):
		GameState.reset_world_state()
		GameState.player_character = null
		GameState.ensure_player_character()
		var no_pool: Array[String] = []
		GameState.current_field_difficulty_tier = 0
		GameState.current_field_monster_pool = no_pool
		GameState.current_field_habitat = ""
		GameState.dungeon_state = {}
		GameState.pending_dungeon_theme_id = themes[attempt % themes.size()]
		GameState.dungeon_entry_requested = true

		var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
		tree.get_root().add_child(fe)
		for i in range(8):
			await tree.process_frame

		if fe._exploration_mode and fe.battle_grid != null:
			for pair in _sealed_pairs_for(fe, fe.battle_grid):
				pairs_checked += 1
				var interior: Vector2i = pair["interior"]
				var corridor: Vector2i = pair["corridor"]
				checks.append(["pair %s/%s is genuinely Chebyshev-adjacent (the old exploit's own precondition)" % [str(interior), str(corridor)],
					maxi(absi(interior.x - corridor.x), absi(interior.y - corridor.y)) <= 1])
				if fe._has_clear_adjacency(corridor, interior):
					leaks_found += 1
					checks.append(["sealed wall pair %s (corridor) / %s (room interior) is correctly refused by _has_clear_adjacency()" % [str(corridor), str(interior)], false])

		fe.queue_free()
		for i in range(2):
			await tree.process_frame

		if pairs_checked >= 30:
			break

	checks.append(["swept a real number of sealed near-face/corridor pairs across generated dungeons", pairs_checked >= 10])
	print("--- Furniture Adjacency Through Wall sweep: %d sealed pairs checked, %d leaks found ---" % [pairs_checked, leaks_found])

	## (b) End-to-end, on one fresh dungeon that has such a pair.
	var found_sample := false
	for attempt in range(24):
		GameState.reset_world_state()
		GameState.player_character = null
		GameState.ensure_player_character()
		var no_pool2: Array[String] = []
		GameState.current_field_difficulty_tier = 0
		GameState.current_field_monster_pool = no_pool2
		GameState.current_field_habitat = ""
		GameState.dungeon_state = {}
		GameState.pending_dungeon_theme_id = themes[attempt % themes.size()]
		GameState.dungeon_entry_requested = true

		var fe2 = load("res://scenes/FieldEncounter.tscn").instantiate()
		tree.get_root().add_child(fe2)
		for i in range(8):
			await tree.process_frame

		if not fe2._exploration_mode or fe2.battle_grid == null:
			fe2.queue_free()
			for i in range(2):
				await tree.process_frame
			continue

		var pairs2: Array = _sealed_pairs_for(fe2, fe2.battle_grid)
		if pairs2.is_empty():
			fe2.queue_free()
			for i in range(2):
				await tree.process_frame
			continue

		found_sample = true
		var pick: Dictionary = pairs2[0]
		var room: Dictionary = pick["room"]
		var interior_cell: Vector2i = pick["interior"]
		var corridor_cell: Vector2i = pick["corridor"]

		room["furniture_type"] = "cupboard"
		room["furniture_cells"] = [interior_cell]
		room["furniture_looted"] = false
		fe2._persist_room(room)
		checks.append(["_adjacent_furniture() reports UNAVAILABLE from across a sealed wall (the exact 'Search the Cupboard' exploit)",
			fe2._adjacent_furniture(corridor_cell).is_empty()])

		room["chest_pos"] = interior_cell
		fe2._persist_room(room)
		checks.append(["_adjacent_quest_chest() reports UNAVAILABLE from across the same sealed wall",
			fe2._adjacent_quest_chest(corridor_cell).is_empty()])

		room.erase("chest_pos")
		room["stairs_pos"] = interior_cell
		fe2._persist_room(room)
		checks.append(["_adjacent_stairs() reports UNAVAILABLE from across the same sealed wall",
			fe2._adjacent_stairs(corridor_cell).is_empty()])

		fe2.queue_free()
		for i in range(3):
			await tree.process_frame
		break

	checks.append(["found at least one sealed near-face/corridor pair to run the end-to-end furniture check on", found_sample])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Furniture Adjacency Through Wall): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
