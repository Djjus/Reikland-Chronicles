extends RefCounted
class_name InventoryGridFavouriteTest
## Per the follow-up request ("First add the current character's
## Encumbrance x/x where indicated... then add a favourite system to
## items in the inventory... add a grid layout to the list and clearly
## list Item name (add skill type for Weapons and colour red if
## unlearned), quantity and Enc values in neat columns with header
## titles above columns, and surround each item line and its buttons
## in a faint box"): confirms the persistent header shows a live,
## coloured Enc x/x; the Carried Items list has a real header row
## (Item/Qty/Enc/Actions) plus one boxed row per item; a weapon's row
## shows its skill group and turns red when genuinely untrained; and
## the star toggle flips Character.favourite_items.
##
## Per the follow-up request ("show favourited items in all shop
## screens, and allow staring/unstaring from that screen"): also
## confirms the Shop's own Party Inventory/sell list now shows a
## favourited item too (rather than hiding it), with no Sell button
## while it's favourited, and that its own Star column can toggle
## Character.favourite_items directly (both un-favouriting and
## favouriting).
##
## Per the further follow-up request ("dont double show equipped items
## in the shop, show those only in the Equipped gear section"): also
## confirms the character's own fully-equipped Sword (no spare copy at
## all) no longer gets a row in the Sell list — it's shown only in the
## Shop's separate Equipped Gear list instead, avoiding the duplicate.

## Recursively collects every Label/Button's own text under `root`, any
## number of levels deep — needed now that the Shop's Sell/Equipped
## lists nest Labels/Buttons inside PanelContainer/GridContainer/
## HBoxContainer wrappers (the boxed-grid row style) rather than sitting
## as flat, one-level-deep HBoxContainer rows.
static func _scrape_all_text(root: Node) -> String:
	var out := ""
	for child in root.get_children():
		if child is Label or child is Button:
			out += child.text + "\n"
		out += _scrape_all_text(child)
	return out

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var character: Character = GameState.player_character
	character.inventory.clear()
	character.favourite_items.clear()
	character.equipped_armour.clear()

	## A trained weapon (Sword — Basic), an untrained one (Halberd —
	## Polearm, never bought), and a plain Trapping, so the grid
	## exercises every code path in one pass.
	character.inventory.append("Sword")
	character.inventory.append("Halberd")
	character.inventory.append("Bedroll")
	character.inventory.append("Bedroll")
	## "Cloak" has no matching ItemDefinition/WeaponDefinition/
	## ArmourDefinition at all (see class_trappings_table.gd's starting
	## kit lists) — exactly the "starting trappings" case the follow-up
	## request ("make it so any item is sellable, even starting
	## trappings") is about.
	character.inventory.append("Cloak")
	character.equipped_weapon = "Sword"

	var melee_skill: SkillDefinition = GameData.skill_db.find_by_name("Melee")
	Advancement.purchase_skill_advance(character, melee_skill, "Basic")

	var menu_scene: PackedScene = load("res://scenes/CharacterMenu.tscn")
	var menu: Node = menu_scene.instantiate()
	tree.get_root().add_child.call_deferred(menu)
	await tree.process_frame
	await tree.process_frame
	menu.open()
	await tree.process_frame

	## --- Header Enc ---------------------------------------------------
	## Per the follow-up request ("move enc to the top row"): the Enc
	## reading now lives on HeaderLine1 (name/XP row), not HeaderLine2.
	var header_line1: RichTextLabel = menu.get_node("%HeaderLine1")
	checks.append(["The persistent header shows a real Enc x/x reading", header_line1.text.contains("Enc:")])
	var expected_capacity := character.get_carrying_capacity()
	## Per the follow-up request ("change all 'x / x' values, remove the
	## spaces, i.e. 'x/x'"): Enc now reads as a tight "x/x" ratio, no
	## space before the slash.
	checks.append(["The header's Enc reading includes the real carrying capacity", header_line1.text.contains("/%d" % expected_capacity)])

	## --- Grid header row + boxed rows -----------------------------------
	## The Carried Items grid: a single GridContainer, 5 columns (Star/
	## Item/Qty/Enc/Actions), header cells first (unboxed Labels), then
	## one boxed PanelContainer cell per item per column.
	var find_grid := func() -> GridContainer:
		var inventory_box: VBoxContainer = menu.get_node("%InventoryBox")
		for child in inventory_box.get_children():
			if child is GridContainer:
				return child
		return null
	var grid: GridContainer = find_grid.call()
	checks.append(["The Carried Items grid is present", grid != null and grid.columns == 5])

	var header_cells: Array = []
	var item_rows: Array = []   ## Array of [star_panel, name_panel, qty_panel, enc_panel, actions_panel]
	if grid != null:
		var all_children := grid.get_children()
		header_cells = all_children.slice(0, 5)
		var i := 5
		while i + 5 <= all_children.size():
			item_rows.append(all_children.slice(i, i + 5))
			i += 5
	var header_texts: Array[String] = []
	for cell in header_cells:
		var lbl: Label = cell.get_child(0)
		header_texts.append(lbl.text)
	checks.append(["Header row reads Item / Qty / Enc / Actions (plus a blank star column)",
		header_texts == ["", "Item", "Qty", "Enc", "Actions"]])
	checks.append(["Each item gets its own boxed row of 5 cells — 4 distinct items -> 4 rows", item_rows.size() == 4])

	## --- Weapon skill-group label + red-if-unlearned -------------------
	var sword_row_label: Label = null
	var halberd_row_label: Label = null
	for cells in item_rows:
		var name_panel: PanelContainer = cells[1]
		var name_lbl: Label = name_panel.get_child(0)
		if name_lbl.text.begins_with("• Sword"):
			sword_row_label = name_lbl
		elif name_lbl.text.begins_with("• Halberd"):
			halberd_row_label = name_lbl
	checks.append(["Sword's row names its skill group (Basic)", sword_row_label != null and sword_row_label.text.contains("(Basic)")])
	checks.append(["A trained weapon's name is NOT coloured red", sword_row_label != null and not sword_row_label.has_theme_color_override("font_color")])
	checks.append(["Halberd's row names its skill group (Polearm)", halberd_row_label != null and halberd_row_label.text.contains("(Polearm)")])
	checks.append(["An untrained weapon's name IS coloured red", halberd_row_label != null and halberd_row_label.has_theme_color_override("font_color") and halberd_row_label.get_theme_color("font_color") == Color(0.85, 0.35, 0.3)])

	## --- Favourite star toggle ------------------------------------------
	var halberd_star_btn: Button = null
	for cells in item_rows:
		var name_panel2: PanelContainer = cells[1]
		var name_lbl2: Label = name_panel2.get_child(0)
		if name_lbl2.text.begins_with("• Halberd"):
			var star_panel: PanelContainer = cells[0]
			halberd_star_btn = star_panel.get_child(0)
	checks.append(["Halberd's star button starts unfavourited (☆)", halberd_star_btn != null and halberd_star_btn.text == "☆"])
	if halberd_star_btn != null:
		halberd_star_btn.pressed.emit()
		await tree.process_frame
	checks.append(["Clicking the star adds the item to Character.favourite_items", character.favourite_items.has("Halberd")])

	## Re-find the rebuilt grid/button (menu rebuilds the whole list on toggle).
	var grid2: GridContainer = find_grid.call()
	var halberd_star_btn2: Button = null
	if grid2 != null:
		var all_children2 := grid2.get_children()
		var j := 5
		while j + 5 <= all_children2.size():
			var cells2 := all_children2.slice(j, j + 5)
			var name_panel3: PanelContainer = cells2[1]
			var name_lbl3: Label = name_panel3.get_child(0)
			if name_lbl3.text.begins_with("• Halberd"):
				var star_panel2: PanelContainer = cells2[0]
				halberd_star_btn2 = star_panel2.get_child(0)
			j += 5
	checks.append(["The star re-renders filled (★) once favourited", halberd_star_btn2 != null and halberd_star_btn2.text == "★"])

	## --- Shop's sell list shows the favourited item too, with staring/
	## unstaring available directly from the Shop's own Star column ------
	var shop_scene: PackedScene = load("res://scenes/Shop.tscn")
	var shop: Node = shop_scene.instantiate()
	tree.get_root().add_child.call_deferred(shop)
	await tree.process_frame
	await tree.process_frame
	## Shop's own _ready() already sets character = GameState.player_character
	## and calls _rebuild_all() — same character this test has been using.

	## Per the follow-up request ("show favourited items in all shop
	## screens, and allow staring/unstaring from that screen"): the
	## Shop's own Party Inventory/sell grid now carries a matching Star
	## column (see shop_screen.gd's _add_sell_grid_row) — a favourited
	## item stays fully visible here (just without a Sell button) rather
	## than being hidden entirely, and the star itself can be toggled
	## right from this grid, without needing to go back to the
	## Character Menu.
	var sell_list: VBoxContainer = shop.get_node("%SellList")

	var find_sell_grid := func() -> GridContainer:
		for child in sell_list.get_children():
			if child is GridContainer:
				return child
		return null
	## Finds the 5 cells (Star/Item/Qty/Price/Actions) belonging to
	## `item_name`'s own row inside the Shop's sell grid — skips the
	## header row and any owner-section row, same convention as
	## shop_grid_test.gd's own _find_sell_row_cells, just 5-columns aware.
	var find_sell_row := func(grid: GridContainer, item_name: String) -> Array:
		if grid == null:
			return []
		var all_children := grid.get_children()
		var i := 5
		while i + 5 <= all_children.size():
			var cells := all_children.slice(i, i + 5)
			## Column 1 is a plain PanelContainer for a real item row, but
			## a MarginContainer for an owner-section divider row (see
			## _add_owner_section_row) — typed as Control so both match,
			## same convention as shop_grid_test.gd's own row-finders.
			var item_panel: Control = cells[1]
			if item_panel.get_child_count() > 0:
				var lbl: Node = item_panel.get_child(0)
				if lbl is Label and lbl.text == "• " + item_name:
					return cells
			i += 5
		return []

	var sell_grid: GridContainer = find_sell_grid.call()
	checks.append(["The Shop's own sell grid is a real 5-column grid (Star/Item/Qty/Price/Actions)", sell_grid != null and sell_grid.columns == 5])

	var halberd_cells: Array = find_sell_row.call(sell_grid, "Halberd")
	checks.append(["The favourited Halberd still gets its own row in the Shop's sell list, not hidden", not halberd_cells.is_empty()])
	if not halberd_cells.is_empty():
		var halberd_shop_star_btn: Button = (halberd_cells[0] as PanelContainer).get_child(0)
		checks.append(["...with its Star button showing filled (★), matching the Inventory tab's own state", halberd_shop_star_btn.text == "★"])
		var halberd_actions_text := _scrape_all_text(halberd_cells[4])
		checks.append(["...and no Sell button while it's still favourited (protected from being sold)", not halberd_actions_text.contains("Sell")])

	## Per the further follow-up request ("dont double show equipped
	## items in the shop, show those only in the Equipped gear
	## section"): Sword is the character's only copy and it's currently
	## equipped (no spare copy at all — _get_spare_sellable_count == 0),
	## so it should no longer get a row here at all, favourited or not —
	## it's already shown, with its own Unequip button, in the Shop's
	## separate Equipped Gear list, and there's nothing left here to
	## Sell or Equip a second copy of.
	var sword_cells_before: Array = find_sell_row.call(sell_grid, "Sword")
	checks.append(["The character's own fully-equipped Sword (no spare copy) does NOT get a duplicate row in the Sell list", sword_cells_before.is_empty()])
	var equipped_list: VBoxContainer = shop.get_node("%EquippedList")
	checks.append(["...it's shown there instead, in the Shop's own separate Equipped Gear list", _scrape_all_text(equipped_list).contains("Sword")])

	## --- "make it so any item is sellable, even starting trappings" ------
	var sell_list_text := _scrape_all_text(sell_list)
	checks.append(["A no-database-entry starting trapping (Cloak) still gets a real, nonzero sell price", shop._find_sell_price("Cloak") > 0])
	checks.append(["That fallback-priced trapping shows a real Sell button in the Shop's sell list", sell_list_text.contains("Cloak") and sell_list_text.contains("Sell 1")])
	checks.append(["A genuinely excluded item (Stolen Idol) still returns 0, not the fallback", shop._find_sell_price("Stolen Idol") == 0])

	## --- Un-favouriting Halberd directly from the Shop's own Star button --
	if not halberd_cells.is_empty():
		var halberd_shop_star_btn2: Button = (halberd_cells[0] as PanelContainer).get_child(0)
		halberd_shop_star_btn2.pressed.emit()
		await tree.process_frame
	checks.append(["Clicking the Shop's own Star button un-favourites the item (Character.favourite_items updated)", not character.favourite_items.has("Halberd")])
	var sell_grid_after: GridContainer = find_sell_grid.call()
	var halberd_cells_after: Array = find_sell_row.call(sell_grid_after, "Halberd")
	checks.append(["...and its row now shows a real Sell button again, no longer protected", not halberd_cells_after.is_empty() and _scrape_all_text(halberd_cells_after[4]).contains("Sell 1")])

	## --- Re-favouriting Halberd directly from the Shop's own Star button
	## again — confirms toggling works both ways from the Shop (Sword
	## can't be used for this half of the check any more since a fully-
	## equipped item no longer gets a row here at all to click on).
	if not halberd_cells_after.is_empty():
		var halberd_shop_star_btn3: Button = (halberd_cells_after[0] as PanelContainer).get_child(0)
		halberd_shop_star_btn3.pressed.emit()
		await tree.process_frame
	checks.append(["Clicking the Shop's own Star button favourites the item too (works both ways)", character.favourite_items.has("Halberd")])

	var sell_grid_after2: GridContainer = find_sell_grid.call()
	var halberd_cells_after2: Array = find_sell_row.call(sell_grid_after2, "Halberd")
	checks.append(["The re-favourited Halberd still shows its own row in the Sell list (not hidden)", not halberd_cells_after2.is_empty()])
	if not halberd_cells_after2.is_empty():
		checks.append(["...but with no Sell button while favourited", not _scrape_all_text(halberd_cells_after2[4]).contains("Sell")])
		var halberd_shop_star_btn4: Button = (halberd_cells_after2[0] as PanelContainer).get_child(0)
		checks.append(["...and its Star button shows filled (★) too", halberd_shop_star_btn4.text == "★"])

	## --- Favourites survive a save/load round-trip -----------------------
	## Per the request ("item favourites needs to save between sessions"):
	## favourite_items was a real Character field, correctly read/written
	## by this screen and the Shop, but was never included in
	## to_save_dict()/from_save_dict() at all, so it silently reset to
	## empty on every reload. At this point in the test the character has
	## un-favourited and then re-favourited Halberd, both from the Shop's
	## own Star column, so only Halberd is currently favourited.
	character.favourite_items.sort()
	var save_dict: Dictionary = character.to_save_dict()
	checks.append(["to_save_dict() includes favourite_items", save_dict.has("favourite_items")])
	checks.append(["...with the currently-favourited item present", (save_dict.get("favourite_items", []) as Array).size() == 1])

	## Round-trip through JSON, exactly as SaveManager does on disk, so
	## this genuinely exercises string-keyed parsing, not just a native
	## Dictionary/Array passed straight back in.
	var json_roundtrip: Dictionary = JSON.parse_string(JSON.stringify(save_dict))
	var reloaded: Character = Character.from_save_dict(json_roundtrip)
	checks.append(["A reloaded Character (from a JSON round-trip) has favourite_items restored", reloaded != null and reloaded.favourite_items.size() == 1])
	checks.append(["...containing exactly the item favourited before saving", reloaded != null and reloaded.favourite_items.has("Halberd")])

	## A save with no favourites at all (older save file, or a character
	## who never favourited anything) must still load cleanly to an empty
	## array, not null/crash — data.get() default path.
	var empty_favourites_dict: Dictionary = save_dict.duplicate(true)
	empty_favourites_dict.erase("favourite_items")
	var reloaded_no_favourites: Character = Character.from_save_dict(empty_favourites_dict)
	checks.append(["A save file with no favourite_items key at all still loads cleanly to an empty array", reloaded_no_favourites != null and reloaded_no_favourites.favourite_items.is_empty()])

	menu.queue_free()
	shop.queue_free()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Inventory Grid + Favourites Check): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
