extends RefCounted
class_name SocialCombatConditionsTest
## Verifies Slice 3 of "Social Combat — Design Doc v1": Exposed and
## Humiliated (Section 5), the Intimidate -> Flustered wiring (Section
## 4's own "Demoralised" reference, treated as this project's existing
## Flustered condition — see social_encounter_screen.gd's npc_momentum
## field comment), and the NPC-momentum mechanic (Section 6).
##
## Driven directly against a real SocialEncounter.tscn instance's own
## functions, same convention social_combat_maneuvers_test.gd already
## established — but this test also needs specific, repeatable dice
## outcomes (a guaranteed critical hit, a guaranteed fumble, a clean
## SL delta to isolate one bonus/penalty from the rest of the roll), so
## _attempt_social_attack()/_attempt_bring_the_muscle()/_run_npc_turn()
## were each given optional forced_roll parameters (default -1, unused
## by every real caller) purely so this test can drive them without
## depending on real dice. Every roll here also has both rollers'
## fortune_points forced to 0 and the screen's own Fortune-chain flags
## pre-armed (see _arm_no_fortune_prompt) so the Fortune/Dark-Deal
## prompt always collapses to its no-choice "Continue" shortcut and
## every call below runs fully synchronously — no frame-driving or
## button-clicking needed anywhere in this file.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	var game_state = tree.get_root().get_node("/root/GameState")
	game_state.reset_world_state()
	game_state.player_character = null
	game_state.ensure_player_character()
	var pc: Character = game_state.player_character
	pc.fortune_points = 0

	var scene_res: PackedScene = load("res://scenes/SocialEncounter.tscn")
	var screen: Control = scene_res.instantiate()
	tree.get_root().add_child(screen)
	for i in range(10):
		await tree.process_frame

	checks.append(["Screen started a real Social Combat", screen.social_combat != null])
	var npc_a: Character = screen.npc_characters[0] if not screen.npc_characters.is_empty() else null
	checks.append(["A real NPC exists to target", npc_a != null])

	if screen.social_combat == null or npc_a == null:
		var all_pass_early := true
		for chk in checks:
			print(("PASS  " if chk[1] else "FAIL  ") + chk[0])
			if not chk[1]:
				all_pass_early = false
		print("RESULT (Social Combat Conditions): ", "ALL PASS" if all_pass_early else "SOME FAILED")
		return all_pass_early

	screen.selected_npc_target = npc_a
	pc.characteristics.strength = 80
	pc.characteristics.intelligence = 80

	var intimidate_def: SkillDefinition = GameData.skill_db.find_by_name("Intimidate")
	var research_def: SkillDefinition = GameData.skill_db.find_by_name("Research")

	## --- Exposed (Design Doc Section 5): a party Critical Hit leaves
	## the NPC Exposed; while Exposed, its own Social Armor reads as 0
	## against the NEXT attack (armor is computed before this hit's own
	## Exposed application, so the zeroing effect shows up starting on
	## the following hit, not the one that caused it). ---------------
	npc_a.remove_condition("Exposed")
	npc_a.remove_condition("Flustered")
	npc_a.composure_max = 200
	npc_a.composure_current = 200
	## Per the Status-comparison rework: Social Armor is now
	## max(0, npc_status - attacker_status) * ARMOR_PER_STATUS_STEP
	## (social_encounter_screen.gd's own _social_armor_against()) rather
	## than a hand-set flat number. `pc` here is GameState's own default
	## test character (ensure_player_character()'s Soldier, Tier 1 =
	## Silver/2 — see data/careers/soldier.tres), not a career-less
	## Brass character. Forcing this NPC to Gold (3) gives a 1-step gap,
	## i.e. armor = (3 - 2) * 2 = 2, the largest achievable against this
	## particular attacker's real Status.
	screen.npc_status_ordinal_by_char[npc_a] = 3

	_arm_no_fortune_prompt(screen)
	screen._attempt_social_attack(pc, SocialCombatResolver.AttackType.INTIMIDATE, intimidate_def, 11, 99)
	await tree.process_frame
	checks.append(["A party Critical Hit leaves the NPC Exposed", npc_a.has_condition("Exposed")])
	checks.append(["An Intimidate hit also leaves the NPC Flustered (Section 4's 'Demoralised')", npc_a.has_condition("Flustered")])
	var drop_with_armor: int = 200 - npc_a.composure_current
	checks.append(["The first hit still had its own Social Armor reduction applied", drop_with_armor > 0])

	npc_a.composure_current = 200   ## re-arm for a second hit, Exposed now already active
	_arm_no_fortune_prompt(screen)
	screen._attempt_social_attack(pc, SocialCombatResolver.AttackType.INTIMIDATE, intimidate_def, 11, 99)
	await tree.process_frame
	var drop_while_exposed: int = 200 - npc_a.composure_current
	checks.append(["While Exposed, the next hit's damage skips the Social Armor reduction entirely (full +2 more than the armored hit)", drop_while_exposed - drop_with_armor == 2])

	## --- Reason saps momentum on a hit (Design Doc Section 6) --------
	screen.npc_momentum[npc_a] = 3
	_arm_no_fortune_prompt(screen)
	screen._attempt_social_attack(pc, SocialCombatResolver.AttackType.REASON, research_def, 11, 99)
	await tree.process_frame
	checks.append(["A successful Reason hit saps 1 point of the target's own momentum", screen.npc_momentum.get(npc_a, 0) == 2])

	screen.npc_momentum[npc_a] = 0
	_arm_no_fortune_prompt(screen)
	screen._attempt_social_attack(pc, SocialCombatResolver.AttackType.REASON, research_def, 11, 99)
	await tree.process_frame
	checks.append(["Momentum never goes negative from repeated Reason hits", screen.npc_momentum.get(npc_a, 0) == 0])

	## --- NPC momentum: +10 per point to the NPC's own attack roll,
	## isolated as a clean Success-Level delta (Design Doc Section 6) --
	var solo_party: Array[Character] = [pc]
	game_state.party = solo_party   ## a single, known defender for every _run_npc_turn call below
	pc.characteristics.willpower = 20
	npc_a.characteristics.fellowship = 50
	npc_a.remove_condition("Flustered")

	pc.composure_max = 200
	pc.composure_current = 200
	screen.npc_momentum[npc_a] = 0
	_arm_no_fortune_prompt(screen)
	screen._run_npc_turn(npc_a, 5, 90)
	await tree.process_frame
	var dmg_no_momentum: int = 200 - pc.composure_current
	checks.append(["The NPC's own turn actually landed with 0 momentum (sanity check)", dmg_no_momentum > 0])

	pc.composure_current = 200
	screen.npc_momentum[npc_a] = 3
	_arm_no_fortune_prompt(screen)
	screen._run_npc_turn(npc_a, 5, 90)
	await tree.process_frame
	var dmg_with_momentum: int = 200 - pc.composure_current
	checks.append(["3 points of momentum add exactly +3 Success Levels (+10/point) to the NPC's own attack, landing 3 more Composure damage", dmg_with_momentum - dmg_no_momentum == 3])
	checks.append(["A landed hit grows the NPC's own momentum by 1 (now capped display aside)", screen.npc_momentum.get(npc_a, 0) == 4])

	## --- Momentum caps at 5 -------------------------------------------
	screen.npc_momentum[npc_a] = 5
	pc.composure_current = 200
	_arm_no_fortune_prompt(screen)
	screen._run_npc_turn(npc_a, 5, 90)
	await tree.process_frame
	checks.append(["Momentum never climbs past its own cap of 5", screen.npc_momentum.get(npc_a, 0) == 5])

	## --- Humiliated: an NPC's own Critical Hit applies it ------------
	pc.remove_condition("Humiliated")
	pc.composure_current = 200
	screen.npc_momentum[npc_a] = 0
	_arm_no_fortune_prompt(screen)
	screen._run_npc_turn(npc_a, 11, 90)
	await tree.process_frame
	checks.append(["An NPC's own Critical Hit leaves the target party member Humiliated", pc.has_condition("Humiliated")])

	## --- Humiliated's own -20 defense penalty, isolated the same way
	## as the momentum bonus above -------------------------------------
	pc.characteristics.willpower = 60
	pc.remove_condition("Humiliated")
	pc.composure_current = 200
	screen.npc_momentum[npc_a] = 0
	_arm_no_fortune_prompt(screen)
	screen._run_npc_turn(npc_a, 5, 50)
	await tree.process_frame
	var dmg_not_humiliated: int = 200 - pc.composure_current

	pc.add_condition("Humiliated")
	pc.composure_current = 200
	screen.npc_momentum[npc_a] = 0
	_arm_no_fortune_prompt(screen)
	screen._run_npc_turn(npc_a, 5, 50)
	await tree.process_frame
	var dmg_humiliated: int = 200 - pc.composure_current
	checks.append(["Humiliated's -20 defense penalty lands exactly 2 more Success Levels of damage (-20 = -2 SL)", dmg_humiliated - dmg_not_humiliated == 2])

	## --- Recompose (Design Doc Section 5's own escape) ----------------
	pc.add_condition("Humiliated")
	screen._use_recompose(pc)
	checks.append(["Recompose clears Humiliated with no roll and no cost", not pc.has_condition("Humiliated")])

	## --- _clear_exposed_start_of_turn() (mirrors _apply_flustered_
	## start_of_turn()'s own directly-testable shape) -------------------
	npc_a.add_condition("Exposed")
	screen._clear_exposed_start_of_turn(npc_a)
	checks.append(["Exposed clears at the start of the NPC's own next turn", not npc_a.has_condition("Exposed")])

	## --- An NPC's own Fumble resets ITS OWN momentum to 0 (this
	## project's own inferred symmetric rule, mirroring the party's own
	## Rapport-resets-on-Fumble) -----------------------------------------
	npc_a.characteristics.fellowship = 5
	screen.npc_momentum[npc_a] = 4
	pc.remove_condition("Humiliated")
	pc.composure_current = 200
	_arm_no_fortune_prompt(screen)
	screen._run_npc_turn(npc_a, 99, 90)   ## 99 % 11 == 0 and a target of 5 guarantees a Fumble
	await tree.process_frame
	checks.append(["An NPC's own Fumble resets its own momentum to 0", screen.npc_momentum.get(npc_a, 0) == 0])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Social Combat Conditions): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass

static func _arm_no_fortune_prompt(screen) -> void:
	## Forces every _offer_fortune_spend() call this test triggers to
	## collapse to its own no-choice "Continue" shortcut (see that
	## function's own comment on options.size() > 1) rather than
	## needing a real button click driven across real frames.
	screen._fortune_chain_active = true
	screen._reroll_used_this_fortune_chain = true
	screen._dark_deal_used_this_fortune_chain = true
