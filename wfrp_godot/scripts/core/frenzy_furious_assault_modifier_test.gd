extends RefCounted
class_name FrenzyFuriousAssaultModifierTest
## Regression test for the user report (screenshot of a Furious Assault
## roll card with NO Modifier row at all): "outnumbering bonus and other
## melee action modifiers should be adding to Furious Assault/Frenzy
## attacks too." See _execute_frenzy_attack()'s own leading comment in
## field_encounter_screen.gd for the full root-cause writeup — this test
## covers the fix for both follow-up attacks.
##
## Calls _execute_frenzy_attack()/_execute_furious_assault() directly
## (same technique deathblow_move_into_square_test.gd uses) with an
## empty deathblow_budget, so each call runs fully synchronously to
## completion — no polling loop needed. Uses `fe` (a live
## FieldEncounter.tscn instance the caller owns), matching this
## project's own `run_test(fe)` convention.
##
## The real regression check isn't just "the breakdown shows the right
## rows" (a bug could show the right numbers while still feeding the
## OLD, wrong total into the actual roll) — it's that the roll's own
## `target` number actually moved by the modifiers' own sum. Calling the
## same attacker/weapon/target twice in a row — once with every optional
## modifier at 0, once with all of them set to distinct nonzero values —
## and diffing `target` between the two calls cancels out every OTHER
## fixed situational modifier this pair might also trigger (Kept at bay,
## Distracting, Size), since those depend only on the attacker/defender/
## weapon, not on the parameters under test here.

static func _latest_attacker_test(fe):
	var entry: Dictionary = fe.history[0]
	var segments: Array = entry.get("segments", [])
	for i in range(segments.size() - 1, -1, -1):
		if segments[i].get("kind", "") == "cards":
			var cards: Array = segments[i].get("cards", [])
			if cards.size() > 0:
				return cards[0].get("test")
	return null

static func _breakdown_matches(modifiers: Array, expected: Array) -> bool:
	if modifiers.size() != expected.size():
		return false
	for i in range(modifiers.size()):
		var got: Dictionary = modifiers[i]
		var want: Dictionary = expected[i]
		if got.get("name", "") != want.get("name", "") or int(got.get("amount", 0)) != int(want.get("amount", 0)):
			return false
	return true

static func run_test(fe) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "FrenzyFuriousModTestPlayer"
	pc.equipped_weapon = "Sword"

	GameState.current_field_difficulty_tier = 0
	var no_pool: Array[String] = []
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_habitat = ""
	GameState.pending_encounter_monster_names = ["Giant Rat"]
	fe._start_encounter()
	for i in range(3):
		await fe.get_tree().process_frame

	var setup_ok: bool = fe.monsters.size() >= 1 and fe.player != null
	checks.append(["setup: player + a real monster target", setup_ok])
	if not setup_ok:
		print("RESULT (Frenzy/Furious Assault Modifiers): SETUP FAILED")
		return false

	var target: Character = fe.monsters[0]
	var weapon: WeaponDefinition = fe.weapons.get(fe.player)
	checks.append(["setup: player's own weapon resolved and is genuinely melee", weapon != null and not weapon.is_ranged])
	if weapon == null or weapon.is_ranged:
		print("RESULT (Frenzy/Furious Assault Modifiers): SETUP FAILED (no melee weapon)")
		return false

	## --- Frenzy -------------------------------------------------------
	fe._execute_frenzy_attack(target, weapon, 0, {}, 0, 0, 0, 0)
	var baseline_test = _latest_attacker_test(fe)
	checks.append(["Frenzy baseline: a real attacker test was logged", baseline_test != null])

	fe._execute_frenzy_attack(target, weapon, 10, {}, 10, -10, -10, -20)
	var boosted_test = _latest_attacker_test(fe)
	checks.append(["Frenzy boosted: a real attacker test was logged", boosted_test != null])

	if baseline_test != null and boosted_test != null:
		checks.append(["Frenzy baseline: no modifier rows shown when every extra modifier is 0", baseline_test.target_modifiers.is_empty()])
		var expected_frenzy_breakdown: Array = [
			{"name": "Outnumbering", "amount": 10},
			{"name": "Charging", "amount": 10},
			{"name": "Fear", "amount": -10},
			{"name": "Darkness", "amount": -10},
			{"name": "Off-hand penalty", "amount": -20},
		]
		checks.append(["Frenzy boosted: every modifier shown, in order, with the right amounts", _breakdown_matches(boosted_test.target_modifiers, expected_frenzy_breakdown)])
		checks.append(["Frenzy: base target unchanged between the two calls (same attacker/weapon/target)", boosted_test.base_target == baseline_test.base_target])
		## The real regression: outnumbering + charging + fear + darkness +
		## off-hand penalty = 10 + 10 - 10 - 10 - 20 = -20. This is what
		## used to be silently dropped from the real roll (only outnumbering
		## ever made it through) -- confirm it's now genuinely in `target`,
		## not just in the display breakdown above.
		checks.append(["Frenzy: the real roll target actually moved by the modifiers' own sum (-20)", boosted_test.target - baseline_test.target == -20])

	## --- Furious Assault ------------------------------------------------
	fe.encounter.advantage_pool.add("ally", 5)
	fe._execute_furious_assault(target, weapon, 0, {}, 0, 0, 0, 0)
	var fa_baseline_test = _latest_attacker_test(fe)
	checks.append(["Furious Assault baseline: a real attacker test was logged", fa_baseline_test != null])

	fe.encounter.advantage_pool.add("ally", 5)
	fe._execute_furious_assault(target, weapon, 10, {}, 10, -10, -10, -20)
	var fa_boosted_test = _latest_attacker_test(fe)
	checks.append(["Furious Assault boosted: a real attacker test was logged", fa_boosted_test != null])

	if fa_baseline_test != null and fa_boosted_test != null:
		checks.append(["Furious Assault baseline: no modifier rows shown when every extra modifier is 0", fa_baseline_test.target_modifiers.is_empty()])
		var expected_furious_breakdown: Array = [
			{"name": "Outnumbering", "amount": 10},
			{"name": "Charging", "amount": 10},
			{"name": "Fear", "amount": -10},
			{"name": "Darkness", "amount": -10},
			{"name": "Off-hand penalty", "amount": -20},
		]
		checks.append(["Furious Assault boosted: every modifier shown, in order, with the right amounts", _breakdown_matches(fa_boosted_test.target_modifiers, expected_furious_breakdown)])
		checks.append(["Furious Assault: base target unchanged between the two calls (same attacker/weapon/target)", fa_boosted_test.base_target == fa_baseline_test.base_target])
		checks.append(["Furious Assault: the real roll target actually moved by the modifiers' own sum (-20)", fa_boosted_test.target - fa_baseline_test.target == -20])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Frenzy/Furious Assault Modifiers): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
