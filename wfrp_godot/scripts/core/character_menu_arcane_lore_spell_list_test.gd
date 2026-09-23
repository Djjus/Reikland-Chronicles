extends RefCounted
class_name CharacterMenuArcaneLoreSpellListTest
## Real bug fix, per the report ("I'm not seeing Fire lore spells to
## learn them"): the Character menu's own "Learn an Arcane Spell
## (<Lore>)" dropdown (character_menu_screen.gd, _rebuild_spells_subtab)
## only ever pulled from GameData.spell_db.find_by_type("Arcane") --
## the generic, any-Lore spell pool -- and never included the 8
## signature spells belonging to the character's own Lore (spell_type
## == "Lore"), even though Advancement.purchase_arcane_spell has always
## been willing to sell them. A Fire Lore wizard could see and learn
## Bolt, Dome, etc. but never Crown of Flame, Purge, or any other Fire
## spell through this actual screen. Fixed by also including
## find_by_type("Lore") entries whose own `lore` field matches the
## character's -- this test proves the dropdown itself now offers them
## (not just that Advancement.purchase_arcane_spell accepts them, which
## core_rulebook_lore_spells_test.gd already covered).

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "Aes"
	pc.talents_taken["Arcane Magic (Fire)"] = 1
	pc.known_spells = ["Bolt"]
	pc.experience_total = 100000

	var menu = load("res://scenes/CharacterMenu.tscn").instantiate()
	tree.get_root().add_child(menu)
	for i in range(3):
		await tree.process_frame
	menu.open(0)
	## Spellbook is a separate top-level tab from whichever one opens by
	## default -- select it explicitly so _rebuild_spells_subtab's own
	## picker actually exists in the tree to inspect.
	if menu.spellbook_tabs != null:
		menu.spellbook_tabs.current_tab = 0
	for i in range(3):
		await tree.process_frame

	var picker: OptionButton = null
	for child in menu.spells_box.get_children():
		if child is HBoxContainer:
			for grandchild in child.get_children():
				if grandchild is OptionButton:
					picker = grandchild
	checks.append(["setup: found the 'Learn an Arcane Spell (Fire)' dropdown", picker != null])

	var offered: Array[String] = []
	if picker != null:
		for i in range(picker.item_count):
			offered.append(picker.get_item_text(i))

	## Per the later "grey out unimplemented spells" request, an offered
	## spell's own item text now carries a "(Not Yet Implemented)" suffix
	## when SpellDefinition.is_mechanically_implemented() is false (see
	## spell_learn_disabled_unimplemented_test.gd for that feature's own
	## dedicated coverage) — Purge and Dome are both still flavor-text
	## only, so checking for their bare names is checked via begins_with
	## rather than an exact match, to survive that suffix regardless of
	## whichever spells this project implements next.
	checks.append(["THE FIX: dropdown now offers a Fire Lore spell (Crown of Flame)", offered.has("Crown of Flame")])
	checks.append(["THE FIX: dropdown now offers another Fire Lore spell (Purge)", offered.any(func(t: String) -> bool: return t.begins_with("Purge"))])
	checks.append(["dropdown still offers a generic Arcane spell (Dome)", offered.any(func(t: String) -> bool: return t.begins_with("Dome"))])
	checks.append(["dropdown does NOT offer a different Lore's spell (Regenerate, Life)", not offered.any(func(t: String) -> bool: return t.begins_with("Regenerate"))])
	checks.append(["dropdown does NOT offer an already-known spell (Bolt)", not offered.any(func(t: String) -> bool: return t.begins_with("Bolt"))])

	menu.close()
	menu.queue_free()
	for i in range(3):
		await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Character Menu Arcane Lore Spell List): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
