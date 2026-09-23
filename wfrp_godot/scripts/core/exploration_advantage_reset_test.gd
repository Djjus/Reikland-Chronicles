extends RefCounted
class_name ExplorationAdvantageResetTest
## Regression test for the request ("clear combat Advantage when game
## enters exploration mode after a fight"): _return_to_exploration_after_
## combat() hands the party back from a dungeon fight to exploration mode
## WITHOUT tearing down the live CombatEncounter — see that function's
## own header comment — so its advantage_pool (Up in Arms, p.133-135)
## used to carry straight through, completely unspent, into whatever
## fight the party stumbled into next deeper in the dungeon. Advantage is
## explicitly a per-fight resource, not a running total, so both pools
## now reset to 0 the moment there's no more combat left to spend it in.
##
## Drives this through a real dungeon exploration fixture: enters
## exploration, has a real fight spawn mid-exploration (mirrors
## _open_door_at()'s own monster-arrival path), gives both sides some
## Advantage (as if it had actually been earned during the fight), then
## calls _return_to_exploration_after_combat() directly (same direct-call
## technique this project's own combat tests already use) and confirms
## both pools come back to exactly 0.

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

	checks.append(["setup: exploration mode entered on a real generated dungeon", fe._exploration_mode and not fe.dungeon_state.is_empty()])
	if not fe._exploration_mode:
		fe.queue_free()
		for i in range(3): await tree.process_frame
		print("RESULT (Exploration Advantage Reset): SETUP FAILED")
		return false

	## Mirrors _open_door_at()'s own real monster-arrival hand-off: adds
	## monsters mid-round into the SAME live CombatEncounter exploration
	## has been running since it began, exactly the mechanism that lets
	## Advantage leak from this fight into a later one if left unreset.
	var spawn_square: Vector2i = fe.dungeon_state.get("entrance_pos", Vector2i(5, 5))
	fe._spawn_monsters_during_exploration(["Giant Rat"], spawn_square, {})
	for i in range(3):
		await tree.process_frame

	checks.append(["a fight genuinely started (exploration mode flipped off, a real monster present)", not fe._exploration_mode and fe.monsters.size() >= 1])

	## Simulate real Advantage having actually been earned by both sides
	## during the fight, per Up in Arms' own pooled-Advantage system.
	fe.encounter.advantage_pool.ally = 5
	fe.encounter.advantage_pool.adversary = 3
	checks.append(["setup: both sides genuinely hold nonzero Advantage right now", fe.encounter.advantage_pool.ally > 0 and fe.encounter.advantage_pool.adversary > 0])

	fe._return_to_exploration_after_combat()
	for i in range(3):
		await tree.process_frame

	checks.append(["back in exploration mode after the fight", fe._exploration_mode])
	## The actual regression: both pools genuinely reset to 0, not merely
	## unchanged or partially cleared.
	checks.append(["THE FIX: the ally side's leftover Advantage was cleared on returning to exploration", fe.encounter.advantage_pool.ally == 0])
	checks.append(["THE FIX: the adversary side's leftover Advantage was cleared too", fe.encounter.advantage_pool.adversary == 0])

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
	print("RESULT (Exploration Advantage Reset): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
