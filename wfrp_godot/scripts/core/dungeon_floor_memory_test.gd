extends RefCounted
class_name DungeonFloorMemoryTest
## Regression test for the user report: "the dungeon should also remember
## which doors have been opened when going back up or down."
##
## _take_stairs_down()/_take_stairs_up() used to unconditionally call
## DungeonGenerator.generate() fresh on every single floor transition,
## discarding the ENTIRE previous floor's dungeon_state (doors,
## encountered/chest_looted flags, explored fog-of-war) even when
## returning to a floor already visited this same delve. Fixed via
## GameState.dungeon_floor_states — a same-session cache, keyed by floor
## number, of each floor's own dungeon_state dict — see that field's own
## comment in game_state.gd for the full story.
##
## Calls _open_door_at()/_take_stairs_down()/_take_stairs_up() directly
## (same direct-call technique this project's own deathblow/frenzy tests
## use) rather than driving the real click-to-move/click-the-stairs-
## button UI flow, since the adjacency checks those buttons' own
## _on_*_pressed() wrappers apply have nothing to do with what this fix
## actually changed.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []
	await tree.process_frame
	await tree.process_frame

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	GameState.current_field_difficulty_tier = 0
	GameState.dungeon_state = {}
	GameState.dungeon_floor_states = {}
	GameState.pending_dungeon_theme_id = "sewer"
	GameState.dungeon_entry_requested = true

	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(8):
		await tree.process_frame

	var rooms0: Array = fe.dungeon_state.get("rooms", [])
	var setup_ok: bool = fe._exploration_mode and not fe.dungeon_state.is_empty() and rooms0.size() > 0
	checks.append(["setup: exploration mode entered on a real generated floor 0", setup_ok])
	if not setup_ok:
		fe.queue_free()
		for i in range(3): await tree.process_frame
		print("RESULT (Dungeon Floor Memory): SETUP FAILED")
		return false

	checks.append(["setup: floor 0 was seeded into the same-session cache", GameState.dungeon_floor_states.has(0)])
	checks.append(["setup: the cached floor 0 is the SAME dict object exploration is live-mutating", GameState.dungeon_floor_states.get(0) == fe.dungeon_state])

	## --- Open a door on floor 0, confirm it's genuinely tracked as open
	## and its room "encountered" (matching real play: opening a door
	## spawns/marks that room, per _open_door_at()'s own comment).
	var target_room: Dictionary = rooms0[0]
	var door_pos: Vector2i = target_room.get("door_pos")
	checks.append(["setup: the chosen room's own door starts closed", not target_room.get("door_open", false)])
	fe._open_door_at(door_pos)

	var reopened_room: Dictionary = fe._room_at_door(door_pos)
	checks.append(["floor 0: the door is now recorded open", reopened_room.get("door_open", false)])
	checks.append(["floor 0: the room is now recorded as encountered", reopened_room.get("encountered", false)])
	var revealed_cells: Array = fe._door_block_cells(reopened_room)
	var visibility_before: Dictionary = fe.dungeon_state.get("visibility", {})
	var door_cell_revealed_before: bool = revealed_cells.size() > 0 and visibility_before.has(revealed_cells[0])
	checks.append(["floor 0: opening the door revealed its own cell (fog of war)", door_cell_revealed_before])

	## --- Descend to floor 1, then come back up to floor 0 -- the actual
	## regression: floor 0 should be resumed exactly as left, not
	## regenerated fresh (which would reset every door/encountered/
	## visibility flag back to a brand new layout's own defaults).
	fe._take_stairs_down()
	for i in range(3):
		await tree.process_frame
	checks.append(["descended: dungeon_floor is now 1", int(fe.dungeon_state.get("dungeon_floor", -1)) == 1])
	checks.append(["descended: floor 1 was seeded into the same-session cache too", GameState.dungeon_floor_states.has(1)])

	fe._take_stairs_up()
	for i in range(3):
		await tree.process_frame
	checks.append(["back up: dungeon_floor is 0 again", int(fe.dungeon_state.get("dungeon_floor", -1)) == 0])
	## The real regression check: this must be the SAME dungeon_state dict
	## as before descending (reused from the cache), not a freshly
	## generated lookalike -- Dictionary identity, not just equal values.
	checks.append(["back up: floor 0's dungeon_state is the exact SAME object as before descending (reused, not regenerated)", fe.dungeon_state == GameState.dungeon_floor_states.get(0)])

	var room_after_roundtrip: Dictionary = fe._room_at_door(door_pos)
	checks.append(["back up: the door opened earlier is STILL recorded open", room_after_roundtrip.get("door_open", false)])
	checks.append(["back up: the room is STILL recorded as encountered (no duplicate monster spawn on a later door click)", room_after_roundtrip.get("encountered", false)])
	var visibility_after: Dictionary = fe.dungeon_state.get("visibility", {})
	var door_cell_still_revealed: bool = revealed_cells.size() > 0 and visibility_after.has(revealed_cells[0])
	checks.append(["back up: the fog of war revealed by opening that door is still remembered", door_cell_still_revealed])

	## --- Leaving the dungeon entirely ends the delve -- the cache should
	## be cleared so a later, genuinely new dungeon doesn't inherit a
	## stale floor from this one.
	## _do_exit_dungeon() calls change_scene_to_file(), which frees
	## whatever the tree's current_scene actually is and replaces it with
	## a brand new scene (see return_to_world_map_test.gd's own comment on
	## this exact caution) -- set explicitly here so it's genuinely `fe`
	## being swapped, matching how it always plays out in real play.
	## Nothing below reads `fe` again after this call.
	tree.current_scene = fe
	fe._do_exit_dungeon()
	for i in range(5):
		await tree.process_frame
	checks.append(["exiting the dungeon clears the same-session floor cache", GameState.dungeon_floor_states.is_empty()])

	var after_exit: Node = tree.current_scene
	if after_exit != null:
		after_exit.queue_free()
	for i in range(3):
		await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Dungeon Floor Memory): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
