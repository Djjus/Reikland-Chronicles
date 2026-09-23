extends RefCounted
class_name ExplorationActionsColumnTest
## Regression test for the request ("While out of combat (explore mode),
## lets replace the Attack / Defence section with a one called Actions,
## and move the Dungeon action buttons there (Open Door/Jump the
## Chasm/Exit the Sewers)"). Drives a real FieldEncounter through both
## states:
##   (a) exploration mode (no monsters yet) — the middle action-menu
##       column's own header reads "Actions", not "Attack / Defence",
##       and it's the one now hosting Open Door/Jump the Chasm/Exit the
##       Sewers, not the "Movement / Free Actions" column they used to
##       live in; the normal combat-only content (Defensive Stance,
##       Disengage) is gone from the menu entirely while there's nothing
##       to fight;
##   (b) the moment a monster is actually encountered (_exploration_mode
##       flips false, same live encounter) — the column reverts to
##       "Attack / Defence" with its normal combat content back
##       (Defensive Stance), and the dungeon buttons are gone.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

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
	for i in range(6):
		await tree.process_frame

	checks.append(["setup: FieldEncounter actually entered exploration mode", fe._exploration_mode])

	## (a) Exploration mode: "Actions" header, dungeon buttons present,
	## Defensive Stance gone.
	var actions_header: Label = _find_label_with_text(fe.target_container, "Actions")
	checks.append(["THE FIX: the middle column's header reads 'Actions' during exploration", actions_header != null])
	var attack_defence_header: Label = _find_label_with_text(fe.target_container, "Attack / Defence")
	checks.append(["the old 'Attack / Defence' header is gone during exploration", attack_defence_header == null])
	checks.append(["'Open Door' is present in the action menu during exploration", _find_button_with_text(fe.target_container, "Open Door") != null])
	checks.append(["'Jump the Chasm' is present in the action menu during exploration", _find_button_with_text(fe.target_container, "Jump the Chasm") != null])
	checks.append(["Defensive Stance is NOT shown while out of combat", _find_button_with_text(fe.target_container, "Defensive Stance  [Z]") == null])

	## The dungeon buttons must actually live under the SAME column as
	## the "Actions" header, not merely somewhere in the menu.
	if actions_header != null:
		var actions_column: Node = actions_header.get_parent()
		checks.append(["'Open Door' lives in the same column as the 'Actions' header", _find_button_with_text(actions_column, "Open Door") != null])

	## (b) Real combat: spawn a monster mid-exploration (same hand-off
	## _open_door_at()/_check_wandering_monsters() already use), then
	## re-render the same menu.
	var entrance: Vector2i = fe.dungeon_state.get("entrance_pos", Vector2i.ZERO)
	fe._spawn_monsters_during_exploration(["Giant Rat"], entrance, null)
	for i in range(3):
		await tree.process_frame
	fe._render_turn_action_menu()
	for i in range(3):
		await tree.process_frame

	checks.append(["setup: _exploration_mode flips false once a monster is encountered", not fe._exploration_mode])
	checks.append(["once real combat starts, the column header reverts to 'Attack / Defence'", _find_label_with_text(fe.target_container, "Attack / Defence") != null])
	checks.append(["once real combat starts, the 'Actions' header is gone", _find_label_with_text(fe.target_container, "Actions") == null])
	checks.append(["once real combat starts, 'Open Door' is no longer offered", _find_button_with_text(fe.target_container, "Open Door") == null])
	checks.append(["once real combat starts, 'Jump the Chasm' is no longer offered", _find_button_with_text(fe.target_container, "Jump the Chasm") == null])
	checks.append(["once real combat starts, Defensive Stance is back", _find_button_with_text(fe.target_container, "Defensive Stance  [Z]") != null])

	## The header/Defensive-Stance checks above only prove SOMETHING
	## reverted — confirm the real weapon Attack button (the whole
	## reason the column exists in combat at all) genuinely comes back
	## too, not just leftover static content, by actually selecting the
	## new monster as a target and checking its dynamic "<Weapon> - <N>"
	## text (see attack_btn.text above in field_encounter_screen.gd).
	var rat: Character = fe.monsters[fe.monsters.size() - 1]
	fe.selected_target = rat
	fe._render_turn_action_menu()
	for i in range(3):
		await tree.process_frame
	var weapon_name: String = fe.weapons[fe.player].weapon_name
	checks.append(["once a target is selected in real combat, the real weapon Attack button (dynamic '<Weapon> - <N>' text) renders in the Attack / Defence column", _find_button_containing(fe.target_container, weapon_name) != null])

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
	print("RESULT (Exploration Actions Column): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass

static func _find_button_with_text(root: Node, label: String) -> Button:
	for child in root.get_children():
		if child is Button and String(child.text) == label:
			return child
		if child.get_child_count() > 0:
			var found: Button = _find_button_with_text(child, label)
			if found != null:
				return found
	return null

static func _find_button_containing(root: Node, substr: String) -> Button:
	for child in root.get_children():
		if child is Button and String(child.text).find(substr) != -1:
			return child
		if child.get_child_count() > 0:
			var found: Button = _find_button_containing(child, substr)
			if found != null:
				return found
	return null

static func _find_label_with_text(root: Node, label: String) -> Label:
	for child in root.get_children():
		if child is Label and String(child.text) == label:
			return child
		if child.get_child_count() > 0:
			var found: Label = _find_label_with_text(child, label)
			if found != null:
				return found
	return null
