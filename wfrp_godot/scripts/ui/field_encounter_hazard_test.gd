extends RefCounted
class_name FieldEncounterHazardTest
## Dedicated regression test for the "New Dungeon building rules" Hazard
## Table's two physical-tile outcomes (Chasm / Spike trap) and their
## interaction mechanic, FieldEncounterScreen._maybe_trigger_hazard() —
## neither DungeonGeneratorTest (map generation only, never enters the
## scene) nor FieldEncounterExplorationTest (never rolls a hazard tile
## along its own forced move) exercises this code path at all.
##
## Drives the real, live FieldEncounter scene (same instantiation pattern
## as FieldEncounterExplorationTest) but injects synthetic Chasm/Spike
## trap rooms directly into dungeon_state["rooms"] rather than depending
## on ever rolling one naturally, so every branch (Chasm pass, Chasm
## fail+revert+falling damage, Spike pass, Spike fail+1d12 damage,
## resolve-only-once) is deterministically covered every run — forced via
## deliberately terrible/excellent linked characteristics (Agility for
## Athletics, Initiative for Perception) rather than a forced_roll, since
## _maybe_trigger_hazard() itself calls TestResolver.resolve_skill_test()
## with no forced_roll parameter threaded through.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []
	var check := func(label: String, passed: bool) -> void:
		checks.append([label, passed])

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	GameState.pending_dungeon_theme_id = "sewer"
	GameState.dungeon_entry_requested = true   ## real dungeon-entry signal, see that field's own header comment

	var screen = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child.call_deferred(screen)
	for i in range(4):
		await tree.process_frame

	check.call("FieldEncounter instantiated without error", screen != null)
	check.call("dungeon_state was generated on entry", not screen.dungeon_state.is_empty())

	## Pick two distinct walkable floor cells (not the entrance) to host
	## our synthetic hazards -- any plain floor cell works, since we call
	## _maybe_trigger_hazard() directly rather than depending on real
	## room/door placement.
	var grid_rows: Array = screen.dungeon_state.get("grid_rows", [])
	var floor_cells: Array = []
	for y in range(grid_rows.size()):
		var row: String = grid_rows[y]
		for x in range(row.length()):
			if row[x] == screen.dungeon_theme.floor_char:
				floor_cells.append(Vector2i(x, y))
	check.call("dungeon has enough floor cells for the test (>=2)", floor_cells.size() >= 2)
	if floor_cells.size() < 2:
		print("RESULT (FieldEncounterHazard): SOME FAILED (not enough floor cells, aborting)")
		return false

	var chasm_pos: Vector2i = floor_cells[0]
	var spike_pos: Vector2i = floor_cells[1]
	var pre_move_pos: Vector2i = screen.dungeon_state.get("entrance_pos")

	var chasm_room := {
		"rect": Rect2i(chasm_pos, Vector2i(1, 1)), "door_pos": Vector2i(-1, -1),
		"door_dir": Vector2i.ZERO, "door_open": true, "room_type": "small", "quest": false,
		"hazard_type": "chasm", "hazard_pos": chasm_pos, "hazard_resolved": false,
		"monster_names": [], "encountered": true, "cleared": true,
		"spawn_far_corner": chasm_pos,
	}
	var spike_room := {
		"rect": Rect2i(spike_pos, Vector2i(1, 1)), "door_pos": Vector2i(-2, -2),
		"door_dir": Vector2i.ZERO, "door_open": true, "room_type": "small", "quest": false,
		"hazard_type": "spike_trap", "hazard_pos": spike_pos, "hazard_resolved": false,
		"monster_names": [], "encountered": true, "cleared": true,
		"spawn_far_corner": spike_pos,
	}
	screen.dungeon_state["rooms"] = [chasm_room, spike_room]
	GameState.dungeon_state = screen.dungeon_state

	var athletics: SkillDefinition = GameData.skill_db.find_by_name("Athletics")
	var perception: SkillDefinition = GameData.skill_db.find_by_name("Perception")
	check.call("Athletics skill def resolved", athletics != null)
	check.call("Perception skill def resolved", perception != null)

	## --- Chasm: forced FAILURE (Agility 0 -- target clamps to 1, only a
	## roll of exactly 1 succeeds, so a real un-forced roll fails ~99% of
	## the time; loop a few times for the ~1% edge case rather than
	## depending on a single roll) ---
	var chasm_fail_ok := false
	var falling_dmg_ok := false
	for attempt in range(10):
		screen.dungeon_state["rooms"][0] = chasm_room.duplicate(true)
		screen.dungeon_state["rooms"][0]["hazard_resolved"] = false
		GameState.dungeon_state = screen.dungeon_state
		var mover := Character.new()
		mover.character_name = "Chasm Faller"
		mover.allegiance = "ally"
		mover.characteristics = CharacteristicSet.new()
		mover.characteristics.agility = 0
		mover.wounds_current = 20
		mover.wounds_max = 20
		screen.battle_positions[mover] = chasm_pos
		await screen._maybe_trigger_hazard(mover, chasm_pos, pre_move_pos)
		var resolved_room: Dictionary = screen.dungeon_state["rooms"][0]
		if resolved_room.get("hazard_resolved", false) and screen.battle_positions[mover] == pre_move_pos:
			chasm_fail_ok = true
			falling_dmg_ok = mover.wounds_current < 20
			break
	check.call("Chasm failure reverts the mover to pre_move_pos", chasm_fail_ok)
	check.call("Chasm failure applies real falling damage (wounds dropped)", falling_dmg_ok)

	## --- Chasm: forced SUCCESS (Agility 100 -- only a 96-100 roll fails,
	## and even that band is excluded once target>=96 per TestResolver's
	## own auto-fail carve-out, so this is a guaranteed pass) ---
	screen.dungeon_state["rooms"][0] = chasm_room.duplicate(true)
	GameState.dungeon_state = screen.dungeon_state
	var strider := Character.new()
	strider.character_name = "Chasm Strider"
	strider.allegiance = "ally"
	strider.characteristics = CharacteristicSet.new()
	strider.characteristics.agility = 100
	strider.wounds_current = 20
	strider.wounds_max = 20
	screen.battle_positions[strider] = chasm_pos
	await screen._maybe_trigger_hazard(strider, chasm_pos, pre_move_pos)
	check.call("Chasm success leaves the mover's position untouched", screen.battle_positions[strider] == chasm_pos)
	check.call("Chasm success applies no falling damage", strider.wounds_current == 20)
	check.call("Chasm room is marked hazard_resolved after a successful crossing too", screen.dungeon_state["rooms"][0].get("hazard_resolved", false))

	## --- Chasm: resolve-only-once (a second trigger on an already-
	## resolved room must be a complete no-op, even for a mover who would
	## otherwise fail) ---
	var already_resolved_room: Dictionary = chasm_room.duplicate(true)
	already_resolved_room["hazard_resolved"] = true
	screen.dungeon_state["rooms"][0] = already_resolved_room
	GameState.dungeon_state = screen.dungeon_state
	var late_faller := Character.new()
	late_faller.character_name = "Late Faller"
	late_faller.allegiance = "ally"
	late_faller.characteristics = CharacteristicSet.new()
	late_faller.characteristics.agility = 0
	late_faller.wounds_current = 20
	late_faller.wounds_max = 20
	screen.battle_positions[late_faller] = chasm_pos
	await screen._maybe_trigger_hazard(late_faller, chasm_pos, pre_move_pos)
	check.call("an already-resolved Chasm never re-triggers (position unchanged)", screen.battle_positions[late_faller] == chasm_pos)
	check.call("an already-resolved Chasm never re-triggers (no damage)", late_faller.wounds_current == 20)

	## --- Spike trap: forced FAILURE (Initiative 0). Damage, not position
	## revert -- "failed test causes 1d12 Damage", the move itself stands. ---
	var spike_fail_ok := false
	var spike_dmg_in_range := false
	for attempt in range(10):
		screen.dungeon_state["rooms"][1] = spike_room.duplicate(true)
		screen.dungeon_state["rooms"][1]["hazard_resolved"] = false
		GameState.dungeon_state = screen.dungeon_state
		var trapped := Character.new()
		trapped.character_name = "Spiked One"
		trapped.allegiance = "ally"
		trapped.characteristics = CharacteristicSet.new()
		trapped.characteristics.initiative = 0
		trapped.wounds_current = 20
		trapped.wounds_max = 20
		screen.battle_positions[trapped] = spike_pos
		await screen._maybe_trigger_hazard(trapped, spike_pos, pre_move_pos)
		var resolved_spike_room: Dictionary = screen.dungeon_state["rooms"][1]
		if resolved_spike_room.get("hazard_resolved", false) and trapped.wounds_current < 20:
			spike_fail_ok = true
			var dmg: int = 20 - trapped.wounds_current
			spike_dmg_in_range = dmg >= 1 and dmg <= 12
			check.call("Spike trap failure does NOT revert position (kept walking)", screen.battle_positions[trapped] == spike_pos)
			break
	check.call("Spike trap failure deals direct wound damage", spike_fail_ok)
	check.call("Spike trap damage is within the 1d12 range", spike_dmg_in_range)

	## --- Spike trap: forced SUCCESS (Initiative 100) ---
	screen.dungeon_state["rooms"][1] = spike_room.duplicate(true)
	GameState.dungeon_state = screen.dungeon_state
	var spotter := Character.new()
	spotter.character_name = "Spike Spotter"
	spotter.allegiance = "ally"
	spotter.characteristics = CharacteristicSet.new()
	spotter.characteristics.initiative = 100
	spotter.wounds_current = 20
	spotter.wounds_max = 20
	screen.battle_positions[spotter] = spike_pos
	await screen._maybe_trigger_hazard(spotter, spike_pos, pre_move_pos)
	check.call("Spike trap success applies no damage", spotter.wounds_current == 20)
	check.call("Spike trap room is marked hazard_resolved after a successful spot too", screen.dungeon_state["rooms"][1].get("hazard_resolved", false))

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (FieldEncounterHazard): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
