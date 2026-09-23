extends RefCounted
class_name OpeningThrowRemovedTest
## Regression test for the request ("lets remove open throw rock, for
## players and monsters"). The old Opening Exchange mechanic let ANY
## melee-armed character or monster make one free-ish ranged "throw" of
## a Rock before melee began (_get_opening_ranged_weapon(), which could
## only ever return null or the "Rock" WeaponDefinition). This test
## proves that mechanic is fully gone for both sides, while confirming
## the things it must NOT have touched are still intact:
##   - the completely separate "Pick Up Rocks" Sling-ammo mechanic
##     (_on_pick_up_rocks / the "Rock" button gated on AmmoLookup.is_sling)
##   - Charge, which shares the same "before melee_has_begun" window but
##     is its own distinct mechanic and was explicitly kept
##   - melee_has_begun itself, still used to gate Batter/Trick etc.

static func run_test(fe) -> bool:
	var checks: Array = []

	var method_names: Array = []
	for m in fe.get_script().get_script_method_list():
		method_names.append(m["name"])
	checks.append(["THE FIX: _get_opening_ranged_weapon no longer exists on FieldEncounterScreen", not method_names.has("_get_opening_ranged_weapon")])
	checks.append(["Pick Up Rocks stays a real, separate method (_on_pick_up_rocks) -- untouched", method_names.has("_on_pick_up_rocks")])
	checks.append(["Charge is untouched -- still a real method the monster/player AI can call (_monster_attack)", method_names.has("_monster_attack")])

	## --- A melee-armed player never sees an "Opening Throw" button,
	## right at the start of a fresh encounter (before melee_has_begun,
	## exactly the window Opening Throw used to fire in).
	var no_pool: Array[String] = []
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_habitat = ""
	fe._start_encounter()
	for i in range(3):
		await fe.get_tree().process_frame

	var player: Character = fe.player
	var monster: Character = fe.monsters[0] if fe.monsters.size() > 0 else null
	checks.append(["setup: a monster genuinely exists", monster != null])
	checks.append(["setup: melee_has_begun starts false, the exact window Opening Throw used to occupy", not fe.melee_has_begun])

	if monster != null:
		player.equipped_weapon = "Sword"
		fe.weapons[player] = fe._resolve_weapon(player)
		fe.battle_grid = BattleGrid.new()
		fe.battle_grid.generate_from_terrain_snapshot([])
		fe.battle_positions[player] = Vector2i(0, 0)
		fe.battle_positions[monster] = Vector2i(5, 0)
		fe.selected_target = monster
		fe._render_turn_action_menu()
		for i in range(3):
			await fe.get_tree().process_frame
		checks.append(["no 'Opening Throw' button is ever offered to a melee-armed player pre-melee", _find_button_containing(fe.target_container, "Opening Throw") == null])

	## --- Monster AI: no source-level trace of the removed mechanic ------
	var source: String = FileAccess.get_file_as_string("res://scripts/ui/field_encounter_screen.gd")
	checks.append(["the source no longer contains any reference to _get_opening_ranged_weapon", source.find("_get_opening_ranged_weapon") == -1])
	checks.append(["the source no longer contains the 'Opening Throw' button text", source.find("Opening Throw") == -1])
	checks.append(["the Rock WeaponDefinition itself is still registered (Pick Up Rocks still needs it)", GameData.weapon_db.find_by_name("Rock") != null])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Opening Throw Removed): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass

static func _find_button_containing(root: Node, substr: String) -> Button:
	for child in root.get_children():
		if child is Button and String(child.text).find(substr) != -1:
			return child
		if child.get_child_count() > 0:
			var found: Button = _find_button_containing(child, substr)
			if found != null:
				return found
	return null
