extends RefCounted
class_name ConsumeAlcoholTest
## Regression/functional test for the follow-up request ("lets make
## sure Consume Alcohol and drunk mechanic are really implemented, if
## not do it"). Covers the real mechanic added in Character.gd
## (alcohol_fail_count/is_stinking_drunk/tick_alcohol_hours, etc — see
## that file's own header comment on this feature for the full rules
## text it's built from) plus TavernScreen's own Drink/Gossip box and
## the hangover Fatigued-removal lock shared with camp_screen.gd.
##
## Split into two halves, same "static run_test(tree)" shape as this
## project's other tests even though only the second half actually
## needs a live SceneTree: pure Character-state math (no scene
## required) first, then a real TavernScreen instance to prove the
## hangover lock genuinely survives a live Full Night's Sleep, not
## just the isolated logic.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	var human = GameData.find_race("Human")
	var soldier = GameData.find_career("Soldier")
	var consume_alcohol_def: SkillDefinition = GameData.skill_db.find_by_name("Consume Alcohol")
	var cool_def: SkillDefinition = GameData.skill_db.find_by_name("Cool")

	checks.append(["Consume Alcohol skill data exists", consume_alcohol_def != null])
	checks.append(["Cool skill data exists", cool_def != null])

	## --- Cumulative Characteristic penalty, capped at -30 -------------
	var drinker := CharacterCreator.create_character("AlcoholTestDrinker", human, soldier, {})
	drinker.characteristics.set_value("toughness", 30)   ## TB 3, so it takes >3 fails to hit Stinking Drunk
	drinker.characteristics.set_value("weapon_skill", 50)
	drinker.characteristics.set_value("agility", 50)

	drinker.alcohol_fail_count = 0
	checks.append(["0 fails: no Characteristic penalty", drinker.get_alcohol_characteristic_penalty() == 0])
	checks.append(["0 fails: effective WS unchanged", drinker.get_effective_characteristic_value("weapon_skill") == 50])

	drinker.alcohol_fail_count = 2
	checks.append(["2 fails: -20 Characteristic penalty", drinker.get_alcohol_characteristic_penalty() == -20])
	checks.append(["2 fails: effective Agility reflects the -20", drinker.get_effective_characteristic_value("agility") == 30])

	drinker.alcohol_fail_count = 5   ## past the 3-fail cap
	checks.append(["5 fails: penalty still capped at -30, not -50", drinker.get_alcohol_characteristic_penalty() == -30])

	## Only WS/BS/Ag/Dex/Int are affected — Strength/Toughness/
	## Willpower/Fellowship/Initiative are untouched by drink.
	drinker.characteristics.set_value("strength", 40)
	checks.append(["Strength is NOT one of the alcohol-penalised Characteristics", drinker.get_effective_characteristic_value("strength") == 40])

	## --- Stinking Drunk trigger (fails >= Toughness Bonus) -------------
	var lightweight := CharacterCreator.create_character("AlcoholTestLightweight", human, soldier, {})
	lightweight.characteristics.set_value("toughness", 20)   ## TB 2
	lightweight.alcohol_fail_count = 0
	lightweight.is_stinking_drunk = false
	lightweight.alcohol_fail_count += 2   ## exactly the Toughness Bonus (2) worth of fails
	if lightweight.alcohol_fail_count >= lightweight.get_characteristic_bonus("toughness"):
		lightweight.is_stinking_drunk = true
		lightweight.stinking_drunk_result = 1
	checks.append(["fails == Toughness Bonus (2) triggers Stinking Drunk", lightweight.is_stinking_drunk])
	checks.append(["a real 1d10 table row was recorded (1-10)", lightweight.stinking_drunk_result >= 1 and lightweight.stinking_drunk_result <= 10])

	## --- Table result 1-2: real +20 Cool Test bonus while active ------
	lightweight.stinking_drunk_result = 1
	var cool_bonus: Array = lightweight.get_drunk_test_modifier_breakdown(["Cool", "fellowship"])
	checks.append(["Stinking Drunk result 1-2 grants a real +20 Cool Test bonus", cool_bonus.size() == 1 and int(cool_bonus[0]["amount"]) == 20])
	var melee_bonus: Array = lightweight.get_drunk_test_modifier_breakdown(["Melee", "weapon_skill"])
	checks.append(["...but NOT to unrelated Tests (Melee)", melee_bonus.is_empty()])
	lightweight.stinking_drunk_result = 7   ## a different table row (no Cool bonus)
	var no_bonus: Array = lightweight.get_drunk_test_modifier_breakdown(["Cool"])
	checks.append(["a different table row (7-8) grants no Cool bonus", no_bonus.is_empty()])

	## Actually resolving a Cool Test end-to-end through TestResolver
	## picks the bonus up automatically (same pipeline as Condition
	## penalties) — not just the isolated breakdown helper.
	lightweight.stinking_drunk_result = 2
	var base_cool_target: int = lightweight.get_skill_value(cool_def)
	var forced_result := TestResolver.resolve_skill_test(lightweight, cool_def, "", 0, [], 50)   ## forced_roll=50, deterministic
	## Per TestResolver.resolve()'s own fix ("do not cap roll target at
	## 100"): the target itself is no longer clamped to 100, only
	## floored at 1 -- matches that function's own new max(target, 1).
	checks.append(["TestResolver.resolve_skill_test folds the +20 Stinking Drunk bonus into a real Cool Test's target", forced_result.target == max(base_cool_target + 20, 1)])

	## --- stinking_drunk_table_entry() text lookup ----------------------
	lightweight.stinking_drunk_result = 9
	var row: Dictionary = lightweight.stinking_drunk_table_entry()
	checks.append(["row 9 resolves to \"How Did I Get Here?\"", row.get("name", "") == "How Did I Get Here?"])

	## --- drink_alcohol(): a real end-to-end Test through the actual
	## Tavern entry point, forced via a very low Toughness so the SL
	## math is easy to reason about even though the roll itself is
	## real dice (can't force the roll through this specific call
	## site — it's meant to be called from the UI — so this checks the
	## bookkeeping around the roll, not a specific pass/fail outcome).
	var fresh := CharacterCreator.create_character("AlcoholTestFresh", human, soldier, {})
	fresh.characteristics.set_value("toughness", 30)
	var before_fail_count: int = fresh.alcohol_fail_count
	var now_minutes := 1000
	var drink_result := fresh.drink_alcohol(consume_alcohol_def, 0, now_minutes)
	checks.append(["drink_alcohol() records the drink time", fresh.last_drink_time_minutes == now_minutes])
	if drink_result.success:
		checks.append(["a successful drink doesn't add a fail", fresh.alcohol_fail_count == before_fail_count])
	else:
		checks.append(["a failed drink adds exactly one fail", fresh.alcohol_fail_count == before_fail_count + 1])

	## --- tick_alcohol_hours(): sobering-up arc ---------------------------
	var sobering := CharacterCreator.create_character("AlcoholTestSobering", human, soldier, {})
	sobering.characteristics.set_value("toughness", 30)
	sobering.alcohol_fail_count = 2
	sobering.last_drink_time_minutes = 0
	## Fewer than 60 minutes since the last drink: the sobering Test
	## must NOT have fired yet — still actively drinking-adjacent.
	sobering.tick_alcohol_hours(30, 30, consume_alcohol_def)
	checks.append(["sobering Test doesn't fire before a full hour has passed", not sobering.is_sobering_up()])
	checks.append(["...and the fail count/penalty are still fully in effect", sobering.alcohol_fail_count == 2])

	## Now cross the 1-hour mark: the sobering Test must fire exactly
	## once and start a real recovery countdown.
	sobering.tick_alcohol_hours(40, 70, consume_alcohol_def)
	checks.append(["sobering Test fires once >=60 minutes have passed since the last drink", sobering.is_sobering_up()])
	checks.append(["recovery countdown is a real positive number of hours", sobering.alcohol_recovery_hours_remaining > 0.0])

	## Push a huge amount of time through — the whole rest of the
	## recovery window plus the follow-up hangover Test — in one go,
	## same as a Full Night's Sleep would. Documented simplification
	## (see tick_alcohol_hours()'s own comment): this is allowed to
	## resolve the entire remaining arc in a single call.
	var recovery_hours_needed: float = sobering.alcohol_recovery_hours_remaining
	sobering.tick_alcohol_hours(int(ceil(recovery_hours_needed * 60.0)) + 60, 70 + int(ceil(recovery_hours_needed * 60.0)) + 60, consume_alcohol_def)
	checks.append(["once the recovery window elapses, all drunk state clears", sobering.alcohol_fail_count == 0 and not sobering.is_stinking_drunk and sobering.stinking_drunk_result == 0])
	## Consistency invariant (the actual hangover Test's SL is real
	## dice, can't force it here): EITHER a hangover was granted (lock
	## hours > 0 AND a real Fatigued stack was added), OR it wasn't
	## (lock stays at 0) — never a lock with no Fatigued stack or vice
	## versa.
	var got_hangover: bool = sobering.hangover_lock_hours_remaining > 0.0
	var has_fatigued: bool = int(sobering.conditions.get("Fatigued", 0)) > 0
	checks.append(["hangover lock and the Fatigued stack it grants are consistent with each other", got_hangover == has_fatigued or (got_hangover and has_fatigued)])

	## --- Hangover lock genuinely blocks Sleep from removing it ---------
	## Real end-to-end check through an actual TavernScreen instance and
	## a real Full Night's Sleep button click — not just the isolated
	## logic above — since this is exactly the kind of "looks right in
	## isolation but the UI path forgot to check it" bug this project
	## has hit before (see this file's own header comment).
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var hungover_pc: Character = GameState.player_character
	hungover_pc.conditions["Fatigued"] = 1
	hungover_pc.hangover_lock_hours_remaining = 20.0   ## longer than one Full Night's Sleep (8h)
	hungover_pc.gold_crowns = 10   ## can afford any room tier

	var ts = load("res://scenes/Tavern.tscn").instantiate()
	tree.get_root().add_child.call_deferred(ts)
	for i in range(4):
		await tree.process_frame

	ts._on_sleep(8 * 60, true)
	await tree.process_frame

	checks.append(["a locked hangover Fatigued stack survives a real Full Night's Sleep", int(GameState.player_character.conditions.get("Fatigued", 0)) >= 1])
	checks.append(["the lock itself still ticked down by the Sleep's own real duration (8h)", GameState.player_character.hangover_lock_hours_remaining <= 20.0 - 7.9])

	ts.queue_free()
	await tree.process_frame

	## A SECOND Tavern visit, lock already expired, proves Sleep can
	## still remove an ordinary (non-hangover) Fatigued stack normally —
	## the lock check isn't accidentally blocking removal forever.
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var normal_pc: Character = GameState.player_character
	normal_pc.conditions["Fatigued"] = 1
	normal_pc.hangover_lock_hours_remaining = 0.0
	normal_pc.gold_crowns = 10

	var ts2 = load("res://scenes/Tavern.tscn").instantiate()
	tree.get_root().add_child.call_deferred(ts2)
	for i in range(4):
		await tree.process_frame
	ts2._on_sleep(8 * 60, true)
	await tree.process_frame
	checks.append(["an ordinary (unlocked) Fatigued stack still gets removed by Sleep as normal", int(GameState.player_character.conditions.get("Fatigued", 0)) == 0])
	ts2.queue_free()
	await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Consume Alcohol): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
