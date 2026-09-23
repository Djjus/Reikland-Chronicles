extends RefCounted
class_name ParryPreferenceMenuTest
## Per the follow-up request ("allow user to select if they want to use
## parry for defensive weapons in the weapon submenu on equipped
## weapons, and make sure it remembers this choice when unequipping and
## reequipping the same weapon"): confirms the Character Menu's Weapons
## sub-tab offers a real "Use Melee (Parry)" checkbox for a currently-
## equipped, one-handed, genuinely Defensive weapon (Main Gauche); that
## toggling it writes to Character.parry_preference (keyed by weapon
## name, via wants_parry_skill()); that a non-eligible weapon (Sword —
## no Defensive Quality at all) offers no such row; and that the choice
## survives a real unequip + re-equip of the SAME weapon.
##
## Per the further follow-up request ("hide this option if the
## character has no training in Melee (Parry)"): also confirms the
## checkbox is genuinely absent for an otherwise-eligible weapon while
## the character has zero Advances in Melee (Parry) itself, and only
## appears once that training is actually purchased.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var character: Character = GameState.player_character
	character.inventory.clear()
	character.parry_preference.clear()
	character.equipped_weapon = "Sword"
	character.equipped_offhand = "Main Gauche"
	character.inventory.append("Sword")
	character.inventory.append("Main Gauche")

	var main_gauche: WeaponDefinition = GameData.weapon_db.find_by_name("Main Gauche")
	checks.append(["Test setup: found the real Main Gauche (one-handed, Defensive)", main_gauche != null and not main_gauche.is_two_handed and main_gauche.qualities.has("Defensive")])

	var menu_scene: PackedScene = load("res://scenes/CharacterMenu.tscn")
	var menu: Node = menu_scene.instantiate()
	tree.get_root().add_child.call_deferred(menu)
	await tree.process_frame
	await tree.process_frame
	menu.open()
	await tree.process_frame

	## Recursively finds every CheckBox under `root`, regardless of
	## nesting depth (matches inventory_grid_favourite_test.gd's own
	## _scrape_all_text pattern for the same reason — this menu nests
	## rows inside HBoxContainer wrappers).
	var find_checkboxes := func(root: Node) -> Array:
		var found: Array = []
		var stack: Array = [root]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			if node is CheckBox:
				found.append(node)
			for child in node.get_children():
				stack.append(child)
		return found

	var weapons_box: VBoxContainer = menu.get_node("%WeaponsBox")
	checks.append(["The Weapons sub-tab is present", weapons_box != null])

	## --- Untrained in Melee (Parry): the checkbox must not appear at all,
	## even though Main Gauche is otherwise fully eligible (equipped,
	## one-handed, genuinely Defensive).
	var checkboxes_untrained: Array = find_checkboxes.call(weapons_box)
	var parry_checkbox_untrained_found := false
	for cb in checkboxes_untrained:
		if (cb as CheckBox).text.contains("Main Gauche"):
			parry_checkbox_untrained_found = true
	checks.append(["No 'Use Melee (Parry)' checkbox is offered while untrained in Melee (Parry)", not parry_checkbox_untrained_found])

	## --- Grant Melee (Parry) training, then rebuild — only now should the
	## checkbox actually appear.
	var melee_skill: SkillDefinition = GameData.skill_db.find_by_name("Melee")
	checks.append(["Test setup: found the real Melee skill definition", melee_skill != null])
	if melee_skill != null:
		character.skill_advances[melee_skill.display_name("Parry")] = 1
	menu._rebuild_all()
	await tree.process_frame

	var checkboxes: Array = find_checkboxes.call(menu.get_node("%WeaponsBox"))
	var parry_checkbox: CheckBox = null
	for cb in checkboxes:
		if (cb as CheckBox).text.contains("Main Gauche"):
			parry_checkbox = cb
	checks.append(["A real 'Use Melee (Parry)' checkbox is offered for the equipped, one-handed, Defensive Main Gauche once trained in Melee (Parry)", parry_checkbox != null])
	checks.append(["It starts unchecked — no preference set yet, per wants_parry_skill()'s own false default", parry_checkbox != null and not parry_checkbox.button_pressed])

	## Sword (main hand) has no Defensive Quality at all — no row for it.
	var sword_parry_checkbox_found := false
	for cb in checkboxes:
		if (cb as CheckBox).text.contains("Sword"):
			sword_parry_checkbox_found = true
	checks.append(["A non-Defensive weapon (Sword) gets no Parry checkbox at all", not sword_parry_checkbox_found])

	## --- Toggling it writes through to Character.parry_preference -------
	if parry_checkbox != null:
		parry_checkbox.button_pressed = true
		parry_checkbox.toggled.emit(true)
	checks.append(["Toggling the checkbox on sets Character.parry_preference for this weapon", character.wants_parry_skill(main_gauche)])

	## --- Unequip, then re-equip the SAME weapon — the choice must still
	## be remembered (keyed by weapon name, not by which slot/whether
	## it's currently worn at all).
	character.equipped_offhand = ""
	menu._rebuild_all()
	await tree.process_frame
	checks.append(["Unequipping Main Gauche does not clear the remembered preference", character.wants_parry_skill(main_gauche)])

	character.equipped_offhand = "Main Gauche"
	menu._rebuild_all()
	await tree.process_frame
	var checkboxes_after: Array = find_checkboxes.call(menu.get_node("%WeaponsBox"))
	var parry_checkbox_after: CheckBox = null
	for cb in checkboxes_after:
		if (cb as CheckBox).text.contains("Main Gauche"):
			parry_checkbox_after = cb
	checks.append(["Re-equipping the same weapon re-renders the checkbox already checked", parry_checkbox_after != null and parry_checkbox_after.button_pressed])

	menu.queue_free()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Parry Preference Menu Check): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
