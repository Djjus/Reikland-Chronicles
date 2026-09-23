extends RefCounted
class_name LightSourceTest
## Per the request ("Make sure that Davrich Lamp and Storm Lantern
## function like a lantern does for light source purposes. Candles too
## but without the Oil/fuel component, candles last 4hrs each (note
## there should be 12/a dozen when buying them)") and its mid-turn
## follow-up ("remember equipped light sources before and after
## combat, after combat characters should have what they where
## carrying again before combat, unless it was destroyed"):
##
## Confirms Storm Lantern's own ItemDefinition data already matches
## Lantern's oil-based mechanics exactly; that Davrich Lamp now also
## requires Lamp Oil and depletes/auto-reloads/extinguishes exactly
## like a real Lantern (it used to have infinite duration); that
## Candle (dozen) instead uses its own self-fuel mechanic — no Lamp
## Oil involved at all — where the one currently-lit unit burns out
## after 4 real-game hours and is silently replaced from remaining
## stock (or the character goes properly dark, unequipped, once truly
## out); that buying "Candle (dozen)" from the Shop grants 12
## individually-trackable inventory copies for the one whole-dozen
## price rather than just 1; that reselling those exploded copies
## can't be exploited back into a profit; and that a party member's
## pre-battle equipped_weapon/equipped_offhand (light source or not)
## comes back exactly as it was once a real FieldEncounter ends,
## unless that specific item was actually destroyed during the fight.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- Item data: Storm Lantern mirrors Lantern; Davrich Lamp now
	## requires oil; Candle (dozen) has its own self-fuel + bundle data --
	var lantern: ItemDefinition = GameData.item_db.find_by_name("Lantern")
	var storm_lantern: ItemDefinition = GameData.item_db.find_by_name("Storm Lantern")
	var davrich_lamp: ItemDefinition = GameData.item_db.find_by_name("Davrich Lamp")
	var candle: ItemDefinition = GameData.item_db.find_by_name("Candle (dozen)")

	checks.append(["Lantern/Storm Lantern/Davrich Lamp/Candle (dozen) all exist", lantern != null and storm_lantern != null and davrich_lamp != null and candle != null])
	checks.append(["Storm Lantern matches Lantern's own oil-based mechanics (radius/low-radius/requires_oil)",
		storm_lantern.light_radius_tiles == lantern.light_radius_tiles and storm_lantern.light_radius_tiles_low == lantern.light_radius_tiles_low and storm_lantern.light_requires_oil == lantern.light_requires_oil])
	checks.append(["Davrich Lamp now requires Lamp Oil like a real lantern (used to have infinite duration)", davrich_lamp.light_requires_oil == true])
	checks.append(["Candle (dozen) does NOT require Lamp Oil", candle.light_requires_oil == false])
	checks.append(["Candle (dozen) burns 240 minutes (4 hours) per individual unit", candle.light_self_fuel_minutes == 240.0])
	checks.append(["Candle (dozen) grants 12 individual units per purchase", candle.purchase_bundle_quantity == 12])
	checks.append(["Everything else still grants exactly 1 unit per purchase (Lantern unaffected)", lantern.purchase_bundle_quantity == 1 and davrich_lamp.purchase_bundle_quantity == 1])
	checks.append(["The four previously-flagged prices are untouched: Grappling Hook (240d)/Storm Lantern (240d)/Davrich Lamp (480d)/Instrument (480d)",
		GameData.item_db.find_by_name("Grappling Hook").price_pennies == 240 and storm_lantern.price_pennies == 240 and davrich_lamp.price_pennies == 480 and GameData.item_db.find_by_name("Instrument").price_pennies == 480])

	## --- Character mechanics: Davrich Lamp now behaves exactly like a
	## Lantern (oil-based) ------------------------------------------------
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.inventory.clear()
	pc.equipped_weapon = ""
	pc.equipped_offhand = ""
	pc.light_mode = "off"
	pc.light_fuel_minutes = 0.0

	pc.inventory.append("Davrich Lamp")
	pc.equipped_weapon = "Davrich Lamp"
	checks.append(["Davrich Lamp is recognised as the equipped light item", pc.get_equipped_light_item() == davrich_lamp])
	checks.append(["Not lit yet -> no active light source", not pc.has_active_light_source()])

	## Switching on with 0 fuel and no spare Lamp Oil to draw from is
	## already correctly inactive (same oil-gating has_active_light_source()
	## already applies to a real Lantern) — and the very next tick
	## confirms it genuinely can't produce light at all.
	pc.light_mode = "on"
	checks.append(["Switched on with 0 fuel and no spare Lamp Oil is correctly NOT an active light source, exactly like a real empty Lantern", not pc.has_active_light_source()])
	var ran_out: bool = pc.tick_light_fuel(1.0)
	checks.append(["Davrich Lamp with no Lamp Oil in reserve and none spare goes dark on first tick, same as a real Lantern would", ran_out and pc.light_mode == "off"])

	## Simulate the Overworld toggle's own "consume a spare Lamp Oil on
	## first turning on" behaviour directly (that hand-off is tested
	## end-to-end in Overworld itself; here we just confirm
	## tick_light_fuel()'s own burn-down + reload math, independent of
	## the toggle UI) — light it with a full reservoir and one spare
	## flask in reserve.
	pc.inventory.append("Lamp Oil")
	pc.light_mode = "on"
	pc.light_fuel_minutes = Character.LAMP_OIL_MINUTES
	pc.tick_light_fuel(120.0)
	checks.append(["120 minutes of a 240-minute Davrich Lamp reservoir burns down by exactly that much", is_equal_approx(pc.light_fuel_minutes, 120.0)])
	var spare_before: int = pc.inventory.count("Lamp Oil")
	pc.tick_light_fuel(130.0)   ## pushes it past empty -> should auto-reload from the spare Lamp Oil
	checks.append(["Running out mid-tick auto-reloads from a spare Lamp Oil, exactly like a real Lantern", pc.light_mode == "on" and is_equal_approx(pc.light_fuel_minutes, Character.LAMP_OIL_MINUTES) and pc.inventory.count("Lamp Oil") == spare_before - 1])

	## --- Candle: self-fuel, no oil, burns out after 4 hours, swaps to
	## the next one from stock, and finally goes dark once truly out ----
	pc.inventory.clear()
	pc.equipped_weapon = ""
	pc.light_mode = "off"
	pc.light_fuel_minutes = 0.0
	for i in range(12):
		pc.inventory.append("Candle (dozen)")
	pc.equipped_weapon = "Candle (dozen)"
	checks.append(["12 candles bought/staged in inventory", pc.inventory.count("Candle (dozen)") == 12])

	pc.light_mode = "on"
	pc.light_fuel_minutes = candle.light_self_fuel_minutes
	pc.tick_light_fuel(239.0)
	checks.append(["A candle just short of its 4-hour life is still lit and still counted (nothing consumed yet)", pc.light_mode == "on" and pc.inventory.count("Candle (dozen)") == 12])

	var out1: bool = pc.tick_light_fuel(5.0)   ## pushes this candle past its 240-minute life
	checks.append(["The spent candle is consumed from inventory (12 -> 11) and the next one lights silently (no 'ran out' notice, light stays on)", not out1 and pc.light_mode == "on" and pc.inventory.count("Candle (dozen)") == 11])
	checks.append(["The freshly-lit replacement candle starts its own full 240-minute life", is_equal_approx(pc.light_fuel_minutes, 240.0)])

	## Burn through the remaining 11 candles.
	var final_out: bool = false
	for i in range(11):
		final_out = pc.tick_light_fuel(240.0)
	checks.append(["Once every candle is spent, the light genuinely goes out (true 'burned out' notice)", final_out and pc.light_mode == "off"])
	checks.append(["No candles left in inventory", pc.inventory.count("Candle (dozen)") == 0])
	checks.append(["Fully out of candles also clears equipped_weapon (nothing left to point at), mirroring a fully-destroyed weapon", pc.equipped_weapon == ""])

	## --- Shop: buying "Candle (dozen)" grants 12 copies for one whole-
	## dozen spend; reselling them can't be exploited back to a profit --
	pc.inventory.clear()
	pc.gold_crowns = 0
	pc.silver_shillings = 0
	pc.brass_pennies = 100

	var shop_scene: PackedScene = load("res://scenes/Shop.tscn")
	var shop: Node = shop_scene.instantiate()
	tree.get_root().add_child.call_deferred(shop)
	await tree.process_frame
	await tree.process_frame

	## Compared via get_total_pennies() rather than the raw brass_pennies
	## field — spend_pennies() renormalizes across gold/silver/brass
	## denominations, so the brass_pennies field alone doesn't reflect
	## how much total value was actually spent.
	var total_before: int = pc.get_total_pennies()
	shop._on_buy_item(candle)
	await tree.process_frame
	checks.append(["Buying 'Candle (dozen)' spends exactly the one 12d list price, not 12x that", total_before - pc.get_total_pennies() == 12])
	checks.append(["...and grants 12 individually-trackable candles in inventory, not 1", pc.inventory.count("Candle (dozen)") == 12])

	var per_candle_sell: int = shop._find_sell_price("Candle (dozen)")
	checks.append(["A single exploded candle's own sell price is a fair per-unit fraction, not the whole-dozen sell price", per_candle_sell < shop._find_sell_price("Lantern")])
	var total_resell_value: int = per_candle_sell * 12
	checks.append(["Buying a dozen for 12d and reselling all 12 individually can never turn a profit", total_resell_value <= 12])

	shop.queue_free()

	## --- Combat: a party member's equipped light source (or any item)
	## comes back exactly as carried into the fight, unless destroyed ----
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var fighter: Character = GameState.player_character
	fighter.character_name = "Lantern Bearer"
	fighter.inventory.clear()
	fighter.inventory.append("Lantern")
	fighter.equipped_weapon = "Lantern"
	fighter.equipped_offhand = ""
	fighter.light_mode = "on"
	fighter.light_fuel_minutes = 77.0

	GameState.pending_encounter_monster_names = ["Giant Rat"]
	if GameData.monster_db.find_by_name("Giant Rat") == null:
		var any_monster: MonsterDefinition = GameData.monster_db.entries[0] if GameData.monster_db.entries.size() > 0 else null
		if any_monster != null:
			GameState.pending_encounter_monster_names = [any_monster.monster_name]

	var fe_scene: PackedScene = load("res://scenes/FieldEncounter.tscn")
	var screen: Node = fe_scene.instantiate()
	tree.get_root().add_child.call_deferred(screen)
	await tree.process_frame
	await tree.process_frame

	checks.append(["FieldEncounter loaded with at least one monster in play", screen.monster_defs.size() > 0])
	var snap: Dictionary = screen._pre_battle_equip.get(fighter, {})
	checks.append(["The Lantern the fighter walked in with is snapshotted before any combat mutation", snap.get("weapon", "??") == "Lantern" and snap.get("offhand", "??") == ""])
	checks.append(["Occupying the weapon slot with a Lantern (not a real weapon) resolves to fighting Unarmed for combat math, without touching equipped_weapon itself", screen.weapons.get(fighter) != null and screen.weapons[fighter].weapon_name == "Unarmed" and fighter.equipped_weapon == "Lantern"])

	## Simulate what an actual mid-battle weapon switch (drawing a real
	## weapon to fight with instead of an unarmed Lantern) leaves behind.
	fighter.inventory.append("Sword")
	fighter.equipped_weapon = "Sword"
	screen._end_battle(true)
	await tree.process_frame
	checks.append(["After the fight, the fighter has their Lantern back in hand — not stuck holding the Sword they only drew to fight with", fighter.equipped_weapon == "Lantern"])
	checks.append(["The Lantern's own light_mode/light_fuel_minutes were never touched by any of this — it just starts working again", fighter.light_mode == "on" and is_equal_approx(fighter.light_fuel_minutes, 77.0)])

	## --- Destroyed items are the one thing that does NOT come back ----
	screen._pre_battle_equip.clear()
	fighter.inventory.erase("Dagger")
	fighter.equipped_weapon = ""
	screen._pre_battle_equip[fighter] = {"weapon": "Dagger", "offhand": ""}
	screen._restore_pre_battle_equipment()
	checks.append(["A pre-battle weapon no longer in inventory (destroyed during the fight) is correctly NOT restored", fighter.equipped_weapon == ""])

	## --- A dropped-but-not-destroyed item (still owned, just knocked
	## out of hand mid-fight, e.g. by a Critical Wound) IS restored -----
	fighter.inventory.append("Buckler")
	fighter.equipped_offhand = ""
	screen._pre_battle_equip.clear()
	screen._pre_battle_equip[fighter] = {"weapon": "", "offhand": "Buckler"}
	screen._restore_pre_battle_equipment()
	checks.append(["A dropped-but-not-destroyed off-hand item (still owned) IS restored", fighter.equipped_offhand == "Buckler"])

	screen.queue_free()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Light Source + Combat Equip Persistence Check): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
