extends RefCounted
class_name TestResolverUncappedTargetTest
## Regression test for the report (with a screenshot of a Bolt cast
## showing "Roll vs Target 15 vs 100" despite +9/-4 modifiers that should
## have pushed the real target well past 100): "do not cap roll target
## at 100, so if the accumulated value is higher then 100 do not cap
## it."
##
## Root cause: TestResolver.resolve() clamped its incoming target to
## clamp(target, 1, 100) before doing ANYTHING else with it -- not just
## for display, but for the actual Success Level math too
## (computed_sl = floor(clamped_target/10) - floor(roll/10)). A
## genuinely stacked Casting Number reduction / Advantage / Additional
## Effort total that added up past 100 got silently truncated back down
## to 100, both showing the wrong number on the roll card AND losing
## real, earned Success Levels it should have granted. d100 itself still
## only ever rolls 1-100 (Dice.d100() is untouched) -- a target above
## 100 just means "always succeeds, and by more SL the higher it is,"
## which is correct WFRP behaviour for a heavily-boosted Test, not
## something to guard against.
##
## Fixed by resolve() now only flooring at 1 (max(target, 1)) rather
## than clamping the top end too. This test drives resolve() directly
## with forced rolls (deterministic), and also end to end through
## resolve_characteristic_test() with a character whose stacked
## modifiers genuinely exceed 100, confirming the roll card's own
## `result.target` reflects the true, uncapped value.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- Direct resolve() calls, forced rolls for determinism ----------
	var r1 := TestResolver.resolve(150, 0, 50)
	checks.append(["THE FIX: a target of 150 is no longer clamped down to 100", r1.target == 150])
	checks.append(["a target of 150 with roll 50 still computes real SL from the true target (floor(150/10)-floor(50/10) = 15-5 = 10)", r1.success_levels == 10])
	checks.append(["target 150, roll 50: succeeds (50 <= 150)", r1.success])

	var r2 := TestResolver.resolve(150, 0, 99)
	checks.append(["target 150, roll 99 (in the old 96-100 auto-fail band): still succeeds since the real target (150) is >= 96", r2.success])
	checks.append(["...with real SL from the uncapped target (floor(150/10)-floor(99/10) = 15-9 = 6)", r2.success_levels == 6])

	var r3 := TestResolver.resolve(150, 0, 100)
	checks.append(["target 150, roll 100 (the literal top of the die): still succeeds (100 <= 150), no longer an auto-fail", r3.success])

	var r4 := TestResolver.resolve(215, 0, 1)
	checks.append(["a much larger target (215, e.g. a heavily-boosted cast) is also left completely uncapped", r4.target == 215])

	## --- Lower floor is unchanged: a target of 0 or negative still
	## floors to 1, not left at 0/negative (which would make every SL
	## computation nonsensical and mean "impossible to ever succeed" in
	## a way the rest of this project's math doesn't expect). ------------
	var r5 := TestResolver.resolve(0, 0, 50)
	checks.append(["a target of 0 still floors to 1 (the lower bound is untouched by this fix)", r5.target == 1])
	var r6 := TestResolver.resolve(-30, 0, 50)
	checks.append(["a negative target also still floors to 1", r6.target == 1])

	## --- End to end: a character whose stacked modifiers genuinely
	## exceed 100 shows the TRUE total on result.target, not a capped
	## 100 -- this is the exact "Roll vs Target ... vs 100" symptom from
	## the report's own screenshot. -------------------------------------
	var caster := Character.new()
	caster.character_name = "TestUncappedCaster"
	caster.characteristics = CharacteristicSet.new()
	caster.characteristics.set_value("willpower", 90)   ## deliberately huge -- real high-Willpower casters exist
	var result := TestResolver.resolve_characteristic_test(caster, "willpower", 40, [], [])   ## +40 modifier on top, e.g. stacked Advantage/Effort/CN reduction
	checks.append(["sanity: this scenario's own accumulated target genuinely exceeds 100 (90 + 40 = 130)", result.base_target + 40 > 100])
	checks.append(["THE FIX, end to end: resolve_characteristic_test()'s own result.target is the true uncapped total, not truncated to 100", result.target == 130])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Test Resolver Uncapped Target): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
