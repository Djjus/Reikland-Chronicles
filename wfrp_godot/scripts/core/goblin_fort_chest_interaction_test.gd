extends RefCounted
class_name GoblinFortChestInteractionTest
## Verifies the two follow-up requests layered on top of the Goblin Fort
## chest (see goblin_fort_chest_test.gd for the chest's own lock/trap/
## loot state machine, which this test does not re-cover):
##
## 1. "chest adjacency" — the player no longer has to stand on the exact
##    chest tile to interact with it; standing on any of its 8
##    neighbouring tiles (per field_encounter_screen.gd's own
##    _is_near_chest()) is enough.
## 2. "Search/Open Chest as Free Actions" — Search (_on_perception_chest_
##    pressed) and Open (_on_open_chest_pressed) no longer cost the
##    character's Action (action_used_this_turn stays false, movement_
##    remaining is untouched), while Break Chest and Pick Lock still do.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	var game_state = tree.get_root().get_node("/root/GameState")
	game_state.reset_world_state()
	game_state.player_character = null
	game_state.ensure_player_character()
	game_state.player_character.skill_advances["Perception"] = 20
	game_state.player_character.skill_advances["Pick Lock"] = 20

	game_state.pending_dungeon_theme_id = "goblin_fort"
	game_state.dungeon_entry_requested = true
	var fes = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fes)
	tree.current_scene = fes
	for i in range(10):
		await tree.process_frame

	var chest_pos: Vector2i = fes.dungeon_state.get("chest_pos", Vector2i(-999, -999))

	## --- Case 1: standing exactly on the chest tile counts as "near".
	checks.append(["Case 1: standing on the chest tile itself is near the chest", fes._is_near_chest(chest_pos)])

	## --- Case 2: a diagonal neighbour of the chest also counts.
	var neighbour_pos: Vector2i = chest_pos + Vector2i(1, 1)
	checks.append(["Case 2: a diagonal neighbour of the chest is near the chest", fes._is_near_chest(neighbour_pos)])

	## --- Case 3: two tiles away does NOT count.
	var far_pos: Vector2i = chest_pos + Vector2i(2, 0)
	checks.append(["Case 3: two tiles away is NOT near the chest", not fes._is_near_chest(far_pos)])

	## --- Case 4: Search the Chest from an adjacent (not exact) tile,
	## as a genuinely Free Action — no Action spent, no movement spent.
	fes.battle_positions[fes.player] = neighbour_pos
	fes.awaiting_player_target = true
	fes.action_used_this_turn = false
	var movement_before_search: int = fes.movement_remaining
	fes._on_perception_chest_pressed()
	checks.append(["Case 4: Search the Chest works from an adjacent tile", fes.dungeon_state.get("chest_trap_spotted", false) == true or fes.dungeon_state.get("chest_locked", true) != null])
	checks.append(["Case 4: Search the Chest did NOT cost the Action", fes.action_used_this_turn == false])
	checks.append(["Case 4: Search the Chest did NOT cost movement", fes.movement_remaining == movement_before_search])

	## --- Case 5: unlock the chest directly (bypassing Break, which is
	## covered by goblin_fort_chest_test.gd) so Open Chest can be
	## exercised on its own from an adjacent tile as a Free Action too.
	fes.dungeon_state["chest_locked"] = false
	fes.action_used_this_turn = false
	var movement_before_open: int = fes.movement_remaining
	var bp_before: int = fes.player.brass_pennies
	var ss_before: int = fes.player.silver_shillings
	fes._on_open_chest_pressed()
	checks.append(["Case 5: Open Chest from an adjacent tile actually loots it", fes.dungeon_state.get("chest_looted", false) == true])
	checks.append(["Case 5: Open Chest granted real coin", fes.player.brass_pennies > bp_before or fes.player.silver_shillings > ss_before])
	checks.append(["Case 5: Open Chest did NOT cost the Action", fes.action_used_this_turn == false])
	checks.append(["Case 5: Open Chest did NOT cost movement", fes.movement_remaining == movement_before_open])

	## --- Case 6: standing too far away, Search/Open/Break/Pick Lock are
	## all correctly refused (no state change at all).
	fes.battle_positions[fes.player] = far_pos
	fes.dungeon_state["chest_looted"] = false
	fes.dungeon_state["chest_locked"] = true
	fes.dungeon_state["chest_trap_spotted"] = false
	fes.action_used_this_turn = false
	fes._on_perception_chest_pressed()
	fes._on_open_chest_pressed()
	checks.append(["Case 6: Search is refused when too far from the chest", fes.dungeon_state.get("chest_trap_spotted", false) == false])
	checks.append(["Case 6: Open is refused when too far from the chest", fes.dungeon_state.get("chest_looted", false) == false])
	var wounds_before_far_break: int = fes.player.wounds_current
	fes._on_break_chest_pressed()
	checks.append(["Case 6: Break Chest is refused when too far from the chest (no trap sprung)", fes.player.wounds_current == wounds_before_far_break])
	checks.append(["Case 6: Break Chest refusal did NOT cost the Action", fes.action_used_this_turn == false])

	## --- Case 7: Break Chest from an adjacent tile still costs the
	## Action, unlike Search/Open above.
	fes.battle_positions[fes.player] = neighbour_pos
	fes.action_used_this_turn = false
	fes._on_break_chest_pressed()
	checks.append(["Case 7: Break Chest from an adjacent tile still costs the Action", fes.action_used_this_turn == true])

	fes.queue_free()
	for i in range(3):
		await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Goblin Fort Chest Interaction): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
