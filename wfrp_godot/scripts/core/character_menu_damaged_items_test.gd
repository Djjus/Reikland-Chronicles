extends RefCounted
class_name CharacterMenuDamagedItemsTest
## Per the request ("Char menu inventory and equipment tabs should show
## damaged items, mark them red and reduce dmg/ap on the appropriate
## location"): confirms the Equipment tab's Weapons and Armor sub-tabs,
## and the Inventory tab's flat list, all genuinely reflect wear damage
## (Character.weapon_damage_taken) and per-location armour damage
## (Character.armour_damage) — reduced figures AND the red "needs
## attention" flag (Color(0.82, 0.35, 0.32)) — rather than just not
## crashing. Covers:
##  - A Worn Armour row at the SPECIFIC damaged location shows reduced
##    "effective/total" AP in red, on both the AP cell and the Name
##    cell, while undamaged locations of the SAME piece stay plain.
##  - An unworn, unequipped multi-location piece in "Equip From
##    Inventory" shows the WORST-damaged location's reduced AP in red,
##    with a tooltip breakdown of every damaged location.
##  - A fully undamaged piece shows full AP, no red, in "Equip From
##    Inventory".
##  - A wear-damaged weapon shows reduced Damage + red on both its Main
##    Hand row and its "Equip From Inventory" row (same weapon name,
##    two physical copies).
##  - An undamaged weapon shows full Damage, no red.
##  - The Inventory tab's flat list: a damaged weapon's name gets a
##    "[Dmg X/Y]" suffix + red; a damaged armour piece's name gets a
##    "[Location X/Y, ...]" suffix (only actually-damaged locations) +
##    red; undamaged items of both kinds get neither.

const DAMAGED_RED := Color(0.82, 0.35, 0.32)

## Recursively collects every Label's own text under `root`, order-
## preserving (pre-order DFS) — same idiom equipment_grids_test.gd uses,
## needed here too since Worn Armour / Equip From Inventory grids nest
## Labels inside PanelContainer cells.
static func _scrape_ordered(root: Node) -> Array:
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

## Direct-children-only grid finder, same as equipment_grids_test.gd's
## own find_grids — every Equipment sub-tab's grids sit straight on the
## tab's own VBoxContainer, never nested in a wrapper.
static func _find_grids(box: VBoxContainer) -> Array:
	var grids: Array = []
	for child in box.get_children():
		if child is GridContainer:
			grids.append(child)
	return grids

## Splits a GridContainer's flat child list into [header_row, row1, row2,
## ...], each an Array of `columns` cells (PanelContainer for item rows,
## MarginContainer for the header — see _boxed_cell/_header_cell in
## character_menu_screen.gd).
static func _grid_rows(grid: GridContainer, columns: int) -> Array:
	var all_children := grid.get_children()
	var rows: Array = []
	var i := 0
	while i + columns <= all_children.size():
		rows.append(all_children.slice(i, i + columns))
		i += columns
	return rows

## Returns the Label inside a boxed/margin cell (its own single child at
## index 0) — null if that cell doesn't directly hold a Label (e.g. the
## Actions cell, which holds an HBoxContainer of buttons instead).
static func _cell_label(cell: Node) -> Label:
	if cell.get_child_count() == 0:
		return null
	var inner: Node = cell.get_child(0)
	return inner as Label

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var character: Character = GameState.player_character
	character.inventory.clear()
	character.equipped_armour.clear()
	character.equipped_weapon = ""
	character.equipped_offhand = ""
	character.armour_damage.clear()
	character.broken_armour.clear()
	character.weapon_damage_taken.clear()

	## --- Weapons fixture --------------------------------------------------
	## Sword: equipped Main Hand, wear-damaged (1 point) — two physical
	## copies (one worn, one spare) so it shows up BOTH as the Main Hand
	## row and as an "Equip (Off-hand)" candidate in Equip From Inventory.
	character.equipped_weapon = "Sword"
	character.inventory.append("Sword")
	character.inventory.append("Sword")
	character.weapon_damage_taken["Sword"] = 1
	## Axe: a genuinely undamaged spare weapon, for the "no damage -> no
	## red" control case in Equip From Inventory.
	character.inventory.append("Axe")
	## Both Sword and Axe are skill_group "Basic" — train that
	## specialisation so the pre-existing "red if untrained" weapon-name
	## flag (see _rebuild_inventory's `elif not is_learned` branch,
	## unrelated to this damaged-items feature) never fires here. Without
	## this, the undamaged Axe's Inventory-tab row would still show red
	## for being untrained, which is a different, older feature than the
	## one under test and would make this a false failure.
	var melee_skill: SkillDefinition = GameData.skill_db.find_by_name("Melee")
	if melee_skill != null:
		character.skill_advances[melee_skill.display_name("Basic")] = 1

	## --- Armour fixture -----------------------------------------------------
	## Mail Coat (AP 2, Body/Left Arm/Right Arm): worn, damaged 1 point at
	## Left Arm ONLY — Body/Right Arm stay undamaged, so the Worn Armour
	## grid must show red/reduced at Left Arm but plain everywhere else
	## for this same piece.
	character.equipped_armour.append("Mail Coat")
	character.inventory.append("Mail Coat")
	character.armour_damage["Mail Coat"] = {"Left Arm": 1}
	## Bracers (AP 2, Left Arm/Right Arm): NOT worn, damaged differently at
	## each of its two locations (1 and 2) — exercises the "worst-damaged
	## location drives the headline AP" logic and a real multi-location
	## tooltip/suffix breakdown.
	character.inventory.append("Bracers")
	character.armour_damage["Bracers"] = {"Left Arm": 1, "Right Arm": 2}
	## Plate Breastplate (AP 2, Body only): NOT worn, genuinely undamaged —
	## the "no damage -> no red, full AP" control case in Equip From
	## Inventory.
	character.inventory.append("Plate Breastplate")

	var mail_coat_def: ArmourDefinition = GameData.armour_db.find_by_name("Mail Coat")
	var bracers_def: ArmourDefinition = GameData.armour_db.find_by_name("Bracers")
	var breastplate_def: ArmourDefinition = GameData.armour_db.find_by_name("Plate Breastplate")
	var sword_def: WeaponDefinition = GameData.weapon_db.find_by_name("Sword")
	var axe_def: WeaponDefinition = GameData.weapon_db.find_by_name("Axe")

	var menu_scene: PackedScene = load("res://scenes/CharacterMenu.tscn")
	var menu: Node = menu_scene.instantiate()
	tree.get_root().add_child.call_deferred(menu)
	await tree.process_frame
	await tree.process_frame
	menu.open()
	await tree.process_frame

	## === Equipment tab: Armor sub-tab =====================================
	var armor_box: VBoxContainer = menu.get_node("%ArmorBox")
	var armor_grids: Array = _find_grids(armor_box)
	checks.append(["Armor sub-tab has 2 grids (Worn Armour + Equip From Inventory)", armor_grids.size() == 2])

	if armor_grids.size() == 2:
		var worn_grid: GridContainer = armor_grids[0]
		var worn_rows: Array = _grid_rows(worn_grid, 5)
		## Columns: 0 Location, 1 Name, 2 AP, 3 Qualities, 4 Actions.
		var left_arm_row = null
		var body_row = null
		var right_arm_row = null
		for row in worn_rows:
			var loc_lbl: Label = _cell_label(row[0])
			var name_lbl: Label = _cell_label(row[1])
			if loc_lbl == null or name_lbl == null or name_lbl.text != "Mail Coat":
				continue
			if loc_lbl.text == "Left Arm":
				left_arm_row = row
			elif loc_lbl.text == "Body":
				body_row = row
			elif loc_lbl.text == "Right Arm":
				right_arm_row = row

		checks.append(["Worn Mail Coat appears under all 3 of its own locations (Body, Left Arm, Right Arm)",
			left_arm_row != null and body_row != null and right_arm_row != null])

		if left_arm_row != null:
			var la_ap_lbl: Label = _cell_label(left_arm_row[2])
			var la_name_lbl: Label = _cell_label(left_arm_row[1])
			var expected_left_arm_ap := "%d/%d" % [maxi(0, mail_coat_def.armour_points - 1), mail_coat_def.armour_points]
			checks.append(["Worn Mail Coat's damaged Left Arm AP cell shows the reduced effective/total figure (%s)" % expected_left_arm_ap,
				la_ap_lbl != null and la_ap_lbl.text == expected_left_arm_ap])
			checks.append(["Worn Mail Coat's damaged Left Arm AP cell is coloured red",
				la_ap_lbl != null and la_ap_lbl.has_theme_color_override("font_color") and la_ap_lbl.get_theme_color("font_color") == DAMAGED_RED])
			checks.append(["Worn Mail Coat's Name cell is ALSO coloured red at the damaged Left Arm row",
				la_name_lbl != null and la_name_lbl.has_theme_color_override("font_color") and la_name_lbl.get_theme_color("font_color") == DAMAGED_RED])

		if body_row != null:
			var body_ap_lbl: Label = _cell_label(body_row[2])
			var body_name_lbl: Label = _cell_label(body_row[1])
			checks.append(["Worn Mail Coat's UNdamaged Body AP cell shows the plain, undamaged AP figure (%d)" % mail_coat_def.armour_points,
				body_ap_lbl != null and body_ap_lbl.text == str(mail_coat_def.armour_points)])
			checks.append(["Worn Mail Coat's UNdamaged Body row is NOT coloured red",
				body_ap_lbl != null and not body_ap_lbl.has_theme_color_override("font_color")
				and body_name_lbl != null and not body_name_lbl.has_theme_color_override("font_color")])

		if right_arm_row != null:
			var ra_ap_lbl: Label = _cell_label(right_arm_row[2])
			checks.append(["Worn Mail Coat's UNdamaged Right Arm AP cell also shows the plain figure and no red",
				ra_ap_lbl != null and ra_ap_lbl.text == str(mail_coat_def.armour_points) and not ra_ap_lbl.has_theme_color_override("font_color")])

		## --- Equip From Inventory (Armor) ----------------------------------
		var inv_grid: GridContainer = armor_grids[1]
		var inv_rows: Array = _grid_rows(inv_grid, 5)
		var bracers_row = null
		var breastplate_row = null
		for row in inv_rows:
			var name_lbl2: Label = _cell_label(row[1])
			if name_lbl2 == null:
				continue
			if name_lbl2.text.begins_with("Bracers"):
				bracers_row = row
			elif name_lbl2.text.begins_with("Plate Breastplate"):
				breastplate_row = row

		checks.append(["The unequipped, damaged Bracers appear in Equip From Inventory", bracers_row != null])
		if bracers_row != null:
			var br_ap_lbl: Label = _cell_label(bracers_row[2])
			var br_name_lbl: Label = _cell_label(bracers_row[1])
			## Worst-damaged location is Right Arm (2 points off an AP-2
			## piece) -> effective AP 0.
			var expected_worst_ap := "%d/%d" % [maxi(0, bracers_def.armour_points - 2), bracers_def.armour_points]
			checks.append(["Unworn Bracers' AP cell shows the WORST-damaged location's reduced figure (%s)" % expected_worst_ap,
				br_ap_lbl != null and br_ap_lbl.text == expected_worst_ap])
			checks.append(["Unworn Bracers' AP cell is coloured red",
				br_ap_lbl != null and br_ap_lbl.has_theme_color_override("font_color") and br_ap_lbl.get_theme_color("font_color") == DAMAGED_RED])
			checks.append(["Unworn Bracers' Name cell is ALSO coloured red",
				br_name_lbl != null and br_name_lbl.has_theme_color_override("font_color") and br_name_lbl.get_theme_color("font_color") == DAMAGED_RED])
			checks.append(["Unworn Bracers' Name tooltip breaks down EVERY damaged location by name (Left Arm and Right Arm both listed)",
				br_name_lbl != null and br_name_lbl.tooltip_text.contains("Left Arm") and br_name_lbl.tooltip_text.contains("Right Arm")])

		checks.append(["The unequipped, UNdamaged Plate Breastplate appears in Equip From Inventory", breastplate_row != null])
		if breastplate_row != null:
			var bp_ap_lbl: Label = _cell_label(breastplate_row[2])
			var bp_name_lbl: Label = _cell_label(breastplate_row[1])
			checks.append(["Undamaged Plate Breastplate's AP cell shows the full, plain AP figure (%d)" % breastplate_def.armour_points,
				bp_ap_lbl != null and bp_ap_lbl.text == str(breastplate_def.armour_points)])
			checks.append(["Undamaged Plate Breastplate's row is NOT coloured red at all",
				bp_ap_lbl != null and not bp_ap_lbl.has_theme_color_override("font_color")
				and bp_name_lbl != null and not bp_name_lbl.has_theme_color_override("font_color")])

	## === Equipment tab: Weapons sub-tab ===================================
	var weapons_box: VBoxContainer = menu.get_node("%WeaponsBox")
	var weapon_grids: Array = _find_grids(weapons_box)
	checks.append(["Weapons sub-tab has 2 grids (Equipped Weapons + Equip From Inventory)", weapon_grids.size() == 2])

	if weapon_grids.size() == 2:
		var equipped_grid: GridContainer = weapon_grids[0]
		var equipped_rows: Array = _grid_rows(equipped_grid, 6)
		## Columns: 0 Slot, 1 Name, 2 Skill, 3 Damage, 4 Qualities, 5 Actions.
		var main_hand_row = null
		for row in equipped_rows:
			var slot_lbl: Label = _cell_label(row[0])
			if slot_lbl != null and slot_lbl.text == "Main Hand":
				main_hand_row = row
		checks.append(["Main Hand row is present in Equipped Weapons", main_hand_row != null])
		if main_hand_row != null:
			var mh_name_lbl: Label = _cell_label(main_hand_row[1])
			var mh_dmg_lbl: Label = _cell_label(main_hand_row[3])
			var expected_dmg := str(sword_def.get_weapon_damage(character))
			checks.append(["Main Hand Sword's Damage cell shows the real wear-reduced figure (get_weapon_damage, %s)" % expected_dmg,
				mh_dmg_lbl != null and mh_dmg_lbl.text == expected_dmg])
			checks.append(["Main Hand Sword's Damage cell is coloured red",
				mh_dmg_lbl != null and mh_dmg_lbl.has_theme_color_override("font_color") and mh_dmg_lbl.get_theme_color("font_color") == DAMAGED_RED])
			checks.append(["Main Hand Sword's Name cell is ALSO coloured red",
				mh_name_lbl != null and mh_name_lbl.has_theme_color_override("font_color") and mh_name_lbl.get_theme_color("font_color") == DAMAGED_RED])

		var inv_weapon_grid: GridContainer = weapon_grids[1]
		var inv_weapon_rows: Array = _grid_rows(inv_weapon_grid, 6)
		var spare_sword_row = null
		var axe_row = null
		for row in inv_weapon_rows:
			var name_lbl3: Label = _cell_label(row[1])
			if name_lbl3 == null:
				continue
			if name_lbl3.text.begins_with("Sword"):
				spare_sword_row = row
			elif name_lbl3.text.begins_with("Axe"):
				axe_row = row

		checks.append(["The spare, damaged Sword copy appears in Equip From Inventory (Weapons)", spare_sword_row != null])
		if spare_sword_row != null:
			var ss_dmg_lbl: Label = _cell_label(spare_sword_row[3])
			var ss_name_lbl: Label = _cell_label(spare_sword_row[1])
			var expected_dmg2 := str(sword_def.get_weapon_damage(character))
			checks.append(["Spare Sword's Equip From Inventory Damage cell also shows the wear-reduced figure (%s)" % expected_dmg2,
				ss_dmg_lbl != null and ss_dmg_lbl.text == expected_dmg2])
			checks.append(["Spare Sword's Equip From Inventory Damage cell is coloured red",
				ss_dmg_lbl != null and ss_dmg_lbl.has_theme_color_override("font_color") and ss_dmg_lbl.get_theme_color("font_color") == DAMAGED_RED])
			checks.append(["Spare Sword's Equip From Inventory Name cell is ALSO coloured red",
				ss_name_lbl != null and ss_name_lbl.has_theme_color_override("font_color") and ss_name_lbl.get_theme_color("font_color") == DAMAGED_RED])

		checks.append(["The undamaged Axe appears in Equip From Inventory (Weapons)", axe_row != null])
		if axe_row != null:
			var axe_dmg_lbl: Label = _cell_label(axe_row[3])
			var axe_name_lbl: Label = _cell_label(axe_row[1])
			var expected_axe_dmg := str(axe_def.get_weapon_damage(character))
			checks.append(["Undamaged Axe's Damage cell shows its full, un-reduced figure (%s)" % expected_axe_dmg,
				axe_dmg_lbl != null and axe_dmg_lbl.text == expected_axe_dmg])
			checks.append(["Undamaged Axe's row is NOT coloured red at all",
				axe_dmg_lbl != null and not axe_dmg_lbl.has_theme_color_override("font_color")
				and axe_name_lbl != null and not axe_name_lbl.has_theme_color_override("font_color")])

	## === Inventory tab: flat list =========================================
	var inventory_box: VBoxContainer = menu.get_node("%InventoryBox")
	var inv_flat_grid: GridContainer = null
	for child in inventory_box.get_children():
		if child is GridContainer:
			inv_flat_grid = child
	checks.append(["The Inventory tab's flat grid is present", inv_flat_grid != null])

	if inv_flat_grid != null:
		var flat_rows: Array = _grid_rows(inv_flat_grid, 5)
		## Columns: 0 Star, 1 Name, 2 Qty, 3 Enc, 4 Actions.
		var flat_sword_lbl: Label = null
		var flat_axe_lbl: Label = null
		var flat_bracers_lbl: Label = null
		var flat_breastplate_lbl: Label = null
		for row in flat_rows:
			var lbl: Label = _cell_label(row[1])
			if lbl == null:
				continue
			if lbl.text.begins_with("• Sword"):
				flat_sword_lbl = lbl
			elif lbl.text.begins_with("• Axe"):
				flat_axe_lbl = lbl
			elif lbl.text.begins_with("• Bracers"):
				flat_bracers_lbl = lbl
			elif lbl.text.begins_with("• Plate Breastplate"):
				flat_breastplate_lbl = lbl

		checks.append(["Inventory tab: the damaged Sword's row was found", flat_sword_lbl != null])
		if flat_sword_lbl != null:
			var expected_dmg3 := "%d/%d" % [sword_def.get_weapon_damage(character), sword_def.damage_flat]
			checks.append(["Inventory tab: the damaged Sword's name gets a '[Dmg %s]' suffix" % expected_dmg3,
				flat_sword_lbl.text.contains("[Dmg %s]" % expected_dmg3)])
			checks.append(["Inventory tab: the damaged Sword's name is coloured red",
				flat_sword_lbl.has_theme_color_override("font_color") and flat_sword_lbl.get_theme_color("font_color") == DAMAGED_RED])

		checks.append(["Inventory tab: the undamaged Axe's row was found", flat_axe_lbl != null])
		if flat_axe_lbl != null:
			checks.append(["Inventory tab: the undamaged Axe's name has NO '[Dmg' suffix", not flat_axe_lbl.text.contains("[Dmg")])
			checks.append(["Inventory tab: the undamaged Axe's name is NOT coloured red", not flat_axe_lbl.has_theme_color_override("font_color")])

		checks.append(["Inventory tab: the damaged Bracers' row was found", flat_bracers_lbl != null])
		if flat_bracers_lbl != null:
			checks.append(["Inventory tab: the damaged Bracers' name lists BOTH damaged locations (Left Arm and Right Arm) with reduced x/y figures",
				flat_bracers_lbl.text.contains("Left Arm 1/%d" % bracers_def.armour_points)
				and flat_bracers_lbl.text.contains("Right Arm 0/%d" % bracers_def.armour_points)])
			checks.append(["Inventory tab: the damaged Bracers' name is coloured red",
				flat_bracers_lbl.has_theme_color_override("font_color") and flat_bracers_lbl.get_theme_color("font_color") == DAMAGED_RED])

		checks.append(["Inventory tab: the undamaged Plate Breastplate's row was found", flat_breastplate_lbl != null])
		if flat_breastplate_lbl != null:
			checks.append(["Inventory tab: the undamaged Plate Breastplate's name has no location-damage suffix at all",
				not flat_breastplate_lbl.text.contains("[")])
			checks.append(["Inventory tab: the undamaged Plate Breastplate's name is NOT coloured red",
				not flat_breastplate_lbl.has_theme_color_override("font_color")])

	menu.queue_free()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Character Menu Damaged Items Check): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
