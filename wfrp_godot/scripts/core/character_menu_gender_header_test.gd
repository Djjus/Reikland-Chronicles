extends RefCounted
class_name CharacterMenuGenderHeaderTest
## Per the request ("lets remove group coin from the menu header and
## display the character gender instead"): HeaderLine1 (name/race/
## career/XP/Enc/...) used to close with "Group Coin: X GC Y SS Z BP"
## (see the old _group_coin_text(), now replaced by _gender_text() in
## character_menu_screen.gd) — that's gone, replaced by "Gender: Male"/
## "Gender: Female". The party's shared coin total is unaffected and
## still shown in full on the Inventory tab's own "Coin (shared by the
## whole party)" line (see _rebuild_inventory), which this test also
## checks, so nothing about the underlying feature was actually removed
## -- only where it's displayed.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var character: Character = GameState.player_character
	character.character_name = "Gwendolyn Ashworth"
	character.gender = "female"
	character.gold_crowns = 7
	character.silver_shillings = 3
	character.brass_pennies = 11

	var menu_scene: PackedScene = load("res://scenes/CharacterMenu.tscn")
	var menu: Node = menu_scene.instantiate()
	tree.get_root().add_child.call_deferred(menu)
	await tree.process_frame
	await tree.process_frame
	menu.open()
	await tree.process_frame
	await tree.process_frame

	var header_line1: RichTextLabel = menu.get_node("%HeaderLine1")

	## --- Group Coin is gone from the header -----------------------------
	checks.append(["HeaderLine1 no longer mentions Group Coin", not header_line1.text.contains("Group Coin")])
	checks.append(["HeaderLine1 no longer mentions the raw coin figures (GC/SS/BP)", not header_line1.text.contains("GC") and not header_line1.text.contains("SS") and not header_line1.text.contains("BP")])

	## --- Gender shows in its place, for both genders --------------------
	checks.append(["HeaderLine1 shows 'Gender: Female' for a female character", header_line1.text.contains("Gender: Female")])

	character.gender = "male"
	menu._rebuild_header()
	await tree.process_frame
	checks.append(["HeaderLine1 shows 'Gender: Male' after switching to a male character", header_line1.text.contains("Gender: Male")])
	checks.append(["Switching gender doesn't resurrect the old Group Coin text", not header_line1.text.contains("Group Coin")])

	## --- The coin figures are still visible elsewhere (Inventory tab) ---
	menu.tabs.current_tab = 2   ## Stats(0)/Equipment(1)/Inventory(2) — see the tab order set up in open()/_rebuild_all
	await tree.process_frame
	var inventory_box: Control = menu.get_node("%InventoryBox") if menu.has_node("%InventoryBox") else null
	if inventory_box != null:
		var found_coin_line := false
		for child in inventory_box.get_children():
			if child is Label and (child as Label).text.contains("7 GC") and (child as Label).text.contains("3 SS") and (child as Label).text.contains("11 BP"):
				found_coin_line = true
				break
		checks.append(["The party's coin total is still shown in full on the Inventory tab", found_coin_line])
	else:
		checks.append(["Could locate %InventoryBox to verify the coin total is still shown on the Inventory tab", false])

	menu.queue_free()
	await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Character Menu Header: Gender replaces Group Coin): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
