extends RefCounted
class_name CraftingTest
## Regression/functional test for the Crafting page (per the request:
## "add a Crafting page to shops, allowing characters to order Crafted
## Weapon's or Armor with any amount of any quality (each one doubles
## the price of the item)... Crafting time will be 2 days per
## quality"). Drives a real ShopScreen instance (same "real scene
## instantiation" convention as shop_grid_test.gd) through its actual
## Crafting tab state and real button presses for both placing and
## collecting an order, confirming: the order genuinely deducts
## payment; registers a new WeaponDefinition/ArmourDefinition with the
## right derived stats; is queued rather than handed over immediately;
## stays queued (per the follow-up request "make it so User needs to
## pick up items when crafting time is finished, rather then appearing
## in inventory") even once real in-game time (via
## GameState.advance_days(), the same production call travel/Sleep
## use) reaches its own 2-days-per-Quality lead time; and is only
## actually delivered into the ordering character's own inventory once
## the Crafting tab's own "Collect" button is pressed. Also covers the
## base-item picker only ever offering true base items (per the further
## follow-up "Crafting item list should only include base items, so
## without Fine/Durable/Lightweight etc.") — never a static Quality-
## variant already in the shop's own catalog, nor a previously-crafted
## item.

static func _find_button_with_text(root: Node, text: String) -> Button:
	for child in root.get_children():
		if child is Button and child.text == text:
			return child
		var found := _find_button_with_text(child, text)
		if found != null:
			return found
	return null

static func _find_option_button(root: Node) -> OptionButton:
	for child in root.get_children():
		if child is OptionButton:
			return child
		var found := _find_option_button(child)
		if found != null:
			return found
	return null

static func _option_button_items(picker: OptionButton) -> Array[String]:
	var items: Array[String] = []
	for i in range(picker.item_count):
		items.append(picker.get_item_text(i))
	return items

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "CraftTester"
	pc.inventory.clear()
	pc.gold_crowns = 1000
	pc.silver_shillings = 0
	pc.brass_pennies = 0

	var shop_scene: PackedScene = load("res://scenes/Shop.tscn")
	var shop: Node = shop_scene.instantiate()
	tree.get_root().add_child.call_deferred(shop)
	await tree.process_frame
	await tree.process_frame

	## --- Village gating (per the request: "crafting should not be
	## available in the Village shop, only in cities") -------------------
	checks.append(["A default Village-tier shop hides the Crafting tab (index 4)", shop.buy_tabs.is_tab_hidden(4)])

	## --- Base-item picker only offers true base items (per the request:
	## "Crafting item list should only include base items, so without
	## Fine/Durable/Lightweight etc."), for both Weapon and Armour. -------
	shop._craft_type = "weapon"
	shop._craft_base_name = ""
	shop._rebuild_crafting_list()
	await tree.process_frame
	var weapon_picker := _find_option_button(shop.crafting_list)
	checks.append(["setup: found the real base-item OptionButton (Weapon)", weapon_picker != null])
	if weapon_picker != null:
		var weapon_names := _option_button_items(weapon_picker)
		checks.append(["The Weapon base-item picker includes plain 'Sword'", weapon_names.has("Sword")])
		checks.append(["The Weapon base-item picker includes plain 'Axe'", weapon_names.has("Axe")])
		checks.append(["...but does NOT include the static shop-stock 'Fine Axe' Quality variant", not weapon_names.has("Fine Axe")])
		var any_quality_prefixed := false
		for n in weapon_names:
			if n.begins_with("Fine ") or n.begins_with("Durable ") or n.begins_with("Lightweight ") or n.begins_with("Practical "):
				any_quality_prefixed = true
		checks.append(["...and no entry at all carries a Quality-name prefix (Fine/Durable/Lightweight/Practical)", not any_quality_prefixed])

	shop._craft_type = "armour"
	shop._craft_base_name = ""
	shop._rebuild_crafting_list()
	await tree.process_frame
	var armour_picker := _find_option_button(shop.crafting_list)
	checks.append(["setup: found the real base-item OptionButton (Armour)", armour_picker != null])
	if armour_picker != null:
		var armour_names := _option_button_items(armour_picker)
		checks.append(["The Armour base-item picker includes plain 'Mail Coat'", armour_names.has("Mail Coat")])
		checks.append(["...but does NOT include the static shop-stock 'Lightweight Mail Coat' Quality variant", not armour_names.has("Lightweight Mail Coat")])
		checks.append(["...nor the static shop-stock 'Durable Mail Coat' Quality variant", not armour_names.has("Durable Mail Coat")])

	## --- Weapon order: Sword + Durable 2 + Fine (3 Quality points) -----
	var sword_def: WeaponDefinition = GameData.weapon_db.find_by_name("Sword")
	checks.append(["setup: found the real Sword definition to commission a custom copy of", sword_def != null])

	shop._craft_type = "weapon"
	shop._craft_base_name = "Sword"
	shop._craft_quality_counts = {"Durable": 2, "Fine": 1, "Lightweight": 0, "Practical": 0}
	shop._rebuild_crafting_list()
	await tree.process_frame

	var order_btn := _find_button_with_text(shop.crafting_list, "Place Order")
	checks.append(["setup: found the real Place Order button", order_btn != null])
	if order_btn != null:
		checks.append(["3 Quality points (Durable 2 + Fine) is affordable at 8x a 240d Sword -- button isn't disabled", not order_btn.disabled])

	var pennies_before := pc.get_total_pennies()
	var now_before := GameState.time_minutes_total()
	var orders_before: int = GameState.pending_craft_orders.size()

	if order_btn != null:
		order_btn.pressed.emit()
	await tree.process_frame

	var expected_price: int = sword_def.price_pennies * 8   ## 2^3 Quality points
	checks.append(["Placing the order spent exactly the doubled-per-Quality price (240d x 8 = 1920d)", pennies_before - pc.get_total_pennies() == expected_price])
	checks.append(["...and queued exactly one new pending order", GameState.pending_craft_orders.size() == orders_before + 1])

	var placed_order: Dictionary = {}
	for order in GameState.pending_craft_orders:
		if order.get("character_name", "") == "CraftTester":
			placed_order = order
	checks.append(["The queued order is for the real ordering character", placed_order.get("character_name", "") == "CraftTester"])
	checks.append(["...tagged as a weapon order", placed_order.get("item_type", "") == "weapon"])
	checks.append(["...naming the real composed item (\"Durable 2 Fine Sword\")", placed_order.get("item_name", "") == "Durable 2 Fine Sword"])
	checks.append(["...recording the real Quality-point count (3)", int(placed_order.get("quality_count", 0)) == 3])
	checks.append(["...ready in exactly 2 days-per-Quality x 3 = 6 days from the moment it was placed", int(placed_order.get("ready_at_minutes", 0)) == now_before + 6 * 24 * 60])

	var crafted_wd: WeaponDefinition = GameData.weapon_db.find_by_name("Durable 2 Fine Sword")
	checks.append(["A real new WeaponDefinition was registered for the crafted item", crafted_wd != null])
	if crafted_wd != null:
		checks.append(["...priced at the same doubled-per-Quality total", crafted_wd.price_pennies == expected_price])
		checks.append(["...shifted 3 Availability steps from the base Sword's Common all the way to Exotic", crafted_wd.availability == "Exotic"])
		checks.append(["...carrying its own real item_qualities (Durable 2, Fine)", crafted_wd.item_qualities == ["Durable 2", "Fine"]])
		checks.append(["...but still the same real Sword stats otherwise (damage_flat)", crafted_wd.damage_flat == sword_def.damage_flat])

	checks.append(["The item is NOT handed over immediately -- it's a queued order, not an instant purchase", not pc.inventory.has("Durable 2 Fine Sword")])
	checks.append(["...and isn't reported ready yet either, immediately after ordering", not GameState.is_craft_order_ready(placed_order)])

	## --- Time passes: the real production advance_days() call makes the
	## order READY, per the follow-up request ("make it so User needs to
	## pick up items when crafting time is finished, rather then
	## appearing in inventory") this must NOT hand the item over on its
	## own any more -- it just becomes collectible. ----------------------
	GameState.advance_days(6)
	checks.append(["Once 6 real in-game days pass, the order reports itself ready", GameState.is_craft_order_ready(placed_order)])
	checks.append(["...but the item is still NOT auto-delivered into inventory", not pc.inventory.has("Durable 2 Fine Sword")])
	checks.append(["...and still genuinely sits in the pending queue, waiting to be collected", GameState.pending_craft_orders.size() == orders_before + 1])

	## --- Only pressing the real "Collect" button actually delivers it --
	shop._rebuild_crafting_list()
	await tree.process_frame
	var collect_btn := _find_button_with_text(shop.crafting_list, "Collect")
	checks.append(["setup: found the real Collect button for the now-ready order", collect_btn != null])
	if collect_btn != null:
		collect_btn.pressed.emit()
	await tree.process_frame

	checks.append(["Pressing Collect delivers the crafted Sword into the ordering character's own inventory", pc.inventory.has("Durable 2 Fine Sword")])
	checks.append(["...and the fulfilled order is removed from the pending queue", GameState.pending_craft_orders.is_empty()])

	## --- Collecting an order that's already been collected (stale
	## order_id) is a safe no-op, not a crash or a double-delivery. ------
	var stale_order_id: int = int(placed_order.get("order_id", -1))
	var double_collect_ok: bool = not GameState.collect_craft_order(stale_order_id)
	checks.append(["Re-collecting an already-collected order_id is refused, not a duplicate delivery", double_collect_ok])

	## --- Insufficient funds: the guard refuses without spending/queueing
	pc.gold_crowns = 0
	pc.silver_shillings = 0
	pc.brass_pennies = 0
	var orders_before_broke: int = GameState.pending_craft_orders.size()
	shop._on_place_craft_order(Array(["Fine"], TYPE_STRING, "", null), 1, 999999999, "Exotic")
	checks.append(["An unaffordable order is refused -- no pennies spent (still at 0)", pc.get_total_pennies() == 0])
	checks.append(["...and nothing gets queued", GameState.pending_craft_orders.size() == orders_before_broke])

	## --- Armour order that EXACTLY matches an existing static shop-stock
	## Quality variant: the same real "Lightweight Mail Coat" catalog
	## entry the Armour tab already stocks (see core_armour.tres) should
	## be REUSED, not duplicated. ------------------------------------------
	pc.gold_crowns = 1000
	var mail_coat_def: ArmourDefinition = GameData.armour_db.find_by_name("Mail Coat")
	checks.append(["setup: found the real Mail Coat definition", mail_coat_def != null])
	var existing_lw_coat: ArmourDefinition = GameData.armour_db.find_by_name("Lightweight Mail Coat")
	checks.append(["setup: 'Lightweight Mail Coat' already exists as a static shop-stock Quality variant", existing_lw_coat != null])
	var armour_count_before := GameData.armour_db.pieces.size()

	shop._craft_type = "armour"
	shop._craft_base_name = "Mail Coat"
	shop._craft_quality_counts = {"Durable": 0, "Fine": 0, "Lightweight": 1, "Practical": 0}
	shop._rebuild_crafting_list()
	await tree.process_frame
	var armour_order_btn := _find_button_with_text(shop.crafting_list, "Place Order")
	if armour_order_btn != null:
		armour_order_btn.pressed.emit()
	await tree.process_frame

	checks.append(["Ordering the exact same combination an existing catalog entry already covers does NOT create a duplicate definition", GameData.armour_db.pieces.size() == armour_count_before])
	checks.append(["...the existing entry's own price is untouched (still the statically-authored 2x)", GameData.armour_db.find_by_name("Lightweight Mail Coat").price_pennies == mail_coat_def.price_pennies * 2])
	var armour_order: Dictionary = {}
	for order in GameState.pending_craft_orders:
		if order.get("item_type", "") == "armour":
			armour_order = order
	checks.append(["The armour order was still genuinely queued (reusing the existing definition doesn't mean skipping the order itself)", armour_order.get("item_name", "") == "Lightweight Mail Coat"])

	shop.queue_free()
	await tree.process_frame

	## --- Village gating, City side: a real Ubersreik-style shop visit
	## (same GameState fields CityScreen._enter_shop() sets) must show
	## the Crafting tab. -----------------------------------------------
	GameState.pending_shop_city_id = "ubersreik"
	GameState.pending_shop_settlement_tier = "City"
	GameState.pending_shop_settlement_name = "Ubersreik"
	var city_shop: Node = shop_scene.instantiate()
	tree.get_root().add_child.call_deferred(city_shop)
	await tree.process_frame
	await tree.process_frame
	checks.append(["A City-tier shop (Ubersreik) shows the Crafting tab (index 4)", not city_shop.buy_tabs.is_tab_hidden(4)])
	city_shop.queue_free()
	await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Crafting Page): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
