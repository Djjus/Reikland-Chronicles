extends RefCounted
class_name EquipmentGridsTest
## Per the request ("Lets move to the Equipment sub tabs and apply a
## similar grid format to those too. Re-order the grouping in Worn
## Armor section from Light/Medium/Heavy, to Head/Body/Left Arm/Right
## Arm/Left Leg/Right Leg. And add a column for qualities and flaws for
## Armor and Weapons in these sub tabs"), plus the two follow-up
## answers ("Include Containers" in scope, and "remove grouping from
## the Equip from Inventory section, just list [Armor] alphabetically"):
## confirms all three Equipment sub-tabs (Weapons/Armor/Containers) now
## render via the same boxed GridContainer convention the Inventory/
## Characteristics/Skills grids already use, with the right column
## counts; that Weapons and Armor both carry a real "Qualities and
## Flaws" column with real data in it; that a multi-location Armour
## piece (Leather Jack — Body, Left Arm, Right Arm) appears under
## EVERY location section it covers, in _ARMOUR_LOCATION_ORDER's own
## order, rather than under a single Light/Medium/Heavy tier; and that
## Armor's own "Equip From Inventory" list is genuinely alphabetical
## (not grouped at all) even when added to inventory out of order.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var character: Character = GameState.player_character
	character.inventory.clear()
	character.equipped_armour.clear()
	character.equipped_container_back = ""
	character.equipped_container_waist = ""
	character.equipped_container_shoulder = ""

	## --- Weapons: a Main Hand (Sword, no qualities), an Off-Hand (Main
	## Gauche, "Defensive"), and a spare unequipped weapon with real
	## Qualities/Flaws of its own (Axe -- "Hack, Unbalanced") so the
	## Equip From Inventory grid has a real row to check too.
	character.equipped_weapon = "Sword"
	character.equipped_offhand = "Main Gauche"
	character.inventory.append("Sword")
	character.inventory.append("Main Gauche")
	character.inventory.append("Axe")

	## --- Armour: Leather Jack (Body/Left Arm/Right Arm) worn, so the
	## Worn Armour section must show it under all three of those
	## location groups. Three more, genuinely un-equipped, added
	## deliberately OUT of alphabetical order (Open Helm, then Mail
	## Coif, then Boiled Leather Breastplate) so a real alphabetical
	## sort is actually being exercised, not just accidentally matching
	## insertion order.
	character.equipped_armour.append("Leather Jack")
	character.inventory.append("Open Helm")
	character.inventory.append("Mail Coif")
	character.inventory.append("Boiled Leather Breastplate")

	## --- Containers: a worn Backpack (Back) plus a spare, unequipped
	## Pouch (Waist) so both the Worn and Equip From Inventory grids
	## have a real row each.
	character.inventory.append("Backpack")
	character.set_equipped_container("Back", "Backpack")
	character.inventory.append("Pouch")

	var menu_scene: PackedScene = load("res://scenes/CharacterMenu.tscn")
	var menu: Node = menu_scene.instantiate()
	tree.get_root().add_child.call_deferred(menu)
	await tree.process_frame
	await tree.process_frame
	menu.open()
	await tree.process_frame

	## Direct-children-only grid finder: every Equipment sub-tab's own
	## grids are added straight onto the tab's own VBoxContainer (never
	## nested inside a wrapper), same as the Inventory tab's own single
	## grid, so this doesn't need to recurse.
	var find_grids := func(box: VBoxContainer) -> Array:
		var grids: Array = []
		for child in box.get_children():
			if child is GridContainer:
				grids.append(child)
		return grids

	## Order-preserving Label-text scrape (proper pre-order DFS, unlike
	## a naive stack-pop which would reverse sibling order) -- lets
	## tests assert on relative ordering (e.g. "Body" before "Left Arm"
	## before "Right Arm", matching _ARMOUR_LOCATION_ORDER) as well as
	## plain containment.
	var scrape_ordered := func(root: Node) -> Array:
		var texts: Array = []
		var stack: Array = [root]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			if node is Label:
				texts.append((node as Label).text)
			var children := node.get_children()
			for i in range(children.size() - 1, -1, -1):
				stack.append(children[i])
		return texts

	## --- Weapons sub-tab --------------------------------------------------
	var weapons_box: VBoxContainer = menu.get_node("%WeaponsBox")
	var weapon_grids: Array = find_grids.call(weapons_box)
	checks.append(["Weapons sub-tab has 2 grids (Equipped Weapons + Equip From Inventory)", weapon_grids.size() == 2])
	if weapon_grids.size() == 2:
		checks.append(["Equipped Weapons grid has 6 columns (Slot/Name/Skill/Damage/Qualities and Flaws/Actions)", weapon_grids[0].columns == 6])
		checks.append(["Equip From Inventory (Weapons) grid also has 6 columns", weapon_grids[1].columns == 6])

	var weapons_text: Array = scrape_ordered.call(weapons_box)
	var weapons_text_joined := "\n".join(weapons_text)
	checks.append(["Main Hand row shows 'Main Hand'", weapons_text_joined.contains("Main Hand")])
	checks.append(["Off-Hand row shows 'Off-Hand'", weapons_text_joined.contains("Off-Hand")])
	checks.append(["The equipped Main Gauche's Qualities and Flaws column shows 'Defensive'", weapons_text_joined.contains("Defensive")])
	checks.append(["The unequipped Axe's Qualities and Flaws column shows 'Hack, Unbalanced'", weapons_text_joined.contains("Hack, Unbalanced")])
	var sword_def: WeaponDefinition = GameData.weapon_db.find_by_name("Sword")
	checks.append(["The Main Hand row shows the real computed Damage value (get_weapon_damage, not the old static SB+N text)", weapons_text_joined.contains(str(sword_def.get_weapon_damage(character)))])

	## --- Armor sub-tab ------------------------------------------------------
	var armor_box: VBoxContainer = menu.get_node("%ArmorBox")
	var armor_grids: Array = find_grids.call(armor_box)
	checks.append(["Armor sub-tab has 2 grids (Worn Armour + Equip From Inventory)", armor_grids.size() == 2])
	if armor_grids.size() == 2:
		checks.append(["Worn Armour grid has 5 columns (Name/Locations/AP/Qualities and Flaws/Actions)", armor_grids[0].columns == 5])
		checks.append(["Equip From Inventory (Armor) grid also has 5 columns", armor_grids[1].columns == 5])

		## Per the follow-up request ("remove the column header from
		## inside the location groups and put a single header at the
		## top, between Worn Armor and Head"): exactly ONE "Name"
		## column-header cell in the whole Worn Armour grid, not one
		## repeated per location section (Leather Jack's own 3 sections
		## would have meant 3 before this fix).
		var worn_grid_texts: Array = scrape_ordered.call(armor_grids[0])
		var name_header_count := 0
		for t in worn_grid_texts:
			if t == "Name":
				name_header_count += 1
		checks.append(["The Worn Armour grid shows exactly ONE shared column-header row, not one per location section", name_header_count == 1])

	var armor_text: Array = scrape_ordered.call(armor_box)
	var armor_text_joined := "\n".join(armor_text)
	var jack_count := 0
	for t in armor_text:
		if t == "Leather Jack":
			jack_count += 1
	checks.append(["The multi-location Leather Jack (Body/Left Arm/Right Arm) appears under all 3 of its own location groups, not just one", jack_count == 3])
	var idx_body: int = armor_text.find("Body")
	var idx_left_arm: int = armor_text.find("Left Arm")
	var idx_right_arm: int = armor_text.find("Right Arm")
	checks.append(["Worn Armour's location section headers appear, and in _ARMOUR_LOCATION_ORDER's own order (Body, then Left Arm, then Right Arm)",
		idx_body >= 0 and idx_left_arm >= 0 and idx_right_arm >= 0 and idx_body < idx_left_arm and idx_left_arm < idx_right_arm])
	## Note: "Head" legitimately appears later in the array too, as the
	## plain Locations-column text for the unworn Open Helm/Mail Coif
	## candidates further down in Equip From Inventory -- so this only
	## checks for a stray "Head" SECTION HEADER before that section
	## starts, not for the substring's mere presence anywhere at all.
	var idx_inventory_header: int = armor_text.find("Equip From Inventory")
	var head_section_before_inventory := false
	for i in range(idx_inventory_header):
		if armor_text[i] == "Head":
			head_section_before_inventory = true
	checks.append(["No 'Head' section header appears in Worn Armour (nothing worn there)", not head_section_before_inventory])
	checks.append(["A real armour piece's Qualities and Flaws column shows real data ('Weakpoints' for the unequipped Boiled Leather Breastplate)", armor_text_joined.contains("Weakpoints")])

	## Per the follow-up request: alphabetical, not grouped at all --
	## Boiled Leather Breastplate / Mail Coif / Open Helm were added to
	## inventory in the OPPOSITE order, so this only passes if a real
	## sort is happening.
	var idx_breastplate: int = armor_text.find("Boiled Leather Breastplate")
	var idx_coif: int = armor_text.find("Mail Coif")
	var idx_helm: int = armor_text.find("Open Helm")
	checks.append(["Armor's Equip From Inventory list is genuinely alphabetical (Boiled Leather Breastplate, then Mail Coif, then Open Helm) despite being added to inventory in reverse order",
		idx_breastplate >= 0 and idx_coif >= 0 and idx_helm >= 0 and idx_breastplate < idx_coif and idx_coif < idx_helm])

	## --- Containers sub-tab ---------------------------------------------
	var container_box: VBoxContainer = menu.get_node("%ContainerBox")
	var container_grids: Array = find_grids.call(container_box)
	checks.append(["Containers sub-tab has 2 grids (Worn Containers + Equip From Inventory)", container_grids.size() == 2])
	if container_grids.size() == 2:
		checks.append(["Worn Containers grid has 4 columns (Slot/Name/Capacity/Actions)", container_grids[0].columns == 4])
		checks.append(["Equip From Inventory (Containers) grid also has 4 columns", container_grids[1].columns == 4])

	var container_text: Array = scrape_ordered.call(container_box)
	var container_text_joined := "\n".join(container_text)
	checks.append(["The worn Backpack's row shows its own Back slot and its real capacity bonus (+3 Enc)", container_text_joined.contains("Back") and container_text_joined.contains("+3 Enc")])
	checks.append(["The spare, unequipped Pouch's row shows its own Waist slot", container_text_joined.contains("Waist") and container_text_joined.contains("Pouch")])

	menu.queue_free()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Equipment Grids Check): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
