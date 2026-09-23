extends RefCounted
class_name CordeliaApothecaryTest
## Regression coverage for the request ("Lets hook up Cordelia's
## Apothecary in Ubersreik. She need a shop screen that will only sell
## Healing Draught, Faxtoryll, Salwort and Vitality Draught. No
## Repairing either. Implement Faxtoryll, Salwort and Vitality Draught
## and add options to consume them and gain their benefits during battle
## (hide these until they are needed). Cordelia is a Master Apothecary
## and will always have all items regardless of Availability. Add
## Healing Draught to normal shops too.").
##
## Group 1: the location itself is unlocked, and the 4 items exist with
## the right shape.
## Group 2: visiting Cordelia's specifically (via
## GameState.pending_shop_location_name, the same field CityScreen's
## _enter_shop() now sets for every shop visit) gets the restricted
## Items-only stock, always exactly her 4 items regardless of how many
## times stock is re-rolled (Master Apothecary), and the Weapons/Armour/
## Repair tabs hidden. A DIFFERENT shop visit is completely unaffected.
## Group 3: a normal (non-apothecary) shop's own roll — Healing Draught
## (Scarce) is a real, reachable normal-shop item now; Faxtoryll
## (Exotic) never appears in a normal shop's stock, per the book's own
## p.291 rule, untouched by this feature.
## Group 4: the 3 new battle consumables' real mechanical effects
## (Faxtoryll's +10 WS/+10 BS for 3 Rounds, Vitality Draught's +10
## Toughness/+2 Movement for 6 Rounds, Salwort's instant Stunned cure),
## plus that their own turn-menu buttons are genuinely offered while
## carried and gone once consumed.
## Group 5: the critical fix — Salwort's button is reachable from
## _prompt_incapacitated_turn() (the ONLY place a genuinely Stunned
## character's turn is ever rendered), and using it actually cures
## Stunned and re-enters a real turn rather than leaving the
## incapacitated auto-pass screen stuck.

static func run_test(fe) -> bool:
	var checks: Array = []

	## --- Group 1: location + item data -----------------------------------
	var city_locations: CityLocationList = load("res://data/maps/ubersreik_city_locations.tres")
	var loc: CityLocationDefinition = null
	for l in city_locations.locations:
		if l.location_name == "Cordelia's Apothecary":
			loc = l
	checks.append(["setup: found Cordelia's Apothecary in Ubersreik's own location list", loc != null])
	if loc != null:
		checks.append(["Cordelia's Apothecary is unlocked", loc.unlocked])
		checks.append(["Cordelia's Apothecary is category \"shop\" (routes through the normal shop-entry radial action)", loc.category == "shop"])

	var healing := GameData.item_db.find_by_name("Healing Draught")
	var faxtoryll := GameData.item_db.find_by_name("Faxtoryll")
	var salwort := GameData.item_db.find_by_name("Salwort")
	var vitality := GameData.item_db.find_by_name("Vitality Draught")
	checks.append(["Healing Draught exists in the item database", healing != null])
	checks.append(["Faxtoryll exists in the item database", faxtoryll != null])
	checks.append(["Salwort exists in the item database", salwort != null])
	checks.append(["Vitality Draught exists in the item database", vitality != null])
	if healing != null:
		checks.append(["Healing Draught is Scarce (a real, reachable normal-shop roll)", healing.availability == "Scarce"])
	if faxtoryll != null:
		checks.append(["Faxtoryll is Exotic (never stocked by a normal shop, per p.291)", faxtoryll.availability == "Exotic"])
	if salwort != null:
		checks.append(["Salwort is Common", salwort.availability == "Common"])
	if vitality != null:
		checks.append(["Vitality Draught is Scarce", vitality.availability == "Scarce"])

	## --- Group 2: visiting Cordelia's specifically -----------------------
	GameState.pending_shop_location_name = "Cordelia's Apothecary"
	GameState.pending_shop_settlement_tier = "City"
	GameState.pending_shop_settlement_name = "Ubersreik"
	var shop_scene: PackedScene = load("res://scenes/Shop.tscn")
	var cordelia_shop: Node = shop_scene.instantiate()
	fe.get_tree().get_root().add_child(cordelia_shop)
	for i in range(3):
		await fe.get_tree().process_frame

	checks.append(["Visiting Cordelia's sets is_apothecary true", cordelia_shop.is_apothecary])
	checks.append(["...and pending_shop_location_name was consumed (read once, then cleared)", GameState.pending_shop_location_name == ""])
	checks.append(["The title reflects Cordelia's own shop name, not the generic \"General Store\"", cordelia_shop.title_label.text == "Cordelia's Apothecary"])

	var stock_names: Array = []
	for i in cordelia_shop.item_stock:
		stock_names.append(i.item_name)
	stock_names.sort()
	var expected_names: Array = ["Faxtoryll", "Healing Draught", "Salwort", "Vitality Draught"]
	checks.append(["Cordelia's stock is EXACTLY her 4 items, no more, no less", stock_names == expected_names])
	checks.append(["Cordelia never stocks weapons", cordelia_shop.weapon_stock.is_empty()])
	checks.append(["Cordelia never stocks armour", cordelia_shop.armour_stock.is_empty()])
	checks.append(["Cordelia never stocks separate ammo", cordelia_shop.ammo_stock.is_empty()])

	## Master Apothecary: "will always have all items regardless of
	## Availability" -- re-rolling stock several times must never vary
	## or come up short, unlike a normal shop's per-item dice.
	var always_full := true
	for i in range(5):
		cordelia_shop._roll_stock()
		var names: Array = []
		for it in cordelia_shop.item_stock:
			names.append(it.item_name)
		names.sort()
		if names != expected_names:
			always_full = false
	checks.append(["Master Apothecary: re-rolling stock 5 times always comes back with exactly all 4 items", always_full])

	## Weapons(1)/Armour(2)/Repair(3) tabs hidden, Items(0) still shown.
	checks.append(["The Items tab stays visible for Cordelia", not cordelia_shop.buy_tabs.is_tab_hidden(0)])
	checks.append(["The Weapons tab is hidden for Cordelia (no Repairing either, per the request)", cordelia_shop.buy_tabs.is_tab_hidden(1)])
	checks.append(["The Armour tab is hidden for Cordelia", cordelia_shop.buy_tabs.is_tab_hidden(2)])
	checks.append(["The Repair tab is hidden for Cordelia", cordelia_shop.buy_tabs.is_tab_hidden(3)])
	cordelia_shop.queue_free()
	for i in range(2):
		await fe.get_tree().process_frame

	## --- Group 2b: a DIFFERENT shop visit is completely unaffected -------
	GameState.pending_shop_location_name = "Some Other Shop"
	GameState.pending_shop_settlement_tier = "City"
	GameState.pending_shop_settlement_name = "Ubersreik"
	var other_shop: Node = shop_scene.instantiate()
	fe.get_tree().get_root().add_child(other_shop)
	for i in range(3):
		await fe.get_tree().process_frame
	checks.append(["A different shop name leaves is_apothecary false", not other_shop.is_apothecary])
	checks.append(["...and its tabs are all still visible", not other_shop.buy_tabs.is_tab_hidden(1) and not other_shop.buy_tabs.is_tab_hidden(2) and not other_shop.buy_tabs.is_tab_hidden(3)])
	checks.append(["...and its title is still the generic General Store label", other_shop.title_label.text == "Ubersreik — General Store"])
	other_shop.queue_free()
	for i in range(2):
		await fe.get_tree().process_frame

	## --- Group 3: normal-shop Healing Draught / Faxtoryll regression
	## guard -- 40 fresh rolls at City tier (90% Scarce odds).
	GameState.pending_shop_settlement_tier = "City"
	GameState.pending_shop_settlement_name = "Ubersreik"
	var normal_shop: Node = shop_scene.instantiate()
	fe.get_tree().get_root().add_child(normal_shop)
	for i in range(3):
		await fe.get_tree().process_frame
	var healing_seen := 0
	var faxtoryll_seen := 0
	for i in range(40):
		normal_shop._roll_stock()
		var names2: Array = []
		for it in normal_shop.item_stock:
			names2.append(it.item_name)
		if names2.has("Healing Draught"):
			healing_seen += 1
		if names2.has("Faxtoryll"):
			faxtoryll_seen += 1
	checks.append(["A normal shop's own roll includes Healing Draught at least sometimes across 40 rolls (a real, reachable Scarce item)", healing_seen > 0])
	checks.append(["A normal shop's own roll NEVER includes Exotic Faxtoryll, across all 40 rolls (p.291's own rule, untouched)", faxtoryll_seen == 0])
	normal_shop.queue_free()
	for i in range(2):
		await fe.get_tree().process_frame

	## --- Group 4/5: real battle consumable mechanics, via a live combat -
	var no_pool: Array[String] = []
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_habitat = ""
	fe._start_encounter()
	for i in range(3):
		await fe.get_tree().process_frame

	var player: Character = fe.player
	var goblin: Character = fe.monsters[0] if fe.monsters.size() > 0 else null
	checks.append(["setup: a monster genuinely exists", goblin != null])
	if goblin == null:
		print("RESULT (Cordelia's Apothecary): SETUP FAILED (no monster)")
		return false

	## Initiative is randomly rolled by _start_encounter() -- if the
	## goblin won it, its own AI turn coroutine (_do_monster_turn(), a
	## multi-frame await chain) is still in flight after only 3 frames,
	## and its attack may leave a genuine "spend Fortune to reroll your
	## Defense" prompt open. Forcing fe._prompt_player_turn() on top of
	## either a live monster-turn coroutine or a lingering Fortune
	## prompt is exactly the race this codebase's own combat tests
	## already guard against (see psychology_test.gd's own settle loop,
	## which both waits AND actively declines any Fortune/Act-Again
	## prompt that comes up) -- if left alone, a stale
	## awaiting_fortune_choice=true makes the skills_row wire Faxtoryll/
	## Vitality Draught/Healing Draught through
	## _decline_fortune_prompt_and_run's queue-for-next-call path
	## instead of firing immediately, which is exactly the flaky
	## "button found and clicked, but nothing happened yet" failure
	## this loop fixes.
	var settle_frames := 0
	while not fe.awaiting_player_target and settle_frames < 300:
		if fe.awaiting_continue:
			fe.awaiting_continue = false
		if fe.awaiting_fortune_choice:
			fe._pending_choice_str = ""
			fe.awaiting_fortune_choice = false
		await fe.get_tree().process_frame
		settle_frames += 1
	if fe.awaiting_fortune_choice:
		fe._pending_choice_str = ""
		fe.awaiting_fortune_choice = false
	## Belt-and-suspenders, same convention as psychology_test.gd/
	## frightening_luck_test.gd: pin the turn to the player explicitly
	## now that things have settled, so nothing downstream can hand the
	## Turn to an ally/monster mid-section.
	fe.encounter.current_turn_index = fe.encounter.turn_order.find(player)

	## Faxtoryll: +10 WS/+10 BS for 3 Rounds.
	player.inventory.append("Faxtoryll")
	fe.action_used_this_turn = false
	fe.selected_target = goblin
	fe._prompt_player_turn(true)
	await fe.get_tree().process_frame
	var faxtoryll_btn := CordeliaApothecaryTest._find_button(fe.target_container, "Chew Faxtoryll")
	checks.append(["Faxtoryll's own \"(Free)\" button is offered in the normal turn menu while carried", faxtoryll_btn != null])
	var ws_before: int = player.get_characteristic_bonus("weapon_skill")
	if faxtoryll_btn != null:
		faxtoryll_btn.pressed.emit()
		await fe.get_tree().process_frame
	checks.append(["Faxtoryll actually grants +10 Weapon Skill immediately", player.get_characteristic_bonus("weapon_skill") == ws_before + 1])
	checks.append(["Faxtoryll actually grants +10 Ballistic Skill immediately", player.active_buffs.any(func(b): return b["name"] == "Faxtoryll" and b["characteristic_bonuses"].get("ballistic_skill", 0) == 10)])
	checks.append(["Faxtoryll is consumed from inventory", not player.inventory.has("Faxtoryll")])
	checks.append(["Faxtoryll's own buff lasts exactly 3 Rounds", player.active_buffs.any(func(b): return b["name"] == "Faxtoryll" and b["rounds_remaining"] == 3)])
	fe.action_used_this_turn = false
	fe._prompt_player_turn(false)
	await fe.get_tree().process_frame
	var faxtoryll_btn_gone := CordeliaApothecaryTest._find_button(fe.target_container, "Chew Faxtoryll")
	checks.append(["...and its button is gone from the menu once consumed", faxtoryll_btn_gone == null])
	player.active_buffs.clear()

	## Vitality Draught: +10 Toughness, +2 Movement for 6 Rounds.
	player.inventory.append("Vitality Draught")
	var movement_before: int = player.get_movement()
	fe.action_used_this_turn = false
	fe._prompt_player_turn(false)
	await fe.get_tree().process_frame
	var vitality_btn := CordeliaApothecaryTest._find_button(fe.target_container, "Drink Vitality Draught")
	checks.append(["Vitality Draught's own \"(Free)\" button is offered while carried", vitality_btn != null])
	if vitality_btn != null:
		vitality_btn.pressed.emit()
		await fe.get_tree().process_frame
	checks.append(["Vitality Draught actually grants +10 Toughness immediately", player.active_buffs.any(func(b): return b["name"] == "Vitality Draught" and b["characteristic_bonuses"].get("toughness", 0) == 10)])
	checks.append(["Vitality Draught actually grants +2 Movement immediately", player.get_movement() == movement_before + 2])
	checks.append(["Vitality Draught's own buff lasts exactly 6 Rounds", player.active_buffs.any(func(b): return b["name"] == "Vitality Draught" and b["rounds_remaining"] == 6)])
	checks.append(["Vitality Draught is consumed from inventory", not player.inventory.has("Vitality Draught")])
	player.active_buffs.clear()

	## Salwort: hidden until genuinely needed -- no button at all while
	## NOT Stunned, even while carried.
	player.inventory.append("Salwort")
	player.conditions.clear()
	fe.action_used_this_turn = false
	fe._prompt_player_turn(false)
	await fe.get_tree().process_frame
	var salwort_btn_not_stunned := CordeliaApothecaryTest._find_button(fe.target_container, "Sniff Salwort")
	checks.append(["Salwort's button is hidden while not Stunned, even while carried (\"hide until needed\")", salwort_btn_not_stunned == null])

	## Now genuinely Stunned -- routes to _prompt_incapacitated_turn(),
	## the ONE place this button is reachable (the critical fix).
	player.conditions["Stunned"] = 1
	## Called WITHOUT await, same "fire and forget a coroutine" pattern
	## other tests in this project already use for a function that
	## itself awaits in a loop (e.g. HardyAmbidextrousTalentTest's own
	## fe._prompt_player_defense() call) -- awaiting it directly here
	## would deadlock this test, since it doesn't resolve until the
	## Continue/Salwort button we're about to click is actually pressed.
	fe._prompt_incapacitated_turn()
	for i in range(3):
		await fe.get_tree().process_frame
	var salwort_btn := CordeliaApothecaryTest._find_button(fe.target_container, "Sniff Salwort")
	checks.append(["Salwort's button IS offered from the incapacitated-turn screen while genuinely Stunned", salwort_btn != null])
	if salwort_btn != null:
		salwort_btn.pressed.emit()
	for i in range(4):
		await fe.get_tree().process_frame
	checks.append(["Clicking Salwort actually cures Stunned", not player.conditions.has("Stunned")])
	checks.append(["Salwort is consumed from inventory", not player.inventory.has("Salwort")])
	checks.append(["Using Salwort re-enters a REAL turn (a genuine target-selection turn), not stuck on the incapacitated auto-pass screen", fe.awaiting_player_target])

	var all_pass := true
	for c in checks:
		var label: String = c[0]
		var passed: bool = c[1]
		if not passed:
			all_pass = false
		print("  [%s] %s" % ["PASS" if passed else "FAIL", label])
	print("RESULT (Cordelia's Apothecary): %s (%d/%d checks)" % ["PASS" if all_pass else "FAIL", checks.filter(func(c): return c[1]).size(), checks.size()])
	return all_pass

## Recursively finds the LAST Button anywhere under `root` whose text
## contains `substr` -- see HardyAmbidextrousTalentTest._find_button's
## own comment for why LAST (queue_free() deferral across repeated
## rebuilds).
static func _find_button(root: Node, substr: String) -> Button:
	if root == null:
		return null
	var last: Button = null
	for child in root.get_children():
		if child is Button and String(child.text).contains(substr):
			last = child
		var found := CordeliaApothecaryTest._find_button(child, substr)
		if found != null:
			last = found
	return last
