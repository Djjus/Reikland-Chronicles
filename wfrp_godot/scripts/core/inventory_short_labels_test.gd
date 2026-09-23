extends RefCounted
class_name InventoryShortLabelsTest
## Per the follow-up requests ("remove the [equipped xxx] label from the
## inventory tab item names. And rename Equip (Main) to Eqp (Main), and
## Equip (Off-hand) to Eqp (Off). And also rename Unequip (Main) to Unqp
## (Main), and Unequip (Off-hand) to Unqp (Off). follow the same logic
## for all other Equip/Unequip buttons in this tab, ie Eqp/Unqp" — then
## "give the same treatment to buttons across all equipment sub tabs
## too"): confirms the Inventory tab's own item names never carry an
## "[equipped ...]" tag any more, and that EVERY Equip/Unequip button
## across all four tabs that can show one (Inventory, and the
## Equipment tab's own Weapons/Armor/Containers sub-tabs) now uses the
## short Eqp/Unqp form — no tab left on the old long-form wording.

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

	character.equipped_weapon = "Sword"
	character.equipped_offhand = "Main Gauche"
	character.inventory.append("Sword")
	character.inventory.append("Main Gauche")
	character.inventory.append("Axe")   ## spare, unequipped -> real Eqp buttons

	character.equipped_armour.append("Leather Jerkin")
	character.inventory.append("Mail Shirt")   ## spare, unequipped armour

	character.inventory.append("Backpack")
	character.set_equipped_container("Back", "Backpack")
	character.inventory.append("Pouch")   ## spare, unequipped container

	var menu_scene: PackedScene = load("res://scenes/CharacterMenu.tscn")
	var menu: Node = menu_scene.instantiate()
	tree.get_root().add_child.call_deferred(menu)
	await tree.process_frame
	await tree.process_frame
	menu.open()
	await tree.process_frame

	## Recursive Label/Button text scrape -- same pattern
	## containers_test.gd's own scrape_all_text uses.
	var scrape_texts := func(root: Node) -> Array:
		var texts: Array = []
		var stack: Array = [root]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			if node is Label or node is Button:
				texts.append((node as Control).get("text"))
			for child in node.get_children():
				stack.append(child)
		return texts

	var inventory_box: VBoxContainer = menu.get_node("%InventoryBox")
	var inv_texts: Array = scrape_texts.call(inventory_box)
	var inv_joined := "\n".join(inv_texts)

	checks.append(["The Inventory tab's own item names never carry an '[equipped ...]' tag", not inv_joined.contains("equipped")])
	checks.append(["...Sword (equipped Main) still gets its own row (plain name, no tag)", inv_joined.contains("Sword")])
	checks.append(["...Main Gauche (equipped Off-hand) still gets its own row (plain name, no tag)", inv_joined.contains("Main Gauche")])
	checks.append(["...Backpack (equipped Back slot) still gets its own row (plain name, no tag)", inv_joined.contains("Backpack")])

	checks.append(["The Inventory tab's worn Sword offers a short 'Unqp (Main)' button", inv_texts.has("Unqp (Main)")])
	checks.append(["The Inventory tab's worn Main Gauche offers a short 'Unqp (Off)' button", inv_texts.has("Unqp (Off)")])
	checks.append(["The Inventory tab's worn Leather Jerkin offers a plain short 'Unqp' button", inv_texts.has("Unqp")])
	checks.append(["The Inventory tab's spare Axe offers short 'Eqp (Main)'/'Eqp (Off)' buttons", inv_texts.has("Eqp (Main)") and inv_texts.has("Eqp (Off)")])
	checks.append(["The Inventory tab's spare Mail Shirt offers a plain short 'Eqp' button", inv_texts.has("Eqp")])
	checks.append(["The Inventory tab's spare Pouch offers a short 'Eqp (Waist)' button", inv_texts.has("Eqp (Waist)")])

	## --- Per the follow-up request: the Equipment tab's own
	## Weapons/Armor/Containers sub-tabs now get the identical
	## treatment -- same short labels, same worn/spare setup reused so
	## every one of the same buttons shows up there too.
	var weapons_box: VBoxContainer = menu.get_node("%WeaponsBox")
	var weapons_texts: Array = scrape_texts.call(weapons_box)
	checks.append(["The Weapons sub-tab's worn Sword offers a short 'Unqp (Main)' button", weapons_texts.has("Unqp (Main)")])
	checks.append(["The Weapons sub-tab's worn Main Gauche offers a short 'Unqp (Off)' button", weapons_texts.has("Unqp (Off)")])
	checks.append(["The Weapons sub-tab's spare Axe offers short 'Eqp (Main)'/'Eqp (Off)' buttons", weapons_texts.has("Eqp (Main)") and weapons_texts.has("Eqp (Off)")])
	checks.append(["The Weapons sub-tab no longer shows the old long-form 'Unequip'/'Equip (Main)'/'Equip (Off-hand)' wording", not weapons_texts.has("Unequip") and not weapons_texts.has("Equip (Main)") and not weapons_texts.has("Equip (Off-hand)")])

	var armor_box: VBoxContainer = menu.get_node("%ArmorBox")
	var armor_texts: Array = scrape_texts.call(armor_box)
	checks.append(["The Armor sub-tab's worn Leather Jerkin offers a plain short 'Unqp' button", armor_texts.has("Unqp")])
	checks.append(["The Armor sub-tab's spare Mail Shirt offers a plain short 'Eqp' button", armor_texts.has("Eqp")])
	checks.append(["The Armor sub-tab no longer shows the old long-form 'Unequip'/'Equip' wording", not armor_texts.has("Unequip") and not armor_texts.has("Equip")])

	var container_box: VBoxContainer = menu.get_node("%ContainerBox")
	var container_texts: Array = scrape_texts.call(container_box)
	checks.append(["The Containers sub-tab's worn Backpack offers a plain short 'Unqp' button", container_texts.has("Unqp")])
	checks.append(["The Containers sub-tab's spare Pouch offers a short 'Eqp (Waist)' button", container_texts.has("Eqp (Waist)")])
	checks.append(["The Containers sub-tab no longer shows the old long-form 'Unequip'/'Equip (Waist)' wording", not container_texts.has("Unequip") and not container_texts.has("Equip (Waist)")])

	menu.queue_free()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Short Eqp/Unqp Labels Check, all 4 tabs): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
