extends RefCounted
class_name DungeonClosedDoorFloorHiddenTest
## Regression test for the request ("the player can still see the first
## row of floor tiles behind closed doors (marked in red), we need to
## hide those until the door is opened (but still show doors and
## walls)"), plus its own immediate follow-up ("Inside closed room, the
## floor tiles next to the grey wall lines are still visible, fix those
## too" — the room's near-face row can be WIDER than its door; the rest
## of that row is sealed off from the corridor via wall_edges instead of
## a door, and was still leaking through the first pass of this fix).
##
## THE FIX: BattleGrid.closed_door_near_face_cells (rebuilt every
## generate_from_dungeon_grid() call from `rooms`' own rect/door_pos/
## door_dir geometry, same `along <= 0` rule the vision-memory-prune fix
## uses) covers a still-closed room's ENTIRE near-face row, not just the
## door's own span. BattleGridView._draw_dungeon_square() forces those
## cells to render as solid unexplored black — WITHOUT touching
## fog_of_war/visibility itself, so the door/wall threshold-line overlay
## (driven by that same fog_of_war entry) keeps rendering exactly as
## before ("still show doors and walls").
##
## Case A: a never-opened door's near-face row is flagged hidden.
## Case A2: the WHOLE near-face row (not just the door's own span) is
## flagged — with a setup check confirming the picked room's face is
## genuinely wider than its door, so the check isn't vacuous.
## Case B: opening the door clears the flag for that door's own full
## near-face row.
## Case C: a DIFFERENT room's still-closed door is unaffected by the
## first door opening.

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

	## Dungeon layout (room count/door state) is randomly generated —
	## needing 2+ still-closed-door rooms out of one single random roll
	## is an occasional, genuine flake, not a real failure. Retries a
	## handful of fresh dungeons (a fresh FieldEncounter + exploration
	## entry each time, same as a real player re-entering) before
	## actually giving up, same tolerance any other test relying on a
	## specific random layout shape would need.
	var fe
	var rooms: Array = []
	var closed_rooms: Array = []
	var exploration_entered := false
	var attempt := 0
	while closed_rooms.size() < 2 and attempt < 5:
		attempt += 1
		GameState.dungeon_state = {}
		fe = load("res://scenes/FieldEncounter.tscn").instantiate()
		tree.get_root().add_child(fe)
		for i in range(8):
			await tree.process_frame
		exploration_entered = fe._exploration_mode
		rooms = fe.dungeon_state.get("rooms", [])
		closed_rooms = []
		for room in rooms:
			if not room.get("door_open", false):
				closed_rooms.append(room)
		if closed_rooms.size() < 2:
			fe.queue_free()

	checks.append(["setup: FieldEncounter actually entered exploration mode", exploration_entered])
	checks.append(["setup: found at least 2 real rooms with still-closed doors", closed_rooms.size() >= 2])
	if closed_rooms.size() < 2:
		print("RESULT (Dungeon Closed Door Floor Hidden): SETUP FAILED (fewer than 2 closed-door rooms after %d attempts)" % attempt)
		return false

	## Prefer a target room whose own near-face row is genuinely WIDER
	## than its door, so Case A2 below isn't vacuous.
	var scale: int = DungeonGenerator.CORRIDOR_SCALE
	var target_room: Dictionary = {}
	var other_room: Dictionary = {}
	for room in closed_rooms:
		var dir_v = room.get("door_dir")
		var rect_v = room.get("rect")
		if dir_v == null or rect_v == null:
			continue
		var dir: Vector2i = dir_v
		var rect: Rect2i = rect_v
		var face_width: int = rect.size.y if dir.x != 0 else rect.size.x
		if face_width > scale and target_room.is_empty():
			target_room = room
		elif not target_room.is_empty() and room != target_room and other_room.is_empty():
			other_room = room
	if target_room.is_empty():
		target_room = closed_rooms[0]
	for room in closed_rooms:
		if room != target_room and other_room.is_empty():
			other_room = room

	var anchor: Vector2i = target_room["door_pos"]
	var dir: Vector2i = target_room["door_dir"]
	var rect: Rect2i = target_room["rect"]
	var face_width: int = rect.size.y if dir.x != 0 else rect.size.x
	checks.append(["setup: the picked room's near-face row is genuinely wider than its own door (Case A2 isn't vacuous)", face_width > scale])

	var battle_grid = fe.battle_grid

	## --- Case A: never-opened door -- the door's own anchor cell is
	## flagged hidden, an interior cell is not, and the underlying
	## fog_of_war/door-line visibility is completely untouched by this.
	var outside_pos: Vector2i = anchor - dir
	fe.battle_positions.clear()
	fe.battle_positions[fe.player] = outside_pos
	fe._reveal_around_party()
	for i in range(2):
		await tree.process_frame
	checks.append(["Case A (never opened): the door's own anchor cell is flagged hidden", battle_grid.closed_door_near_face_cells.has(anchor)])
	var interior_cell: Vector2i = anchor + dir * 2
	checks.append(["Case A: a genuinely-interior cell (along > 0) is NOT flagged hidden by this mechanism", not battle_grid.closed_door_near_face_cells.has(interior_cell)])
	checks.append(["Case A: the door's own threshold-line visibility (fog_of_war) is untouched -- still shows the door itself", int(battle_grid.fog_of_war.get(anchor, 0)) > 0])

	## --- Case A2: the WHOLE near-face row is flagged, not just the
	## door's own CORRIDOR_SCALE-wide span.
	var all_face_hidden := true
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var cell := Vector2i(x, y)
			var diff: Vector2i = cell - anchor
			var along: int = diff.x * dir.x + diff.y * dir.y
			if along <= 0 and not battle_grid.closed_door_near_face_cells.has(cell):
				all_face_hidden = false
	checks.append(["Case A2: the room's ENTIRE near-face row is flagged hidden, not just the door's own span", all_face_hidden])

	## --- Case B: opening the door clears the flag for its own full
	## near-face row.
	fe._open_door_at(anchor)
	for i in range(2):
		await tree.process_frame
	checks.append(["Case B: once opened, the door's own anchor cell is no longer flagged hidden", not fe.battle_grid.closed_door_near_face_cells.has(anchor)])
	var still_face_hidden_after_open := false
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var cell := Vector2i(x, y)
			var diff: Vector2i = cell - anchor
			var along: int = diff.x * dir.x + diff.y * dir.y
			if along <= 0 and fe.battle_grid.closed_door_near_face_cells.has(cell):
				still_face_hidden_after_open = true
	checks.append(["Case B: ...and none of that room's near-face row is still flagged hidden", not still_face_hidden_after_open])

	## --- Case C: a DIFFERENT room's still-closed door is unaffected by
	## the first door opening.
	checks.append(["setup: found a second, genuinely different closed-door room to check", not other_room.is_empty()])
	if not other_room.is_empty():
		var other_anchor: Vector2i = other_room["door_pos"]
		checks.append(["Case C: a different room's still-closed door remains flagged hidden after an unrelated door opened", fe.battle_grid.closed_door_near_face_cells.has(other_anchor)])

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
	print("RESULT (Dungeon Closed Door Floor Hidden): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
