extends RefCounted
class_name DungeonStairsUpLandingTest
## Regression test for the report ("player is moved back to the down
## stairs in the quest room when coming back up from a lower dungeon
## level, right now its returning them to the Exit/Up if they go from
## level 1 to level 0"):
##
## _take_stairs_up() generates a fresh, independently-random layout for
## the shallower floor it's returning to (every floor visit is its own
## fresh DungeonGenerator.generate() call — there's no persisted "the
## floor as you left it" state anywhere in this project, see
## _take_stairs_down()'s own comment), then re-placed the party via
## _setup_dungeon_battle_grid()'s normal auto-placement, which always
## anchors on dungeon_state's own entrance_pos. That's correct for
## _take_stairs_down() (arriving at a new, deeper floor genuinely lands
## you at "the top of its own stairs down", i.e. its entrance_pos) but
## wrong for _take_stairs_up(): on the ground floor especially,
## entrance_pos is the dungeon's real world-map exit door, not a
## stairwell at all, so climbing up from Floor 1 dropped the party right
## in front of "Leave the Dungeon" instead of at the new Floor 0's own
## Quest room stairs (the stairwell they'd actually have climbed).
##
## Fixed by _setup_dungeon_battle_grid() taking an optional spawn_anchor
## override, which _take_stairs_up() now populates with the freshly
## generated arriving floor's own Quest room stairs_pos (falling back to
## entrance_pos only defensively, since every floor short of
## MAX_DUNGEON_FLOOR always has one).
##
## This test drives the real functions directly (not the button click
## handlers, which additionally gate on standing in the right spot to
## trigger them at all -- irrelevant here, this is about WHERE the party
## ends up afterward, not whether the action is offered) across both a
## floor 1 -> 0 climb (the exact reported case) and a floor 2 -> 1 climb
## (proving this isn't special-cased to the ground floor), and confirms
## _take_stairs_down() itself is completely unchanged (still anchors on
## entrance_pos, per its own correct existing behaviour).

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
	GameState.dungeon_entry_requested = true

	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(8):
		await tree.process_frame

	checks.append(["setup: FieldEncounter actually entered exploration mode", fe._exploration_mode])
	if not fe._exploration_mode:
		fe.queue_free()
		for i in range(3): await tree.process_frame
		print("RESULT (Dungeon Stairs Up Landing): SETUP FAILED")
		return false

	checks.append(["setup: starts on Floor 0", int(fe.dungeon_state.get("dungeon_floor", -1)) == 0])

	## --- Floor 0 -> 1 -> back to 0 (the exact reported case) -----------
	fe._take_stairs_down()
	checks.append(["_take_stairs_down() advances to Floor 1", int(fe.dungeon_state.get("dungeon_floor", -1)) == 1])
	checks.append(["_take_stairs_down() still anchors on the new floor's own entrance_pos (unchanged behaviour)",
		fe.battle_positions.get(fe.player, Vector2i(-2, -2)) == fe.dungeon_state.get("entrance_pos")])

	fe._take_stairs_up()
	checks.append(["_take_stairs_up() returns to Floor 0", int(fe.dungeon_state.get("dungeon_floor", -1)) == 0])

	var floor0_stairs_pos := Vector2i(-1, -1)
	for room in fe.dungeon_state.get("rooms", []):
		var sp: Vector2i = room.get("stairs_pos", Vector2i(-1, -1))
		if sp != Vector2i(-1, -1):
			floor0_stairs_pos = sp
			break
	checks.append(["setup: the freshly-generated Floor 0 has a real Quest room stairs_pos", floor0_stairs_pos != Vector2i(-1, -1)])
	var player_pos_after_up: Vector2i = fe.battle_positions.get(fe.player, Vector2i(-2, -2))
	checks.append(["THE FIX: climbing from Floor 1 back to Floor 0 lands the party AT the new Floor 0's own Quest room stairs, not entrance_pos",
		player_pos_after_up == floor0_stairs_pos])
	checks.append(["...and genuinely NOT at entrance_pos (the old, wrong landing spot) unless they happen to coincide",
		floor0_stairs_pos != fe.dungeon_state.get("entrance_pos") and player_pos_after_up != fe.dungeon_state.get("entrance_pos")])

	## --- A deeper climb too: Floor 0 -> 1 -> 2 -> back to 1 -------------
	## Proves this isn't special-cased to "landing on the ground floor" --
	## the same fix applies climbing back to ANY shallower floor.
	fe._take_stairs_down()
	fe._take_stairs_down()
	checks.append(["setup: now on Floor 2", int(fe.dungeon_state.get("dungeon_floor", -1)) == 2])
	fe._take_stairs_up()
	checks.append(["climbing from Floor 2 lands back on Floor 1", int(fe.dungeon_state.get("dungeon_floor", -1)) == 1])
	var floor1_stairs_pos := Vector2i(-1, -1)
	for room in fe.dungeon_state.get("rooms", []):
		var sp2: Vector2i = room.get("stairs_pos", Vector2i(-1, -1))
		if sp2 != Vector2i(-1, -1):
			floor1_stairs_pos = sp2
			break
	checks.append(["setup: the freshly-generated Floor 1 has a real Quest room stairs_pos", floor1_stairs_pos != Vector2i(-1, -1)])
	checks.append(["climbing from Floor 2 to Floor 1 also lands at THAT floor's own Quest room stairs",
		fe.battle_positions.get(fe.player, Vector2i(-2, -2)) == floor1_stairs_pos])

	## --- Floor 0 is still the floor: climbing from it is a no-op --------
	fe._take_stairs_up()
	fe._take_stairs_up()
	checks.append(["climbing while already on Floor 0 is a no-op (never goes negative)", int(fe.dungeon_state.get("dungeon_floor", -1)) == 0])

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
	print("RESULT (Dungeon Stairs Up Landing): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
