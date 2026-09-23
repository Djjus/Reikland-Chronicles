extends RefCounted
class_name ExplorationAllyPassThroughTest
## Regression test for the request: "While In dungeon and in exploration
## mode/out of combat, allow character to move over each other." —
## FieldEncounterScreen._occupied_squares_excluding() used to treat
## EVERY combatant's footprint as a blocker for pathing/reachability,
## which made sense in real tactical combat but meant a party of two
## exploring a dungeon corridor (single-file, single-square-wide) could
## get stuck unable to swap places or walk past one another even though
## nothing was actually fighting. Fixed by having that same function
## return no blockers at all while _exploration_mode is true (its
## battle_positions only ever holds living party members during
## exploration — see the fix's own comment) — this test confirms both
## halves: free pass-through/stacking while exploring, and that real
## combat (once a monster joins the fight) still blocks allies from each
## other exactly as before.
##
## Needs a live SceneTree (instantiates the real scene), same pattern as
## FieldEncounterExplorationTest.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []
	var check := func(label: String, passed: bool) -> void:
		checks.append([label, passed])

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var mover: Character = GameState.player_character
	mover.character_name = "Mover"

	var human = GameData.find_race("Human")
	var soldier = GameData.find_career("Soldier")
	var companion: Character = CharacterCreator.create_character("Companion", human, soldier, {})
	GameState.add_party_member(companion)

	GameState.pending_dungeon_theme_id = "sewer"
	GameState.dungeon_entry_requested = true   ## real dungeon-entry signal, see that field's own header comment

	var screen = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child.call_deferred(screen)
	for i in range(4):
		await tree.process_frame

	check.call("FieldEncounter instantiated without error", screen != null)
	check.call("starts in exploration mode", screen._exploration_mode)
	check.call("both party members placed on the dungeon grid", screen.battle_positions.has(mover) and screen.battle_positions.has(companion))

	var comp_pos: Vector2i = screen.battle_positions[companion]

	## --- Case 1: while exploring, a companion's own square is never a
	## blocker for someone else's pathing/reachability at all.
	var occupied_while_exploring: Dictionary = screen._occupied_squares_excluding(mover)
	check.call("Case 1: exploration mode reports zero blocked squares from the companion", occupied_while_exploring.is_empty())

	## --- Case 2: a real Move can actually land the mover ON the
	## companion's own square (moving "over" them), same as a player
	## would experience clicking that square on the map.
	screen.movement_remaining = mover.get_movement() * 4
	screen._on_move_button_pressed()
	check.call("Case 2: move mode entered", screen.move_mode_active)
	check.call("Case 2: the companion's own square is itself reachable while exploring", screen._move_mode_reachable.has(comp_pos))
	if screen._move_mode_reachable.has(comp_pos):
		screen._try_commit_move(comp_pos)
		check.call("Case 2: the mover successfully landed on/passed over the companion's square", screen.battle_positions[mover] == comp_pos)
		check.call("Case 2: the companion itself is undisturbed, still on the same square (both now stacked)", screen.battle_positions[companion] == comp_pos)

	## --- Case 3: once real combat starts (a monster joins the fight),
	## _exploration_mode flips false and ally-vs-ally blocking resumes
	## exactly as normal tactical combat has always worked.
	var open_square: Vector2i = screen.battle_grid.find_open_square_near(screen.battle_positions[mover], {})
	screen._spawn_monsters_during_exploration(["Giant Rat"], open_square, null)
	check.call("Case 3: setup -- a monster actually joined the fight", not screen.monsters.is_empty())
	check.call("Case 3: _exploration_mode flipped false the instant real combat started", not screen._exploration_mode)
	var occupied_in_combat: Dictionary = screen._occupied_squares_excluding(mover)
	check.call("Case 3: in real combat, the companion's own square blocks pathing again, same as always", occupied_in_combat.has(screen.battle_positions[companion]))

	screen.queue_free()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Exploration Ally Pass-Through): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
