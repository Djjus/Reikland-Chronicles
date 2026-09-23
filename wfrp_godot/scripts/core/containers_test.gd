extends RefCounted
class_name ContainersTest
## Per the request ("lets implement packs and containers... make sure
## they are buyable in shops. Then add 3 new Container equip slots on
## characters, Back (Backpack), Waist(Pouch) and Shoulder(sling bag)...
## these containers when worn/equipped will add their Carries value
## minus their worn Enc value to the character's maximum Enc"):
## confirms the 4 new items (Backpack/Pouch/Saddlebags/Sling Bag) are
## real, correctly priced/statted ItemDefinitions; that they're
## genuinely buyable in the Shop; that equipping one into its own
## Character slot via the real Character Menu grants the right
## Carrying Capacity bonus and applies the Worn Items -1 discount to
## its own Enc (while a spare, unequipped second copy stays full
## price); that Saddlebags (no equip slot, per the request's own
## 3-slot scope) never offers an Equip action anywhere; and that the
## Shop's Equipped/Sell lists both correctly treat a worn container as
## "still needed" the same way a worn weapon/armour piece already is.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- Item data itself -----------------------------------------------
	var backpack: ItemDefinition = GameData.item_db.find_by_name("Backpack")
	var pouch: ItemDefinition = GameData.item_db.find_by_name("Pouch")
	var saddlebags: ItemDefinition = GameData.item_db.find_by_name("Saddlebags")
	var sling_bag: ItemDefinition = GameData.item_db.find_by_name("Sling Bag")
	## Per the correction ("saddlebags for 18ss, not 18gc... backpack
	## costs 4/10 (4ss 10bp)... Sling Bag costs 1/- (1ss)"): these three
	## had been mis-encoded as if their book "X/Y" shillings/pence prices
	## were GC/SS instead — fixed to their real book prices (Backpack
	## 4/10 = 58d, Sling Bag 1/- = 12d, Saddlebags 18/- = 216d).
	checks.append(["Backpack exists (Enc 2, Carries 4, Back slot, 58d)", backpack != null and backpack.encumbrance == 2 and backpack.container_capacity == 4 and backpack.container_slot == "Back" and backpack.price_pennies == 58])
	checks.append(["Pouch exists (Enc 0, Carries 1, Waist slot, 4d)", pouch != null and pouch.encumbrance == 0 and pouch.container_capacity == 1 and pouch.container_slot == "Waist" and pouch.price_pennies == 4])
	checks.append(["Sling Bag exists (Enc 1, Carries 2, Shoulder slot, 12d)", sling_bag != null and sling_bag.encumbrance == 1 and sling_bag.container_capacity == 2 and sling_bag.container_slot == "Shoulder" and sling_bag.price_pennies == 12])
	checks.append(["Saddlebags exists (Enc 4, Carries 8, NO equip slot, 216d) — per the request's 3-slot scope", saddlebags != null and saddlebags.encumbrance == 4 and saddlebags.container_capacity == 8 and saddlebags.container_slot == "" and saddlebags.price_pennies == 216])

	## --- Character setup --------------------------------------------------
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var character: Character = GameState.player_character
	character.inventory.clear()
	character.equipped_container_back = ""
	character.equipped_container_waist = ""
	character.equipped_container_shoulder = ""
	character.gold_crowns = 50
	character.silver_shillings = 0
	character.brass_pennies = 0

	var base_capacity: int = character.get_characteristic_bonus("strength") + character.get_characteristic_bonus("toughness")
	checks.append(["No containers worn -> no capacity bonus yet", character.get_carrying_capacity() == base_capacity])

	## --- Equip/unequip mechanics + capacity bonus math --------------------
	character.inventory.append("Backpack")
	character.set_equipped_container("Back", "Backpack")
	## Backpack: Carries 4, worn Enc = max(0, 2-1) = 1 -> bonus = 4-1 = 3.
	checks.append(["Wearing a Backpack grants +3 Carrying Capacity (Carries 4 minus worn Enc 1)", character.get_carrying_capacity() == base_capacity + 3])

	character.inventory.append("Pouch")
	character.set_equipped_container("Waist", "Pouch")
	## Pouch: Carries 1, worn Enc = max(0, 0-1) = 0 -> bonus = 1-0 = 1.
	checks.append(["...and a Pouch on top grants +1 more (total +4)", character.get_carrying_capacity() == base_capacity + 4])

	character.inventory.append("Sling Bag")
	character.set_equipped_container("Shoulder", "Sling Bag")
	## Sling Bag: Carries 2, worn Enc = max(0, 1-1) = 0 -> bonus = 2-0 = 2.
	checks.append(["...and a Sling Bag on top grants +2 more (total +6)", character.get_carrying_capacity() == base_capacity + 6])

	## --- Encumbrance: worn discount vs. a spare unequipped copy -----------
	## A second, unequipped Backpack should count at its FULL Enc (2),
	## while the worn one still only counts at its discounted Enc (1) —
	## total contribution from "Backpack" entries: 1 (worn) + 2 (spare) = 3.
	character.inventory.append("Backpack")   ## a spare, unequipped second copy
	var enc_before_spare_check := character.get_current_encumbrance()
	character.inventory.erase("Backpack")   ## remove the spare again for the next checks
	character.inventory.erase("Backpack")   ## (erase() only removes one at a time -- put the worn one back)
	character.inventory.append("Backpack")
	var enc_without_spare := character.get_current_encumbrance()
	checks.append(["A spare, unequipped second Backpack adds its own FULL Enc (2), not the discounted worn value", is_equal_approx(enc_before_spare_check - enc_without_spare, 2.0)])

	var breakdown: Dictionary = character.get_encumbrance_breakdown()
	checks.append(["The Encumbrance breakdown has a real 'Containers' category once something is worn", breakdown.has("Containers") and breakdown["Containers"] > 0])

	## --- Real Character Menu: Inventory tab equip/unequip ------------------
	## Per the follow-up request ("remove the [equipped xxx] label from the
	## inventory tab item names"): the Inventory tab's own item name no
	## longer carries an "[equipped ...]" tag at all — worn state is only
	## shown via which action buttons a row offers (Unqp vs Eqp), so this
	## just confirms the plain name and the short "Unqp" button are both
	## present for the worn Backpack, and that the old tag text is
	## genuinely gone.
	var menu_scene: PackedScene = load("res://scenes/CharacterMenu.tscn")
	var menu: Node = menu_scene.instantiate()
	tree.get_root().add_child.call_deferred(menu)
	await tree.process_frame
	await tree.process_frame
	menu.open()
	await tree.process_frame

	var find_grid := func() -> GridContainer:
		var inventory_box: VBoxContainer = menu.get_node("%InventoryBox")
		for child in inventory_box.get_children():
			if child is GridContainer:
				return child
		return null
	var grid: GridContainer = find_grid.call()
	var found_backpack_row := false
	var found_backpack_tag := false
	if grid != null:
		var all_children := grid.get_children()
		var i := 5
		while i + 5 <= all_children.size():
			var cells: Array = all_children.slice(i, i + 5)
			var name_panel: PanelContainer = cells[1]
			var name_lbl: Label = name_panel.get_child(0)
			if name_lbl.text.begins_with("• Backpack"):
				found_backpack_row = true
				if name_lbl.text.contains("equipped"):
					found_backpack_tag = true
			i += 5
	checks.append(["The worn Backpack still gets a real Inventory row", found_backpack_row])
	checks.append(["...but its item name no longer carries an [equipped ...] tag", not found_backpack_tag])

	## --- Equipment tab: Containers sub-tab ---------------------------------
	## Per the follow-up request ("apply a similar grid format to
	## [Weapons/Armor/Containers]"): the sub-tab's rows now live inside a
	## boxed GridContainer (Label cells nested inside PanelContainer
	## wrappers) rather than flat HBoxContainer rows, so this scrapes
	## recursively for every Label under container_box regardless of
	## nesting depth — same pattern parry_preference_menu_test.gd's own
	## find_checkboxes and inventory_grid_favourite_test.gd's own
	## _scrape_all_text already use for the identical reason.
	var container_box: VBoxContainer = menu.get_node("%ContainerBox")
	var scrape_all_text := func(root: Node) -> String:
		var text := ""
		var stack: Array = [root]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			if node is Label:
				text += (node as Label).text + "\n"
			for child in node.get_children():
				stack.append(child)
		return text
	var container_box_text: String = scrape_all_text.call(container_box)
	checks.append(["The Equipment tab's Containers sub-tab lists all 3 worn slots", container_box_text.contains("Back") and container_box_text.contains("Pouch") and container_box_text.contains("Sling Bag")])

	## Saddlebags: buyable/carryable, but genuinely no Equip action
	## anywhere (no container_slot) — add one and confirm the Containers
	## sub-tab's "Equip From Inventory" section never lists it.
	character.inventory.append("Saddlebags")
	menu._rebuild_all()
	await tree.process_frame
	var container_box_text2: String = scrape_all_text.call(container_box)
	checks.append(["Saddlebags never appears in the Containers sub-tab's Equip-From-Inventory list (no slot of its own)", not container_box_text2.contains("Saddlebags")])

	## --- Unequip via the Inventory tab's own button ------------------------
	## Per the follow-up request ("rename Unequip to Unqp... follow the
	## same logic for all other Equip/Unequip buttons in this tab"): the
	## Inventory tab's own container Unequip button now reads "Unqp".
	var grid2: GridContainer = find_grid.call()
	var unequip_btn: Button = null
	if grid2 != null:
		var all_children2 := grid2.get_children()
		var j := 5
		while j + 5 <= all_children2.size():
			var cells2: Array = all_children2.slice(j, j + 5)
			var name_panel2: PanelContainer = cells2[1]
			var name_lbl2: Label = name_panel2.get_child(0)
			if name_lbl2.text.begins_with("• Backpack"):
				var actions_panel: PanelContainer = cells2[4]
				var actions_row: HBoxContainer = actions_panel.get_child(0)
				for btn in actions_row.get_children():
					if btn is Button and btn.text == "Unqp":
						unequip_btn = btn
			j += 5
	checks.append(["Found the worn Backpack's Unqp button in the Inventory tab", unequip_btn != null])
	if unequip_btn != null:
		unequip_btn.pressed.emit()
		await tree.process_frame
	checks.append(["Clicking Unequip genuinely clears the Back slot", character.equipped_container_back == ""])
	checks.append(["...and Carrying Capacity drops back down accordingly", character.get_carrying_capacity() == base_capacity + 1 + 2])   ## Pouch (+1) + Sling Bag (+2) still worn

	## --- Dropping the last copy of a worn container auto-unequips it ------
	character.set_equipped_container("Waist", "Pouch")
	menu.character = character
	menu._on_drop_item("Pouch")
	await tree.process_frame
	checks.append(["Dropping the last copy of a worn Pouch auto-unequips it (Character.equipped_container_waist clears)", character.equipped_container_waist == ""])

	## --- Shop: buyable, Equipped list, sell-list "still needed" check -----
	GameState.pending_encounter_monster_names = []
	var shop_scene: PackedScene = load("res://scenes/Shop.tscn")
	var shop: Node = shop_scene.instantiate()
	tree.get_root().add_child.call_deferred(shop)
	await tree.process_frame
	await tree.process_frame

	var item_stock_names: Array[String] = []
	for it in shop.item_stock:
		item_stock_names.append(it.item_name)
	checks.append(["Backpack/Pouch/Saddlebags/Sling Bag are all genuinely stocked for sale (Common availability)",
		item_stock_names.has("Backpack") and item_stock_names.has("Pouch") and item_stock_names.has("Saddlebags") and item_stock_names.has("Sling Bag")])

	var gc_before: int = character.gold_crowns
	shop._on_buy_item(backpack)
	await tree.process_frame
	checks.append(["Buying a Backpack from the Shop genuinely spends coin and adds it to inventory", character.gold_crowns < gc_before and character.inventory.has("Backpack")])

	## Equip the freshly-bought Sling Bag (still worn from earlier) and
	## Backpack, then confirm the Shop's own Equipped list shows them and
	## can unequip them too.
	character.set_equipped_container("Back", "Backpack")
	shop._rebuild_all()
	await tree.process_frame
	var equipped_list: VBoxContainer = shop.get_node("%EquippedList")
	var equipped_text := ""
	for child in equipped_list.get_children():
		if child is HBoxContainer:
			for c2 in child.get_children():
				if c2 is Label:
					equipped_text += c2.text + "\n"
	checks.append(["The Shop's own Equipped list shows the worn Back-slot Backpack", equipped_text.contains("Back") and equipped_text.contains("Backpack")])

	## Spare/worn distinction in the sell list: 2 Backpacks owned (1
	## worn), only 1 should be sellable.
	var spare: int = shop._get_spare_sellable_count(character, "Backpack", character.inventory.count("Backpack"))
	checks.append(["With 1 worn Backpack out of however many carried, exactly that many fewer are sellable", spare == character.inventory.count("Backpack") - 1])

	shop._on_unequip_container("Back")
	await tree.process_frame
	checks.append(["Shop's own Unequip action genuinely clears the Back slot", character.equipped_container_back == ""])

	menu.queue_free()
	shop.queue_free()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Packs & Containers Check): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
