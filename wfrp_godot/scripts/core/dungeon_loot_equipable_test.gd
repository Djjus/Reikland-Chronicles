extends RefCounted
class_name DungeonLootEquipableTest
## Regression test for the report ("dungeon weapon and armor drops seem
## not to be equipable/usable"). Two separate, independently-confirmed
## root causes, both fixed here:
##
## (1) Five monster entries in core_monsters.tres carried flavor-text
## weapon_name/armour values that never matched any real entry in
## weapon_db/armour_db at all (Stormvermin's "Chainmail Shirt", Chaos
## Warrior's "Great Weapon"/"Plate Armour", Mutant's "Hand Weapon",
## Wight's "Ancient Sword", Plague Monk's "Rusted Blade") — a kill's
## loot roll pushed that exact string into the recipient's inventory
## (see FieldEncounterScreen._generate_loot()/_apply_kept_battle_
## report_loot()), and since GameData.weapon_db.find_by_name()/
## armour_db.find_by_name() had nothing to match, character_menu_
## screen.gd's own equip-button logic (inv_weapon/inv_armour both null)
## fell through to a plain, buttonless name label — the item just sat
## in inventory, permanently unusable. Fixed by correcting those five
## monster entries to real, already-registered weapon/armour names.
##
## (2) Separately, a dungeon Weapon Rack/Cupboard reward that rolled at
## least one Item Quality (floor > 0 — see _grant_weapon_reward()/
## _grant_armour_reward()) composes a name like "Durable Sword" and
## registers a brand-new WeaponDefinition/ArmourDefinition live into
## GameData.weapon_db.weapons/armour_db.pieces the first time it's
## seen. That registration only ever lived in memory — nothing
## persists those two arrays (SaveManager only saves Character data),
## so the composed name resolved fine for the rest of that session but
## became permanently un-equippable the moment the app restarted and
## GameData._ready() reloaded weapon_db/armour_db fresh from their
## static .tres files, which never had the dynamic entry. Fixed by
## WeaponDatabase/ArmourDatabase's own find_by_name() now self-healing:
## when a plain lookup misses, it peels known Item Quality tokens
## (Durable/Fine/Lightweight/Practical, optionally rated) off the front
## of the name until the remainder resolves to a real base item, then
## recomposes and re-registers it exactly the way the original reward/
## crafting code did — fully transparent to every existing caller
## (equip UI, combat, shop), since it only ever engages once the plain
## loop has already failed. The exact same bug/fix applies to
## ShopScreen's own Crafting order flow (_on_place_craft_order()),
## which uses the identical compose-and-register pattern — covered
## here too since it shares the same underlying database method.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- (1) The five previously-broken monster loot names now resolve
	for pair in [
		["Stormvermin", "armour", "Mail Shirt"],
		["Chaos Warrior", "weapon", "Great Axe"],
		["Chaos Warrior", "armour", "Plate Breastplate"],
		["Mutant", "weapon", "Club"],
		["Wight", "weapon", "Sword"],
		["Plague Monk", "weapon", "Dagger"],
	]:
		var monster_name: String = pair[0]
		var kind: String = pair[1]
		var expected_item: String = pair[2]
		var mdef: MonsterDefinition = GameData.monster_db.find_by_name(monster_name) if GameData.monster_db != null else null
		checks.append(["setup: %s exists in the monster database" % monster_name, mdef != null])
		if mdef == null:
			continue
		if kind == "weapon":
			checks.append(["%s's own weapon_name (\"%s\") is a real, registered weapon" % [monster_name, mdef.weapon_name],
				GameData.weapon_db.find_by_name(mdef.weapon_name) != null])
			checks.append(["...specifically the expected replacement (\"%s\")" % expected_item, mdef.weapon_name == expected_item])
		else:
			checks.append(["setup: %s's own armour list actually contains \"%s\"" % [monster_name, expected_item], mdef.armour.has(expected_item)])
			checks.append(["%s's own armour entry (\"%s\") is a real, registered armour piece" % [monster_name, expected_item],
				GameData.armour_db.find_by_name(expected_item) != null])

	## --- (2a) WeaponDatabase self-heals a never-registered composed name
	var sword_base: WeaponDefinition = GameData.weapon_db.find_by_name("Sword")
	checks.append(["setup: \"Sword\" is a real base weapon", sword_base != null])
	## Deliberately NOT calling _grant_weapon_reward() here -- this
	## simulates exactly the broken scenario: a composed name that
	## exists in a Character's saved inventory string but was NEVER
	## (re-)registered into weapon_db.weapons this session, e.g. after
	## an app restart.
	var never_registered_name := "Durable Sword"
	checks.append(["setup: \"%s\" is genuinely not pre-registered anywhere" % never_registered_name,
		not GameData.weapon_db.weapons.any(func(w): return w.weapon_name == never_registered_name)])
	var healed_sword: WeaponDefinition = GameData.weapon_db.find_by_name(never_registered_name)
	checks.append(["THE FIX: find_by_name() self-heals a never-registered composed name instead of returning null", healed_sword != null])
	if healed_sword != null:
		checks.append(["...with the correct item_qualities peeled off the name", healed_sword.item_qualities == ["Durable"]])
		checks.append(["...and every other stat copied straight from the real base weapon", healed_sword.skill_group == sword_base.skill_group and healed_sword.damage_flat == sword_base.damage_flat])
		var expected_derived: Dictionary = ItemQualityRules.compute_derived(sword_base.price_pennies, sword_base.availability, ["Durable"], [], sword_base.encumbrance)
		checks.append(["...with a correctly-derived price (doubled once, for one Item Quality)", healed_sword.price_pennies == int(expected_derived["price_pennies"])])
		checks.append(["it's now genuinely registered for next time, not just handed back once", GameData.weapon_db.weapons.any(func(w): return w.weapon_name == never_registered_name)])
		var second_lookup: WeaponDefinition = GameData.weapon_db.find_by_name(never_registered_name)
		checks.append(["a second lookup returns the SAME Resource instance, not a fresh duplicate each time", second_lookup == healed_sword])

	## --- (2b) A rated quality ("Durable 2") is parsed correctly
	var rated_name := "Durable 2 Dagger"
	var healed_rated: WeaponDefinition = GameData.weapon_db.find_by_name(rated_name)
	checks.append(["a rated quality token (\"Durable 2\") is peeled as one entry, not split apart", healed_rated != null and healed_rated.item_qualities == ["Durable 2"]])

	## --- (2c) Nested case: a further-qualified name where the FIRST
	## peelable run happens to include a word ("Fine") that's ALSO the
	## start of its own separately-registered static item ("Fine
	## Sword"). Deliberately resolved as "both Durable and Fine are
	## rolled qualities on top of plain Sword" (the greedy LONGEST
	## peel), not "Durable on top of the existing Fine Sword" — see
	## _resolve_composed_quality_name()'s own header comment for why:
	## Crafting's own base is ALWAYS quality-prefix-free (guaranteed by
	## its own base-item picker), so the longest peel keeps that much
	## more heavily-used flow 100% correct; the rarer dungeon-reward
	## nested case still comes out as a fully valid, correctly-priced,
	## genuinely equippable item either way, just possibly with a
	## slightly different derived base than the exact original roll.
	var plain_sword_base: WeaponDefinition = GameData.weapon_db.find_by_name("Sword")
	var nested_name := "Durable Fine Sword"
	var healed_nested: WeaponDefinition = GameData.weapon_db.find_by_name(nested_name)
	checks.append(["THE FIX handles a nested case: \"Durable Fine Sword\" resolves at all (still equippable either way)", healed_nested != null])
	if healed_nested != null:
		checks.append(["...treating BOTH Durable and Fine as rolled qualities (the longest peel), keeping plain Sword as the base",
			healed_nested.item_qualities == ["Durable", "Fine"]])
		checks.append(["...so its stats come from the plain Sword base", healed_nested.damage_flat == plain_sword_base.damage_flat and healed_nested.encumbrance == plain_sword_base.encumbrance])

	## --- (2d) ArmourDatabase gets the identical fix
	var jack_base: ArmourDefinition = GameData.armour_db.find_by_name("Leather Jack")
	checks.append(["setup: \"Leather Jack\" is a real base armour piece", jack_base != null])
	var never_registered_armour := "Fine Leather Jack"
	var healed_armour: ArmourDefinition = GameData.armour_db.find_by_name(never_registered_armour)
	checks.append(["THE FIX, for armour too: a never-registered composed armour name self-heals", healed_armour != null])
	if healed_armour != null:
		checks.append(["...with the correct item_qualities peeled off", healed_armour.item_qualities == ["Fine"]])
		checks.append(["...and locations copied straight from the real base piece", healed_armour.locations == jack_base.locations])

	## --- (2e) End-to-end: exactly the reported symptom. A composed name
	## sitting in a Character's inventory (as if loaded from a save where
	## it was never re-registered this session) now gets real Equip
	## buttons, using the exact same lookups character_menu_screen.gd's
	## own inventory row builder uses.
	var human = GameData.find_race("Human")
	var soldier = GameData.find_career("Soldier")
	var looted_char := CharacterCreator.create_character("LootTestChar", human, soldier, {})
	looted_char.inventory.append("Practical Halberd")   ## never granted via _grant_weapon_reward -- simulates a reloaded save
	var found_weapon := false
	for item_name in looted_char.inventory:
		if item_name == "Practical Halberd":
			var inv_weapon: WeaponDefinition = GameData.weapon_db.find_by_name(item_name)
			checks.append(["THE FIX, end to end: a composed weapon name sitting in inventory now resolves to a real WeaponDefinition (so the Equip button actually renders)", inv_weapon != null])
			found_weapon = true
	checks.append(["setup: the test item was actually in the inventory to check", found_weapon])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Dungeon Loot Equipable): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
