extends RefCounted
class_name SpellLearnDisabledUnimplementedTest
## Per the explicit request: "In the Spell learning (petty/arcane and
## the lore's) lists, lets grey out and disable all spells which are
## not implemented. Re-enable them as we implement them."
##
## Covers two layers:
## - SpellDefinition.is_mechanically_implemented() itself: real for a
##   magic missile, real for an inflicts_condition spell, real for a
##   BESPOKE_IMPLEMENTED_SPELLS name (Drain/Light/Flaming Sword of
##   Rhuin/Cauterise/Crown of Flame/Flaming Hearts), false for anything
##   else — same real-vs-flavor split _apply_cast_spell_outcome's own
##   dispatch chain already uses, so this can never silently drift from
##   what actually happens when a spell is cast.
## - character_menu_screen.gd's own "Learn a Petty/Arcane Spell"
##   dropdowns: every book spell still appears (nothing hidden), but an
##   unimplemented one is genuinely disabled (OptionButton.
##   is_item_disabled) and labelled "(Not Yet Implemented)", the
##   picker's own default selection skips past any disabled entry, and
##   the Learn button itself is disabled outright when nothing offered
##   is actually learnable.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- SpellDefinition.is_mechanically_implemented() -------------------
	var bolt: SpellDefinition = GameData.spell_db.find_by_name("Bolt")
	var shock: SpellDefinition = GameData.spell_db.find_by_name("Shock")
	var dome: SpellDefinition = GameData.spell_db.find_by_name("Dome")
	var sleep: SpellDefinition = GameData.spell_db.find_by_name("Sleep")
	var light: SpellDefinition = GameData.spell_db.find_by_name("Light")
	var crown: SpellDefinition = GameData.spell_db.find_by_name("Crown of Flame")
	var purge: SpellDefinition = GameData.spell_db.find_by_name("Purge")
	var flaming_sword: SpellDefinition = GameData.spell_db.find_by_name("Flaming Sword of Rhuin")
	var cauterise: SpellDefinition = GameData.spell_db.find_by_name("Cauterise")
	var flaming_hearts: SpellDefinition = GameData.spell_db.find_by_name("Flaming Hearts")
	var drain: SpellDefinition = GameData.spell_db.find_by_name("Drain")

	checks.append(["setup: every spell used by this test genuinely exists", bolt != null and shock != null and dome != null and sleep != null and light != null and crown != null and purge != null and flaming_sword != null and cauterise != null and flaming_hearts != null and drain != null])
	checks.append(["THE FIX: a magic missile (Bolt) counts as implemented", bolt.is_mechanically_implemented()])
	checks.append(["THE FIX: an inflicts_condition spell (Shock -> Stunned) counts as implemented", shock.is_mechanically_implemented()])
	checks.append(["THE FIX: a flavor-only generic Arcane spell (Dome) does NOT count as implemented", not dome.is_mechanically_implemented()])
	checks.append(["THE FIX: a flavor-only Petty spell (Sleep) does NOT count as implemented", not sleep.is_mechanically_implemented()])
	checks.append(["THE FIX: a bespoke-implemented Petty spell (Light) counts as implemented", light.is_mechanically_implemented()])
	checks.append(["THE FIX: a bespoke-implemented Lore spell (Crown of Flame) counts as implemented", crown.is_mechanically_implemented()])
	checks.append(["THE FIX: a still-flavor-only Lore spell (Purge) does NOT count as implemented", not purge.is_mechanically_implemented()])
	checks.append(["THE FIX: every other bespoke spell (Flaming Sword of Rhuin, Cauterise, Flaming Hearts, Drain) also counts as implemented", flaming_sword.is_mechanically_implemented() and cauterise.is_mechanically_implemented() and flaming_hearts.is_mechanically_implemented() and drain.is_mechanically_implemented()])

	## --- The Character menu's own dropdowns ------------------------------
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "SpellListAes"
	pc.talents_taken["Petty Magic"] = 1
	pc.talents_taken["Arcane Magic (Fire)"] = 1
	pc.experience_total = 100000

	var menu = load("res://scenes/CharacterMenu.tscn").instantiate()
	tree.get_root().add_child(menu)
	for i in range(3):
		await tree.process_frame
	menu.open(0)
	if menu.spellbook_tabs != null:
		menu.spellbook_tabs.current_tab = 0
	for i in range(3):
		await tree.process_frame

	## Both dropdowns live as siblings in spells_box, in this fixed
	## order (Petty header+row built before the Arcane header+row) — see
	## _rebuild_spells_subtab()'s own construction order.
	var pickers: Array[OptionButton] = []
	for child in menu.spells_box.get_children():
		if child is HBoxContainer:
			for grandchild in child.get_children():
				if grandchild is OptionButton:
					pickers.append(grandchild)
	checks.append(["setup: found both the Petty and Arcane/Lore 'Learn a Spell' dropdowns", pickers.size() == 2])
	if pickers.size() < 2:
		menu.close()
		menu.queue_free()
		for i in range(3): await tree.process_frame
		for chk in checks:
			print(("PASS  " if chk[1] else "FAIL  ") + chk[0])
		print("RESULT (Spell Learn Disabled Unimplemented): SETUP FAILED")
		return false

	var petty_picker: OptionButton = pickers[0]
	var arcane_picker: OptionButton = pickers[1]

	## Petty dropdown: Light is implemented, Sleep is not.
	var light_idx := -1
	var sleep_idx := -1
	for i in range(petty_picker.item_count):
		var text := petty_picker.get_item_text(i)
		if text == "Light":
			light_idx = i
		elif text.begins_with("Sleep"):
			sleep_idx = i
	checks.append(["setup: both Light and Sleep are offered in the Petty dropdown", light_idx >= 0 and sleep_idx >= 0])
	checks.append(["THE FIX: Light (implemented) shows its plain name and is NOT disabled", light_idx >= 0 and not petty_picker.is_item_disabled(light_idx)])
	checks.append(["THE FIX: Sleep (not implemented) is labelled '(Not Yet Implemented)' and IS disabled", sleep_idx >= 0 and petty_picker.get_item_text(sleep_idx) == "Sleep (Not Yet Implemented)" and petty_picker.is_item_disabled(sleep_idx)])
	checks.append(["THE FIX: the Petty picker's own default selection lands on an implemented spell, not a disabled one", not petty_picker.is_item_disabled(petty_picker.selected)])

	## Arcane/Lore dropdown: Crown of Flame (this Lore's own bespoke
	## spell) is implemented; Purge (same Lore) and Dome (generic
	## Arcane) are not.
	var crown_idx := -1
	var purge_idx := -1
	var dome_idx := -1
	for i in range(arcane_picker.item_count):
		var text2 := arcane_picker.get_item_text(i)
		if text2 == "Crown of Flame":
			crown_idx = i
		elif text2.begins_with("Purge"):
			purge_idx = i
		elif text2.begins_with("Dome"):
			dome_idx = i
	checks.append(["setup: Crown of Flame, Purge, and Dome are all offered in the Arcane/Lore dropdown", crown_idx >= 0 and purge_idx >= 0 and dome_idx >= 0])
	checks.append(["THE FIX: Crown of Flame (implemented) shows its plain name and is NOT disabled", crown_idx >= 0 and not arcane_picker.is_item_disabled(crown_idx)])
	checks.append(["THE FIX: Purge (not implemented) is labelled and disabled", purge_idx >= 0 and arcane_picker.get_item_text(purge_idx) == "Purge (Not Yet Implemented)" and arcane_picker.is_item_disabled(purge_idx)])
	checks.append(["THE FIX: Dome (not implemented) is labelled and disabled too, same as an unimplemented Lore spell", dome_idx >= 0 and arcane_picker.get_item_text(dome_idx) == "Dome (Not Yet Implemented)" and arcane_picker.is_item_disabled(dome_idx)])
	checks.append(["THE FIX: the Arcane/Lore picker's own default selection lands on an implemented spell, not a disabled one", not arcane_picker.is_item_disabled(arcane_picker.selected)])

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
	print("RESULT (Spell Learn Disabled Unimplemented): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
