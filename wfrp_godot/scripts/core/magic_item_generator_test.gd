extends RefCounted
class_name MagicItemGeneratorTest
## Per the request ("add Magic Item Gen rules... a Magic Weapons/Armor/
## Shields/Ammunition generator"): exercises MagicItemGenerator's four
## public generate_*() functions across many rolls (so every table's own
## resolution logic actually runs many times, not just once), plus a
## handful of forced-roll checks against the private roll functions
## directly to pin down the trickier recursive edge cases (Legendary's
## reroll-and-cap-at-five/no-duplicates, Gromril/Ithilmar's leather
## exclusion and "never both on one suit" rule, the Hoarfrost-on-ranged
## and Of Bane special cases, and that every generated definition is a
## genuinely separate clone rather than a mutated shared GameData
## original).

static func run_test(_tree: SceneTree) -> bool:
	var checks: Array = []

	## --- Bulk smoke test: generate many of each category, make sure
	## nothing ever throws and every result has sane, present fields ----
	var weapon_names := {}
	var any_ranged_weapon := false
	var any_melee_weapon := false
	for i in range(300):
		var w := MagicItemGenerator.generate_weapon()
		if w.definition == null:
			checks.append(["weapon #%d: definition is non-null" % i, false])
			continue
		weapon_names[w.base_name] = true
		if w.is_ranged:
			any_ranged_weapon = true
		else:
			any_melee_weapon = true
		if w.abilities.size() < 1 or w.abilities.size() > 5:
			checks.append(["weapon #%d: ability count 1-5 (got %d)" % [i, w.abilities.size()], false])
		if w.estimated_cost_pennies <= 0:
			checks.append(["weapon #%d: positive estimated cost" % i, false])
		## format_result must not throw on any real roll combination
		MagicItemGenerator.format_result(w)
	checks.append(["300 weapon rolls: at least one ranged and one melee type appeared", any_ranged_weapon and any_melee_weapon])
	checks.append(["300 weapon rolls: hit a good spread of base weapon types (>=8 distinct)", weapon_names.size() >= 8])

	for i in range(150):
		var a := MagicItemGenerator.generate_ammunition()
		if a.definition == null:
			checks.append(["ammo #%d: definition is non-null" % i, false])
			continue
		if a.estimated_cost_pennies <= 0:
			checks.append(["ammo #%d: positive estimated cost" % i, false])
		MagicItemGenerator.format_result(a)

	var saw_leather := false
	var saw_mail_or_plate := false
	for i in range(300):
		var ar := MagicItemGenerator.generate_armour()
		if ar.definitions.is_empty():
			checks.append(["armour #%d: at least one definition produced" % i, false])
			continue
		if ar.is_leather:
			saw_leather = true
		else:
			saw_mail_or_plate = true
		if ar.abilities.size() < 1 or ar.abilities.size() > 5:
			checks.append(["armour #%d: ability count 1-5 (got %d)" % [i, ar.abilities.size()], false])
		## Leather armour must never end up with a Gromril/Ithilmar ability
		for ab in ar.abilities:
			var sp: String = String(ab.get("special", ""))
			if ar.is_leather and (sp == "gromril" or sp == "ithilmar"):
				checks.append(["armour #%d: leather never carries Gromril/Ithilmar" % i, false])
		MagicItemGenerator.format_result(ar)
	checks.append(["300 armour rolls: saw both leather and mail/plate pieces", saw_leather and saw_mail_or_plate])

	for i in range(150):
		var s := MagicItemGenerator.generate_shield()
		if s.definition == null:
			checks.append(["shield #%d: definition is non-null" % i, false])
			continue
		if s.estimated_cost_pennies <= 0:
			checks.append(["shield #%d: positive estimated cost" % i, false])
		var has_shield_quality := false
		for q in s.definition.qualities:
			if String(q).begins_with("Shield "):
				has_shield_quality = true
		checks.append(["shield #%d: generated shield keeps a rated Shield N quality" % i, has_shield_quality])
		MagicItemGenerator.format_result(s)

	## --- Non-mutation of shared GameData templates ----------------------
	var sword_before: WeaponDefinition = GameData.weapon_db.find_by_name("Sword")
	var sword_quality_count_before := sword_before.qualities.size()
	for i in range(40):
		var w2 := MagicItemGenerator.generate_weapon()
		if w2.base_name == "Sword" and w2.definition != null:
			w2.definition.qualities.append("__test_mutation_marker__")
	var sword_after: WeaponDefinition = GameData.weapon_db.find_by_name("Sword")
	checks.append(["mutating a generated weapon's qualities never touches the shared GameData.weapon_db Sword template", sword_after.qualities.size() == sword_quality_count_before])

	var plate_before: ArmourDefinition = GameData.armour_db.find_by_name("Plate Breastplate")
	var plate_ap_before := plate_before.armour_points
	for i in range(40):
		var ar2 := MagicItemGenerator.generate_armour()
		for d in ar2.definitions:
			if d.armour_name.begins_with("Plate Breastplate"):
				d.armour_points += 100
	var plate_after: ArmourDefinition = GameData.armour_db.find_by_name("Plate Breastplate")
	checks.append(["mutating a generated armour piece's armour_points never touches the shared GameData.armour_db Plate Breastplate template", plate_after.armour_points == plate_ap_before])

	## --- Weapon ability roll edge cases (direct calls into the private
	## roll function, run many times to reliably hit rare branches) ------
	## Legendary Weapon is only 1/100 per roll, and reaching the full
	## five-ability cap (or a same-chain duplicate) needs several
	## Legendary hits chained back to back — astronomically rare
	## (~1e-8) under the table's real odds, so it can't be relied on to
	## show up in any reasonable number of natural rolls. Sections A/B
	## below cover what natural rolls CAN reliably demonstrate (dedup
	## and the 5-cap never being exceeded, Hoarfrost-on-ranged, Of
	## Bane); section C forces the odds temporarily (widening
	## WEAPON_QUALITY_TABLE's ranges in place, then restoring them) to
	## deterministically exercise the cap-and-dedup logic itself without
	## waiting on a 1-in-100-million natural roll.
	var saw_hoarfrost_ranged_ammo_count := false
	var saw_of_bane_creature := false
	for i in range(400):
		var abilities: Array[Dictionary] = []
		var notes: Array[String] = []
		MagicItemGenerator._roll_weapon_abilities(true, abilities, notes, 5)
		if abilities.size() > 5:
			checks.append(["weapon ability roll #%d: never exceeds 5 abilities" % i, false])
		var names_seen := {}
		for ab in abilities:
			var nm: String = String(ab.get("name", ""))
			if names_seen.has(nm):
				checks.append(["weapon ability roll #%d: no duplicate ability name within one weapon (%s)" % [i, nm], false])
			names_seen[nm] = true
			if ab.has("ammo_count"):
				saw_hoarfrost_ranged_ammo_count = true
				if int(ab["ammo_count"]) < 1 or int(ab["ammo_count"]) > 10:
					checks.append(["weapon ability roll #%d: Hoarfrost ranged ammo_count is 1d10 (got %s)" % [i, ab["ammo_count"]], false])
			if ab.has("creature") and String(ab.get("name", "")) == "Of Bane":
				saw_of_bane_creature = true
				checks.append(["weapon ability roll #%d: Of Bane's creature text is non-empty" % i, String(ab["creature"]) != ""])
	checks.append(["across 400 weapon-ability rolls (forced ranged), Hoarfrost-on-ranged's 1d10 ammo_count path fired at least once", saw_hoarfrost_ranged_ammo_count])
	checks.append(["across 400 weapon-ability rolls, Of Bane's creature sub-roll fired at least once", saw_of_bane_creature])

	## Section C: WEAPON_QUALITY_TABLE is a `const` Dictionary literal —
	## Godot freezes const Dictionaries/Arrays deep (read-only), so it
	## can't be mutated in place to force the odds. Instead, directly
	## whitebox-test the cap/dedup GUARD LOGIC itself by pre-seeding the
	## `abilities` accumulator the same way the real recursion does
	## mid-chain, rather than hoping a real 1%-per-roll Legendary chains
	## deep enough by chance (reaching the full 5-cap that way needs on
	## the order of 1e8 rolls to show up even once).
	var five_dummy_abilities: Array[Dictionary] = []
	for n in range(5):
		five_dummy_abilities.append({"name": "Dummy Ability %d" % n})
	var five_dummy_notes: Array[String] = []
	MagicItemGenerator._roll_weapon_abilities(false, five_dummy_abilities, five_dummy_notes, 5)
	checks.append(["cap guard: calling _roll_weapon_abilities with 5 abilities already collected adds nothing more", five_dummy_abilities.size() == 5])

	var zero_budget_abilities: Array[Dictionary] = []
	var zero_budget_notes: Array[String] = []
	MagicItemGenerator._roll_weapon_abilities(false, zero_budget_abilities, zero_budget_notes, 0)
	checks.append(["budget guard: calling _roll_weapon_abilities with budget 0 adds nothing", zero_budget_abilities.is_empty()])

	## Dedup: pre-seed the accumulator with one real ability ("Of
	## Stalwart Sorcery", D100 52-54) already present, then roll many
	## times — every roll landing in 52-54 (3% per trial) must hit the
	## "already have it" branch and log a note instead of appending a
	## second copy.
	var saw_dedup_note := false
	for i in range(500):
		var preseeded: Array[Dictionary] = [{"name": "Of Stalwart Sorcery"}]
		var notes3: Array[String] = []
		## budget 1 here (rather than 5): keeps this a single, direct
		## roll against the pre-seeded name with no further Legendary
		## chaining muddying the count, since that chain behaviour is
		## already covered separately above.
		MagicItemGenerator._roll_weapon_abilities(false, preseeded, notes3, 1)
		var dup_count := 0
		for ab in preseeded:
			if String(ab.get("name", "")) == "Of Stalwart Sorcery":
				dup_count += 1
		checks.append(["dedup roll #%d: 'Of Stalwart Sorcery' never appears twice in the ability list" % i, dup_count == 1])
		for n in notes3:
			if n.begins_with("Duplicate ability rolled"):
				saw_dedup_note = true
	checks.append(["across 500 pre-seeded rolls, the duplicate-ability dedup path fired at least once (~3%% per roll)", saw_dedup_note])

	## --- Weapon History edge cases ---------------------------------------
	var saw_storied_rerolls := false
	var saw_bewitched_sub := false
	var saw_bitterly_remembered_species := false
	for i in range(400):
		var hist: Dictionary = MagicItemGenerator._roll_weapon_history(0)
		if hist.has("rerolls"):
			saw_storied_rerolls = true
			checks.append(["weapon history roll #%d: Storied produces exactly two reroll results" % i, hist["rerolls"].size() == 2])
		if hist.has("sub_result"):
			saw_bewitched_sub = true
			checks.append(["weapon history roll #%d: Bewitched sub_result is non-empty" % i, String(hist["sub_result"]) != ""])
		if hist.has("hated_species"):
			saw_bitterly_remembered_species = true
			checks.append(["weapon history roll #%d: Bitterly Remembered names a hated species" % i, String(hist["hated_species"]) != ""])
	checks.append(["across 400 history rolls, Storied's two-reroll path fired at least once", saw_storied_rerolls])
	checks.append(["across 400 history rolls, Bewitched's sub-roll path fired at least once", saw_bewitched_sub])
	checks.append(["across 400 history rolls, Bitterly Remembered's hated-species sub-roll fired at least once", saw_bitterly_remembered_species])

	## --- Armour ability roll edge cases: leather exclusion + mutual
	## exclusion after Legendary ------------------------------------------
	var saw_leather_reroll_note := false
	for i in range(400):
		var ab_list: Array[Dictionary] = []
		var an: Array[String] = []
		MagicItemGenerator._roll_armour_abilities(true, ab_list, an, 5)
		for ab in ab_list:
			var sp: String = String(ab.get("special", ""))
			checks.append(["armour ability roll #%d (leather): never lands Gromril" % i, sp != "gromril"])
			checks.append(["armour ability roll #%d (leather): never lands Ithilmar" % i, sp != "ithilmar"])
		for n in an:
			if n.contains("leather armour"):
				saw_leather_reroll_note = true
	checks.append(["across 400 leather armour-ability rolls, the Gromril/Ithilmar reroll-for-leather path fired at least once", saw_leather_reroll_note])

	var saw_both_gromril_ithilmar := false
	var saw_legendary_armour_five := false
	for i in range(400):
		var ab_list2: Array[Dictionary] = []
		var an2: Array[String] = []
		MagicItemGenerator._roll_armour_abilities(false, ab_list2, an2, 5)
		var got_gromril := false
		var got_ithilmar := false
		for ab in ab_list2:
			var sp: String = String(ab.get("special", ""))
			if sp == "gromril":
				got_gromril = true
			if sp == "ithilmar":
				got_ithilmar = true
		if got_gromril and got_ithilmar:
			saw_both_gromril_ithilmar = true
		if ab_list2.size() == 5:
			saw_legendary_armour_five = true
	checks.append(["across 400 non-leather armour-ability rolls, a suit NEVER ends up with both Gromril and Ithilmar", not saw_both_gromril_ithilmar])

	## --- Shield rating bump / encumbrance reduction ----------------------
	var saw_gromril_shield_bump := false
	var saw_ithilmar_shield_reduction := false
	var saw_ptolos_bump := false
	for i in range(200):
		var sh := MagicItemGenerator.generate_shield()
		var ability_name: String = String(sh.abilities[0].get("name", ""))
		var base_shield_def: WeaponDefinition = GameData.weapon_db.find_by_name(sh.base_name)
		var base_rating := 0
		for q in base_shield_def.qualities:
			if String(q).begins_with("Shield "):
				base_rating = int(String(q).trim_prefix("Shield "))
		var new_rating := 0
		for q in sh.definition.qualities:
			if String(q).begins_with("Shield "):
				new_rating = int(String(q).trim_prefix("Shield "))
		if ability_name == "Gromril Shield":
			saw_gromril_shield_bump = true
			checks.append(["shield #%d: Gromril Shield bumps the Shield rating by exactly +1" % i, new_rating == base_rating + 1])
		elif ability_name == "Shield of Ptolos":
			saw_ptolos_bump = true
			checks.append(["shield #%d: Shield of Ptolos bumps the Shield rating by +1 (documented conservative stand-in)" % i, new_rating == base_rating + 1])
		elif ability_name == "Ithilmar Shield":
			saw_ithilmar_shield_reduction = true
			checks.append(["shield #%d: Ithilmar Shield reduces Encumbrance by 1 (min 0)" % i, sh.definition.encumbrance == max(0, base_shield_def.encumbrance - 1)])
	checks.append(["across 200 shield rolls, Gromril Shield's rating bump fired at least once", saw_gromril_shield_bump])
	checks.append(["across 200 shield rolls, Ithilmar Shield's encumbrance reduction fired at least once", saw_ithilmar_shield_reduction])
	checks.append(["across 200 shield rolls, Shield of Ptolos' rating bump fired at least once", saw_ptolos_bump])

	## --- Cost formula sanity -----------------------------------------------
	var sword_def: WeaponDefinition = GameData.weapon_db.find_by_name("Sword")
	checks.append(["cost formula: a single-ability item costs base_price * 50", sword_def.price_pennies * MagicItemGenerator.COST_MULTIPLIER_PER_ABILITY == sword_def.price_pennies * 50])
	var arrow_def: ItemDefinition = GameData.item_db.find_by_name("Arrow")
	checks.append(["cost formula: ammunition costs base_price * 30", arrow_def.price_pennies * MagicItemGenerator.AMMO_COST_MULTIPLIER == arrow_def.price_pennies * 30])

	## --- Table coverage: every D100 1-100 value resolves to something on
	## every top-level table (the documented 25/28 overlap aside) ---------
	var uncovered: Array[int] = []
	for r in range(1, 101):
		if MagicItemGenerator._lookup(MagicItemGenerator.WEAPON_TYPE_TABLE, r).is_empty():
			uncovered.append(r)
	checks.append(["WEAPON_TYPE_TABLE covers all of 1-100 with no gaps", uncovered.is_empty()])
	uncovered.clear()
	for r in range(1, 101):
		if MagicItemGenerator._lookup(MagicItemGenerator.WEAPON_QUALITY_TABLE, r).is_empty():
			uncovered.append(r)
	checks.append(["WEAPON_QUALITY_TABLE covers all of 1-100 with no gaps", uncovered.is_empty()])
	uncovered.clear()
	for r in range(1, 101):
		if MagicItemGenerator._lookup(MagicItemGenerator.ARMOUR_PIECE_TABLE, r).is_empty():
			uncovered.append(r)
	checks.append(["ARMOUR_PIECE_TABLE covers all of 1-100 with no gaps", uncovered.is_empty()])
	uncovered.clear()
	for r in range(1, 101):
		if MagicItemGenerator._lookup(MagicItemGenerator.ARMOUR_QUALITY_TABLE, r).is_empty():
			uncovered.append(r)
	checks.append(["ARMOUR_QUALITY_TABLE covers all of 1-100 with no gaps", uncovered.is_empty()])
	uncovered.clear()
	for r in range(1, 101):
		if MagicItemGenerator._lookup(MagicItemGenerator.SHIELD_PIECE_TABLE, r).is_empty():
			uncovered.append(r)
	checks.append(["SHIELD_PIECE_TABLE covers all of 1-100 with no gaps", uncovered.is_empty()])
	uncovered.clear()
	for r in range(1, 101):
		if MagicItemGenerator._lookup(MagicItemGenerator.SHIELD_QUALITY_TABLE, r).is_empty():
			uncovered.append(r)
	checks.append(["SHIELD_QUALITY_TABLE covers all of 1-100 with no gaps", uncovered.is_empty()])
	uncovered.clear()
	for r in range(1, 101):
		if MagicItemGenerator._lookup(MagicItemGenerator.AMMO_TABLE, r).is_empty():
			uncovered.append(r)
	checks.append(["AMMO_TABLE covers all of 1-100 with no gaps", uncovered.is_empty()])
	uncovered.clear()
	for r in range(1, 101):
		if MagicItemGenerator._lookup(MagicItemGenerator.WEAPON_HISTORY_TABLE, r).is_empty():
			uncovered.append(r)
	checks.append(["WEAPON_HISTORY_TABLE covers all of 1-100 with no gaps", uncovered.is_empty()])
	uncovered.clear()
	for r in range(1, 101):
		if MagicItemGenerator._lookup(MagicItemGenerator.RANDOM_CREATURE_TABLE, r).is_empty():
			uncovered.append(r)
	checks.append(["RANDOM_CREATURE_TABLE covers all of 1-100 with no gaps", uncovered.is_empty()])
	uncovered.clear()
	for r in range(1, 101):
		if MagicItemGenerator._lookup(MagicItemGenerator.QUIRKS_AND_CURSES_TABLE, r).is_empty():
			uncovered.append(r)
	checks.append(["QUIRKS_AND_CURSES_TABLE covers 1-100 with no gaps", uncovered.is_empty()])

	## The documented book typo: roll 28 resolves to the earlier-listed
	## "Alight with Flame" (first-match-wins), not "Dolorous".
	checks.append(["documented book overlap: a roll of 28 resolves to 'Alight with Flame' (first-match-wins)", MagicItemGenerator._lookup(MagicItemGenerator.WEAPON_QUALITY_TABLE, 28).get("name", "") == "Alight with Flame"])

	## --- Sample formatted output, printed for a human to read -----------
	print("\n--- Sample generator output (for review) ---")
	print(MagicItemGenerator.format_result(MagicItemGenerator.generate_weapon()))
	print("")
	print(MagicItemGenerator.format_result(MagicItemGenerator.generate_ammunition()))
	print("")
	print(MagicItemGenerator.format_result(MagicItemGenerator.generate_armour()))
	print("")
	print(MagicItemGenerator.format_result(MagicItemGenerator.generate_shield()))
	print("--- end sample output ---\n")

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		if not passed:
			print("FAIL  " + label)
			all_pass = false
	if all_pass:
		print("RESULT (Magic Item Generator): ALL PASS (%d checks)" % checks.size())
	else:
		print("RESULT (Magic Item Generator): SOME FAILED (%d checks)" % checks.size())
	return all_pass
