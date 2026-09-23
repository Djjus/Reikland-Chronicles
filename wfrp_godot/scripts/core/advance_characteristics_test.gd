extends RefCounted
class_name AdvanceCharacteristicsTest
## Regression test for the follow-up request: "it should replace the
## Bonus +1 to 2 Characteristics that is currently in place for
## Human's, and should be the same for all Races." — the WFRP4e
## "Advance Characteristics" rule (p.33's Advance Scheme): allocate 5
## free Advances across the 3 Characteristics marked with a cross in the
## chosen Career's own Advance Scheme, which per clarification are
## exactly the Characteristics keyed in that Career's own Tier 1
## (Brass) CareerLevel.attribute_advances. Unlike the old mechanic it
## replaces (the Human-only Bonus Pick, and the since-removed
## Human-only Reroll Pick -- not part of the rules), this must work
## identically for every Race, because the book ties it to the chosen
## Career, not the Species.

static func run_test(_tree) -> bool:
	var checks: Array = []

	## --- Case 1: data integrity -- every real Career in the game has
	## exactly 3 Characteristics in its own Tier 1 attribute_advances,
	## the precondition CharacterCreator.get_advance_characteristics()
	## relies on (see the riverwoman.tres data-bug fix this uncovered --
	## it used to have 4).
	var all_exactly_three := true
	var bad_careers: Array[String] = []
	for career in GameData.careers:
		var keys: Array = CharacterCreator.get_advance_characteristics(career)
		if keys.size() != 3:
			all_exactly_three = false
			bad_careers.append("%s (%d)" % [career.career_name, keys.size()])
	checks.append(["Case 1: every real Career's Tier 1 Advance Scheme has exactly 3 Characteristics", all_exactly_three])
	if not all_exactly_three:
		print("    (bad careers: ", bad_careers, ")")

	## --- Case 2: get_advance_characteristics() reads the right data --
	## Outlaw's own Tier 1 ("Brigand") is weapon_skill/strength/toughness.
	var outlaw: CareerDefinition = GameData.find_career("Outlaw")
	checks.append(["Case 2: setup -- Outlaw career exists", outlaw != null])
	if outlaw != null:
		var outlaw_keys: Array = CharacterCreator.get_advance_characteristics(outlaw)
		checks.append(["Case 2: Outlaw's Advance Characteristics are exactly weapon_skill/strength/toughness",
			outlaw_keys.size() == 3 and outlaw_keys.has("weapon_skill") and outlaw_keys.has("strength") and outlaw_keys.has("toughness")])

	## --- Case 3: apply_advance_characteristics() bumps BOTH the raw
	## Characteristic value AND character.characteristic_advances (the
	## ledger Advancement.gd's own XP-cost curve builds on for every
	## later PAID Advance -- see purchase_characteristic_advance) by the
	## same amount, so these free creation-time Advances aren't an
	## invisible bonus that mis-prices whatever's purchased next.
	var human: RaceDefinition = GameData.find_race("Human")
	if human != null and outlaw != null:
		var before_ws: int
		var character := CharacterCreator.create_character("AdvanceTest", human, outlaw, {})
		before_ws = character.characteristics.get_value("weapon_skill")
		var before_advances: int = character.characteristic_advances.get("weapon_skill", 0)
		CharacterCreator.apply_advance_characteristics(character, {"weapon_skill": 3, "strength": 2})
		checks.append(["Case 3: weapon_skill raw value increased by exactly 3", character.characteristics.get_value("weapon_skill") == before_ws + 3])
		checks.append(["Case 3: weapon_skill characteristic_advances increased by exactly 3", character.characteristic_advances.get("weapon_skill", 0) == before_advances + 3])
		checks.append(["Case 3: strength characteristic_advances increased by exactly 2", character.characteristic_advances.get("strength", 0) == 2])
		## A key NOT in advance_choices, or a non-positive amount, must
		## not be touched at all.
		var before_toughness: int = character.characteristics.get_value("toughness")
		CharacterCreator.apply_advance_characteristics(character, {"toughness": 0, "fellowship": -1})
		checks.append(["Case 3: a zero/negative amount is a no-op", character.characteristics.get_value("toughness") == before_toughness and not character.characteristic_advances.has("fellowship")])

	## --- Case 4: universal, not Human-only (or any-Race-only). A Dwarf
	## gets the exact same Advance Characteristics allocation for the
	## same Career as a Human would -- the whole point of the
	## replacement.
	var dwarf: RaceDefinition = GameData.find_race("Dwarf")
	if dwarf != null and outlaw != null:
		var dwarf_char := CharacterCreator.create_character("AdvanceTestDwarf", dwarf, outlaw, {})
		var before: int = dwarf_char.characteristics.get_value("strength")
		CharacterCreator.apply_advance_characteristics(dwarf_char, {"strength": 5})
		checks.append(["Case 4: a Dwarf's Advance Characteristics allocation applies exactly like a Human's would", dwarf_char.characteristics.get_value("strength") == before + 5])

	## --- Case 5: the old Bonus Pick AND Reroll Pick fields are actually
	## gone from RaceDefinition, not just unused -- catches a stale
	## re-add. Reroll was removed as a follow-up: "not part of the rules."
	checks.append(["Case 5: RaceDefinition no longer exposes bonus_pick_count", not (human != null and "bonus_pick_count" in human)])
	checks.append(["Case 5: RaceDefinition no longer exposes gets_reroll_pick", not (human != null and "gets_reroll_pick" in human)])
	checks.append(["Case 5: RaceDefinition no longer exposes reroll_pick_count", not (human != null and "reroll_pick_count" in human)])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Advance Characteristics): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
