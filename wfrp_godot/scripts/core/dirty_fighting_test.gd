extends RefCounted
class_name DirtyFightingTest
## Per the request ("lets implement it fully"), for the Dirty Fighting
## Talent: "Max: Weapon Skill Bonus / Tests: Melee (Brawling) / You have
## been taught all the dirty tricks of unarmed combat. You may choose to
## cause an extra +1 Damage for each level in Dirty Fighting with any
## successful Melee (Brawling) hit. Note: using this Talent will be seen
## as cheating in any formal bout." (the data for this already existed —
## talent_name/max/tests/summary/effect_tags in core_talents.tres — but
## nothing actually applied the Damage bonus before this fix; see
## CombatResolver._apply_hit()).
##
## Confirms: the flat per-rank Damage bonus genuinely applies on a
## successful hit with a real Brawling weapon (Unarmed); it does NOT
## apply with a non-Brawling melee weapon (Sword) even for the same
## character/rank; the card's own "Tests: Melee (Brawling)" line ALSO
## grants the ruleset's generic +1 Success Level per rank on that same
## Test — layered on top of the Damage bonus, not replaced by it (a
## real bug in the first pass of this fix left
## overrides_default_test_effect = true, wrongly suppressing that SL
## bonus entirely — fixed per follow-up correction); and the Damage
## bonus stacks additively with Strike Mighty Blow when a character
## somehow has both and is using a Brawling weapon, rather than the two
## silently overwriting one another.

static func run_test() -> bool:
	var checks: Array = []

	var human := GameData.find_race("Human")
	var soldier := GameData.find_career("Soldier")
	var unarmed: WeaponDefinition = GameData.weapon_db.find_by_name("Unarmed")
	var sword: WeaponDefinition = GameData.weapon_db.find_by_name("Sword")
	checks.append(["Test setup: found the real Unarmed (Brawling) weapon", unarmed != null and unarmed.skill_group == "Brawling"])
	checks.append(["Test setup: found the real Sword (non-Brawling) weapon", sword != null and sword.skill_group != "Brawling"])
	if unarmed == null or sword == null:
		print("FAIL  could not find Unarmed/Sword weapon data — aborting")
		return false

	var attacker := Character.new()
	attacker.race = human
	attacker.career = soldier
	attacker.current_tier = 1
	attacker.characteristics = CharacteristicSet.new()
	attacker.recompute_max_wounds()
	var defender := Character.new()
	defender.race = human
	defender.career = soldier
	defender.current_tier = 1
	defender.characteristics = CharacteristicSet.new()
	defender.recompute_max_wounds()

	## A fixed, successful, non-critical hitting test — SL 2 — reused
	## across every case below so only the Talent/weapon combination
	## under test varies.
	var make_hit := func() -> TestResolver.TestResult:
		var t := TestResolver.TestResult.new()
		t.roll = 45
		t.success = true
		t.success_levels = 2
		t.is_critical = false
		return t

	## --- Case 1: no Dirty Fighting at all -> no bonus, regardless of weapon.
	var result_none := CombatResolver.AttackResult.new()
	CombatResolver._apply_hit(result_none, attacker, defender, unarmed, make_hit.call())
	checks.append(["No Dirty Fighting: Unarmed hit gets no talent Damage bonus", result_none.talent_damage_bonus == 0])

	## --- Case 2: Dirty Fighting rank 2, Unarmed (Brawling) -> +2 Damage,
	## and it's actually folded into the final `damage` total, not just
	## sitting in the bonus field unused.
	attacker.talents_taken["Dirty Fighting"] = 2
	var result_unarmed := CombatResolver.AttackResult.new()
	CombatResolver._apply_hit(result_unarmed, attacker, defender, unarmed, make_hit.call())
	checks.append(["Dirty Fighting rank 2, Unarmed hit: +2 Damage bonus applied", result_unarmed.talent_damage_bonus == 2])
	checks.append(["...and its source is correctly attributed", result_unarmed.talent_damage_source == "Dirty Fighting"])
	checks.append(["...and it's genuinely folded into the final damage total (weapon + SL + bonus)", result_unarmed.damage == result_unarmed.weapon_damage + result_unarmed.damage_sl_used + 2])

	## --- Case 3: SAME character/rank, but a non-Brawling melee weapon
	## (Sword) -> no bonus. Per the Talent's own "Tests: Melee
	## (Brawling)" scope, this must not leak onto other Melee weapons.
	var result_sword := CombatResolver.AttackResult.new()
	CombatResolver._apply_hit(result_sword, attacker, defender, sword, make_hit.call())
	checks.append(["Dirty Fighting rank 2, but Sword (non-Brawling): no Damage bonus", result_sword.talent_damage_bonus == 0])

	## --- Case 4: per the card's own "Tests: Melee (Brawling)" line, the
	## ruleset's generic default Tests-field effect (+1 Success Level per
	## rank on a successful use of that Test) ALSO applies here, layered
	## on TOP of the bespoke +1 Damage/rank effect described in the
	## Talent's own text — the two are additional to each other, not
	## alternatives. (An earlier version of this fix incorrectly left
	## overrides_default_test_effect = true, on the assumption the
	## Damage line fully replaced the default Tests-field bonus; fixed
	## per follow-up correction — Strike Mighty Blow/Accurate Shot, by
	## contrast, genuinely have no "Tests" line of their own at all
	## (tests = [] in their own data), so overrides_default_test_effect
	## is moot for them either way and was never a real signal to copy
	## from.)
	var td: TalentDefinition = GameData.talent_db.find_by_name("Dirty Fighting")
	checks.append(["Dirty Fighting is correctly NOT flagged overrides_default_test_effect — the Tests-field default and the Damage bonus both apply", td != null and not td.overrides_default_test_effect])
	var sl_bonus := attacker.get_test_success_level_bonus(["Melee (Brawling)"])
	checks.append(["...and genuinely grants +2 Success Levels on a Melee (Brawling) Test at rank 2 (the ruleset's own default Tests-field effect)", sl_bonus == 2])
	var sl_bonus_other_skill := attacker.get_test_success_level_bonus(["Melee (Basic)"])
	checks.append(["...but grants nothing on a DIFFERENT Melee group (Basic) — correctly scoped to Brawling only", sl_bonus_other_skill == 0])

	## --- Case 4b: confirmed through a real resolve_skill_test() call
	## (not just the breakdown helper in isolation) — a Melee (Brawling)
	## Test genuinely comes back with 2 more Success Levels than the
	## same roll/target would give without the Talent. The SL bonus only
	## ever applies once a Test has already succeeded on its own (see
	## TestResolver.resolve()) — a fresh character's default WS 20 would
	## fail outright against this roll, masking the bonus entirely (both
	## sides would show the same negative SL, a false pass) rather than
	## genuinely exercising it, so WS is bumped well above the forced
	## roll here to guarantee a real success on both sides first.
	var melee_skill_def: SkillDefinition = GameData.skill_db.find_by_name("Melee")
	var shared_characteristics := CharacteristicSet.new()
	shared_characteristics.weapon_skill = 60
	var no_dirty_fighting_char := Character.new()
	no_dirty_fighting_char.race = human
	no_dirty_fighting_char.career = soldier
	no_dirty_fighting_char.current_tier = 1
	no_dirty_fighting_char.characteristics = shared_characteristics
	attacker.characteristics = shared_characteristics
	var baseline_test := TestResolver.resolve_skill_test(no_dirty_fighting_char, melee_skill_def, "Brawling", 0, [], 45)
	var with_talent_test := TestResolver.resolve_skill_test(attacker, melee_skill_def, "Brawling", 0, [], 45)
	checks.append(["Sanity: the forced roll (45) actually succeeded against the boosted target on both sides", baseline_test.success and with_talent_test.success])
	checks.append(["A real Melee (Brawling) Test genuinely scores +2 more Success Levels with Dirty Fighting rank 2 than without it (same roll/target)", with_talent_test.success_levels == baseline_test.success_levels + 2])

	## --- Case 5: stacks additively with Strike Mighty Blow on a
	## Brawling weapon, rather than one silently overwriting the other.
	attacker.talents_taken["Strike Mighty Blow"] = 1
	var result_stacked := CombatResolver.AttackResult.new()
	CombatResolver._apply_hit(result_stacked, attacker, defender, unarmed, make_hit.call())
	checks.append(["Dirty Fighting (rank 2) + Strike Mighty Blow (rank 1) on a Brawling weapon: bonuses stack to +3, not overwrite", result_stacked.talent_damage_bonus == 3])
	checks.append(["...and both sources are named in the breakdown label", result_stacked.talent_damage_source.contains("Strike Mighty Blow") and result_stacked.talent_damage_source.contains("Dirty Fighting")])

	## --- Case 6: Max rank sanity — "Max: Weapon Skill Bonus" is already
	## enforced generically by TalentDefinition.get_max_rank() for
	## max_mode == "characteristic_bonus" — confirm this Talent's own
	## data is actually wired to that (not left at the "fixed" default),
	## since a data mistake here would silently let a character take
	## unlimited ranks.
	checks.append(["Dirty Fighting's own Max is wired to Weapon Skill Bonus (characteristic_bonus mode), not a flat fixed number", td.max_mode == "characteristic_bonus" and td.max_characteristic == "weapon_skill"])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Dirty Fighting Talent Check): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
