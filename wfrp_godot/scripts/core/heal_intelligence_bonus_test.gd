extends RefCounted
class_name HealIntelligenceBonusTest
## Regression test for the request ("heal skill should add Intelligence
## Bonus + SL outcome on a successful roll"): _apply_heal_outcome() in
## field_encounter_screen.gd previously healed a flat max(1, SL) Wounds on
## a successful Heal Test — matching the book's own SL term but silently
## dropping its other half, "your Intelligence Bonus" (p.138: "the patient
## recovers a number of Wounds equal to your Intelligence Bonus plus the
## SL"). Confirmed live by the user's own attached roll card: SL +4 on a
## successful Heal produced exactly "Healed 4 Wound(s)", with no
## Intelligence Bonus term added anywhere.
##
## "your" in the book's own wording is the HEALER's Intelligence Bonus —
## Heal is a Test the healer (player) makes, not the patient (target); a
## bare Heal Self case has player == target so that distinction can't be
## observed there, which is why this test also drives a genuine
## player-heals-ally case with the two Characters given different
## Intelligence scores.
##
## Drives _apply_heal_outcome() directly (same direct-call technique this
## project's own combat/skill tests already use) against a real
## FieldEncounter fixture, with a hand-built TestResult standing in for a
## real roll so the exact SL is known and reproducible.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []
	await tree.process_frame
	await tree.process_frame

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	GameState.current_field_difficulty_tier = 0
	GameState.dungeon_entry_requested = false

	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(5):
		await tree.process_frame

	var player: Character = fe.player
	## Int 44 -> Intelligence Bonus 4 (floor(44/10)), distinct from the
	## ally's own Intelligence below so a mix-up (target's Bonus used
	## instead of the healer's) would be caught.
	player.characteristics.intelligence = 44

	var ally := Character.new()
	ally.character_name = "Ally"
	ally.characteristics = CharacteristicSet.new()
	ally.characteristics.intelligence = 20   ## Bonus 2 — must NOT be the value used
	ally.wounds_max = 20
	ally.wounds_current = 5

	## --- Case 1: healing an ally, SL +4 (mirrors the user's own screenshot) ---
	var test1 := TestResolver.TestResult.new()
	test1.success = true
	test1.success_levels = 4
	var wounds_before1: int = ally.wounds_current
	fe._apply_heal_outcome(ally, test1, wounds_before1, 0, 0, false)

	## THE FIX: 4 (SL) + 4 (healer's own Intelligence Bonus) = 8, not the
	## old flat SL-only result of 4.
	checks.append(["THE FIX: SL 4 + healer's Intelligence Bonus 4 heals 8 Wounds, not just SL's 4", ally.wounds_current - wounds_before1 == 8])
	checks.append(["the ally's OWN Intelligence Bonus (2) was not what got used", ally.wounds_current - wounds_before1 != 4 + 2])

	## --- Case 2: capped at wounds_max — the extra Bonus shouldn't overheal past the cap ---
	ally.wounds_current = ally.wounds_max - 2   ## only 2 Wounds of headroom left
	var test2 := TestResolver.TestResult.new()
	test2.success = true
	test2.success_levels = 4
	var wounds_before2: int = ally.wounds_current
	fe._apply_heal_outcome(ally, test2, wounds_before2, 0, 0, false)
	checks.append(["healing still caps at wounds_max even with the added Intelligence Bonus", ally.wounds_current == ally.wounds_max])

	## --- Case 3: a failed Test still heals nothing, Intelligence Bonus or not ---
	ally.wounds_current = 5
	var test3 := TestResolver.TestResult.new()
	test3.success = false
	test3.success_levels = -2
	var wounds_before3: int = ally.wounds_current
	fe._apply_heal_outcome(ally, test3, wounds_before3, 0, 0, false)
	checks.append(["a failed Heal Test still heals nothing", ally.wounds_current == wounds_before3])

	## --- Case 4: Heal Self (player == target) still gets the Bonus term too ---
	player.wounds_max = 20
	player.wounds_current = 5
	var test4 := TestResolver.TestResult.new()
	test4.success = true
	test4.success_levels = 1
	var wounds_before4: int = player.wounds_current
	fe._apply_heal_outcome(player, test4, wounds_before4, 0, 0, false)
	checks.append(["Heal Self also adds the healer's Intelligence Bonus (SL 1 + Bonus 4 = 5)", player.wounds_current - wounds_before4 == 5])

	## --- Case 5: an Intelligence Bonus of 0 still leaves the pre-existing SL floor of 1 intact ---
	player.characteristics.intelligence = 5   ## Bonus 0
	ally.wounds_current = 5
	var test5 := TestResolver.TestResult.new()
	test5.success = true
	test5.success_levels = 0
	var wounds_before5: int = ally.wounds_current
	fe._apply_heal_outcome(ally, test5, wounds_before5, 0, 0, false)
	checks.append(["a bare SL-0 success with a 0 Intelligence Bonus still floors at 1 Wound (pre-existing behavior, untouched)", ally.wounds_current - wounds_before5 == 1])

	fe.queue_free()
	for i in range(3):
		await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Heal Intelligence Bonus): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
