extends RefCounted
class_name DungeonDifficultyTierTest
## Verifies the fix for "goblin in the greenskin fort has 25 Weaponskill
## ... not the +20 ... on top of the base ... stats": the bug was that
## only _trigger_idol_ambush() ever copied dungeon_theme.difficulty_tier
## into GameState.current_field_difficulty_tier, so every OTHER dungeon
## fight (via _spawn_monsters_during_exploration()) used whatever tier
## was last left over from Overworld — often 0, giving raw, unbonused
## monster stats. The fix moved that assignment into the generic
## _load_or_generate_dungeon() so it applies uniformly to every dungeon
## theme (Goblin Fort, Cave, Sewer — all difficulty_tier == 2) on both
## the fresh-generate path and the resume-an-existing-dungeon path.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	var game_state = tree.get_root().get_node("/root/GameState")

	## --- Case 1: fresh-generate path, Goblin Fort. Deliberately leave a
	## stale, WRONG tier (0) sitting in GameState first — exactly the
	## real-world scenario (Overworld's own per-tile system leaves this
	## set to whatever the last outdoor tile was) — so this case actually
	## proves _load_or_generate_dungeon() overwrites it rather than
	## merely happening to already hold the right value.
	game_state.reset_world_state()
	game_state.player_character = null
	game_state.ensure_player_character()
	game_state.current_field_difficulty_tier = 0
	game_state.pending_dungeon_theme_id = "goblin_fort"
	game_state.dungeon_entry_requested = true
	var fes1 = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fes1)
	tree.current_scene = fes1
	for i in range(10):
		await tree.process_frame
	checks.append(["Case 1: Goblin Fort (fresh-generate) sets tier to its own difficulty_tier (2)", game_state.current_field_difficulty_tier == 2])
	checks.append(["Case 1: dungeon_theme.difficulty_tier really is 2", fes1.dungeon_theme.difficulty_tier == 2])
	fes1.queue_free()
	for i in range(3):
		await tree.process_frame

	## --- Case 2: fresh-generate path, Cave — confirms the fix is
	## generic across themes, not special-cased to the Goblin Fort like
	## the old _trigger_idol_ambush()-only assignment was.
	game_state.reset_world_state()
	game_state.player_character = null
	game_state.ensure_player_character()
	game_state.current_field_difficulty_tier = 0
	game_state.pending_dungeon_theme_id = "cave"
	game_state.dungeon_entry_requested = true
	var fes2 = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fes2)
	tree.current_scene = fes2
	for i in range(10):
		await tree.process_frame
	checks.append(["Case 2: Cave (fresh-generate) sets tier to its own difficulty_tier (2)", game_state.current_field_difficulty_tier == 2])
	fes2.queue_free()
	for i in range(3):
		await tree.process_frame

	## --- Case 3: fresh-generate path, Sewer.
	game_state.reset_world_state()
	game_state.player_character = null
	game_state.ensure_player_character()
	game_state.current_field_difficulty_tier = 0
	game_state.pending_dungeon_theme_id = "sewer"
	game_state.dungeon_entry_requested = true
	var fes3 = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fes3)
	tree.current_scene = fes3
	for i in range(10):
		await tree.process_frame
	checks.append(["Case 3: Sewer (fresh-generate) sets tier to its own difficulty_tier (2)", game_state.current_field_difficulty_tier == 2])

	## --- Case 4: a real spawned monster's Characteristic actually
	## reflects the Tier bonus (the original bug report's own symptom —
	## "Goblin has 25 WS, not +20 on top of base").
	var base_goblin: MonsterDefinition = GameData.monster_db.find_by_name("Goblin")
	var base_ws: int = base_goblin.characteristics.get_value("weapon_skill") if base_goblin != null else -1
	fes3._spawn_monsters_during_exploration(["Goblin"], fes3.dungeon_state.get("chest_pos", Vector2i.ZERO), null)
	var spawned_ws: int = -1
	for m in fes3.monsters:
		if m.character_name.begins_with("Goblin"):
			spawned_ws = m.characteristics.get_value("weapon_skill")
			break
	checks.append(["Case 4: a Goblin spawned during Sewer exploration got the +20 Tier bonus on WS", base_ws >= 0 and spawned_ws == base_ws + 20])
	fes3.queue_free()
	for i in range(3):
		await tree.process_frame

	## --- Case 5: resume-an-existing-dungeon path. Simulate leaving and
	## coming back to a Goblin Fort already in progress (GameState.
	## dungeon_state non-empty on load) with the stale wrong tier again —
	## proves the fix also covers the "if not GameState.dungeon_state.
	## is_empty()" resume branch, not just the fresh-generate branch.
	game_state.reset_world_state()
	game_state.player_character = null
	game_state.ensure_player_character()
	game_state.pending_dungeon_theme_id = "goblin_fort"
	game_state.dungeon_entry_requested = true
	var fes4 = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fes4)
	tree.current_scene = fes4
	for i in range(10):
		await tree.process_frame
	var saved_dungeon_state: Dictionary = game_state.dungeon_state.duplicate(true)
	fes4.queue_free()
	for i in range(3):
		await tree.process_frame

	game_state.current_field_difficulty_tier = 0
	game_state.dungeon_state = saved_dungeon_state
	game_state.pending_dungeon_theme_id = ""
	game_state.dungeon_entry_requested = true
	var fes5 = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fes5)
	tree.current_scene = fes5
	for i in range(10):
		await tree.process_frame
	checks.append(["Case 5: resuming an existing Goblin Fort visit also sets the tier correctly", game_state.current_field_difficulty_tier == 2])
	fes5.queue_free()
	for i in range(3):
		await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Dungeon Difficulty Tier): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
