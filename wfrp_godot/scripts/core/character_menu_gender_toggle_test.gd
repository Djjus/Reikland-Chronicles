extends RefCounted
class_name CharacterMenuGenderToggleTest
## Per the request ("lets now remove the Gender toggle button"): the
## always-visible "Toggle Gender" button this test used to drive (added
## as a one-click self-correction for characters caught by the old
## gender-not-persisted save/load bug — see CharacterGenderPersistenceTest)
## is gone from character_menu_screen.gd. That underlying bug has long
## since been fixed for real in Character.to_save_dict()/from_save_dict(),
## so the manual workaround button is no longer needed.
##
## Repurposed (rather than left testing a control that no longer exists,
## or deleted outright — this device bridge has no file-delete capability,
## only write/overwrite) into the regression guard for its removal: confirms
## no "Toggle Gender" button is built into the header any more, while the
## read-only "Gender: Male"/"Gender: Female" display itself (_gender_text(),
## covered in full by CharacterMenuGenderHeaderTest) is untouched and still
## correctly reflects the character's own gender.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var character: Character = GameState.player_character
	character.character_name = "Branwen Oakheart"
	character.gender = "male"

	var menu_scene: PackedScene = load("res://scenes/CharacterMenu.tscn")
	var menu: Node = menu_scene.instantiate()
	tree.get_root().add_child.call_deferred(menu)
	await tree.process_frame
	await tree.process_frame
	menu.open()
	await tree.process_frame

	var header_cheat_row: HBoxContainer = menu.get_node("%HeaderCheatRow")
	var found_toggle_btn := false
	for child in header_cheat_row.get_children():
		if child is Button and (child as Button).text == "Toggle Gender":
			found_toggle_btn = true
	checks.append(["No 'Toggle Gender' button is built into the header any more", not found_toggle_btn])

	var header_line1: RichTextLabel = menu.get_node("%HeaderLine1")
	checks.append(["The read-only Gender display still shows 'Gender: Male' for a male character", header_line1.text.contains("Gender: Male")])

	character.gender = "female"
	menu._rebuild_header()
	await tree.process_frame
	checks.append(["...and still correctly shows 'Gender: Female' after the character's own gender changes elsewhere", header_line1.text.contains("Gender: Female")])
	found_toggle_btn = false
	for child in header_cheat_row.get_children():
		if child is Button and (child as Button).text == "Toggle Gender":
			found_toggle_btn = true
	checks.append(["Still no 'Toggle Gender' button after a header rebuild", not found_toggle_btn])

	menu.queue_free()
	await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Character Menu Gender Toggle Button Removed): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
