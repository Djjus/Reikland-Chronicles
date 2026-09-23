extends RefCounted
class_name CharacterMenuQeExplorationTest
## Regression test for the user report: "the character menu doesn't allow
## switching character while in exploration mode, fix that."
##
## FieldEncounter.tscn's own Character Menu (opened via "M" while
## _exploration_mode is true — see field_encounter_character_menu_test.gd
## for that feature's own original coverage) never wired Q/E to
## character_menu.cycle_displayed_character() the way Overworld's and
## City's own _unhandled_input() both already do for their own Character
## Menu instances — with nothing to catch Q/E before the screen's own
## blanket "menu's open, ignore every other hotkey" return, the keys did
## nothing at all. See field_encounter_screen.gd's own comment on the
## fix, right above the new Q/E branch in _unhandled_input().
##
## Goes through the real scene (same technique battle_report_test.gd uses
## for its own Q/E character-switch coverage), with a real second party
## member so cycling actually has somewhere to go.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []
	await tree.process_frame
	await tree.process_frame

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "QeTestGrimm"

	## A second party member so Q/E actually has somewhere to cycle to —
	## with only one party member, cycle_displayed_character() is a
	## deliberate no-op (see its own early-return for GameState.party.size()
	## <= 1), which would make this test pass even with the bug still
	## present.
	var ally := Character.new()
	ally.character_name = "QeTestSabine"
	ally.race = pc.race
	ally.characteristics = pc.characteristics.duplicate()
	ally.wounds_max = 10
	ally.wounds_current = 10
	if GameState.party.size() < 2:
		GameState.party.append(ally)

	GameState.current_field_difficulty_tier = 0
	GameState.dungeon_state = {}
	GameState.dungeon_floor_states = {}
	GameState.pending_dungeon_theme_id = "sewer"
	GameState.dungeon_entry_requested = true

	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(8):
		await tree.process_frame

	checks.append(["setup: FieldEncounter actually entered exploration mode", fe._exploration_mode])
	checks.append(["setup: FieldEncounter has its own Character Menu instance", fe.character_menu != null])
	checks.append(["setup: the party really has two members to cycle between", GameState.party.size() >= 2])
	if not fe._exploration_mode or fe.character_menu == null or GameState.party.size() < 2:
		fe.queue_free()
		for i in range(3): await tree.process_frame
		print("RESULT (Character Menu Q/E in Exploration): SETUP FAILED")
		return false

	var q_press := InputEventKey.new()
	q_press.keycode = KEY_Q
	q_press.pressed = true
	var e_press := InputEventKey.new()
	e_press.keycode = KEY_E
	e_press.pressed = true

	## Q/E before the menu is even open should do nothing harmful (no
	## crash, menu stays closed) -- this screen's normal WASD-navigation
	## Q/E-adjacent hotkeys, if any, are unaffected by this fix.
	fe._unhandled_input(e_press)
	for i in range(2):
		await tree.process_frame
	checks.append(["E before the menu is open leaves it closed", not fe.character_menu.visible])

	var m_press := InputEventKey.new()
	m_press.physical_keycode = KEY_M   ## matches project.godot's own "open_menu" binding exactly
	m_press.pressed = true
	fe._unhandled_input(m_press)
	for i in range(3):
		await tree.process_frame
	checks.append(["pressing M opens the Character Menu", fe.character_menu.visible])
	checks.append(["Character Menu starts showing the real player character", fe.character_menu.character == pc])

	## --- The actual regression: E cycles forward while the menu is open.
	fe._unhandled_input(e_press)
	for i in range(2):
		await tree.process_frame
	checks.append(["E while the menu is open cycles to the other party member", fe.character_menu.character == ally])
	checks.append(["the Character Menu is still open after E (not swallowed as a close)", fe.character_menu.visible])

	## --- Q cycles back the other way.
	fe._unhandled_input(q_press)
	for i in range(2):
		await tree.process_frame
	checks.append(["Q while the menu is open cycles back to the player", fe.character_menu.character == pc])

	## --- Everything else the menu-open guard already covered stays
	## covered -- a stray Space press still doesn't leak through to the
	## exploration turn underneath it (same check
	## field_encounter_character_menu_test.gd already runs; re-verified
	## here since the guard itself was edited by this fix).
	var space_press := InputEventKey.new()
	space_press.keycode = KEY_SPACE
	space_press.pressed = true
	var awaiting_target_before: bool = fe.awaiting_player_target
	fe._unhandled_input(space_press)
	for i in range(2):
		await tree.process_frame
	checks.append(["Space while the menu is open still doesn't leak through", fe.awaiting_player_target == awaiting_target_before])
	checks.append(["...and the menu is still open", fe.character_menu.visible])

	## Pressing M again closes it -- and GameState.active_party_index (who
	## you're actively controlling) must be completely unaffected by all
	## this Q/E browsing, per cycle_displayed_character()'s own explicit
	## scope (it's a "who am I viewing" concept, independent of who you
	## control).
	var active_index_before: int = GameState.active_party_index
	fe._unhandled_input(m_press)
	for i in range(3):
		await tree.process_frame
	checks.append(["pressing M again closes the Character Menu", not fe.character_menu.visible])
	checks.append(["Q/E browsing never touched GameState.active_party_index", GameState.active_party_index == active_index_before])

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
	print("RESULT (Character Menu Q/E in Exploration): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
