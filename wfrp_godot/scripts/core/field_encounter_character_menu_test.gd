extends RefCounted
class_name FieldEncounterCharacterMenuTest
## Regression test for the request ("allow opening Character Menu during
## dungeon exploring"): FieldEncounter.tscn never carried its own
## Character Menu at all before this — only Overworld did, and
## FieldEncounter is reached via change_scene_to_file(), which tears
## Overworld's whole scene (menu included) down. There was simply no way
## to check inventory/equipment/spells while exploring a dungeon.
##
## Fixed by giving FieldEncounter its own CharacterMenu.tscn instance
## (character_menu, instantiated in _ready()), toggled by the same
## "open_menu" action (M) Overworld's own menu uses, gated to
## exploration mode only (not mid-combat-turn), and guarded so this
## screen's own hotkeys (WASD/Space/Enter, all written assuming a live
## turn) don't leak through to whatever's behind the menu while it's
## open -- the same class of bug this project already hit once for
## Overworld itself when its own character_menu/pause_menu were created
## too late (see Overworld._unhandled_input's own comment on that).

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
	checks.append(["FieldEncounter now instantiates its own Character Menu", fe.character_menu != null])
	if not fe._exploration_mode or fe.character_menu == null:
		fe.queue_free()
		for i in range(3): await tree.process_frame
		print("RESULT (Field Encounter Character Menu): SETUP FAILED")
		return false

	checks.append(["Character Menu starts closed", not fe.character_menu.visible])

	var m_press := InputEventKey.new()
	m_press.physical_keycode = KEY_M   ## matches project.godot's own "open_menu" binding exactly
	m_press.pressed = true

	fe._unhandled_input(m_press)
	for i in range(3):
		await tree.process_frame
	checks.append(["pressing M (open_menu) while exploring opens the Character Menu", fe.character_menu.visible])

	## Confirms the character actually shown is the real player, not an
	## empty/uninitialized popup shell.
	checks.append(["the Character Menu is showing the real player character", fe.character_menu.character == fe.player])

	## While open, this screen's OWN hotkeys must not leak through --
	## Space is heavily overloaded elsewhere in _unhandled_input (accepts
	## prompts, ends turns, etc.) and would misfire against whatever
	## state this screen is in if it reached those branches while a
	## modal menu is sitting on top.
	var space_press := InputEventKey.new()
	space_press.keycode = KEY_SPACE
	space_press.pressed = true
	var awaiting_target_before: bool = fe.awaiting_player_target
	fe._unhandled_input(space_press)
	for i in range(2):
		await tree.process_frame
	checks.append(["Space while the Character Menu is open doesn't change awaiting_player_target underneath it", fe.awaiting_player_target == awaiting_target_before])
	checks.append(["Character Menu is still open after that stray Space press", fe.character_menu.visible])

	## Pressing M again closes it.
	fe._unhandled_input(m_press)
	for i in range(3):
		await tree.process_frame
	checks.append(["pressing M again closes the Character Menu", not fe.character_menu.visible])

	fe.queue_free()
	for i in range(3):
		await tree.process_frame

	## --- Gated to exploration mode: a plain combat encounter (no
	## dungeon) doesn't get a Character Menu wired to the M key. Not
	## required by the request, but proves this doesn't change ordinary
	## combat-screen behaviour at all.
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	GameState.dungeon_state = {}
	GameState.dungeon_entry_requested = false
	GameState.pending_encounter_monster_names = ["Giant Rat"]
	var fe2 = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe2)
	for i in range(5):
		await tree.process_frame

	checks.append(["setup: fe2 is a plain combat encounter, not exploring", not fe2._exploration_mode])
	fe2._unhandled_input(m_press)
	for i in range(2):
		await tree.process_frame
	checks.append(["M does nothing mid-combat (not exploring) -- Character Menu stays closed", fe2.character_menu == null or not fe2.character_menu.visible])

	fe2.queue_free()
	for i in range(3):
		await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Field Encounter Character Menu): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
