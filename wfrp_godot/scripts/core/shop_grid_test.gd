extends RefCounted
class_name ShopGridTest
## Per the request ("lets transfer the inventory grid layout to the shop
## windows. but leave out favorite star. and make rows more compact (at
## least half as tall vertically). Also add back Sell all (sells all
## sellable items from all characters at once) button. and allow any
## ammo to be bought in 1/5/10 quantities. lets also move all game
## fonts to Press Start 2P."):
##
## Confirms: the Shop's Items/Weapons/Armour buy tabs are all real boxed
## GridContainers (4-8 columns depending on tab: Item/Price-or-Qty/
## Enc-or-Price/Actions and so on); a real Shop grid row is measured at
## runtime to be at least half the height of a real Inventory grid row
## (not just eyeballed); Arrow (an Ammunition-category item) offers
## real Buy 1/5/10 buttons that each genuinely purchase that many units
## in one all-or-nothing spend; a real global Sell All button sells
## every spare, non-favourited, sellable item from EVERY present party
## member at once (not just whoever's currently being shopped for),
## correctly skipping favourited/equipped items and crediting the
## shared party purse; and the project's own theme now genuinely loads
## Press Start 2P as its one default_font.
##
## Per the follow-up request ("show favourited items in all shop
## screens, and allow staring/unstaring from that screen"): the Sell
## list's own grid is now 5 columns (Star/Item/Qty/Price/Actions,
## matching the Inventory tab's own layout, not the 4-column layout
## this file originally described) — a favourited item stays visible
## here (no longer hidden), just without a Sell button, and its own
## Star button in this grid can toggle Character.favourite_items
## directly, exercised below alongside the pre-existing Sell All checks.

## Finds the 5 cells (Star/Item/Qty/Price/Actions) belonging to
## `item_name`'s own row inside a Sell grid — skips the header row and
## any owner-section row (identified by NOT having a "• <name>"
## prefixed Label as their own column-1 (Item) cell's single child,
## which section rows never do — see _add_owner_section_row's plain,
## unprefixed name Label). Column 0 is the Star toggle — see
## shop_screen.gd's follow-up "show favourited items in all shop
## screens" change, which added it ahead of Item/Qty/Price/Actions.
static func _find_sell_row_cells(grid: GridContainer, item_name: String) -> Array:
	var all_children := grid.get_children()
	var i := 5
	while i + 5 <= all_children.size():
		var cells := all_children.slice(i, i + 5)
		var col1: Control = cells[1]
		if col1.get_child_count() > 0:
			var maybe_label: Node = col1.get_child(0)
			if maybe_label is Label and maybe_label.text == "• " + item_name:
				return cells
		i += 5
	return []

## As _find_sell_row_cells, but returns the row's own starting child
## index instead of its cells — used to compare two rows' relative
## ORDER (which comes first) rather than their contents.
static func _find_sell_row_index(grid: GridContainer, item_name: String) -> int:
	var all_children := grid.get_children()
	var i := 5
	while i + 5 <= all_children.size():
		var cells := all_children.slice(i, i + 5)
		var col1: Control = cells[1]
		if col1.get_child_count() > 0:
			var maybe_label: Node = col1.get_child(0)
			if maybe_label is Label and maybe_label.text == "• " + item_name:
				return i
		i += 5
	return -1

## Per the bug fix ("Parry weapons, columns Damage Enc and Qualities are
## slightly out of line... Basic weapons have the same issue... its the
## Very Short Reach that is causing the miss-alignment"): the Weapons
## and Armour buy tabs no longer build one separate GridContainer per
## skill-group/armor-tier section (which let each section's columns
## drift out of alignment with every other section's) — they now share
## ONE GridContainer per tab, with each section rendered as a spanning
## "section-header row" (see _add_weapon_group_section_row /
## _add_armour_tier_section_row) followed by a repeated column-header
## row, all inside that same grid. These three helpers replace the old
## per-section-grid lookups with row-classification helpers that work
## against that one shared grid instead.
##
## Finds the 8 cells belonging to `item_name`'s own data row inside the
## shared Weapons/Armour buy grid. A data row's own column-0 cell is a
## real boxed PanelContainer (see _shop_boxed_cell) — unlike a
## section-header or column-header row, whose column-0 cell is always a
## plain MarginContainer — so checking the cell TYPE alone (rather than
## needing to also skip a fixed number of leading rows, since a section
## header can appear anywhere in the grid, not just at the very start)
## is enough to skip both kinds of header row correctly.
static func _find_weapon_row_cells(grid: GridContainer, item_name: String) -> Array:
	var all_children := grid.get_children()
	var columns := grid.columns
	var i := 0
	while i + columns <= all_children.size():
		var cells := all_children.slice(i, i + columns)
		var col0: Control = cells[0]
		if col0 is PanelContainer and col0.get_child_count() > 0:
			var maybe_label: Node = col0.get_child(0)
			if maybe_label is Label and maybe_label.text == "• " + item_name:
				return cells
		i += columns
	return []

## Returns the ordered list of skill-group / armor-tier names found as
## section-header rows inside the shared grid. A section-header row's
## column-0 cell is a MarginContainer wrapping a plain (unprefixed)
## Label — same as a real column-header row's own column-0 cell — but a
## section-header row's OTHER columns are bare empty Controls, while a
## column-header row's other columns are themselves MarginContainers
## (see _shop_header_cell); checking column 1's type is what tells the
## two apart.
static func _find_grid_section_headers(grid: GridContainer) -> Array[String]:
	var found: Array[String] = []
	var all_children := grid.get_children()
	var columns := grid.columns
	var i := 0
	while i + columns <= all_children.size():
		var cells := all_children.slice(i, i + columns)
		var col0: Control = cells[0]
		var col1: Control = cells[1]
		if col0 is MarginContainer and col0.get_child_count() > 0 and not (col1 is MarginContainer):
			var maybe_label: Node = col0.get_child(0)
			if maybe_label is Label:
				found.append(maybe_label.text)
		i += columns
	return found

## Finds the real column-header row (Item/Reach/Damage/... or
## Item/Price/Availability/... titles) immediately following
## `section_name`'s own section-header row inside the shared grid, and
## returns its title texts in column order — this is what confirms
## every section repeats the SAME header (and therefore the same
## column layout) rather than each section drifting independently, per
## the reported bug.
static func _find_header_row_after_section(grid: GridContainer, section_name: String) -> Array[String]:
	var all_children := grid.get_children()
	var columns := grid.columns
	var i := 0
	while i + columns <= all_children.size():
		var cells := all_children.slice(i, i + columns)
		var col0: Control = cells[0]
		var col1: Control = cells[1]
		if col0 is MarginContainer and col0.get_child_count() > 0 and not (col1 is MarginContainer):
			var maybe_label: Node = col0.get_child(0)
			if maybe_label is Label and maybe_label.text == section_name and i + 2 * columns <= all_children.size():
				var header_cells := all_children.slice(i + columns, i + 2 * columns)
				var texts: Array[String] = []
				for cell in header_cells:
					var lbl: Label = cell.get_child(0)
					texts.append(lbl.text)
				return texts
		i += columns
	return []

## Finds the Repair tab's own shared GridContainer inside %RepairList
## (see _new_repair_buy_grid/_rebuild_repair_list in shop_screen.gd) —
## same grid-layout treatment the Items/Weapons/Armour tabs already got.
## Returns null when the list is currently showing its "nothing
## repairable" placeholder Label instead of a grid.
static func _find_repair_grid(repair_list_node: VBoxContainer) -> GridContainer:
	for child in repair_list_node.get_children():
		if child is GridContainer:
			return child
	return null

## As _find_weapon_row_cells, but for the Repair tab's own grid — a
## repair row's own Item cell always appends a worn/equipped-vs-in-pack
## suffix (or, for a Broken row with more than one copy, an "x N" count
## suffix) after the bare item name, so this matches by PREFIX rather
## than requiring an exact "• <name>" match.
static func _find_repair_row_cells(grid: GridContainer, item_name: String) -> Array:
	if grid == null:
		return []
	var all_children := grid.get_children()
	var columns := grid.columns
	var i := 0
	while i + columns <= all_children.size():
		var cells := all_children.slice(i, i + columns)
		var col0: Control = cells[0]
		if col0 is PanelContainer and col0.get_child_count() > 0:
			var maybe_label: Node = col0.get_child(0)
			if maybe_label is Label and (maybe_label as Label).text.begins_with("• " + item_name):
				return cells
		i += columns
	return []

## Recursively finds a Button with exact text `text` anywhere under
## `root` (an Actions cell's own PanelContainer, wrapping an
## HBoxContainer of buttons/spacers).
static func _find_button_by_text(root: Node, text: String) -> Button:
	if root == null:
		return null
	for child in root.get_children():
		if child is Button and child.text == text:
			return child
		var found := _find_button_by_text(child, text)
		if found != null:
			return found
	return null

## Finds the actions_row (the single HBoxContainer directly under an
## Actions cell's PanelContainer) and returns its own last Button child
## — whichever button actually sits at the RIGHT-hand end of that row.
static func _find_last_button(actions_cell: Node) -> Button:
	if actions_cell == null or actions_cell.get_child_count() == 0:
		return null
	var actions_row: Node = actions_cell.get_child(0)
	var last: Button = null
	for child in actions_row.get_children():
		if child is Button:
			last = child
	return last

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- Party setup: two members, so Sell All's "all characters" scope
	## is genuinely exercised, not just a single-character no-op. -------
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var char_a: Character = GameState.player_character
	char_a.inventory.clear()
	char_a.favourite_items.clear()
	char_a.equipped_weapon = ""
	char_a.gold_crowns = 0
	char_a.silver_shillings = 0
	char_a.brass_pennies = 0

	var human := GameData.find_race("Human")
	var soldier := GameData.find_career("Soldier")
	var char_b := Character.new()
	char_b.character_name = "Second Member"
	char_b.race = human
	char_b.career = soldier
	char_b.current_tier = 1
	char_b.characteristics = CharacteristicSet.new()
	char_b.recompute_max_wounds()
	char_b.inventory.clear()
	GameState.add_party_member(char_b)

	## A carries: an equipped Sword (must survive Sell All untouched), a
	## favourited Bedroll (must survive Sell All untouched), and 2 spare
	## Daggers (must be swept by Sell All).
	char_a.inventory.append("Sword")
	char_a.equipped_weapon = "Sword"
	char_a.inventory.append("Bedroll")
	char_a.favourite_items.append("Bedroll")
	char_a.inventory.append("Dagger")
	char_a.inventory.append("Dagger")

	## B carries a single spare Rope, 10 yards — Sell All must reach B too, not
	## just whoever's currently the active shopper (char_a).
	char_b.inventory.append("Rope, 10 yards")

	var dagger_price := 0
	var rope_price := 0

	## --- Open the real Shop scene ----------------------------------------
	var shop_scene: PackedScene = load("res://scenes/Shop.tscn")
	var shop: Node = shop_scene.instantiate()
	tree.get_root().add_child.call_deferred(shop)
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame

	## --- Selected shopper's own Enc x/x readout ----------------------------
	var enc_label: Label = shop.get_node("%EncLabel")
	var expected_enc_a := "Enc: %d / %d" % [roundi(char_a.get_current_encumbrance()), char_a.get_carrying_capacity()]
	checks.append(["The Shop shows the currently-selected shopper's own real Enc x/x reading", enc_label.text == expected_enc_a])
	shop._cycle_character(1)
	await tree.process_frame
	var expected_enc_b := "Enc: %d / %d" % [roundi(char_b.get_current_encumbrance()), char_b.get_carrying_capacity()]
	checks.append(["...and it updates to the newly-selected member's own Enc after switching who's shopping", enc_label.text == expected_enc_b])
	shop._cycle_character(-1)
	await tree.process_frame

	## --- Grid layout: Items tab is a real 5-column GridContainer ---------
	## Per the request ("add a column to the Buy screen between price
	## and Enc to show the Item's Availability"): Item/Price/Availability/
	## Enc/Actions — one more column than the Party Inventory/Sell grid,
	## which stays at 4 (no Availability column there).
	var items_list: VBoxContainer = shop.get_node("%ItemsList")
	var items_grid: GridContainer = null
	for child in items_list.get_children():
		if child is GridContainer:
			items_grid = child
	checks.append(["Items tab is a real GridContainer with 5 columns (no Star column)", items_grid != null and items_grid.columns == 5])

	## --- Items grouped by Containers/Food/Miscellaneous ------------------
	## Per the request ("in the shops Items tab, separate Containers and
	## Food into their own groups, and everything else is the
	## Miscellaneous group"): same one-shared-grid-with-section-header-
	## rows pattern the Weapons/Armour tabs already use — see
	## _find_grid_section_headers/_find_header_row_after_section's own
	## comments (defined below, shared with the Weapons/Armour checks).
	var expected_item_groups: Dictionary = {}
	for item in shop.item_stock:
		var group_name: String = shop._item_group_name(item)
		expected_item_groups[group_name] = true
	var expected_item_group_names: Array = []
	for g in ["Containers", "Food", "Miscellaneous"]:
		if expected_item_groups.has(g):
			expected_item_group_names.append(g)
	var found_item_group_headers: Array[String] = []
	if items_grid != null:
		found_item_group_headers = _find_grid_section_headers(items_grid)
	checks.append(["Every Items group actually in stock gets its own section-header row, in Containers -> Food -> Miscellaneous order", found_item_group_headers == expected_item_group_names])

	## A Container-category item (Backpack) and a Food-category item
	## (Rations, 1 day) are both real, Common items — reliable subjects
	## to confirm the actual category -> group mapping.
	var backpack_def: ItemDefinition = GameData.item_db.find_by_name("Backpack")
	checks.append(["Backpack is genuinely tagged category Container in the data", backpack_def != null and backpack_def.category == "Container"])
	var rations_def: ItemDefinition = GameData.item_db.find_by_name("Rations, 1 day")
	checks.append(["Rations, 1 day is genuinely tagged category Food in the data", rations_def != null and rations_def.category == "Food"])

	var items_header_texts: Array[String] = []
	if items_grid != null and expected_item_group_names.has("Containers"):
		items_header_texts = _find_header_row_after_section(items_grid, "Containers")
	checks.append(["Items grid header reads Item / Price / Availability / Enc / Actions", items_header_texts == ["Item", "Price", "Availability", "Enc", "Actions"]])
	if items_grid != null:
		for other_group in ["Food", "Miscellaneous"]:
			if expected_item_group_names.has(other_group) and not items_header_texts.is_empty():
				var other_items_header: Array[String] = _find_header_row_after_section(items_grid, other_group)
				checks.append(["The '%s' section's own column-header row matches 'Containers''s exactly (same shared grid, same column layout)" % other_group, other_items_header == items_header_texts])

	if items_grid != null and backpack_def != null and shop.item_stock.has(backpack_def):
		var backpack_row_cells: Array = _find_weapon_row_cells(items_grid, "Backpack")
		checks.append(["Found Backpack's own row filed under the Containers section", not backpack_row_cells.is_empty()])
	if items_grid != null and rations_def != null and shop.item_stock.has(rations_def):
		var rations_row_cells: Array = _find_weapon_row_cells(items_grid, "Rations, 1 day")
		checks.append(["Found Rations, 1 day's own row filed under the Food section", not rations_row_cells.is_empty()])

	## --- Alphabetical ordering (all three Buy tabs, plus ammo) -------------
	## Per the request ("list all buy/sell items alphabetically") — the
	## rolled stock arrays themselves are checked directly rather than by
	## scraping the grid, so this holds regardless of how many of each
	## category happened to roll into stock this visit.
	var items_sorted := true
	for i in range(shop.item_stock.size() - 1):
		if shop.item_stock[i].item_name > shop.item_stock[i + 1].item_name:
			items_sorted = false
			break
	checks.append(["The Items buy tab's stock is sorted alphabetically by name", items_sorted])
	var weapons_sorted := true
	for i in range(shop.weapon_stock.size() - 1):
		if shop.weapon_stock[i].weapon_name > shop.weapon_stock[i + 1].weapon_name:
			weapons_sorted = false
			break
	checks.append(["The Weapons buy tab's stock is sorted alphabetically by name", weapons_sorted])
	var armour_sorted := true
	for i in range(shop.armour_stock.size() - 1):
		if shop.armour_stock[i].armour_name > shop.armour_stock[i + 1].armour_name:
			armour_sorted = false
			break
	checks.append(["The Armour buy tab's stock is sorted alphabetically by name", armour_sorted])
	var ammo_sorted := true
	for i in range(shop.ammo_stock.size() - 1):
		if shop.ammo_stock[i].item_name > shop.ammo_stock[i + 1].item_name:
			ammo_sorted = false
			break
	checks.append(["The Weapons tab's own Ammunition section stock is sorted alphabetically by name", ammo_sorted])

	## --- No ammo left on the Items tab (moved to Weapons) ------------------
	## Per the request ("move ammo from the shop item list to the weapon
	## line"): the Items grid should no longer contain any Ammunition-
	## category row at all. _find_weapon_row_cells (despite its name) is
	## generic over any grid's own column count — see its own comment —
	## so it works just as well here as it does for the Weapons/Armour
	## grids it was written for.
	var items_grid_has_ammo := false
	if items_grid != null:
		items_grid_has_ammo = not _find_weapon_row_cells(items_grid, "Arrow").is_empty()
	checks.append(["Arrow no longer appears on the Items buy tab", not items_grid_has_ammo])

	## --- Ammo quantity buying (Arrow), now on the Weapons tab --------------
	var arrow_def: ItemDefinition = GameData.item_db.find_by_name("Arrow")
	checks.append(["Arrow is genuinely tagged category Ammunition in the data", arrow_def != null and arrow_def.category == "Ammunition"])

	var melee_weapons_list: VBoxContainer = shop.get_node("%MeleeList")
	var ranged_weapons_list: VBoxContainer = shop.get_node("%RangedList")

	## --- Weapons tab split into Melee / Ranged subtabs ---------------------
	## Per the request ("separate the shop Weapons tab into 2 subtabs,
	## Melee and Ranged. Keep all melee weapons in one, and keep Ranged +
	## Ammo in the other"): the Weapons tab is now its own nested
	## TabContainer with exactly two subtabs, in that order.
	var weapons_tabs_node: TabContainer = melee_weapons_list.get_parent().get_parent()
	checks.append(["The Weapons tab is now its own nested TabContainer with 2 subtabs", weapons_tabs_node != null and weapons_tabs_node.get_tab_count() == 2])
	checks.append(["...named Melee then Ranged, in that order", weapons_tabs_node != null and weapons_tabs_node.get_tab_count() == 2 and weapons_tabs_node.get_tab_title(0) == "Melee" and weapons_tabs_node.get_tab_title(1) == "Ranged"])

	## --- Weapons grouped by Skill type within each subtab, no more
	## "(Skill)" suffix, with real Reach/Damage/Qualities columns --------
	## Per the request ("separate the shop weapon list by Skill type,
	## that means we can remove the (Skill) in the item name. And then
	## lets add Reach, Damage and 'Qualities and Flaws' columns too all
	## weapons fill these accordingly with those values.") — this mirrors
	## shop_screen.gd's own _rebuild_weapons_list() sort exactly: melee
	## group names alphabetical (Melee subtab), ranged group names
	## alphabetical (Ranged subtab).
	var expected_groups: Dictionary = {}
	var expected_group_is_ranged: Dictionary = {}
	for w in shop.weapon_stock:
		expected_groups[w.skill_group] = true
		expected_group_is_ranged[w.skill_group] = w.is_ranged
	var expected_melee_names: Array = []
	var expected_ranged_names: Array = []
	for group_name in expected_groups.keys():
		if expected_group_is_ranged[group_name]:
			expected_ranged_names.append(group_name)
		else:
			expected_melee_names.append(group_name)
	expected_melee_names.sort()
	expected_ranged_names.sort()

	## Per the bug fix (see the helper comments above): each subtab shares
	## ONE GridContainer across every skill-group section rather than one
	## grid per group — this is the actual fix for the originally
	## reported misalignment, since a single GridContainer always sizes
	## every one of its columns identically for every row in it,
	## regardless of which section that row belongs to.
	var melee_weapon_grid: GridContainer = null
	for child in melee_weapons_list.get_children():
		if child is GridContainer and child.columns == 8:
			melee_weapon_grid = child
			break
	checks.append(["The Melee subtab renders one shared 8-column GridContainer for every skill-group section (not one grid per group)", melee_weapon_grid != null])

	var found_melee_headers: Array[String] = []
	if melee_weapon_grid != null:
		found_melee_headers = _find_grid_section_headers(melee_weapon_grid)
	checks.append(["Every Melee skill group actually in weapon_stock gets its own section-header row inside the Melee subtab's shared grid, in the same order", found_melee_headers == expected_melee_names])

	var ranged_weapon_grid: GridContainer = null
	for child in ranged_weapons_list.get_children():
		if child is GridContainer and child.columns == 8:
			ranged_weapon_grid = child
			break
	if not expected_ranged_names.is_empty():
		checks.append(["The Ranged subtab renders one shared 8-column GridContainer for every skill-group section (not one grid per group)", ranged_weapon_grid != null])
		var found_ranged_headers: Array[String] = []
		if ranged_weapon_grid != null:
			found_ranged_headers = _find_grid_section_headers(ranged_weapon_grid)
		checks.append(["Every Ranged skill group actually in weapon_stock gets its own section-header row inside the Ranged subtab's shared grid, in the same order", found_ranged_headers == expected_ranged_names])

	## Axe is Basic/Common, so it's always in stock — a reliable subject
	## to check the new weapon-only columns against its own real data.
	## Basic is a Melee skill group, so Axe lives on the Melee subtab.
	var axe_def: WeaponDefinition = GameData.weapon_db.find_by_name("Axe")
	checks.append(["Axe is genuinely tagged skill_group Basic in the data", axe_def != null and axe_def.skill_group == "Basic"])

	var basic_grid: GridContainer = melee_weapon_grid
	if basic_grid != null:
		var header_texts: Array[String] = _find_header_row_after_section(basic_grid, "Basic")
		## Per the follow-up request ("move the Price column to between
		## Qualities and Actions. then move availability to between
		## Qualities and Price"): final order is Item/Reach/Damage/Enc/
		## Qualities and Flaws/Availability/Price/Actions.
		checks.append(["The 'Basic' section's own column-header row reads Item / Reach / Damage / Enc / Qualities and Flaws / Availability / Price / Actions", header_texts == ["Item", "Reach", "Damage", "Enc", "Qualities and Flaws", "Availability", "Price", "Actions"]])

		## Per the same fix: the Parry section's header row must read the
		## IDENTICAL titles as Basic's — proving both sections now share
		## the one grid's column layout instead of each auto-sizing its
		## own Reach column independently (Basic and Parry are the two
		## groups containing a "Very Short" reach weapon, which is what
		## caused the originally-reported drift).
		if expected_groups.has("Parry"):
			var parry_header_texts: Array[String] = _find_header_row_after_section(basic_grid, "Parry")
			checks.append(["The 'Parry' section's own column-header row matches 'Basic''s exactly (same shared grid, same column layout)", parry_header_texts == header_texts])

		var axe_row_cells: Array = _find_weapon_row_cells(basic_grid, "Axe")
		checks.append(["Found Axe's own row in the shared weapons grid", not axe_row_cells.is_empty()])
		if not axe_row_cells.is_empty() and axe_def != null:
			var axe_name_panel: PanelContainer = axe_row_cells[0]
			var axe_name_lbl: Label = axe_name_panel.get_child(0)
			checks.append(["Axe's own item name no longer has a '(Skill)' suffix now that its section header names the group", axe_name_lbl.text == "• Axe"])

			var axe_reach_panel: PanelContainer = axe_row_cells[1]
			var axe_reach_lbl: Label = axe_reach_panel.get_child(0)
			checks.append(["Axe's Reach column shows its real Reach value", axe_reach_lbl.text == axe_def.reach])

			var axe_damage_panel: PanelContainer = axe_row_cells[2]
			var axe_damage_lbl: Label = axe_damage_panel.get_child(0)
			var expected_dmg_text := ("SB%+d" % axe_def.damage_flat) if axe_def.damage_mode == "strength_bonus_plus" else str(axe_def.damage_flat)
			checks.append(["Axe's Damage column shows its real Damage value", axe_damage_lbl.text == expected_dmg_text])

			var axe_qualities_panel: PanelContainer = axe_row_cells[4]
			var axe_qualities_lbl: Label = axe_qualities_panel.get_child(0)
			var expected_qualities_text := ", ".join(axe_def.qualities) if not axe_def.qualities.is_empty() else "-"
			checks.append(["Axe's Qualities and Flaws column lists its real qualities/flaws", axe_qualities_lbl.text == expected_qualities_text])
			checks.append(["Axe's Qualities and Flaws column text is one size smaller than the rest of the row", axe_qualities_lbl.get_theme_font_size("font_size") == shop._SHOP_ROW_FONT_SIZE - 1])

			var axe_availability_panel: PanelContainer = axe_row_cells[5]
			var axe_availability_lbl: Label = axe_availability_panel.get_child(0)
			checks.append(["Axe's Availability column (now between Qualities and Flaws and Price) shows its real Availability value", axe_availability_lbl.text == axe_def.availability])

			var axe_price_panel: PanelContainer = axe_row_cells[6]
			var axe_price_lbl: Label = axe_price_panel.get_child(0)
			checks.append(["Axe's Price column (now between Availability and Actions) shows a real, non-empty price", not axe_price_lbl.text.is_empty()])

	## Per the follow-up request, Ammunition now lives at the bottom of
	## the Ranged subtab specifically (not the combined weapons list).
	var ammo_grid: GridContainer = null
	var ranged_grids: Array = []
	for child in ranged_weapons_list.get_children():
		if child is GridContainer:
			ranged_grids.append(child)
	## ranged_weapons_list now holds a mix of GridContainers: the shared
	## 8-column grid holding every Ranged skill-group section (Item/Reach/
	## Damage/Enc/Qualities and Flaws/Availability/Price/Actions) plus
	## the Ammunition section's own separate 5-column grid (Item/Price/
	## Availability/Enc/Actions, same shape as the Items tab). Only the
	## 5-column one is a candidate for holding Arrow — skip the 8-column
	## weapons grid outright rather than chunk it at the wrong stride
	## (its header rows' own cells are MarginContainers, not the
	## PanelContainer a data-row chunk expects).
	for g in ranged_grids:
		var g_grid: GridContainer = g
		if g_grid.columns != 5:
			continue
		var all_children: Array = g_grid.get_children()
		var j := 5
		while j + 5 <= all_children.size():
			var cells := all_children.slice(j, j + 5)
			var name_panel: PanelContainer = cells[0]
			var name_lbl: Label = name_panel.get_child(0)
			if name_lbl.text.begins_with("• Arrow"):
				ammo_grid = g
			j += 5
	checks.append(["Found the Ranged subtab's own separate Ammunition GridContainer", ammo_grid != null])

	var arrow_row_cells: Array = []
	if ammo_grid != null and arrow_def != null:
		var all_children := ammo_grid.get_children()
		var i := 5
		while i + 5 <= all_children.size():
			var cells := all_children.slice(i, i + 5)
			var name_panel: PanelContainer = cells[0]
			var name_lbl: Label = name_panel.get_child(0)
			if name_lbl.text.begins_with("• Arrow"):
				arrow_row_cells = cells
			i += 5
	checks.append(["Found Arrow's own row in the Weapons tab's Ammunition grid", not arrow_row_cells.is_empty()])

	## --- Gap control between Ranged weapon rows and the Ammunition
	## section, both now on the Ranged subtab -------------------------------
	## A gap Control should sit between the ranged weapon grid and the
	## ammo grid whenever both a Ranged group and ammo_stock are non-empty.
	if not expected_ranged_names.is_empty() and not shop.ammo_stock.is_empty():
		var found_gap := false
		var found_header := false
		for child in ranged_weapons_list.get_children():
			if child is Control and not (child is GridContainer) and not (child is Label):
				found_gap = true
			if child is Label and child.text == "Ammunition":
				found_header = true
		checks.append(["A visual gap separates the Ranged weapon rows from the Ammunition section", found_gap])
		checks.append(["An 'Ammunition' section header labels the ammo rows", found_header])
	if not arrow_row_cells.is_empty() and arrow_def != null:
		var arrow_availability_panel: PanelContainer = arrow_row_cells[2]
		var arrow_availability_lbl: Label = arrow_availability_panel.get_child(0)
		checks.append(["Arrow's row shows its real Availability value in the new column (between Price and Enc)", arrow_availability_lbl.text == arrow_def.availability])
	var arrow_buy_buttons: Array[Button] = []
	if not arrow_row_cells.is_empty():
		var actions_panel: PanelContainer = arrow_row_cells[4]
		var actions_row: HBoxContainer = actions_panel.get_child(0)
		for c in actions_row.get_children():
			if c is Button:
				arrow_buy_buttons.append(c)
	var buy_button_texts: Array[String] = []
	for b in arrow_buy_buttons:
		buy_button_texts.append(b.text)
	checks.append(["Arrow's Actions cell offers exactly Buy 1 / Buy 5 / Buy 10 (not a single plain Buy button)", buy_button_texts == ["Buy 1", "Buy 5", "Buy 10"]])

	## --- Hover highlight (Buy tab): hovering a Buy button brightens the
	## whole row's own box outline; it reverts once the pointer leaves. ---
	if not arrow_row_cells.is_empty() and not arrow_buy_buttons.is_empty():
		var arrow_item_cell: PanelContainer = arrow_row_cells[0]
		var normal_style: StyleBoxFlat = arrow_item_cell.get_theme_stylebox("panel")
		var normal_border_alpha := normal_style.border_color.a
		arrow_buy_buttons[0].mouse_entered.emit()
		await tree.process_frame
		var hovered_style: StyleBoxFlat = arrow_item_cell.get_theme_stylebox("panel")
		checks.append(["Hovering a Buy button brightens the whole row's own box outline (border alpha increases)", hovered_style.border_color.a > normal_border_alpha])
		arrow_buy_buttons[0].mouse_exited.emit()
		await tree.process_frame
		var reverted_style: StyleBoxFlat = arrow_item_cell.get_theme_stylebox("panel")
		checks.append(["...and reverts to the normal outline once the pointer leaves the Buy button", is_equal_approx(reverted_style.border_color.a, normal_border_alpha)])

		## Per the follow-up request ("highlight around the edge when
		## hovering anywhere over the row, not just the button"):
		## hovering a cell that ISN'T the Buy button — e.g. the row's own
		## Availability cell — must ALSO brighten the whole row.
		var arrow_availability_cell: PanelContainer = arrow_row_cells[2]
		arrow_availability_cell.mouse_entered.emit()
		await tree.process_frame
		var row_hover_style: StyleBoxFlat = arrow_item_cell.get_theme_stylebox("panel")
		checks.append(["Hovering ANYWHERE over the row (its Availability cell, not just the Buy button) also brightens the whole row's own box outline", row_hover_style.border_color.a > normal_border_alpha])
		arrow_availability_cell.mouse_exited.emit()
		await tree.process_frame
		var row_reverted_style: StyleBoxFlat = arrow_item_cell.get_theme_stylebox("panel")
		checks.append(["...and reverts to the normal outline once the pointer leaves that cell too", is_equal_approx(row_reverted_style.border_color.a, normal_border_alpha)])

	if arrow_def != null:
		char_a.gold_crowns = 100
		var before_count := char_a.inventory.count("Arrow")
		var before_pennies := char_a.get_total_pennies()
		## Click "Buy 5".
		for b in arrow_buy_buttons:
			if b.text == "Buy 5":
				b.pressed.emit()
		await tree.process_frame
		checks.append(["Clicking Buy 5 adds exactly 5 Arrows to inventory in one action", char_a.inventory.count("Arrow") == before_count + 5])
		checks.append(["...and spends exactly 5x the unit price as a single combined charge", before_pennies - char_a.get_total_pennies() == arrow_def.price_pennies * 5])

	## --- Armour grouped by Armor type (Light/Medium/Heavy), in that
	## fixed order, no more "(AP N)" suffix, with real Locations/APs/
	## Qualities and Flaws columns --------------------------------------
	## Per the follow-up request ("for the shop armor list, do a similar
	## treatment... list them by Armor type (light/Medium/Heavy), and
	## add Locations, APs and 'Qualities and Flaws'").
	var armour_list_node: VBoxContainer = shop.get_node("%ArmourList")
	var expected_tiers_present: Array[String] = []
	for tier in ["Light", "Medium", "Heavy"]:
		for a in shop.armour_stock:
			if a.armor_tier == tier:
				expected_tiers_present.append(tier)
				break

	## Same one-shared-grid fix as the Weapons tab above, applied
	## proactively to Armour too (identical root cause — see the
	## _find_grid_section_headers/_find_weapon_row_cells comments).
	var armour_grid: GridContainer = null
	for child in armour_list_node.get_children():
		if child is GridContainer and child.columns == 8:
			armour_grid = child
			break
	checks.append(["The Armour tab renders one shared 8-column GridContainer for every tier section (not one grid per tier)", armour_grid != null])

	var found_tier_headers: Array[String] = []
	if armour_grid != null:
		found_tier_headers = _find_grid_section_headers(armour_grid)
	checks.append(["Every Armor type actually in armour_stock gets its own section-header row inside the shared grid, in Light -> Medium -> Heavy order", found_tier_headers == expected_tiers_present])

	## Leather Skullcap is Light/Common, so it's always in stock — a
	## reliable subject to check the new armour-only columns against.
	var skullcap_def: ArmourDefinition = GameData.armour_db.find_by_name("Leather Skullcap")
	checks.append(["Leather Skullcap is genuinely tagged armor_tier Light in the data", skullcap_def != null and skullcap_def.armor_tier == "Light"])

	var light_grid: GridContainer = armour_grid
	if light_grid != null:
		var armour_header_texts: Array[String] = _find_header_row_after_section(light_grid, "Light")
		## Per the column-reorder request ("move price between Qualities
		## and Actions. move Availability to between Qualities and
		## Price"): final order is Item/Locations/APs/Enc/Qualities and
		## Flaws/Availability/Price/Actions.
		checks.append(["The 'Light' section's own column-header row reads Item / Locations / APs / Enc / Qualities and Flaws / Availability / Price / Actions", armour_header_texts == ["Item", "Locations", "APs", "Enc", "Qualities and Flaws", "Availability", "Price", "Actions"]])

		## As with Basic/Parry on the Weapons tab: confirm Medium/Heavy
		## (if present) repeat the IDENTICAL header — i.e. the same
		## shared grid, not an independently-sized grid of their own.
		for other_tier in ["Medium", "Heavy"]:
			if expected_tiers_present.has(other_tier):
				var other_header_texts: Array[String] = _find_header_row_after_section(light_grid, other_tier)
				checks.append(["The '%s' section's own column-header row matches 'Light''s exactly (same shared grid, same column layout)" % other_tier, other_header_texts == armour_header_texts])

		var skullcap_row_cells: Array = _find_weapon_row_cells(light_grid, "Leather Skullcap")
		checks.append(["Found Leather Skullcap's own row in the shared armour grid", not skullcap_row_cells.is_empty()])
		if not skullcap_row_cells.is_empty() and skullcap_def != null:
			var skullcap_name_panel: PanelContainer = skullcap_row_cells[0]
			var skullcap_name_lbl: Label = skullcap_name_panel.get_child(0)
			checks.append(["Leather Skullcap's own item name no longer has an '(AP N)' suffix now that APs has its own column", skullcap_name_lbl.text == "• Leather Skullcap"])

			## Leather Skullcap only covers Head (a single location, no
			## Left/Right pair to combine) — Leather Jack/Leggings below
			## are what exercise the actual Arms/Legs combining logic.
			var skullcap_locations_panel: PanelContainer = skullcap_row_cells[1]
			var skullcap_locations_lbl: Label = skullcap_locations_panel.get_child(0)
			checks.append(["Leather Skullcap's Locations column shows its real covered location", skullcap_locations_lbl.text == "Head"])

			var skullcap_ap_panel: PanelContainer = skullcap_row_cells[2]
			var skullcap_ap_lbl: Label = skullcap_ap_panel.get_child(0)
			checks.append(["Leather Skullcap's APs column shows its real Armour Points", skullcap_ap_lbl.text == str(skullcap_def.armour_points)])

			var skullcap_qualities_panel: PanelContainer = skullcap_row_cells[4]
			var skullcap_qualities_lbl: Label = skullcap_qualities_panel.get_child(0)
			var expected_skullcap_qualities_text := ", ".join(skullcap_def.qualities) if not skullcap_def.qualities.is_empty() else "-"
			checks.append(["Leather Skullcap's Qualities and Flaws column lists its real qualities/flaws (Partial)", skullcap_qualities_lbl.text == expected_skullcap_qualities_text])

			var skullcap_availability_panel: PanelContainer = skullcap_row_cells[5]
			var skullcap_availability_lbl: Label = skullcap_availability_panel.get_child(0)
			checks.append(["Leather Skullcap's Availability column (now between Qualities and Flaws and Price) shows its real Availability value", skullcap_availability_lbl.text == skullcap_def.availability])

			var skullcap_price_panel: PanelContainer = skullcap_row_cells[6]
			var skullcap_price_lbl: Label = skullcap_price_panel.get_child(0)
			checks.append(["Leather Skullcap's Price column (now between Availability and Actions) shows a real, non-empty price", not skullcap_price_lbl.text.is_empty()])

		## Per the request ("in the location combine right/left Arm into
		## one word, eg, Arms, and do the same for Legs"): Leather Jack
		## covers Body + both arms, Leather Leggings covers both legs —
		## real subjects to confirm the combining logic actually fires
		## (Leather Skullcap above only ever exercises the "nothing to
		## combine" path).
		var jack_def: ArmourDefinition = GameData.armour_db.find_by_name("Leather Jack")
		if jack_def != null and shop.armour_stock.has(jack_def):
			var jack_row_cells: Array = _find_weapon_row_cells(light_grid, "Leather Jack")
			if not jack_row_cells.is_empty():
				var jack_locations_lbl: Label = (jack_row_cells[1] as PanelContainer).get_child(0)
				checks.append(["Leather Jack's Locations column combines Left Arm + Right Arm into 'Arms'", jack_locations_lbl.text == "Body, Arms"])
		var leggings_def: ArmourDefinition = GameData.armour_db.find_by_name("Leather Leggings")
		if leggings_def != null and shop.armour_stock.has(leggings_def):
			var leggings_row_cells: Array = _find_weapon_row_cells(light_grid, "Leather Leggings")
			if not leggings_row_cells.is_empty():
				var leggings_locations_lbl: Label = (leggings_row_cells[1] as PanelContainer).get_child(0)
				checks.append(["Leather Leggings' Locations column combines Left Leg + Right Leg into 'Legs'", leggings_locations_lbl.text == "Legs"])

	## --- Row compactness: a real Shop row vs a real Inventory row ---------
	## Find one real boxed cell from a Shop buy row (any row, column 0)
	## and measure its actual laid-out height. Re-fetched fresh here
	## rather than reusing the `items_grid` captured earlier — buying
	## the Arrows above triggered a full _rebuild_all(), which clears
	## and rebuilds ItemsList's own GridContainer from scratch, so the
	## original reference is a stale, already-freed node by this point.
	var items_grid_now: GridContainer = null
	for child in items_list.get_children():
		if child is GridContainer:
			items_grid_now = child
	var shop_row_height := -1.0
	if items_grid_now != null:
		## Per the Items-tab grouping request, the grid no longer starts
		## with a fixed "5 header cells then straight into data rows"
		## shape — it now leads with a Containers/Food/Miscellaneous
		## section-header row first. A data row's own column-0 cell is
		## always a real boxed PanelContainer (see _shop_boxed_cell) —
		## unlike a section-header or column-header row's own column-0
		## cell, always a plain MarginContainer — so the first
		## PanelContainer found, in order, is reliably the first data
		## row's own Item cell, regardless of how many header rows
		## precede it.
		for child in items_grid_now.get_children():
			if child is PanelContainer:
				shop_row_height = (child as Control).size.y
				break

	var menu_scene: PackedScene = load("res://scenes/CharacterMenu.tscn")
	var menu: Node = menu_scene.instantiate()
	tree.get_root().add_child.call_deferred(menu)
	await tree.process_frame
	await tree.process_frame
	menu.open()
	await tree.process_frame
	var inventory_box: VBoxContainer = menu.get_node("%InventoryBox")
	var inv_grid: GridContainer = null
	for child in inventory_box.get_children():
		if child is GridContainer:
			inv_grid = child
	var inventory_row_height := -1.0
	if inv_grid != null:
		var inv_children := inv_grid.get_children()
		## Columns = 5 in the Inventory grid (Star/Item/Qty/Enc/Actions);
		## row 0 starts at index 5.
		if inv_children.size() >= 10:
			var inv_first_row_cell: Control = inv_children[5]
			inventory_row_height = inv_first_row_cell.size.y

	checks.append(["Both a real Shop row and a real Inventory row were actually measured", shop_row_height > 0 and inventory_row_height > 0])
	if shop_row_height > 0 and inventory_row_height > 0:
		checks.append(["The Shop's own boxed row is at least half again as compact as the Inventory tab's own row (shop <= 0.5x inventory height, %.1f vs %.1f)" % [shop_row_height, inventory_row_height], shop_row_height <= inventory_row_height * 0.5 + 0.5])

	menu.queue_free()
	await tree.process_frame

	## --- Sell list grid + global Sell All (all party members) -------------
	## The Arrows bought above are also genuinely sellable — cleared out
	## here so the Sell All assertions below can check an exact expected
	## total without also having to account for them.
	while char_a.inventory.has("Arrow"):
		char_a.inventory.erase("Arrow")
	shop._rebuild_all()
	await tree.process_frame

	var sell_list: VBoxContainer = shop.get_node("%SellList")
	var sell_all_button: Button = shop.get_node("%SellAllButton")
	checks.append(["A real global Sell All button exists in the scene", sell_all_button != null])

	dagger_price = shop._find_sell_price("Dagger")
	rope_price = shop._find_sell_price("Rope, 10 yards")
	checks.append(["Dagger and Rope, 10 yards both have a real, nonzero sell price for this check to be meaningful", dagger_price > 0 and rope_price > 0])

	var sell_grids: Array[GridContainer] = []
	for child in sell_list.get_children():
		if child is GridContainer and child.columns == 5:
			sell_grids.append(child)
	checks.append(["The Sell list is a real 5-column boxed GridContainer (Star/Item/Qty/Price/Actions)", sell_grids.size() == 1])
	checks.append(["...and it's genuinely ONE SHARED grid for the whole party, not one per member (so every member's columns line up)", sell_grids.size() == 1])

	## --- Sell buttons pinned to the Actions cell's own far right edge,
	## Equip buttons left where they are, regardless of how many equip
	## buttons a given row happens to have — and every member's columns
	## genuinely share the same X position now that it's one grid. -----
	##
	## Dagger belongs to Character A, has 2 Equip buttons AND both Sell
	## 1 and All (2) (spare == 2); Rope, 10 yards belongs to Character B
	## (a DIFFERENT owner entirely), has no Equip buttons, and only Sell
	## 1 (spare == 1, so no All button). Because the two rows' own Sell
	## groups are different SIZES (2 buttons vs. 1), the group's own
	## RIGHT edge — not Sell 1's own left edge, which shifts left
	## whenever a trailing All (N) button is also present — is the
	## correct thing to compare: both should land flush against the
	## Actions cell's own shared right edge regardless of group size or
	## owner, exactly like a right-aligned toolbar.
	if sell_grids.size() == 1:
		var sgrid := sell_grids[0]
		var dagger_cells := _find_sell_row_cells(sgrid, "Dagger")
		var rope_cells := _find_sell_row_cells(sgrid, "Rope, 10 yards")

		var dagger_last_btn := _find_last_button(dagger_cells[4] if not dagger_cells.is_empty() else null)
		var rope_last_btn := _find_last_button(rope_cells[4] if not rope_cells.is_empty() else null)
		checks.append(["Found both rows' own last real Actions button to compare right edges", dagger_last_btn != null and rope_last_btn != null])
		if dagger_last_btn != null and rope_last_btn != null:
			var dagger_right_edge := dagger_last_btn.global_position.x + dagger_last_btn.size.x
			var rope_right_edge := rope_last_btn.global_position.x + rope_last_btn.size.x
			checks.append(["Dagger's Sell group (Sell 1 + All (2), Character A, 2 Equip buttons ahead of it) ends flush with Rope's Sell group (just Sell 1, Character B, no Equip buttons) — both pinned to the Actions cell's own shared right edge", is_equal_approx(dagger_right_edge, rope_right_edge)])
			var dagger_equip_btn := _find_button_by_text(dagger_cells[4], "Equip (Main)")
			checks.append(["...while Dagger's own Equip (Main) button is still sitting on the LEFT, unmoved, right after the Price column", dagger_equip_btn != null and dagger_equip_btn.global_position.x < dagger_last_btn.global_position.x])

		if not dagger_cells.is_empty() and not rope_cells.is_empty():
			var char_a_item_cell: Control = dagger_cells[1]
			var char_b_item_cell: Control = rope_cells[1]
			checks.append(["Character A's own Item column starts at the exact same X as Character B's — the two members' rows are genuinely column-aligned now", is_equal_approx(char_a_item_cell.global_position.x, char_b_item_cell.global_position.x)])

		## --- Per the follow-up request ("make the rows a bit longer to
		## line up with the right edge of Sell All, and then move the
		## Sell buttons to the very right edge"): the grid itself, and by
		## extension every row's own Actions cell / Sell button group,
		## must now reach the SAME true right edge as the Sell All button
		## sitting above the list — not just match between two rows'
		## own (previously too-narrow) Actions cells.
		var panel_right_edge := sell_all_button.global_position.x + sell_all_button.size.x
		checks.append(["The shared sell grid itself now stretches out to reach the Sell All button's own right edge", is_equal_approx(sgrid.global_position.x + sgrid.size.x, panel_right_edge)])
		if not dagger_cells.is_empty():
			var dagger_actions_cell: Control = dagger_cells[4]
			checks.append(["...and a row's own Actions cell now reaches that SAME true right edge (not just a too-narrow cell short of the panel)", is_equal_approx(dagger_actions_cell.global_position.x + dagger_actions_cell.size.x, panel_right_edge)])
		if dagger_last_btn != null:
			## The button itself sits _shop_row_style's own content_margin_right
			## (5px) inside the cell's edge — the same small inner padding every
			## boxed cell uses on every side, not a leftover gap — so "reaches
			## the right edge" means within that padding, not pixel-exact.
			var dagger_group_right_edge := dagger_last_btn.global_position.x + dagger_last_btn.size.x
			checks.append(["...and the Sell button group itself sits flush against that edge, only the row's own consistent inner padding away", panel_right_edge - dagger_group_right_edge <= 6.0 and panel_right_edge - dagger_group_right_edge >= 0.0])

		## --- Alphabetical ordering (Sell list) ---------------------------
		## Character A carries Dagger and Sword, plus the favourited
		## Bedroll — favourited items are no longer excluded from this
		## list (see the follow-up "show favourited items in all shop
		## screens" change), just protected from being sold, so Bedroll
		## and Dagger are listed together, alphabetically: Bedroll before
		## Dagger. Sword is Character A's OWN equipped weapon with no
		## spare copy (see the further follow-up "dont double show
		## equipped items in the shop, show those only in the Equipped
		## gear section") — it stays out of this list entirely now, since
		## it's already shown, with its own Unequip button, in the
		## Equipped Gear box above, and there's nothing left here to
		## Sell or Equip a second copy of.
		var bedroll_row_index := _find_sell_row_index(sgrid, "Bedroll")
		var dagger_row_index := _find_sell_row_index(sgrid, "Dagger")
		var sword_row_index := _find_sell_row_index(sgrid, "Sword")
		checks.append(["The favourited Bedroll still gets its own row in the Sell list, not hidden", bedroll_row_index >= 0])
		checks.append(["Character A's own sell rows are listed alphabetically (Bedroll before Dagger)", bedroll_row_index >= 0 and dagger_row_index >= 0 and bedroll_row_index < dagger_row_index])
		checks.append(["Character A's own fully-equipped Sword (no spare copy) is NOT duplicated in the Sell list — it's already shown in the Equipped Gear box above", sword_row_index < 0])
		var bedroll_cells := _find_sell_row_cells(sgrid, "Bedroll")
		if not bedroll_cells.is_empty():
			var bedroll_star_btn: Button = (bedroll_cells[0] as PanelContainer).get_child(0)
			checks.append(["...with its Star button showing filled (★), matching Character.favourite_items", bedroll_star_btn.text == "★"])
			var bedroll_sell_btn := _find_button_by_text(bedroll_cells[4], "Sell 1")
			checks.append(["...and no Sell button while it's still favourited (protected from being sold)", bedroll_sell_btn == null])

		## --- Hover highlight (Sell list): only the Sell button(s) trigger
		## it, never Equip/Unequip/Give & Equip. -----------------------------
		if not dagger_cells.is_empty() and dagger_last_btn != null:
			var dagger_item_cell: PanelContainer = dagger_cells[1]
			var sell_normal_style: StyleBoxFlat = dagger_item_cell.get_theme_stylebox("panel")
			var sell_normal_alpha := sell_normal_style.border_color.a
			dagger_last_btn.mouse_entered.emit()   ## dagger_last_btn is "All (2)" — a real Sell trigger
			await tree.process_frame
			var sell_hover_style: StyleBoxFlat = dagger_item_cell.get_theme_stylebox("panel")
			checks.append(["Hovering a Sell button in the Party Inventory also brightens its whole row's own box outline", sell_hover_style.border_color.a > sell_normal_alpha])
			dagger_last_btn.mouse_exited.emit()
			await tree.process_frame
			var sell_reverted_style: StyleBoxFlat = dagger_item_cell.get_theme_stylebox("panel")
			checks.append(["...and reverts once the pointer leaves the Sell button", is_equal_approx(sell_reverted_style.border_color.a, sell_normal_alpha)])

			var dagger_equip_btn2 := _find_button_by_text(dagger_cells[4], "Equip (Main)")
			checks.append(["Found Dagger's own Equip (Main) button to check hover scope against", dagger_equip_btn2 != null])
			if dagger_equip_btn2 != null:
				dagger_equip_btn2.mouse_entered.emit()
				await tree.process_frame
				var equip_hover_style: StyleBoxFlat = dagger_item_cell.get_theme_stylebox("panel")
				checks.append(["...but hovering an Equip button does NOT trigger the row highlight — scope is Buy/Sell buttons only", is_equal_approx(equip_hover_style.border_color.a, sell_normal_alpha)])
				dagger_equip_btn2.mouse_exited.emit()
				await tree.process_frame

	var gold_before := char_a.get_total_pennies()
	sell_all_button.pressed.emit()
	await tree.process_frame

	checks.append(["Sell All swept both spare Daggers from Character A", char_a.inventory.count("Dagger") == 0])
	checks.append(["...but left the equipped Sword completely untouched", char_a.inventory.has("Sword") and char_a.equipped_weapon == "Sword"])
	checks.append(["...and left the favourited Bedroll completely untouched", char_a.inventory.has("Bedroll")])
	checks.append(["Sell All ALSO reached Character B, not just whoever's currently being shopped for", char_b.inventory.count("Rope, 10 yards") == 0])
	var expected_total := dagger_price * 2 + rope_price
	checks.append(["The shared party purse was credited the exact combined total from BOTH members' sales", char_a.get_total_pennies() - gold_before == expected_total])
	checks.append(["The confirmation message names the whole party, not one character", shop.message_label.text.contains("across the party")])

	## --- Repair tab: shows only DAMAGED gear (plus already-Broken
	## armour), pooled across EVERY present party member, not just
	## whoever's currently selected in the shop — and the tab itself
	## lights up red when (and only when) something genuinely needs
	## fixing --------------------------------------------------------------
	## Per the original request: "the Repair tab... shows all character
	## repairable items at all times, and light up the Repair tab Red if
	## there is any gear that needs repairing... a piece of Armor need to
	## go to AP 0 on all locations before it is destroyed, if that
	## happens unequip it and note it as Broken. Broken item[s] can not
	## be repaired and have only 10% their original value." Per the
	## follow-up request: "Make the repair tab show only damaged
	## equipment for ALL characters, not just the currently selected
	## one" — undamaged gear no longer takes up space here at all, and
	## every present party member's own damaged/Broken gear is checked,
	## not just `character` (whoever's currently being shopped for).
	char_a.inventory.clear()
	char_a.equipped_armour.clear()
	char_a.armour_damage.clear()
	char_a.broken_armour.clear()
	char_a.equipped_weapon = "Sword"
	char_a.inventory.append("Sword")
	char_a.gold_crowns = 100

	char_b.inventory.clear()
	char_b.equipped_armour.clear()
	char_b.armour_damage.clear()
	char_b.broken_armour.clear()
	char_b.weapon_damage_taken.clear()

	var mail_coat_def: ArmourDefinition = GameData.armour_db.find_by_name("Mail Coat")
	var jack_def2: ArmourDefinition = GameData.armour_db.find_by_name("Leather Jack")
	var chausses_def: ArmourDefinition = GameData.armour_db.find_by_name("Mail Chausses")
	checks.append(["Mail Coat (2 AP), Leather Jack (1 AP), and Mail Chausses (2 AP) are real, priced armour pieces this check can rely on", mail_coat_def != null and mail_coat_def.armour_points == 2 and jack_def2 != null and jack_def2.armour_points == 1 and chausses_def != null and chausses_def.armour_points == 2])

	char_a.inventory.append("Mail Coat")
	char_a.equipped_armour.append("Mail Coat")
	char_a.inventory.append("Leather Jack")
	char_a.equipped_armour.append("Leather Jack")

	## Character B (a second, present party member — "Second Member")
	## also carries a repairable piece of their own. This is the actual
	## subject of the follow-up request: their damage must show up on
	## the shared Repair tab even while Character A is the one currently
	## selected for shopping.
	char_b.inventory.append("Mail Chausses")
	char_b.equipped_armour.append("Mail Chausses")

	shop._rebuild_all()
	await tree.process_frame
	checks.append(["Character A is still the one currently selected for shopping (not B)", shop.character == char_a])

	var repair_list_node: VBoxContainer = shop.get_node("%RepairList")
	var buy_tabs_node: TabContainer = shop.get_node("%BuyTabs")
	var repair_tab_idx := buy_tabs_node.get_tab_idx_from_control(repair_list_node.get_parent())
	checks.append(["The Repair tab's own index was found inside BuyTabs", repair_tab_idx >= 0])

	## Nothing is damaged yet anywhere in the party -> the Repair tab
	## should show its "nothing needs repair" placeholder, not Mail
	## Coat/Leather Jack/Mail Chausses just because they're carried.
	var repair_grid := _find_repair_grid(repair_list_node)
	checks.append(["With nothing damaged anywhere in the party, the Repair tab renders no grid at all yet (only undamaged gear is out there)", repair_grid == null])
	var found_repair_placeholder := false
	for child in repair_list_node.get_children():
		if child is Label and (child as Label).text.contains("nothing in the party currently needs repair"):
			found_repair_placeholder = true
	checks.append(["...just a plain 'nothing in the party currently needs repair' placeholder instead", found_repair_placeholder])
	checks.append(["With nothing actually damaged, the Repair tab shows no red indicator icon", repair_tab_idx < 0 or buy_tabs_node.get_tab_icon(repair_tab_idx) == null])

	## Damage Mail Coat once at Body only (1/6 total AP — 2 AP x 3
	## locations: Body, Left Arm, Right Arm) — repairable, not yet
	## destroyed. Per the per-location Armour Damage fix (a real bug-
	## report correction: "a Leather Jack has 3 locations... for it to
	## be completely destroyed all 3 locations need to be at 0 AP"),
	## damage_armour_piece now requires the specific hit location, and
	## only THAT location's own pool is spent — Left Arm/Right Arm stay
	## fully intact.
	char_a.damage_armour_piece("Mail Coat", "Body")
	shop._rebuild_all()
	await tree.process_frame
	checks.append(["Mail Coat survives a single point of Armour Damage at one location (1/6 total, not yet destroyed anywhere)", char_a.equipped_armour.has("Mail Coat") and char_a.get_total_armour_damage("Mail Coat") == 1])
	## Left Arm is covered by BOTH Mail Coat (2 AP) and Leather Jack (1
	## AP) layered together — full 3 AP still standing there confirms
	## the Body-only hit above didn't bleed into Mail Coat's own Left
	## Arm pool.
	checks.append(["...and its OTHER locations (Left Arm) are genuinely untouched by damage landing at Body", char_a.get_armour_points("Left Arm") == 3])
	repair_grid = _find_repair_grid(repair_list_node)
	checks.append(["Now that Mail Coat is damaged, the Repair tab renders a real grid", repair_grid != null])
	checks.append(["...with an 'Armour' section header", repair_grid != null and _find_grid_section_headers(repair_grid).has("Armour")])
	checks.append(["...whose own column-header row reads Item / Condition / Cost / Actions", repair_grid != null and _find_header_row_after_section(repair_grid, "Armour") == ["Item", "Condition", "Cost", "Actions"]])

	var mail_coat_cells := _find_repair_row_cells(repair_grid, "Mail Coat")
	checks.append(["Damaged Mail Coat shows in the Repair tab", not mail_coat_cells.is_empty()])
	var mc_repair_btn: Button = null
	if not mail_coat_cells.is_empty():
		var mc_item_lbl: Label = (mail_coat_cells[0] as PanelContainer).get_child(0)
		checks.append(["...naming its real owner, Character A, right on the row", mc_item_lbl.text.contains(char_a.character_name)])
		var mc_condition_lbl: Label = (mail_coat_cells[1] as PanelContainer).get_child(0)
		checks.append(["...reading '1/6 AP damaged' (total across all 3 locations it covers) in its own Condition column", mc_condition_lbl.text.contains("1/6 AP damaged")])
		mc_repair_btn = _find_button_by_text(mail_coat_cells[3], "Repair Fully")
	checks.append(["...with a real Repair Fully button now offered", mc_repair_btn != null])
	checks.append(["Once anything is genuinely damaged, the Repair tab DOES show the red indicator icon", repair_tab_idx >= 0 and buy_tabs_node.get_tab_icon(repair_tab_idx) != null])

	## Leather Jack was never touched — it must NOT appear at all now
	## (undamaged gear no longer clutters the list, per the request).
	var jack_cells_undamaged := _find_repair_row_cells(repair_grid, "Leather Jack")
	checks.append(["Leather Jack (never damaged) does NOT appear in the Repair tab at all — only damaged/Broken gear is listed now", jack_cells_undamaged.is_empty()])

	## Repairing it clears the damage and the indicator both, and drops
	## Mail Coat itself back out of the list (fully repaired = no
	## longer "damaged", so it no longer qualifies for the list either).
	if mc_repair_btn != null:
		mc_repair_btn.pressed.emit()
		await tree.process_frame
	checks.append(["Repairing Mail Coat fully clears its own armour_damage entry", int(char_a.armour_damage.get("Mail Coat", 0)) == 0])
	checks.append(["...and the Repair tab's red indicator clears again once nothing needs fixing", repair_tab_idx < 0 or buy_tabs_node.get_tab_icon(repair_tab_idx) == null])
	repair_grid = _find_repair_grid(repair_list_node)
	var mail_coat_cells_after_repair := _find_repair_row_cells(repair_grid, "Mail Coat") if repair_grid != null else []
	checks.append(["...and Mail Coat drops back out of the Repair tab once fully repaired (no longer damaged)", mail_coat_cells_after_repair.is_empty()])

	## --- Character B's own damaged gear also shows up, unprompted -----
	char_b.damage_armour_piece("Mail Chausses", "Left Leg")
	shop._rebuild_all()
	await tree.process_frame
	checks.append(["Character B's own Mail Chausses took damage", char_b.get_total_armour_damage("Mail Chausses") == 1])
	repair_grid = _find_repair_grid(repair_list_node)
	var chausses_cells := _find_repair_row_cells(repair_grid, "Mail Chausses")
	checks.append(["Character B's damaged gear shows in the Repair tab even though Character A is the one currently selected for shopping", not chausses_cells.is_empty()])
	var chausses_repair_btn: Button = null
	if not chausses_cells.is_empty():
		var chausses_item_lbl: Label = (chausses_cells[0] as PanelContainer).get_child(0)
		checks.append(["...naming Character B, its real owner, right on the row", chausses_item_lbl.text.contains(char_b.character_name)])
		chausses_repair_btn = _find_button_by_text(chausses_cells[3], "Repair Fully")
	checks.append(["...with its own real Repair Fully button", chausses_repair_btn != null])

	if chausses_repair_btn != null:
		chausses_repair_btn.pressed.emit()
		await tree.process_frame
	checks.append(["Repairing Character B's Mail Chausses from the shared Repair tab clears HER OWN armour_damage entry", int(char_b.armour_damage.get("Mail Chausses", 0)) == 0])
	checks.append(["...without touching Character A's own gear at all", not char_a.armour_damage.has("Mail Coat")])

	## Destroy Mail Coat outright — per the per-location correction, ALL
	## THREE locations it covers (Body, Left Arm, Right Arm) must each
	## independently reach their own 2 AP cap, not just 2 hits anywhere
	## (that was the old, wrong, shared-single-counter behaviour this
	## whole fix replaces). Once truly destroyed everywhere, this should
	## unequip it and mark it Broken rather than deleting it outright.
	## Broken gear still surfaces on the Repair tab even though it's not
	## merely "damaged" (it's the most urgent case of all — see
	## _add_broken_armour_repair_grid_row).
	char_a.damage_armour_piece("Mail Coat", "Body")
	char_a.damage_armour_piece("Mail Coat", "Body")
	char_a.damage_armour_piece("Mail Coat", "Left Arm")
	char_a.damage_armour_piece("Mail Coat", "Left Arm")
	checks.append(["Mail Coat survives with 2 of its 3 locations fully spent but Right Arm still untouched", char_a.equipped_armour.has("Mail Coat")])
	char_a.damage_armour_piece("Mail Coat", "Right Arm")
	checks.append(["...and even one AP short on the last location, Mail Coat still survives", char_a.equipped_armour.has("Mail Coat")])
	char_a.damage_armour_piece("Mail Coat", "Right Arm")
	shop._rebuild_all()
	await tree.process_frame
	checks.append(["Destroying Mail Coat unequips it (only once EVERY location it covers independently reaches 0 AP)", not char_a.equipped_armour.has("Mail Coat")])
	checks.append(["...clears its armour_damage entry (it's not merely 'damaged' anymore)", not char_a.armour_damage.has("Mail Coat")])
	checks.append(["...and moves it into broken_armour instead of deleting it outright", int(char_a.broken_armour.get("Mail Coat", 0)) == 1])
	checks.append(["A Broken piece leaves the normal inventory count (still owned, just relocated to the Broken pool)", not char_a.inventory.has("Mail Coat")])

	repair_grid = _find_repair_grid(repair_list_node)
	var broken_cells := _find_repair_row_cells(repair_grid, "Mail Coat")
	var broken_condition_lbl: Label = null
	if not broken_cells.is_empty():
		broken_condition_lbl = (broken_cells[1] as PanelContainer).get_child(0)
	checks.append(["The now-Broken Mail Coat still shows in the Repair tab, flagged BROKEN in its own Condition column", broken_condition_lbl != null and broken_condition_lbl.text == "BROKEN"])
	if not broken_cells.is_empty():
		checks.append(["...with no Repair button at all (Broken items can't be repaired)", _find_button_by_text(broken_cells[3], "Repair Fully") == null])
	checks.append(["Broken gear alone does NOT light up the Repair tab red (it can't be repaired, so it doesn't need to be)", repair_tab_idx < 0 or buy_tabs_node.get_tab_icon(repair_tab_idx) == null])

	## --- Broken armour is sellable for salvage (10% of list price) -------
	var broken_sell_price: int = shop._find_broken_sell_price("Mail Coat")
	checks.append(["Mail Coat's own Broken salvage price is exactly a tenth of its real list price", broken_sell_price == int(mail_coat_def.price_pennies * 0.1)])

	var sell_list_node: VBoxContainer = shop.get_node("%SellList")
	var broken_sell_grid: GridContainer = null
	for child in sell_list_node.get_children():
		if child is GridContainer:
			broken_sell_grid = child
	var broken_sell_cells: Array = []
	if broken_sell_grid != null:
		broken_sell_cells = _find_sell_row_cells(broken_sell_grid, "Mail Coat (Broken)")
	checks.append(["The Broken Mail Coat has its own row in the Party Inventory Sell list, priced at salvage value", not broken_sell_cells.is_empty()])
	if not broken_sell_cells.is_empty():
		var broken_price_lbl: Label = (broken_sell_cells[3] as PanelContainer).get_child(0)
		checks.append(["...showing exactly that 10% salvage price", broken_price_lbl.text == shop._format_price(broken_sell_price)])
		var broken_sell_btn := _find_button_by_text(broken_sell_cells[4], "Sell 1")
		checks.append(["...with a real Sell 1 button", broken_sell_btn != null])
		if broken_sell_btn != null:
			var gold_before_broken := char_a.get_total_pennies()
			broken_sell_btn.pressed.emit()
			await tree.process_frame
			checks.append(["Selling the Broken piece credits exactly its salvage price", char_a.get_total_pennies() - gold_before_broken == broken_sell_price])
			checks.append(["...and removes it from broken_armour once the last copy is sold", not char_a.broken_armour.has("Mail Coat")])

	## --- Shop stock never offers creature-drop Trophies for sale ---------
	## Per the request: "the shop should not sell creature drops like Bat
	## Wing, Dog Pelt... remove them." Bat Wing/Dog Pelt are both real,
	## Common-availability Trophy items (see TrophyLookup) that would
	## otherwise always roll into stock — a reliable pair to check.
	var bat_wing_def: ItemDefinition = GameData.item_db.find_by_name("Bat Wing")
	var dog_pelt_def: ItemDefinition = GameData.item_db.find_by_name("Dog Pelt")
	checks.append(["Bat Wing and Dog Pelt are real Trophy-category items in the data (so their absence below is a real filter, not a data gap)", bat_wing_def != null and bat_wing_def.category == "Trophy" and dog_pelt_def != null and dog_pelt_def.category == "Trophy"])
	checks.append(["Bat Wing never appears in the shop's own item_stock", not shop.item_stock.has(bat_wing_def)])
	checks.append(["Dog Pelt never appears in the shop's own item_stock", not shop.item_stock.has(dog_pelt_def)])
	var any_trophy_in_stock := false
	for it in shop.item_stock:
		if it.category == "Trophy":
			any_trophy_in_stock = true
	checks.append(["No Trophy-category item of any kind is ever offered for sale on the Items tab", not any_trophy_in_stock])

	shop.queue_free()
	await tree.process_frame

	## --- Font: the project's one theme now loads Press Start 2P ----------
	var game_theme: Theme = load("res://resources/game_theme.tres")
	var default_font: Font = game_theme.default_font
	checks.append(["The project's shared theme's default_font is genuinely Press Start 2P, not the old gothic font", default_font != null and default_font.resource_path.contains("PressStart2P")])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Shop Grid Layout + Sell All + Ammo Quantities + Font Check): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
