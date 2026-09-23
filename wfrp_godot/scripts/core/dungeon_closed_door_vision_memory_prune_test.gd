extends RefCounted
class_name DungeonClosedDoorVisionMemoryPruneTest
## Regression test for the request ("Player can still see the tiles
## behind door (but not longer move to them), lets fix it so they
## cant"), sent with fresh screenshots after the earlier v0.2.536 fix
## (which addressed the reported MOVEMENT-through-a-closed-door bug —
## see impassable_diagonal_corner_cut_test.gd — but left the door's own
## near-face-row VISION reveal untouched, since that part was
## investigated at the time and found to be working correctly for a
## door that had never been opened).
##
## Investigating this fresh report (a live repro script swept 161
## closed-door rooms across 40 generated dungeons) confirmed
## _light_bfs() itself still correctly refuses to reveal a room's
## interior through a door that's never been opened — the underlying
## flood-fill/boundary logic was never the bug. What WAS still broken:
## once a room's interior genuinely became visible some other way (the
## door WAS opened at some point), nothing ever un-revealed it again —
## dungeon_state["visibility"] only ever gets cells ADDED to it
## (_commit_visibility_from_centers only ever upgrades 0->1->2, and
## downgrades 2->1, never all the way back to 0). This project's doors
## never re-close through any in-game action, so this can't yet surface
## from a single door alone in a brand new game session — but it's
## exactly the shape of bug a save file from an earlier build (visited
## a room, then this build's OWN pruning never existed to correct it)
## would exhibit forever after, matching a "door I never opened is
## somehow already seen-through" report.
##
## THE FIX: _commit_visibility_from_centers() now also PRUNES, every
## single commit: for every room whose own door is still closed, any of
## THAT room's own interior floor cells not justified by the very
## bright/dim reached-or-boundary sets this commit just computed gets
## its visibility cleared outright. The near-face row (the door's own
## surface, plus its 2 flanking pad cells) is deliberately left alone —
## same "see the surface, not through it" rule used everywhere else in
## this fog-of-war system.
##
## Simulates a "door closes again" scenario directly (there's no real
## close-door action in this game to drive through the UI) by hand-
## rewriting a room's own door_open flag/grid_rows cells back to closed
## after having genuinely opened and walked into it — the closest
## reproducible stand-in for what a stale save (or, in principle, any
## future re-closable-door mechanic) would look like, and the exact
## thing _commit_visibility_from_centers must now correct for on its
## very next run.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	await tree.process_frame
	await tree.process_frame

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var no_pool: Array[String] = []
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_habitat = ""
	GameState.dungeon_state = {}
	GameState.pending_dungeon_theme_id = "sewer"
	GameState.dungeon_entry_requested = true   ## real dungeon-entry signal, see that field's own header comment

	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(8):
		await tree.process_frame

	checks.append(["setup: FieldEncounter actually entered exploration mode", fe._exploration_mode])

	var rooms: Array = fe.dungeon_state.get("rooms", [])
	var target_room: Dictionary = {}
	for room in rooms:
		if not room.get("door_open", false):
			target_room = room
			break
	checks.append(["setup: found a real room with a still-closed door", not target_room.is_empty()])
	if target_room.is_empty():
		fe.queue_free()
		print("RESULT (Dungeon Closed Door Vision Memory Prune): SETUP FAILED (no closed-door room)")
		return false

	var anchor: Vector2i = target_room["door_pos"]
	var dir: Vector2i = target_room["door_dir"]
	var rect: Rect2i = target_room["rect"]
	var outside_pos: Vector2i = anchor - dir

	## An interior floor cell of the target room, strictly past the
	## door's own near-face row (along > 0 in the door's own facing
	## direction) -- the exact cell class this whole fix is about.
	var interior_cell: Vector2i = anchor + dir * 2

	## --- Case A: never-opened door -- no leak at all (regression guard,
	## confirms the underlying flood-fill itself was never the bug) -----
	fe.battle_positions.clear()
	fe.battle_positions[fe.player] = outside_pos
	fe._reveal_around_party()
	for i in range(2):
		await tree.process_frame
	var visibility: Dictionary = fe.dungeon_state.get("visibility", {})
	checks.append(["Case A (never opened): the room's own interior stays completely unseen", int(visibility.get(interior_cell, 0)) == 0])
	checks.append(["Case A (never opened): the door's own near-face row IS visible (the surface itself, not a leak)", int(visibility.get(anchor, 0)) > 0])

	## --- Case B: open the door and walk in -- interior genuinely visible
	fe._open_door_at(anchor)
	for i in range(2):
		await tree.process_frame
	fe.battle_positions[fe.player] = interior_cell
	fe._reveal_around_party()
	for i in range(2):
		await tree.process_frame
	visibility = fe.dungeon_state.get("visibility", {})
	checks.append(["Case B (door opened, walked in): the interior cell is genuinely visible now", int(visibility.get(interior_cell, 0)) > 0])

	## --- Case C: THE FIX -- simulate the door closing again (stand-in
	## for a re-closable-door mechanic / a stale save from an older
	## build) and confirm the stale interior memory is pruned on the
	## very next visibility commit, while the near-face row stays put.
	fe.battle_positions[fe.player] = outside_pos
	for room2 in fe.dungeon_state.get("rooms", []):
		if room2["door_pos"] == anchor:
			room2["door_open"] = false
	var grid_rows: Array = fe.dungeon_state.get("grid_rows", [])
	var perp: Vector2i = Vector2i(0, 1) if dir.x != 0 else Vector2i(1, 0)
	for i in range(DungeonGenerator.CORRIDOR_SCALE):
		var cell: Vector2i = anchor + perp * i
		var row: String = grid_rows[cell.y]
		row[cell.x] = fe.dungeon_theme.door_closed_char
		grid_rows[cell.y] = row
	fe.dungeon_state["grid_rows"] = grid_rows
	fe._refresh_dungeon_battle_grid()
	fe._reveal_around_party()
	for i in range(2):
		await tree.process_frame
	visibility = fe.dungeon_state.get("visibility", {})
	checks.append(["THE FIX: once the door is closed again, the interior cell's stale visibility is pruned back to unseen", int(visibility.get(interior_cell, 0)) == 0])
	checks.append(["THE FIX: ...same for every genuinely-interior cell of the room, not just the one sampled above", _all_interior_cells_unseen(rect, anchor, dir, visibility)])
	checks.append(["THE FIX: the door's own near-face row REMAINS visible (still a real surface, not swept away by the prune)", int(visibility.get(anchor, 0)) > 0])

	fe.queue_free()
	for i in range(3):
		await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Dungeon Closed Door Vision Memory Prune): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass

static func _all_interior_cells_unseen(rect: Rect2i, anchor: Vector2i, dir: Vector2i, visibility: Dictionary) -> bool:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var cell := Vector2i(x, y)
			var diff: Vector2i = cell - anchor
			var along: int = diff.x * dir.x + diff.y * dir.y
			if along <= 0:
				continue   ## near-face row -- deliberately still visible, not part of this check
			if int(visibility.get(cell, 0)) != 0:
				return false
	return true
