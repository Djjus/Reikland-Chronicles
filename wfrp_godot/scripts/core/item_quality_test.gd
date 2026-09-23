extends RefCounted
class_name ItemQualityTest
## Regression/functional test for the new general Trapping "Item
## Qualities & Flaws" system (rulebook p.301-302: Durable, Fine,
## Lightweight, Practical / Ugly, Shoddy — see ItemQualityRules),
## requested to "live side by side" with this project's pre-existing,
## unrelated Weapon/Armour combat qualities system (Fast, Defensive,
## Precise, ... / Dangerous, Imprecise, Reload N, ...).
##
## Covers: the pure ItemQualityRules price/availability/classification
## math; Durable's extra durability points (damage_weapon/
## damage_armour_piece) and its saving throw (destroy_weapon/
## destroy_armour_piece); Lightweight's -1 Encumbrance (weapon,
## off-hand, armour); Practical's +1 SL on a failed attack Test and its
## armour-Encumbrance-penalty-tier reduction; Ugly's -10 Fellowship
## Test penalty (both a raw characteristic Test and a Fellowship-linked
## skill Test); and Shoddy's weapon-break-on-failed-double and
## armour-break-on-Critical-Hit-to-a-protected-location, both routed
## through the real CombatResolver.resolve_melee_attack() with forced
## dice, matching this project's own "drive the real production call
## with forced rolls" convention (see critical_wound_deflect_repro_test.gd).
##
## Test-only WeaponDefinition/ArmourDefinition instances are registered
## into GameData.weapon_db/armour_db for the duration of this test (many
## of the Character methods being tested look items up by name via
## those databases) and unregistered again at the end, regardless of
## pass/fail, so this test never leaves stray data behind for any test
## that runs after it in the same process.

static func _register_weapon(wd: WeaponDefinition) -> void:
	GameData.weapon_db.weapons.append(wd)

static func _unregister_weapon(name: String) -> void:
	for i in range(GameData.weapon_db.weapons.size() - 1, -1, -1):
		if GameData.weapon_db.weapons[i].weapon_name == name:
			GameData.weapon_db.weapons.remove_at(i)

static func _register_armour(ad: ArmourDefinition) -> void:
	GameData.armour_db.pieces.append(ad)

static func _unregister_armour(name: String) -> void:
	for i in range(GameData.armour_db.pieces.size() - 1, -1, -1):
		if GameData.armour_db.pieces[i].armour_name == name:
			GameData.armour_db.pieces.remove_at(i)

static func _make_character(name: String) -> Character:
	var c := Character.new()
	c.character_name = name
	c.race = GameData.find_race("Human")
	c.career = GameData.find_career("Soldier")
	c.current_tier = 1
	c.characteristics = CharacteristicSet.new()
	c.recompute_max_wounds()
	return c

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []
	var registered_weapons: Array[String] = []
	var registered_armour: Array[String] = []

	await tree.process_frame

	## ================= ItemQualityRules pure math =======================
	var parsed := ItemQualityRules.parse_entry("Durable 2")
	checks.append(["parse_entry splits a rated entry's name", parsed["name"] == "Durable"])
	checks.append(["parse_entry splits a rated entry's rating", parsed["rating"] == 2])
	var parsed_bare := ItemQualityRules.parse_entry("Practical")
	checks.append(["parse_entry defaults a bare entry to rating 1", parsed_bare["rating"] == 1])

	checks.append(["rating_of finds a rated entry's own rating", ItemQualityRules.rating_of(["Durable 3", "Fine"], "Durable") == 3])
	checks.append(["rating_of defaults a bare entry to rating 1", ItemQualityRules.rating_of(["Durable 3", "Fine"], "Fine") == 1])
	checks.append(["rating_of returns 0 for an absent quality", ItemQualityRules.rating_of(["Durable 3", "Fine"], "Ugly") == 0])
	checks.append(["has() is true for a present quality", ItemQualityRules.has(["Lightweight"], "Lightweight")])
	checks.append(["has() is false for an absent quality", not ItemQualityRules.has(["Lightweight"], "Practical")])

	checks.append(["total_rating sums every entry's own rating", ItemQualityRules.total_rating(["Durable 2", "Fine 3"]) == 5])

	checks.append(["shift_availability moves one step toward Exotic", ItemQualityRules.shift_availability("Common", 1) == "Scarce"])
	checks.append(["shift_availability clamps at Exotic, however many steps", ItemQualityRules.shift_availability("Exotic", 5) == "Exotic"])
	checks.append(["shift_availability moves one step toward Common (negative steps)", ItemQualityRules.shift_availability("Rare", -1) == "Scarce"])
	checks.append(["shift_availability clamps at Common, however many negative steps", ItemQualityRules.shift_availability("Common", -3) == "Common"])

	checks.append(["price_multiplier doubles once per Quality", is_equal_approx(ItemQualityRules.price_multiplier(1, 0), 2.0)])
	checks.append(["price_multiplier compounds across multiple Qualities", is_equal_approx(ItemQualityRules.price_multiplier(3, 0), 8.0)])
	checks.append(["price_multiplier halves once per Flaw", is_equal_approx(ItemQualityRules.price_multiplier(0, 1), 0.5)])

	checks.append(["classify: more Qualities than Flaws, but not more than Encumbrance -> Quality Trapping", ItemQualityRules.classify(1, 0, 5) == "Quality Trapping"])
	checks.append(["classify: more Qualities than Encumbrance AND no Flaws -> Best Quality Trapping", ItemQualityRules.classify(2, 0, 1) == "Best Quality Trapping"])
	checks.append(["classify: more Flaws than Qualities -> Flawed Trapping", ItemQualityRules.classify(0, 1, 0) == "Flawed Trapping"])
	checks.append(["classify: equal counts (including zero/zero) -> neither label", ItemQualityRules.classify(0, 0, 0) == "" and ItemQualityRules.classify(1, 1, 0) == ""])

	var derived := ItemQualityRules.compute_derived(100, "Common", ["Fine"], [], 1)
	checks.append(["compute_derived: 1 Quality doubles the price", derived["price_pennies"] == 200])
	checks.append(["compute_derived: 1 Quality shifts availability one step", derived["availability"] == "Scarce"])
	checks.append(["compute_derived: Quality count == Encumbrance is Quality, not Best Quality", derived["classification"] == "Quality Trapping"])

	checks.append(["combined_display shows both systems separated by ' | '", ItemQualityRules.combined_display(["Fast"], ["Fine"], []) == "Fast | Fine"])
	checks.append(["combined_display falls back to just the item side when there's no combat quality", ItemQualityRules.combined_display([], ["Lightweight"], []) == "Lightweight"])
	checks.append(["combined_display falls back to '-' when both are empty", ItemQualityRules.combined_display([], [], []) == "-"])

	## ================= Durable: extra durability + saving throw =========
	var attacker := _make_character("QualityTestAttacker")
	var defender := _make_character("QualityTestDefender")
	attacker.characteristics.set_value("weapon_skill", 20)
	defender.characteristics.set_value("weapon_skill", 20)
	defender.characteristics.set_value("agility", 20)
	var pool := GroupAdvantagePool.new()

	## -- Durable weapon: extra durability points before breaking --------
	var durable_wpn := WeaponDefinition.new()
	durable_wpn.weapon_name = "QT Durable Threshold Weapon"
	durable_wpn.skill_group = "Basic"
	durable_wpn.damage_mode = "strength_bonus_plus"
	durable_wpn.damage_flat = 3
	durable_wpn.item_qualities = ["Durable 2"]
	_register_weapon(durable_wpn)
	registered_weapons.append(durable_wpn.weapon_name)
	attacker.inventory = [durable_wpn.weapon_name]
	attacker.equipped_weapon = durable_wpn.weapon_name
	attacker.weapon_damage_taken.clear()
	for i in range(4):
		attacker.damage_weapon(durable_wpn.weapon_name)
	checks.append(["Durable 2 raises damage_flat 3's own break threshold to 5 -- 4 hits isn't enough yet", attacker.equipped_weapon == durable_wpn.weapon_name])
	attacker.damage_weapon(durable_wpn.weapon_name)
	checks.append(["...but the 5th hit (3 base + 2 Durable) finally breaks it", attacker.equipped_weapon == ""])
	checks.append(["...and it's actually gone from inventory", not attacker.inventory.has(durable_wpn.weapon_name)])

	## -- Durable weapon: saving throw on instant destruction ------------
	var durable_save_wpn := WeaponDefinition.new()
	durable_save_wpn.weapon_name = "QT Durable Save Weapon"
	durable_save_wpn.item_qualities = ["Durable 2"]   ## save target: 10-2=8
	_register_weapon(durable_save_wpn)
	registered_weapons.append(durable_save_wpn.weapon_name)
	attacker.inventory = [durable_save_wpn.weapon_name]
	attacker.equipped_weapon = durable_save_wpn.weapon_name
	var saved := not attacker.destroy_weapon(durable_save_wpn.weapon_name, 8)
	checks.append(["Durable 2's saving throw target is 8+ -- rolling exactly 8 survives", saved])
	checks.append(["...and the weapon is genuinely untouched after a successful save", attacker.equipped_weapon == durable_save_wpn.weapon_name])
	var destroyed := attacker.destroy_weapon(durable_save_wpn.weapon_name, 7)
	checks.append(["...but rolling 7 (below the 8+ target) fails the save and destroys it", destroyed])
	checks.append(["...and it's actually removed this time", attacker.equipped_weapon == ""])

	## -- Durable armour: extra durability points + saving throw ---------
	var durable_armour := ArmourDefinition.new()
	durable_armour.armour_name = "QT Durable Armour"
	durable_armour.locations = ["Body"]
	durable_armour.armour_points = 2
	durable_armour.item_qualities = ["Durable 1"]   ## threshold: 2+1=3
	_register_armour(durable_armour)
	registered_armour.append(durable_armour.armour_name)
	defender.inventory = [durable_armour.armour_name]
	defender.equipped_armour = [durable_armour.armour_name]
	defender.armour_damage.clear()
	defender.broken_armour.clear()
	defender.damage_armour_piece(durable_armour.armour_name, "Body")
	defender.damage_armour_piece(durable_armour.armour_name, "Body")
	checks.append(["Durable 1 raises armour_points 2's own break threshold to 3 -- 2 hits isn't enough yet", defender.equipped_armour.has(durable_armour.armour_name)])
	defender.damage_armour_piece(durable_armour.armour_name, "Body")
	checks.append(["...but the 3rd hit (2 base + 1 Durable) finally breaks it", not defender.equipped_armour.has(durable_armour.armour_name)])
	checks.append(["...and it's moved into broken_armour, not just deleted", defender.broken_armour.get(durable_armour.armour_name, 0) > 0])

	var durable_save_armour := ArmourDefinition.new()
	durable_save_armour.armour_name = "QT Durable Save Armour"
	durable_save_armour.locations = ["Body"]
	durable_save_armour.armour_points = 1
	durable_save_armour.item_qualities = ["Durable 3"]   ## save target: 10-3=7
	_register_armour(durable_save_armour)
	registered_armour.append(durable_save_armour.armour_name)
	defender.inventory = [durable_save_armour.armour_name]
	defender.equipped_armour = [durable_save_armour.armour_name]
	defender.armour_damage.clear()
	defender.broken_armour.clear()
	var armour_saved := not defender.destroy_armour_piece(durable_save_armour.armour_name, 7)
	checks.append(["Durable 3's saving throw target is 7+ -- rolling exactly 7 survives", armour_saved])
	checks.append(["...and it's genuinely still equipped after the save", defender.equipped_armour.has(durable_save_armour.armour_name)])
	var armour_destroyed := defender.destroy_armour_piece(durable_save_armour.armour_name, 6)
	checks.append(["...but rolling 6 (below the 7+ target) fails the save and destroys it outright", armour_destroyed])
	checks.append(["...moving it to broken_armour, same as the gradual-damage path", defender.broken_armour.get(durable_save_armour.armour_name, 0) > 0])

	## ================= Lightweight: -1 Encumbrance =======================
	var lw_wpn := WeaponDefinition.new()
	lw_wpn.weapon_name = "QT Lightweight Weapon"
	lw_wpn.encumbrance = 3
	lw_wpn.item_qualities = ["Lightweight"]
	_register_weapon(lw_wpn)
	registered_weapons.append(lw_wpn.weapon_name)
	var enc_tester := _make_character("QualityEncTester")
	enc_tester.inventory = [lw_wpn.weapon_name]
	enc_tester.equipped_weapon = lw_wpn.weapon_name
	enc_tester.gold_crowns = 0
	enc_tester.silver_shillings = 0
	enc_tester.brass_pennies = 0
	checks.append(["Lightweight reduces a weapon's own Encumbrance by 1 (3 -> 2)", is_equal_approx(enc_tester.get_current_encumbrance(), 2.0)])

	var lw_armour := ArmourDefinition.new()
	lw_armour.armour_name = "QT Lightweight Armour"
	lw_armour.locations = ["Body"]
	lw_armour.encumbrance = 3
	lw_armour.item_qualities = ["Lightweight"]
	_register_armour(lw_armour)
	registered_armour.append(lw_armour.armour_name)
	var plain_armour := ArmourDefinition.new()
	plain_armour.armour_name = "QT Plain Armour For Enc"
	plain_armour.locations = ["Body"]
	plain_armour.encumbrance = 3
	_register_armour(plain_armour)
	registered_armour.append(plain_armour.armour_name)
	enc_tester.equipped_weapon = ""
	enc_tester.inventory = [lw_armour.armour_name]
	enc_tester.equipped_armour = [lw_armour.armour_name]
	var lw_total := enc_tester.get_current_encumbrance()
	enc_tester.inventory = [plain_armour.armour_name]
	enc_tester.equipped_armour = [plain_armour.armour_name]
	var plain_total := enc_tester.get_current_encumbrance()
	checks.append(["A Lightweight armour piece's total Encumbrance is 1 less than an otherwise-identical plain piece (stacks with the existing Worn Items -1)", is_equal_approx(plain_total - lw_total, 1.0)])

	## ================= Practical: weapon +1 SL on failure ================
	var plain_wpn := WeaponDefinition.new()
	plain_wpn.weapon_name = "QT Plain Weapon"
	plain_wpn.skill_group = "Basic"
	_register_weapon(plain_wpn)
	registered_weapons.append(plain_wpn.weapon_name)
	var practical_wpn := WeaponDefinition.new()
	practical_wpn.weapon_name = "QT Practical Weapon"
	practical_wpn.skill_group = "Basic"
	practical_wpn.item_qualities = ["Practical"]
	_register_weapon(practical_wpn)
	registered_weapons.append(practical_wpn.weapon_name)

	var sl_attacker := _make_character("QualitySLAttacker")
	sl_attacker.characteristics.set_value("weapon_skill", 40)
	var sl_defender := _make_character("QualitySLDefender")
	sl_defender.characteristics.set_value("weapon_skill", 20)
	sl_defender.characteristics.set_value("agility", 20)
	var pool2 := GroupAdvantagePool.new()

	var plain_result: CombatResolver.AttackResult = CombatResolver.resolve_melee_attack(sl_attacker, sl_defender, plain_wpn, pool2, null, "", false, 0, 0, 75, [], 0, [], 1)
	var practical_result: CombatResolver.AttackResult = CombatResolver.resolve_melee_attack(sl_attacker, sl_defender, practical_wpn, pool2, null, "", false, 0, 0, 75, [], 0, [], 1)
	checks.append(["setup: the forced roll (75) is a genuine failure against WS 40 for both weapons", not plain_result.attacker_test.success and not practical_result.attacker_test.success])
	checks.append(["Practical softens a failed attack Test by exactly +1 SL", practical_result.attacker_test.success_levels == plain_result.attacker_test.success_levels + 1])
	checks.append(["...but a Practical weapon's failure never turns into a success", not practical_result.attacker_test.success])

	## ================= Practical: armour Encumbrance-tier reduction ======
	var tier_tester := _make_character("QualityTierTester")
	tier_tester.carrying_capacity_override = 10
	var heavy_wpn := WeaponDefinition.new()
	heavy_wpn.weapon_name = "QT Heavy Test Weapon"
	heavy_wpn.encumbrance = 15
	_register_weapon(heavy_wpn)
	registered_weapons.append(heavy_wpn.weapon_name)
	tier_tester.inventory = [heavy_wpn.weapon_name]
	tier_tester.equipped_weapon = heavy_wpn.weapon_name
	tier_tester.gold_crowns = 0
	tier_tester.silver_shillings = 0
	tier_tester.brass_pennies = 0
	var baseline_penalty := tier_tester.get_encumbrance_penalty()
	checks.append(["setup: 15 Enc against a capacity-10 override lands in the Encumbered tier", baseline_penalty["tier"] == "Encumbered" and baseline_penalty["agility_penalty"] == 10])

	var practical_armour := ArmourDefinition.new()
	practical_armour.armour_name = "QT Practical Armour"
	practical_armour.locations = ["Body"]
	practical_armour.encumbrance = 0
	practical_armour.item_qualities = ["Practical"]
	_register_armour(practical_armour)
	registered_armour.append(practical_armour.armour_name)
	tier_tester.inventory.append(practical_armour.armour_name)
	tier_tester.equipped_armour = [practical_armour.armour_name]
	var practical_penalty := tier_tester.get_encumbrance_penalty()
	checks.append(["Practical armour drops the WHOLE Encumbrance-penalty tier by one step (Encumbered -> None)", practical_penalty["tier"] == "None" and practical_penalty["agility_penalty"] == 0])

	## ================= Ugly: -10 Fellowship Test penalty ==================
	var ugly_tester := _make_character("QualityUglyTester")
	ugly_tester.characteristics.set_value("fellowship", 50)
	ugly_tester.characteristics.set_value("strength", 50)
	var baseline_fel := TestResolver.resolve_characteristic_test(ugly_tester, "fellowship")
	checks.append(["setup: a bare Fellowship Test's target is the raw characteristic value (no Ugly item yet)", baseline_fel.target == 50])

	var ugly_wpn := WeaponDefinition.new()
	ugly_wpn.weapon_name = "QT Ugly Weapon"
	ugly_wpn.item_flaws = ["Ugly"]
	_register_weapon(ugly_wpn)
	registered_weapons.append(ugly_wpn.weapon_name)
	ugly_tester.inventory = [ugly_wpn.weapon_name]
	ugly_tester.equipped_weapon = ugly_wpn.weapon_name

	var ugly_fel := TestResolver.resolve_characteristic_test(ugly_tester, "fellowship")
	checks.append(["Ugly applies a real -10 to a raw Fellowship characteristic Test", ugly_fel.target == 40])
	var ugly_strength := TestResolver.resolve_characteristic_test(ugly_tester, "strength")
	checks.append(["...but does NOT touch an unrelated (Strength) characteristic Test", ugly_strength.target == 50])

	var charm_skill: SkillDefinition = GameData.skill_db.find_by_name("Charm")
	checks.append(["setup: found the real Charm skill (Fellowship-linked) to test with", charm_skill != null])
	if charm_skill != null:
		var charm_result := TestResolver.resolve_skill_test(ugly_tester, charm_skill)
		checks.append(["Ugly also applies -10 to a Fellowship-LINKED skill Test (Charm), not just the raw characteristic", charm_result.target == 40])
		ugly_tester.equipped_weapon = ""
		var charm_without_ugly := TestResolver.resolve_skill_test(ugly_tester, charm_skill)
		checks.append(["...and Charm returns to its normal target once the Ugly item is unequipped", charm_without_ugly.target == 50])

	## ================= Shoddy: weapon breaks on a failed double ==========
	var shoddy_wpn := WeaponDefinition.new()
	shoddy_wpn.weapon_name = "QT Shoddy Weapon"
	shoddy_wpn.skill_group = "Basic"
	shoddy_wpn.item_flaws = ["Shoddy"]
	_register_weapon(shoddy_wpn)
	registered_weapons.append(shoddy_wpn.weapon_name)
	var shoddy_attacker := _make_character("QualityShoddyAttacker")
	shoddy_attacker.characteristics.set_value("weapon_skill", 20)
	shoddy_attacker.inventory = [shoddy_wpn.weapon_name]
	shoddy_attacker.equipped_weapon = shoddy_wpn.weapon_name
	var shoddy_defender := _make_character("QualityShoddyDefender")
	shoddy_defender.characteristics.set_value("weapon_skill", 20)
	shoddy_defender.characteristics.set_value("agility", 20)
	var pool3 := GroupAdvantagePool.new()
	var shoddy_result: CombatResolver.AttackResult = CombatResolver.resolve_melee_attack(shoddy_attacker, shoddy_defender, shoddy_wpn, pool3, null, "", false, 0, 0, 99, [], 0, [], 1)
	checks.append(["setup: the forced roll (99) is a genuine failed double against WS 20", not shoddy_result.attacker_test.success and shoddy_result.attacker_test.roll % 11 == 0])
	checks.append(["Shoddy breaks the weapon on a failed Test rolling a double", shoddy_result.attacker_weapon_broke_shoddy])
	checks.append(["...and it's genuinely gone from the attacker's own inventory", not shoddy_attacker.inventory.has(shoddy_wpn.weapon_name)])

	## Otherwise-identical plain weapon: the SAME failed-double roll must
	## NOT break it -- isolates the effect to the Shoddy Flaw specifically.
	var plain_wpn2 := WeaponDefinition.new()
	plain_wpn2.weapon_name = "QT Plain Weapon 2"
	plain_wpn2.skill_group = "Basic"
	_register_weapon(plain_wpn2)
	registered_weapons.append(plain_wpn2.weapon_name)
	var plain_attacker2 := _make_character("QualityPlainAttacker2")
	plain_attacker2.characteristics.set_value("weapon_skill", 20)
	plain_attacker2.inventory = [plain_wpn2.weapon_name]
	plain_attacker2.equipped_weapon = plain_wpn2.weapon_name
	var plain_result2: CombatResolver.AttackResult = CombatResolver.resolve_melee_attack(plain_attacker2, shoddy_defender, plain_wpn2, pool3, null, "", false, 0, 0, 99, [], 0, [], 1)
	checks.append(["A plain (non-Shoddy) weapon survives the exact same failed-double roll", not plain_result2.attacker_weapon_broke_shoddy and plain_attacker2.inventory.has(plain_wpn2.weapon_name)])

	## ================= Shoddy: armour breaks on a Critical Hit ===========
	var shoddy_armour := ArmourDefinition.new()
	shoddy_armour.armour_name = "QT Shoddy Armour"
	shoddy_armour.locations = ["Body"]
	shoddy_armour.armour_points = 3
	shoddy_armour.item_flaws = ["Shoddy"]
	_register_armour(shoddy_armour)
	registered_armour.append(shoddy_armour.armour_name)
	var crit_attacker := _make_character("QualityCritAttacker")
	crit_attacker.characteristics.set_value("weapon_skill", 150)
	var crit_weapon := WeaponDefinition.new()
	crit_weapon.weapon_name = "QT Crit Test Weapon"
	crit_weapon.skill_group = "Basic"
	crit_weapon.damage_flat = 1
	_register_weapon(crit_weapon)
	registered_weapons.append(crit_weapon.weapon_name)
	var crit_defender := _make_character("QualityCritDefender")
	crit_defender.characteristics.set_value("weapon_skill", 20)
	crit_defender.characteristics.set_value("agility", 20)
	crit_defender.characteristics.set_value("toughness", 20)
	crit_defender.inventory = [shoddy_armour.armour_name]
	crit_defender.equipped_armour = [shoddy_armour.armour_name]
	crit_defender.armour_damage.clear()
	crit_defender.broken_armour.clear()
	var pool4 := GroupAdvantagePool.new()
	## Same "attacker roll 55 (a double, self-reverse-symmetric so it
	## also lands the Body hit-location band), defender roll 99 (a
	## near-guaranteed failure)" convention as
	## critical_wound_deflect_repro_test.gd's own real production-call
	## repro -- forced_hit_location="Body" pins the location directly
	## rather than relying on that digit-reversal math here too.
	var crit_result: CombatResolver.AttackResult = CombatResolver.resolve_melee_attack(crit_attacker, crit_defender, crit_weapon, pool4, null, "", false, 0, 0, 55, [], 0, [], 99, false, [], [], "Body")
	checks.append(["setup: the attack genuinely hit with a genuine Critical Hit", crit_result.hit and crit_result.was_critical])
	checks.append(["Shoddy breaks an armour piece that took a real Critical Hit to a location it protects", crit_result.shoddy_armour_broken.has(shoddy_armour.armour_name)])
	checks.append(["...and it's genuinely moved to broken_armour (destroy_armour_piece's own real effect), not just flagged", crit_defender.broken_armour.get(shoddy_armour.armour_name, 0) > 0])
	checks.append(["...no longer equipped", not crit_defender.equipped_armour.has(shoddy_armour.armour_name)])

	## Otherwise-identical plain armour: the SAME Critical Hit must NOT
	## break it -- isolates the effect to the Shoddy Flaw specifically.
	var plain_armour2 := ArmourDefinition.new()
	plain_armour2.armour_name = "QT Plain Armour 2"
	plain_armour2.locations = ["Body"]
	plain_armour2.armour_points = 3
	_register_armour(plain_armour2)
	registered_armour.append(plain_armour2.armour_name)
	var crit_defender2 := _make_character("QualityCritDefender2")
	crit_defender2.characteristics.set_value("weapon_skill", 20)
	crit_defender2.characteristics.set_value("agility", 20)
	crit_defender2.characteristics.set_value("toughness", 20)
	crit_defender2.inventory = [plain_armour2.armour_name]
	crit_defender2.equipped_armour = [plain_armour2.armour_name]
	crit_defender2.armour_damage.clear()
	crit_defender2.broken_armour.clear()
	var crit_result2: CombatResolver.AttackResult = CombatResolver.resolve_melee_attack(crit_attacker, crit_defender2, crit_weapon, pool4, null, "", false, 0, 0, 55, [], 0, [], 99, false, [], [], "Body")
	checks.append(["A plain (non-Shoddy) armour piece survives the exact same Critical Hit", crit_result2.hit and crit_result2.was_critical and crit_result2.shoddy_armour_broken.is_empty() and crit_defender2.equipped_armour.has(plain_armour2.armour_name)])

	## ================= Cleanup: unregister every test-only item ==========
	for name in registered_weapons:
		_unregister_weapon(name)
	for name in registered_armour:
		_unregister_armour(name)

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Item Quality/Flaw System): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
